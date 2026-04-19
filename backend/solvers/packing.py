"""
Crate packing solver.

Primary:  GaMSPy MIP — maximises items packed (then area used) in a single solve.
Fallback: backtracking branch-and-bound (original algorithm) used when GaMSPy is
          unavailable or raises any exception.
"""

from __future__ import annotations

import logging

from models import PackedCrate, PackedItem, PackingItem, PackingRequest, PackingResponse

logger = logging.getLogger(__name__)


def _resolve_budget_remaining(req: PackingRequest) -> int | None:
    if req.budget_remaining is not None:
        return max(0, int(req.budget_remaining))
    if req.budget is not None:
        return max(0, int(req.budget))
    return None


def _resolve_packaging_cost_per_crate(req: PackingRequest) -> int:
    if req.packaging_cost_per_crate is not None:
        return max(0, int(req.packaging_cost_per_crate))
    if req.packaging_cost_per_item is not None:
        return max(0, int(req.packaging_cost_per_item))
    return 50


def _build_crate_matrix(crate_size: list[int], packed_items: list[PackedItem]) -> list[list[int]]:
    W, H = int(crate_size[0]), int(crate_size[1])
    matrix = [[-1 for _ in range(W)] for _ in range(H)]
    for item in packed_items:
        for gy in range(item.grid_y, item.grid_y + item.h):
            for gx in range(item.grid_x, item.grid_x + item.w):
                if 0 <= gy < H and 0 <= gx < W:
                    matrix[gy][gx] = item.id
    return matrix


# ── GaMSPy MIP ───────────────────────────────────────────────────────────────


def _solve_packing_gamspy(
    crate_size: list[int],
    items: list[PackingItem],
    time_remaining: float = 300.0,
) -> tuple[list[PackedItem], list[int], float, str]:
    import pandas as pd
    from gamspy import Container, Equation, Model, Parameter, Sense, Set, Sum, Variable

    W, H = int(crate_size[0]), int(crate_size[1])
    if W <= 0 or H <= 0 or not items:
        return [], [item.id for item in items], 0.0, "gamspy"

    m = Container()

    # ── Sets ──────────────────────────────────────────────────────────────────
    I = Set(m, name="I", records=[str(item.id) for item in items])
    GX = Set(m, name="GX", records=[str(v) for v in range(W)])
    GY = Set(m, name="GY", records=[str(v) for v in range(H)])

    # Valid top-left placement positions per item (item fits inside the crate)
    valid_placements: list[tuple[str, str, str]] = []
    for item in items:
        for gx in range(W - item.w + 1):
            for gy in range(H - item.h + 1):
                valid_placements.append((str(item.id), str(gx), str(gy)))

    if not valid_placements:
        return [], [item.id for item in items], 0.0, "gamspy"

    PLACE = Set(m, name="PLACE", domain=[I, GX, GY], records=valid_placements)

    # Coverage: which placements cover each cell (cx, cy)
    covers_records: list[tuple[str, str, str, str, str]] = []
    for item in items:
        for gx in range(W - item.w + 1):
            for gy in range(H - item.h + 1):
                for cx in range(gx, gx + item.w):
                    for cy in range(gy, gy + item.h):
                        covers_records.append(
                            (str(item.id), str(gx), str(gy), str(cx), str(cy))
                        )

    CX = Set(m, name="CX", records=[str(v) for v in range(W)])
    CY = Set(m, name="CY", records=[str(v) for v in range(H)])
    COVERS = Set(
        m,
        name="COVERS",
        domain=[I, GX, GY, CX, CY],
        records=covers_records,
    )

    # ── Parameters ────────────────────────────────────────────────────────────
    total_cells = W * H
    area_records = pd.DataFrame({
        "I": [str(item.id) for item in items],
        "value": [item.w * item.h / (total_cells + 1) for item in items],
    })
    area_param = Parameter(m, name="area_param", domain=[I], records=area_records)

    # ── Variables ─────────────────────────────────────────────────────────────
    # x[i,gx,gy] = 1  →  item i placed with top-left corner at (gx, gy)
    x = Variable(m, name="x", type="binary", domain=[I, GX, GY])
    # y[i] = 1  →  item i is packed into this crate
    y = Variable(m, name="y", type="binary", domain=[I])

    # ── Equations ─────────────────────────────────────────────────────────────
    # Each item uses exactly one valid placement iff selected
    eq_once = Equation(m, name="eq_once", domain=[I])
    eq_once[I] = Sum((GX, GY), x[I, GX, GY].where[PLACE[I, GX, GY]]) == y[I]

    # No two items may cover the same cell
    eq_nooverlap = Equation(m, name="eq_nooverlap", domain=[CX, CY])
    eq_nooverlap[CX, CY] = (
        Sum(
            (I, GX, GY),
            x[I, GX, GY].where[COVERS[I, GX, GY, CX, CY]],
        )
        <= 1
    )

    # ── Objective ─────────────────────────────────────────────────────────────
    # Maximise items packed; break ties by maximising area used (area term < 1).
    obj_var = Variable(m, name="obj_var")
    obj_eq = Equation(m, name="obj_eq")
    obj_eq[...] = obj_var == Sum(I, y[I] + area_param[I] * y[I])

    model = Model(
        m,
        name="packing_mip",
        equations=m.getEquations(),
        problem="MIP",
        sense=Sense.MAX,
        objective=obj_var,
    )
    # Use at most 20% of remaining game time, between 2 and 15 seconds.
    solve_limit = max(2.0, min(time_remaining * 0.2, 15.0))
    try:
        from gamspy import Options
        model.solve(options=Options(time_limit=solve_limit))
    except Exception:
        model.solve()

    # ── Extract solution ───────────────────────────────────────────────────────
    packed: list[PackedItem] = []
    item_map = {str(item.id): item for item in items}

    if x.records is not None:
        placed_df = x.records[x.records["level"] > 0.5]
        for _, row in placed_df.iterrows():
            iid = str(int(float(row["I"])))
            gx = int(float(row["GX"]))
            gy = int(float(row["GY"]))
            item = item_map.get(iid)
            if item:
                packed.append(
                    PackedItem(
                        id=item.id,
                        type=item.type,
                        grid_x=gx,
                        grid_y=gy,
                        w=item.w,
                        h=item.h,
                        color=item.color,
                    )
                )

    packed_ids = {p.id for p in packed}
    rejected_ids = [item.id for item in items if item.id not in packed_ids]
    used_area = sum(p.w * p.h for p in packed)
    fill_ratio = used_area / (W * H) if W * H > 0 else 0.0
    return packed, rejected_ids, fill_ratio, "gamspy"


# ── Backtracking fallback ─────────────────────────────────────────────────────


def _can_place(grid: list[list[bool]], x: int, y: int, w: int, h: int) -> bool:
    height = len(grid)
    width = len(grid[0]) if grid else 0
    if x < 0 or y < 0 or w <= 0 or h <= 0:
        return False
    if x + w > width or y + h > height:
        return False
    for gy in range(y, y + h):
        for gx in range(x, x + w):
            if grid[gy][gx]:
                return False
    return True


def _set_cells(
    grid: list[list[bool]], x: int, y: int, w: int, h: int, value: bool
) -> None:
    for gy in range(y, y + h):
        for gx in range(x, x + w):
            grid[gy][gx] = value


def _solve_packing_backtrack(
    crate_size: list[int],
    items: list[PackingItem],
) -> tuple[list[PackedItem], list[int], float]:
    if len(crate_size) < 2:
        return [], [item.id for item in items], 0.0

    W = max(0, int(crate_size[0]))
    H = max(0, int(crate_size[1]))
    if W == 0 or H == 0 or not items:
        return [], [item.id for item in items], 0.0

    ordered = sorted(items, key=lambda i: (-i.w * i.h, -max(i.w, i.h), i.id))
    grid = [[False] * W for _ in range(H)]

    best_placements: list[PackedItem] = []
    best_count = 0
    best_area = 0
    current: list[PackedItem] = []

    def search(index: int, area_used: int) -> None:
        nonlocal best_placements, best_count, best_area

        selected = len(current)
        # Prune: can't beat best even if all remaining items are placed
        if selected + (len(ordered) - index) < best_count:
            return
        if index >= len(ordered):
            if selected > best_count or (selected == best_count and area_used > best_area):
                best_count = selected
                best_area = area_used
                best_placements = [PackedItem.model_validate(i.model_dump()) for i in current]
            return

        item = ordered[index]
        search(index + 1, area_used)

        for gy in range(0, H - item.h + 1):
            for gx in range(0, W - item.w + 1):
                if not _can_place(grid, gx, gy, item.w, item.h):
                    continue
                _set_cells(grid, gx, gy, item.w, item.h, True)
                current.append(
                    PackedItem(
                        id=item.id,
                        type=item.type,
                        grid_x=gx,
                        grid_y=gy,
                        w=item.w,
                        h=item.h,
                        color=item.color,
                    )
                )
                search(index + 1, area_used + item.w * item.h)
                current.pop()
                _set_cells(grid, gx, gy, item.w, item.h, False)

    search(0, 0)

    packed_ids = {p.id for p in best_placements}
    rejected_ids = [item.id for item in items if item.id not in packed_ids]
    fill_ratio = best_area / float(W * H) if W > 0 and H > 0 else 0.0
    return best_placements, rejected_ids, fill_ratio


# ── Public entry point ────────────────────────────────────────────────────────


def solve_packing(req: PackingRequest) -> PackingResponse:
    if len(req.crate_size) < 2:
        req.crate_size = [6, 6]

    W = max(1, int(req.crate_size[0]))
    H = max(1, int(req.crate_size[1]))
    crate_area = W * H
    crate_size = [W, H]

    packaging_cost_per_crate = _resolve_packaging_cost_per_crate(req)
    budget_before = _resolve_budget_remaining(req)
    max_affordable_crates: int | None = None
    if budget_before is not None and packaging_cost_per_crate > 0:
        max_affordable_crates = max(0, budget_before // packaging_cost_per_crate)

    impossible_ids = [item.id for item in req.items if item.w > W or item.h > H]
    impossible_id_set = set(impossible_ids)
    remaining_items = [item for item in req.items if item.id not in impossible_id_set]

    crates: list[PackedCrate] = []
    total_selected = 0
    total_used_area = 0
    solver_used = "gamspy-multicrate"

    while remaining_items:
        if max_affordable_crates is not None and len(crates) >= max_affordable_crates:
            break

        try:
            packed, _rejected_ids, crate_fill_ratio, _solver = _solve_packing_gamspy(
                crate_size,
                remaining_items,
                req.time_remaining,
            )
        except Exception as exc:
            logger.error("GaMSPy solver failed, falling back to backtrack: %s", exc, exc_info=True)
            packed, _rejected_ids, crate_fill_ratio = _solve_packing_backtrack(
                crate_size,
                remaining_items,
            )
            solver_used = "backtrack-multicrate"

        if not packed:
            break

        crate_index = len(crates)
        crate_items: list[PackedItem] = []
        for p in packed:
            crate_items.append(
                PackedItem(
                    id=p.id,
                    type=p.type,
                    grid_x=p.grid_x,
                    grid_y=p.grid_y,
                    w=p.w,
                    h=p.h,
                    crate_index=crate_index,
                    color=p.color,
                )
            )

        used_cells = sum(item.w * item.h for item in crate_items)
        crate = PackedCrate(
            crate_index=crate_index,
            selected_count=len(crate_items),
            used_cells=used_cells,
            unused_cells=max(0, crate_area - used_cells),
            fill_ratio=round(crate_fill_ratio, 4),
            packed_items=crate_items,
            matrix=_build_crate_matrix(crate_size, crate_items),
        )
        crates.append(crate)

        selected_ids = {item.id for item in crate_items}
        remaining_items = [item for item in remaining_items if item.id not in selected_ids]
        total_selected += len(crate_items)
        total_used_area += used_cells

    packed_items = [item for crate in crates for item in crate.packed_items]
    remaining_ids = [item.id for item in remaining_items]
    rejected_ids = sorted(set(impossible_ids + remaining_ids))

    crates_used = len(crates)
    total_capacity = crates_used * crate_area
    fill_ratio = (total_used_area / total_capacity) if total_capacity > 0 else 0.0
    unused_cells = max(0, total_capacity - total_used_area)

    packing_cost = crates_used * packaging_cost_per_crate

    return PackingResponse(
        crate_size=crate_size,
        selected_count=total_selected,
        unused_cells=unused_cells,
        fill_ratio=round(fill_ratio, 4),
        packed_items=packed_items,
        rejected_item_ids=rejected_ids,
        total_packing_cost=packing_cost,
        crates_used=crates_used,
        crates=crates,
        solver=solver_used,
    )

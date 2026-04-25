"""Machine placement optimiser for sequential stage processing.

Request uses only budget, time_remaining, and corpse_count. The optimiser picks
up to four machines for each stage. Stages are strictly sequential:
cutting -> assembly -> packaging.
"""

from __future__ import annotations

import logging
import math
from collections import Counter, defaultdict
from itertools import combinations_with_replacement

from constants import MACHINE_DEFS
from models import MachinePlacementRequest, MachinePlacementResponse, SlotAssignment

logger = logging.getLogger(__name__)

STAGES = ["cutting", "assembly", "packaging"]
MAX_MACHINES_PER_STAGE = 4


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _stage_rate(stage: str, machines: list[str]) -> float:
    # Speed values are interpreted as seconds per body for that stage.
    return sum(1.0 / max(float(MACHINE_DEFS[m][f"{stage}_speed"]), 1e-9) for m in machines)


def _stage_effective_time(stage: str, machines: list[str]) -> float:
    """Return effective seconds/body for a stage with parallel machines.

    If each machine speed is interpreted as seconds per body, then each machine
    contributes capacity of 1/speed body/sec. Parallel capacities add up; the
    effective stage time per body is the reciprocal of that sum.
    """
    stage_rate = _stage_rate(stage, machines)
    if stage_rate <= 0.0:
        return 0.0
    return 1.0 / stage_rate


def _pipeline_total_time(n_items: int, stage_assignments: dict[str, list[str]]) -> float:
    """Pipeline completion time for n items.

    Uses classical pipeline model:
      L = sum(stage_effective_times)
      B = max(stage_effective_times)
      T(n) = L + (n-1) * B for n >= 1, else 0
    """
    if n_items <= 0:
        return 0.0

    stage_times: list[float] = []
    for stage in STAGES:
        stage_time = _stage_effective_time(stage, stage_assignments.get(stage, []))
        if stage_time <= 0.0:
            return 0.0
        stage_times.append(stage_time)

    latency = sum(stage_times)
    bottleneck = max(stage_times)
    return latency + (n_items - 1) * bottleneck


def _items_from_time_limit(
    time_available: float,
    stage_assignments: dict[str, list[str]],
    max_items: int | None = None,
) -> int:
    """Max pipeline output under time budget.

    N = floor(1 + (T - L) / B), where:
      L = latency (sum of stage times)
      B = bottleneck (max stage time)
    """
    if time_available <= 0.0:
        return 0

    stage_times: list[float] = []
    for stage in STAGES:
        stage_time = _stage_effective_time(stage, stage_assignments.get(stage, []))
        if stage_time <= 0.0:
            return 0
        stage_times.append(stage_time)

    latency = sum(stage_times)
    bottleneck = max(stage_times)
    if bottleneck <= 0.0:
        return 0

    n_items = int(math.floor(1.0 + (time_available - latency) / bottleneck))
    n_items = max(0, n_items)
    if max_items is not None:
        n_items = min(n_items, max_items)
    return n_items


def _build_slot_assignments(stage_assignments: dict[str, list[str]]) -> list[SlotAssignment]:
    result: list[SlotAssignment] = []
    slot_index = 0
    for stage in STAGES:
        for machine in stage_assignments.get(stage, []):
            result.append(
                SlotAssignment(
                    slot_index=slot_index,
                    stage=stage,
                    machine=machine,
                    machine_cost=MACHINE_DEFS[machine]["cost"],
                )
            )
            slot_index += 1
    return result


def _evaluate_assignments(
    req: MachinePlacementRequest,
    stage_assignments: dict[str, list[str]],
) -> tuple[int, float, int]:
    machine_cost = sum(
        MACHINE_DEFS[m]["cost"]
        for stage in STAGES
        for m in stage_assignments.get(stage, [])
    )
    if machine_cost > req.budget:
        return 0, 0.0, machine_cost

    # No throughput until each stage has at least one machine.
    if any(len(stage_assignments.get(stage, [])) == 0 for stage in STAGES):
        return 0, 0.0, machine_cost

    n_proc = _items_from_time_limit(
        req.time_remaining,
        stage_assignments,
        max_items=req.corpse_count,
    )
    total_time = _pipeline_total_time(n_proc, stage_assignments)
    return n_proc, total_time, machine_cost


def _count_machines(stage_assignments: dict[str, list[str]]) -> int:
    return sum(len(stage_assignments.get(stage, [])) for stage in STAGES)


def _minimum_feasible_machine_cost() -> int:
    """Minimum budget required to place at least one machine per stage."""
    if not MACHINE_DEFS:
        return 0
    min_machine_cost = min(int(v["cost"]) for v in MACHINE_DEFS.values())
    return len(STAGES) * min_machine_cost


def _score_plan(n_proc: int, machine_cost: int, machine_count: int, total_time: float) -> float:
    # Lexicographic preference:
    # 1) maximize packages
    # 2) minimize machine cost
    # 3) minimize machine count
    # 4) minimize total processing time
    return 10_000_000.0 * n_proc - 1_000.0 * machine_cost - 100.0 * machine_count - total_time


def _build_response(
    req: MachinePlacementRequest,
    assignments: list[SlotAssignment],
    machine_cost: int,
    proc_time: float,
    n_proc: int,
    solver_name: str,
) -> MachinePlacementResponse:
    remaining = req.budget - machine_cost
    items_budget_limit = req.corpse_count if machine_cost <= req.budget else 0
    stage_assignments: dict[str, list[str]] = {s: [] for s in STAGES}
    for assignment in assignments:
        if assignment.stage in stage_assignments:
            stage_assignments[assignment.stage].append(assignment.machine)
    items_time_limit = _items_from_time_limit(req.time_remaining, stage_assignments)
    stage_machine_counts = {
        stage: dict(Counter(stage_assignments[stage])) for stage in STAGES
    }

    return MachinePlacementResponse(
        total_machine_cost=machine_cost,
        remaining_budget=remaining,
        stage_machine_counts=stage_machine_counts,
        stage_assignments=stage_assignments,
        slot_assignments=assignments,
        predicted_throughput=n_proc,
        total_packages_output=n_proc,
        items_budget_limit=items_budget_limit,
        items_time_limit=items_time_limit,
        items_processable=["Body"] * n_proc,
        total_processing_time=round(proc_time, 2),
        solver=solver_name,
    )


# ---------------------------------------------------------------------------
# Brute-force fallback
# ---------------------------------------------------------------------------

def _solve_brute(
    req: MachinePlacementRequest,
) -> tuple[list[SlotAssignment], int, float, int]:
    machine_names = list(MACHINE_DEFS.keys())
    stage_patterns: list[list[str]] = []
    for n in range(1, MAX_MACHINES_PER_STAGE + 1):
        for combo in combinations_with_replacement(machine_names, n):
            stage_patterns.append(list(combo))

    best_stage: dict[str, list[str]] = {s: [] for s in STAGES}
    best_n, best_time, best_cost = -1, float("inf"), float("inf")
    best_score = float("-inf")

    for cut in stage_patterns:
        for asm in stage_patterns:
            for pkg in stage_patterns:
                candidate = {"cutting": cut, "assembly": asm, "packaging": pkg}
                n_items, total_time, total_cost = _evaluate_assignments(req, candidate)
                machine_count = _count_machines(candidate)
                score = _score_plan(n_items, total_cost, machine_count, total_time)
                if score > best_score:
                    best_score = score
                    best_n, best_time, best_cost = n_items, total_time, total_cost
                    best_stage = candidate

    if best_n <= 0:
        return [], 0, 0.0, 0

    assignments = _build_slot_assignments(best_stage)
    return assignments, int(best_cost), best_time, best_n


# ---------------------------------------------------------------------------
# GAMSPy MIP
# ---------------------------------------------------------------------------

def _solve_gamspy(
    req: MachinePlacementRequest,
) -> tuple[list[SlotAssignment], int, float, int]:
    from gamspy import Container, Equation, Model, Parameter, Sense, Set, Sum, Variable

    slot_names = [f"slot_{i+1}" for i in range(MAX_MACHINES_PER_STAGE)]
    machine_names = list(MACHINE_DEFS.keys())
    n_max = req.corpse_count
    if n_max <= 0:
        return [], 0, 0.0, 0

    c = Container()

    S_set = Set(c, name="S", records=STAGES)
    K_set = Set(c, name="K", records=slot_names)
    M_set = Set(c, name="M", records=machine_names)

    # cost_m[m]: machine purchase cost
    cost_records = [(mn, float(MACHINE_DEFS[mn]["cost"])) for mn in machine_names]
    cost_param = Parameter(c, name="cost_m", domain=[M_set], records=cost_records)

    # rate[s,m]: processed items per second for one machine at stage s.
    rate_records = [
        (
            stage,
            mn,
            1.0 / max(float(MACHINE_DEFS[mn][f"{stage}_speed"]), 1e-9),
        )
        for stage in STAGES
        for mn in machine_names
    ]
    rate_param = Parameter(c, name="rate", domain=[S_set, M_set], records=rate_records)

    # Decision variables
    # x[s, k, m] = 1 if machine m is selected for stage s, slot k
    x = Variable(c, name="x", type="binary", domain=[S_set, K_set, M_set])
    # n_proc: integer number of completed packages
    n_proc = Variable(c, name="n_proc", type="integer")
    n_proc.lo[...] = 0
    n_proc.up[...] = n_max

    # Stage processing time allocations, enforcing sequential behaviour.
    t = Variable(c, name="t", type="positive", domain=[S_set])
    t.lo[S_set] = 0
    t.up[S_set] = req.time_remaining

    # Linearisation variable y[s,k,m] = t[s] * x[s,k,m]
    y = Variable(c, name="y", type="positive", domain=[S_set, K_set, M_set])
    y.lo[S_set, K_set, M_set] = 0
    y.up[S_set, K_set, M_set] = req.time_remaining

    # ── Constraints ──────────────────────────────────────────────────────────

    # 1. At most one machine per stage-slot (slot may stay empty).
    eq_slot = Equation(c, name="eq_slot", domain=[S_set, K_set])
    eq_slot[S_set, K_set] = Sum(M_set, x[S_set, K_set, M_set]) <= 1

    # 2. Budget: only machine purchase costs.
    eq_budget = Equation(c, name="eq_budget")
    eq_budget[...] = (
        Sum((S_set, K_set, M_set), cost_param[M_set] * x[S_set, K_set, M_set])
        <= req.budget
    )

    # 3. Total elapsed process time across sequential stages.
    eq_total_time = Equation(c, name="eq_total_time")
    eq_total_time[...] = Sum(S_set, t[S_set]) <= req.time_remaining

    # 4. Link y and x using McCormick (binary-continuous product).
    eq_y_ub_t = Equation(c, name="eq_y_ub_t", domain=[S_set, K_set, M_set])
    eq_y_ub_t[S_set, K_set, M_set] = y[S_set, K_set, M_set] <= t[S_set]

    eq_y_ub_x = Equation(c, name="eq_y_ub_x", domain=[S_set, K_set, M_set])
    eq_y_ub_x[S_set, K_set, M_set] = y[S_set, K_set, M_set] <= req.time_remaining * x[S_set, K_set, M_set]

    eq_y_lb = Equation(c, name="eq_y_lb", domain=[S_set, K_set, M_set])
    eq_y_lb[S_set, K_set, M_set] = y[S_set, K_set, M_set] >= t[S_set] - req.time_remaining * (1 - x[S_set, K_set, M_set])

    # 5. Stage capacity in allocated stage time.
    eq_stage_cap = Equation(c, name="eq_stage_cap", domain=[S_set])
    eq_stage_cap[S_set] = n_proc <= Sum(
        (K_set, M_set),
        rate_param[S_set, M_set] * y[S_set, K_set, M_set],
    )

    # 6. Queue bound (already enforced by n_proc.up, kept explicit)
    eq_queue = Equation(c, name="eq_queue")
    eq_queue[...] = n_proc <= req.corpse_count

    # ── Objective ─────────────────────────────────────────────────────────────
    # Maximise completed packages first, then minimise machine cost, machine count,
    # and finally total process time.
    obj_var = Variable(c, name="obj_var")
    obj_eq = Equation(c, name="obj_eq")
    machine_count_expr = Sum((S_set, K_set, M_set), x[S_set, K_set, M_set])
    obj_eq[...] = obj_var == 10_000_000.0 * n_proc - 1_000.0 * Sum(
        (S_set, K_set, M_set), cost_param[M_set] * x[S_set, K_set, M_set]
    ) - 100.0 * machine_count_expr - Sum(S_set, t[S_set])

    model = Model(
        c,
        name="machine_placement_mip",
        equations=c.getEquations(),
        problem="MIP",
        sense=Sense.MAX,
        objective=obj_var,
    )

    try:
        from gamspy import Options
        model.solve(options=Options(time_limit=10.0))
    except Exception:
        model.solve()

    # ── Extract solution ───────────────────────────────────────────────────────
    n_proc_val = 0
    if n_proc.records is not None and not n_proc.records.empty:
        try:
            n_proc_val = int(round(float(n_proc.records["level"].iloc[0])))
        except (KeyError, IndexError, ValueError):
            n_proc_val = 0

    stage_assignments: dict[str, list[str]] = defaultdict(list)
    if x.records is not None:
        chosen_df = x.records[x.records["level"] > 0.5]
        for _, row in chosen_df.iterrows():
            stage_assignments[str(row["S"])].append(str(row["M"]))

    for stage in STAGES:
        if stage not in stage_assignments:
            stage_assignments[stage] = []

    if any(len(stage_assignments[s]) == 0 for s in STAGES):
        return [], 0, 0.0, 0

    total_machine_cost = sum(
        MACHINE_DEFS[m]["cost"]
        for stage in STAGES
        for m in stage_assignments[stage]
    )
    total_proc_time = _pipeline_total_time(n_proc_val, stage_assignments)

    assignments = _build_slot_assignments(stage_assignments)

    return assignments, total_machine_cost, total_proc_time, n_proc_val


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def solve_machine_placement(req: MachinePlacementRequest) -> MachinePlacementResponse:
    if req.corpse_count <= 0:
        return MachinePlacementResponse(
            total_machine_cost=0,
            remaining_budget=req.budget,
            stage_machine_counts={s: {} for s in STAGES},
            stage_assignments={s: [] for s in STAGES},
            slot_assignments=[],
            predicted_throughput=0,
            total_packages_output=0,
            items_budget_limit=0,
            items_time_limit=0,
            items_processable=[],
            total_processing_time=0.0,
            solver="none",
        )

    # Infeasible budget: each sequential stage needs at least one machine.
    min_required_budget = _minimum_feasible_machine_cost()
    if req.budget < min_required_budget:
        return _build_response(req, [], 0, 0.0, 0, "infeasible-budget")

    # Infeasible time horizon.
    if req.time_remaining <= 0:
        return _build_response(req, [], 0, 0.0, 0, "infeasible-time")

    solver_name = "brute"
    try:
        assignments, machine_cost, proc_time, n_proc = _solve_brute(req)
        if not assignments:
            return _build_response(req, [], 0, 0.0, 0, "infeasible-no-plan")
    except Exception as exc:
        logger.error(
            "Brute-force machine placement failed, using GAMSPy fallback: %s", exc, exc_info=True
        )
        assignments, machine_cost, proc_time, n_proc = _solve_gamspy(req)
        solver_name = "gamspy"

    if not assignments:
        return _build_response(req, [], 0, 0.0, 0, "infeasible-no-plan")

    return _build_response(req, assignments, machine_cost, proc_time, n_proc, solver_name)

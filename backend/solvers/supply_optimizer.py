"""
Supply optimisation solver – GAMSPy MIP (greedy fallback).

Problem
-------
Given:
  - player budget
  - owned truck fleet (1 Small is free; player cannot buy more Smalls)
  - N forests, each with capacity, regen_rate, and distance to factory
  - time_remaining in the game session

Decide:
  - how many Medium / Large trucks to *purchase* within budget
  - which forest to assign each truck to

Objective: maximise total wood delivered to the factory with minimum spend.

Truck catalogue (must mirror TRUCK_DATA in supply_zone.gd)
-----------------------------------------------------------
  Small  – speed 300, capacity 2, cost   0   (1 free, CANNOT buy more)
  Medium – speed 200, capacity 4, cost 150
  Large  – speed 120, capacity 8, cost 250
"""

from __future__ import annotations

import logging

from constants import LOAD_TIME, UNLOAD_TIME
from models import ForestInput, SupplyAssignment, SupplyRequest, SupplyResponse

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Truck catalogue (mirrors TRUCK_DATA in supply_zone.gd)
# ---------------------------------------------------------------------------

TRUCK_TYPES: dict[str, dict] = {
    "Small":  {"speed": 300.0, "capacity": 2, "cost": 0},
    "Medium": {"speed": 200.0, "capacity": 4, "cost": 150},
    "Large":  {"speed": 120.0, "capacity": 8, "cost": 250},
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _round_trip_time(distance: float, speed: float) -> float:
    """Seconds for one factory ↔ forest ↔ factory trip."""
    return 2.0 * distance / max(speed, 0.1) + LOAD_TIME + UNLOAD_TIME


def _forest_available(forest: ForestInput, time_remaining: float) -> int:
    """Wood available in this forest for the remainder of the session."""
    return max(0, min(forest.capacity, int(forest.regen_rate * time_remaining)))


# ---------------------------------------------------------------------------
# GAMSPy MIP solver
# ---------------------------------------------------------------------------

def _solve_supply_gamspy(req: SupplyRequest) -> SupplyResponse:
    import pandas as pd
    from gamspy import Container, Equation, Model, Options, Parameter, Sense, Set, Sum, Variable

    trucks    = TRUCK_TYPES
    forests   = {f.name: f for f in req.forests}
    time_rem  = req.time_remaining
    budget    = req.budget
    all_types = list(trucks.keys())

    # How many of each type the player already owns (cannot increase for cost=0 types)
    owned_counts: dict[str, int] = {t: req.owned_trucks.get(t, 0) for t in trucks}
    # Types that have cost=0 are "owned-only" – buying more is forbidden
    owned_only: list[str] = [t for t, d in trucks.items() if d["cost"] == 0]

    # Pre-compute available wood per forest
    forest_avail: dict[str, int] = {
        fname: _forest_available(f, time_rem) for fname, f in forests.items()
    }

    # Pre-compute max trips a SINGLE truck of type t can make to forest f
    # This is a constant – it does NOT depend on any decision variable
    trips_tf: dict[str, dict[str, int]] = {}
    for t, tdata in trucks.items():
        trips_tf[t] = {}
        for fname, forest in forests.items():
            rt = _round_trip_time(forest.distance, tdata["speed"])
            trips_tf[t][fname] = int(time_rem // rt) if rt > 0 else 0

    # ── Build model ───────────────────────────────────────────────────────────
    m = Container()

    T = Set(m, name="T", records=all_types)
    F = Set(m, name="F", records=list(forests.keys()))

    cost_p = Parameter(
        m, name="cost_p", domain=[T],
        records=pd.DataFrame({
            "T":     all_types,
            "value": [trucks[t]["cost"] for t in all_types],
        }),
    )
    cap_p = Parameter(
        m, name="cap_p", domain=[T],
        records=pd.DataFrame({
            "T":     all_types,
            "value": [trucks[t]["capacity"] for t in all_types],
        }),
    )
    owned_p = Parameter(
        m, name="owned_p", domain=[T],
        records=pd.DataFrame({
            "T":     all_types,
            "value": [owned_counts[t] for t in all_types],
        }),
    )
    trips_p = Parameter(
        m, name="trips_p", domain=[T, F],
        records=pd.DataFrame([
            {"T": t, "F": fname, "value": trips_tf[t][fname]}
            for t in all_types for fname in forests
        ]),
    )
    avail_p = Parameter(
        m, name="avail_p", domain=[F],
        records=pd.DataFrame({
            "F":     list(forests.keys()),
            "value": [forest_avail[f] for f in forests],
        }),
    )

    # ── Decision variables ────────────────────────────────────────────────────
    # buy[T]     – additional trucks purchased; 0 for owned-only types (enforced via up-bound)
    # assign[T,F]– number of trucks of type T sent to forest F
    # wood[T,F]  – wood delivered by that (type, forest) group
    buy    = Variable(m, name="buy",    type="integer",  domain=[T])
    assign = Variable(m, name="assign", type="integer",  domain=[T, F])
    wood   = Variable(m, name="wood",   type="positive", domain=[T, F])

    buy.lo[T]       = 0
    assign.lo[T, F] = 0
    wood.lo[T, F]   = 0

    # Owned-only types (Small) cannot be bought – hard upper bound of 0
    for ot in owned_only:
        buy.up[ot] = 0

    # ── Constraints ───────────────────────────────────────────────────────────

    # 1. Purchase cost must not exceed budget
    eq_budget = Equation(m, name="eq_budget")
    eq_budget[...] = Sum(T, buy[T] * cost_p[T]) <= budget

    # 2. Trucks assigned to forests ≤ owned + purchased (per type)
    #    • Small:  0 + buy[Small]=0 → capped at owned_counts["Small"] (e.g. 1)
    #    • Medium/Large: owned_counts=0 by default, so capped at buy[t]
    eq_fleet = Equation(m, name="eq_fleet", domain=[T])
    eq_fleet[T] = Sum(F, assign[T, F]) <= owned_p[T] + buy[T]

    # 3. Wood moved ≤ assigned trucks × capacity × trips
    eq_wood_cap = Equation(m, name="eq_wood_cap", domain=[T, F])
    eq_wood_cap[T, F] = wood[T, F] <= assign[T, F] * cap_p[T] * trips_p[T, F]

    # 4. Wood taken from a forest ≤ what is available
    eq_forest = Equation(m, name="eq_forest", domain=[F])
    eq_forest[F] = Sum(T, wood[T, F]) <= avail_p[F]

    # ── Objective ────────────────────────────────────────────────────────────
    # Maximise wood delivered.
    # As a tiebreaker, prefer lower spending (penalty weight < 1/total_wood).
    max_possible_wood = max(sum(forest_avail.values()), 1)
    cost_penalty = 1.0 / ((budget + 1) * max_possible_wood)

    obj_var = Variable(m, name="obj_var")
    obj_eq  = Equation(m, name="obj_eq")
    obj_eq[...] = obj_var == (
        Sum((T, F), wood[T, F])
        - cost_penalty * Sum(T, buy[T] * cost_p[T])
    )

    model = Model(
        m,
        name="supply_mip",
        equations=m.getEquations(),
        problem="MIP",
        sense=Sense.MAX,
        objective=obj_var,
    )

    solve_limit = max(2.0, min(time_rem * 0.1, 10.0))
    try:
        model.solve(options=Options(time_limit=solve_limit))
    except Exception:
        model.solve()

    # ── Extract solution ───────────────────────────────────────────────────────
    trucks_to_buy: dict[str, int] = {t: 0 for t in trucks}
    if buy.records is not None:
        for _, row in buy.records.iterrows():
            trucks_to_buy[str(row["T"])] = max(0, int(round(float(row["level"]))))

    assign_map: dict[tuple[str, str], int] = {}
    if assign.records is not None:
        for _, row in assign.records.iterrows():
            assign_map[(str(row["T"]), str(row["F"]))] = max(0, int(round(float(row["level"]))))

    assignments: list[SupplyAssignment] = []
    if wood.records is not None:
        for _, row in wood.records.iterrows():
            t     = str(row["T"])
            fname = str(row["F"])
            w     = max(0, int(round(float(row["level"]))))
            a     = assign_map.get((t, fname), 0)
            if w > 0 or a > 0:
                assignments.append(
                    SupplyAssignment(
                        truck=t,
                        forest=fname,
                        assigned_count=a,
                        trips=trips_tf[t].get(fname, 0),
                        wood=w,
                    )
                )

    total_wood = sum(a.wood for a in assignments)
    total_cost = sum(trucks_to_buy[t] * trucks[t]["cost"] for t in trucks)

    return SupplyResponse(
        total_wood_delivered=total_wood,
        total_truck_cost=total_cost,
        trucks_to_buy=trucks_to_buy,
        assignments=assignments,
        solver="gamspy",
    )


# ---------------------------------------------------------------------------
# Greedy fallback (no external dependencies)
# ---------------------------------------------------------------------------

def _solve_supply_greedy(req: SupplyRequest) -> SupplyResponse:
    """
    Simple greedy fallback used when GAMSPy is unavailable.

    Strategy:
      1. Buy purchasable trucks (cost > 0) with best wood/cost ratio until budget runs out.
         Owned-only types (Small, cost=0) are NEVER added here.
      2. Assign each truck to the forest where it delivers the most wood,
         tracking forest depletion as trucks are assigned.
    """
    trucks   = TRUCK_TYPES
    forests  = {f.name: f for f in req.forests}
    time_rem = req.time_remaining

    # Start from owned counts; purchasable types default to 0
    owned: dict[str, int] = {t: req.owned_trucks.get(t, 0) for t in trucks}
    forest_avail: dict[str, int] = {
        fname: _forest_available(f, time_rem) for fname, f in forests.items()
    }

    def single_truck_wood(t: str, fname: str) -> int:
        tdata = trucks[t]
        rt = _round_trip_time(forests[fname].distance, tdata["speed"])
        if rt <= 0:
            return 0
        trips = int(time_rem // rt)
        return min(trips * tdata["capacity"], forest_avail[fname])

    # ── Step 1: purchase trucks (only those with cost > 0) ───────────────────
    trucks_to_buy: dict[str, int] = {t: 0 for t in trucks}
    budget_left = req.budget

    purchasable = [t for t, d in trucks.items() if d["cost"] > 0]
    purchasable.sort(
        key=lambda t: (
            max((single_truck_wood(t, fn) for fn in forests), default=0) / trucks[t]["cost"]
        ),
        reverse=True,
    )

    for t in purchasable:
        cost = trucks[t]["cost"]
        while budget_left >= cost:
            best = max((single_truck_wood(t, fn) for fn in forests), default=0)
            if best == 0:
                break
            trucks_to_buy[t] += 1
            owned[t] += 1
            budget_left -= cost

    # ── Step 2: assign trucks to forests ─────────────────────────────────────
    assignments: list[SupplyAssignment] = []

    for t in trucks:
        total_owned = owned.get(t, 0)
        if total_owned <= 0:
            continue

        remaining = total_owned
        sorted_forests = sorted(forests.keys(), key=lambda fn: -single_truck_wood(t, fn))

        for fname in sorted_forests:
            if remaining <= 0:
                break
            w = single_truck_wood(t, fname)
            if w <= 0:
                continue
            actual_wood = min(w, forest_avail[fname])
            if actual_wood <= 0:
                continue

            tdata = trucks[t]
            rt = _round_trip_time(forests[fname].distance, tdata["speed"])
            trips = int(time_rem // rt) if rt > 0 else 0

            forest_avail[fname] = max(0, forest_avail[fname] - actual_wood)
            assignments.append(
                SupplyAssignment(
                    truck=t,
                    forest=fname,
                    assigned_count=1,
                    trips=trips,
                    wood=actual_wood,
                )
            )
            remaining -= 1

    total_wood = sum(a.wood for a in assignments)
    total_cost = sum(trucks_to_buy[t] * trucks[t]["cost"] for t in trucks)

    return SupplyResponse(
        total_wood_delivered=total_wood,
        total_truck_cost=total_cost,
        trucks_to_buy=trucks_to_buy,
        assignments=assignments,
        solver="greedy-fallback",
    )


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def solve_supply(req: SupplyRequest) -> SupplyResponse:
    try:
        return _solve_supply_gamspy(req)
    except Exception as exc:
        logger.error(
            "GAMSPy supply solver failed, falling back to greedy: %s", exc, exc_info=True
        )
        return _solve_supply_greedy(req)

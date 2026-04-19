import math
from time import perf_counter

from constants import LOAD_TIME, UNLOAD_TIME
from models import Forest, TransportRequest, TransportResponse, TruckAssignment

TRUCK_DATA: dict[str, dict[str, float | int]] = {
    "Small": {"speed": 300.0, "capacity": 2, "cost": 0},
    "Medium": {"speed": 200.0, "capacity": 4, "cost": 150},
    "Large": {"speed": 120.0, "capacity": 8, "cost": 250},
}


def _build_truck_catalog(req: TransportRequest) -> dict[str, dict[str, float | int]]:
    catalog: dict[str, dict[str, float | int]] = {
        "Small": dict(TRUCK_DATA["Small"]),
    }

    # Request only needs purchasable types. If missing, fall back to defaults.
    for truck in req.trucks:
        if truck.type not in ("Medium", "Large"):
            continue
        default_cost = int(TRUCK_DATA.get(truck.type, {}).get("cost", 0))
        catalog[truck.type] = {
            "speed": float(truck.speed),
            "capacity": int(truck.capacity),
            "cost": int(truck.cost) if truck.cost > 0 else default_cost,
        }

    for t in ("Medium", "Large"):
        if t not in catalog:
            catalog[t] = dict(TRUCK_DATA[t])

    return catalog


def _distance(a: list[float], b: list[float]) -> float:
    return math.dist(a, b)


def _round_trip_time(forest: Forest, factory_position: list[float], speed: float) -> float:
    return 2 * _distance(forest.position, factory_position) / max(speed, 0.1) + LOAD_TIME + UNLOAD_TIME


def _available_wood(req: TransportRequest) -> dict[str, int]:
    return {
        forest.name: min(
            forest.capacity,
            max(
                0,
                (forest.current_stock if forest.current_stock is not None else forest.capacity)
                + int(req.time_remaining // max(forest.regen_rate, 0.1)),
            ),
        )
        for forest in req.forests
    }


def _solve_with_fleet(
    req: TransportRequest,
    fleet: dict[str, int],
    truck_catalog: dict[str, dict[str, float | int]],
    remaining_wood_seed: dict[str, int],
) -> tuple[int, list[TruckAssignment]]:
    remaining_wood = dict(remaining_wood_seed)
    assignments: list[TruckAssignment] = []

    for truck_type in ("Small", "Medium", "Large"):
        count = max(0, int(fleet.get(truck_type, 0)))
        if count <= 0:
            continue

        speed = float(truck_catalog[truck_type]["speed"])
        capacity = int(truck_catalog[truck_type]["capacity"])

        for _ in range(count):
            best_forest: Forest | None = None
            best_score = 0.0
            best_trips = 0
            best_wood = 0

            for forest in req.forests:
                round_trip = _round_trip_time(forest, req.factory_position, speed)
                if round_trip <= 0:
                    continue

                trips = int(req.time_remaining // round_trip)
                if trips <= 0:
                    continue

                stock_left = remaining_wood.get(forest.name, 0)
                wood_per_trip = min(capacity, stock_left)
                if wood_per_trip <= 0:
                    continue

                total_wood = min(trips * wood_per_trip, stock_left)
                actual_trips = math.ceil(total_wood / wood_per_trip) if wood_per_trip > 0 else 0
                score = total_wood / (actual_trips * round_trip) if actual_trips > 0 else 0.0

                if score > best_score:
                    best_score = score
                    best_forest = forest
                    best_trips = actual_trips
                    best_wood = total_wood

            if best_forest is not None and best_wood > 0:
                remaining_wood[best_forest.name] = max(0, remaining_wood[best_forest.name] - best_wood)
                assignments.append(
                    TruckAssignment(
                        truck=truck_type,
                        forest=best_forest.name,
                        trips=best_trips,
                        wood=best_wood,
                    )
                )

    total_wood = sum(a.wood for a in assignments)
    return total_wood, assignments


def _bruteforce_purchase_and_assign(
    req: TransportRequest,
    truck_catalog: dict[str, dict[str, float | int]],
    remaining_wood: dict[str, int],
) -> tuple[int, int, dict[str, int], list[TruckAssignment], list[TruckAssignment], str]:
    budget = max(0, int(req.budget))
    owned_small = max(1, int(req.owned_trucks.get("Small", 1)))

    max_medium = budget // int(truck_catalog["Medium"]["cost"])
    max_large = budget // int(truck_catalog["Large"]["cost"])

    best_wood = -1
    best_cost = 0
    best_buy = {"Small": 0, "Medium": 0, "Large": 0}
    best_assignments: list[TruckAssignment] = []
    best_purchased_assignments: list[TruckAssignment] = []

    for medium_to_buy in range(max_medium + 1):
        for large_to_buy in range(max_large + 1):
            total_cost = medium_to_buy * int(truck_catalog["Medium"]["cost"]) + large_to_buy * int(truck_catalog["Large"]["cost"])
            if total_cost > budget:
                continue

            fleet = {
                "Small": owned_small,
                "Medium": medium_to_buy,
                "Large": large_to_buy,
            }

            total_wood, assignments = _solve_with_fleet(req, fleet, truck_catalog, remaining_wood)
            if total_wood > best_wood or (total_wood == best_wood and total_cost < best_cost):
                best_wood = total_wood
                best_cost = total_cost
                best_buy = {"Small": 0, "Medium": medium_to_buy, "Large": large_to_buy}
                best_assignments = assignments
                best_purchased_assignments = [a for a in assignments if a.truck in ("Medium", "Large")]

    if best_wood < 0:
        best_wood = 0

    note = "Selected minimum-cost fleet among max-wood plans."
    if best_buy["Medium"] + best_buy["Large"] <= 1:
        note = "Only one purchasable truck was enough to saturate reachable wood/time constraints."

    return best_wood, best_cost, best_buy, best_assignments, best_purchased_assignments, note


def _gamspy_purchase_and_assign(
    req: TransportRequest,
    truck_catalog: dict[str, dict[str, float | int]],
    remaining_wood: dict[str, int],
) -> tuple[int, int, dict[str, int], list[TruckAssignment], list[TruckAssignment], str]:
    import pandas as pd
    from gamspy import Container, Equation, Model, Options, Parameter, Sense, Set, Sum, Variable

    budget = max(0, int(req.budget))
    owned_small = max(1, int(req.owned_trucks.get("Small", 1)))
    truck_types = ["Small", "Medium", "Large"]

    forest_by_name = {f.name: f for f in req.forests}
    forest_names = list(forest_by_name.keys())

    trips_tf: dict[str, dict[str, int]] = {t: {} for t in truck_types}
    for t in truck_types:
        speed = float(truck_catalog[t]["speed"])
        for fname in forest_names:
            rt = _round_trip_time(forest_by_name[fname], req.factory_position, speed)
            trips_tf[t][fname] = int(req.time_remaining // rt) if rt > 0 else 0

    m = Container()
    T = Set(m, name="T", records=truck_types)
    F = Set(m, name="F", records=forest_names)

    cost_p = Parameter(
        m,
        name="cost_p",
        domain=[T],
        records=pd.DataFrame({"T": truck_types, "value": [int(truck_catalog[t]["cost"]) for t in truck_types]}),
    )
    cap_p = Parameter(
        m,
        name="cap_p",
        domain=[T],
        records=pd.DataFrame({"T": truck_types, "value": [int(truck_catalog[t]["capacity"]) for t in truck_types]}),
    )
    owned_p = Parameter(
        m,
        name="owned_p",
        domain=[T],
        records=pd.DataFrame({"T": truck_types, "value": [owned_small, 0, 0]}),
    )
    trips_p = Parameter(
        m,
        name="trips_p",
        domain=[T, F],
        records=pd.DataFrame([
            {"T": t, "F": fname, "value": trips_tf[t][fname]}
            for t in truck_types
            for fname in forest_names
        ]),
    )
    avail_p = Parameter(
        m,
        name="avail_p",
        domain=[F],
        records=pd.DataFrame({"F": forest_names, "value": [remaining_wood[f] for f in forest_names]}),
    )

    buy = Variable(m, name="buy", type="integer", domain=[T])
    assign = Variable(m, name="assign", type="integer", domain=[T, F])
    wood = Variable(m, name="wood", type="positive", domain=[T, F])

    buy.lo[T] = 0
    assign.lo[T, F] = 0
    wood.lo[T, F] = 0
    buy.up["Small"] = 0

    eq_budget = Equation(m, name="eq_budget")
    eq_budget[...] = Sum(T, buy[T] * cost_p[T]) <= budget

    eq_fleet = Equation(m, name="eq_fleet", domain=[T])
    eq_fleet[T] = Sum(F, assign[T, F]) <= owned_p[T] + buy[T]

    eq_wood_cap = Equation(m, name="eq_wood_cap", domain=[T, F])
    eq_wood_cap[T, F] = wood[T, F] <= assign[T, F] * cap_p[T] * trips_p[T, F]

    eq_forest = Equation(m, name="eq_forest", domain=[F])
    eq_forest[F] = Sum(T, wood[T, F]) <= avail_p[F]

    max_possible_wood = max(sum(remaining_wood.values()), 1)
    cost_penalty = 1.0 / ((budget + 1) * max_possible_wood)

    obj_var = Variable(m, name="obj_var")
    obj_eq = Equation(m, name="obj_eq")
    obj_eq[...] = obj_var == Sum((T, F), wood[T, F]) - cost_penalty * Sum(T, buy[T] * cost_p[T])

    model = Model(
        m,
        name="transport_mip",
        equations=m.getEquations(),
        problem="MIP",
        sense=Sense.MAX,
        objective=obj_var,
    )
    model.solve(options=Options(time_limit=max(2.0, min(req.time_remaining * 0.1, 10.0))))

    trucks_to_buy = {"Small": 0, "Medium": 0, "Large": 0}
    if buy.records is not None:
        for _, row in buy.records.iterrows():
            t = str(row["T"])
            trucks_to_buy[t] = max(0, int(round(float(row["level"]))))

    assign_count: dict[tuple[str, str], int] = {}
    if assign.records is not None:
        for _, row in assign.records.iterrows():
            t = str(row["T"])
            f = str(row["F"])
            assign_count[(t, f)] = max(0, int(round(float(row["level"]))))

    assignments: list[TruckAssignment] = []
    if wood.records is not None:
        for _, row in wood.records.iterrows():
            t = str(row["T"])
            fname = str(row["F"])
            wood_total = max(0, int(round(float(row["level"]))))
            count = assign_count.get((t, fname), 0)
            if wood_total <= 0 or count <= 0:
                continue
            per_truck_wood = max(1, wood_total // count)
            trips = trips_tf[t][fname]
            for i in range(count):
                this_wood = per_truck_wood if i < count - 1 else max(0, wood_total - per_truck_wood * (count - 1))
                assignments.append(
                    TruckAssignment(
                        truck=t,
                        forest=fname,
                        trips=trips,
                        wood=this_wood,
                    )
                )

    purchased_assignments = [a for a in assignments if a.truck in ("Medium", "Large")]
    total_wood = sum(a.wood for a in assignments)
    total_cost = (
        trucks_to_buy["Medium"] * int(truck_catalog["Medium"]["cost"])
        + trucks_to_buy["Large"] * int(truck_catalog["Large"]["cost"])
    )

    note = "GAMSPy MIP solved purchase+assignment jointly with budget and forest caps."
    if trucks_to_buy["Medium"] + trucks_to_buy["Large"] <= 1:
        note = "GAMSPy found that buying more trucks does not increase delivered wood under time/wood constraints."

    return total_wood, total_cost, trucks_to_buy, assignments, purchased_assignments, note


def solve_transport(req: TransportRequest) -> TransportResponse:
    started = perf_counter()
    if not req.forests:
        return TransportResponse(
            optimal_wood_delivered=0,
            assignments=[],
            purchased_assignments=[],
            total_truck_cost=0,
            trucks_to_buy={"Small": 0, "Medium": 0, "Large": 0},
            solve_time_ms=(perf_counter() - started) * 1000.0,
            solver="none",
            purchase_decision_note="No forests provided.",
        )

    truck_catalog = _build_truck_catalog(req)
    remaining_wood = _available_wood(req)

    solver_used = "gamspy"
    try:
        best_wood, best_cost, best_buy, best_assignments, best_purchased_assignments, note = _gamspy_purchase_and_assign(
            req, truck_catalog, remaining_wood
        )
    except Exception:
        solver_used = "bruteforce"
        best_wood, best_cost, best_buy, best_assignments, best_purchased_assignments, note = _bruteforce_purchase_and_assign(
            req, truck_catalog, remaining_wood
        )

    return TransportResponse(
        optimal_wood_delivered=best_wood,
        assignments=best_assignments,
        purchased_assignments=best_purchased_assignments,
        total_truck_cost=best_cost,
        trucks_to_buy=best_buy,
        solve_time_ms=(perf_counter() - started) * 1000.0,
        solver=solver_used,
        purchase_decision_note=note,
    )

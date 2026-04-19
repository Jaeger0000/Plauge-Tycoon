from __future__ import annotations

import logging
import math
from itertools import permutations

from constants import LOAD_TIME, UNLOAD_TIME
from models import RouteTrip, Shop, TSPRequest, TSPResponse

logger = logging.getLogger(__name__)

DEPOT_NAME = "Depot"


def _distance(a: list[float], b: list[float]) -> float:
    return math.dist(a, b)


def _resolve_start_load(req: TSPRequest) -> int:
    if req.truck_load is not None and req.truck_load > 0:
        return max(0, int(req.truck_load))
    return max(0, int(req.available_crates))


def _resolve_trip_load(req: TSPRequest, initial_load: int, elapsed_time: float, total_demand: int) -> int:
    if total_demand <= 0:
        return 0
    restocked = initial_load + int(max(0.0, elapsed_time) * max(0.0, req.depot_restock_rate))
    return max(0, min(total_demand, restocked))


def _city_map(shops: list[Shop]) -> dict[str, Shop]:
    return {shop.name: shop for shop in shops if shop.demand > 0}


def _build_distance_lookup(req: TSPRequest, cities: list[Shop]) -> dict[tuple[str, str], float]:
    node_names = [DEPOT_NAME] + [city.name for city in cities]
    expected_size = len(node_names)

    if req.distance_matrix is not None:
        matrix = req.distance_matrix
        if len(matrix) == expected_size and all(len(row) == expected_size for row in matrix):
            lookup: dict[tuple[str, str], float] = {}
            for i, from_name in enumerate(node_names):
                for j, to_name in enumerate(node_names):
                    lookup[(from_name, to_name)] = max(0.0, float(matrix[i][j]))
            return lookup
        if len(matrix) == len(cities) and all(len(row) == len(cities) for row in matrix):
            lookup = {}
            points: dict[str, list[float]] = {DEPOT_NAME: req.depot}
            for city in cities:
                points[city.name] = city.position

            for city in cities:
                lookup[(DEPOT_NAME, city.name)] = _distance(points[DEPOT_NAME], points[city.name])
                lookup[(city.name, DEPOT_NAME)] = _distance(points[city.name], points[DEPOT_NAME])

            for i, from_city in enumerate(cities):
                for j, to_city in enumerate(cities):
                    lookup[(from_city.name, to_city.name)] = max(0.0, float(matrix[i][j]))

            lookup[(DEPOT_NAME, DEPOT_NAME)] = 0.0
            return lookup

    lookup: dict[tuple[str, str], float] = {}
    points: dict[str, list[float]] = {DEPOT_NAME: req.depot}
    for city in cities:
        points[city.name] = city.position

    for from_name in node_names:
        for to_name in node_names:
            lookup[(from_name, to_name)] = _distance(points[from_name], points[to_name])

    return lookup


def _route_distance(route: list[str], distance_lookup: dict[tuple[str, str], float]) -> float:
    total = 0.0
    for i in range(len(route) - 1):
        total += distance_lookup[(route[i], route[i + 1])]
    return total


def _route_time(distance: float, visited_count: int, truck_speed: float) -> float:
    return distance / max(truck_speed, 0.1) + LOAD_TIME + visited_count * UNLOAD_TIME


def _simulate_order(
    order: list[Shop],
    city_map: dict[str, Shop],
    distance_lookup: dict[tuple[str, str], float],
    load_limit: int,
    time_limit: float,
    truck_speed: float,
) -> tuple[list[str], dict[str, int], float, float, int] | None:
    remaining_load = max(0, load_limit)
    if remaining_load <= 0 or time_limit <= 0.0:
        return None

    route: list[str] = [DEPOT_NAME]
    delivered: dict[str, int] = {name: 0 for name in city_map}
    current_name = DEPOT_NAME
    route_distance = 0.0
    visited_count = 0

    for city in order:
        if remaining_load <= 0:
            break

        demand_left = max(0, city_map.get(city.name, city).demand - delivered.get(city.name, 0))
        if demand_left <= 0:
            continue

        deliver_here = min(demand_left, remaining_load)
        if deliver_here <= 0:
            continue

        candidate_distance = route_distance + distance_lookup[(current_name, city.name)]
        candidate_visited = visited_count + 1
        candidate_total_distance = candidate_distance + distance_lookup[(city.name, DEPOT_NAME)]
        candidate_time = _route_time(candidate_total_distance, candidate_visited, truck_speed)

        if candidate_time > time_limit + 1e-9:
            continue

        route.append(city.name)
        delivered[city.name] = delivered.get(city.name, 0) + deliver_here
        remaining_load -= deliver_here
        current_name = city.name
        route_distance = candidate_distance
        visited_count = candidate_visited

    if len(route) == 1:
        return None

    route.append(DEPOT_NAME)
    final_distance = _route_distance(route, distance_lookup)
    final_time = _route_time(final_distance, visited_count, truck_speed)
    total_delivered = sum(delivered.values())
    if total_delivered <= 0:
        return None

    return route, delivered, final_distance, final_time, total_delivered


def _solve_single_trip_exact(
    cities: list[Shop],
    city_map: dict[str, Shop],
    distance_lookup: dict[tuple[str, str], float],
    load_limit: int,
    time_limit: float,
    truck_speed: float,
) -> tuple[list[str], dict[str, int], float, float, int] | None:
    best: tuple[list[str], dict[str, int], float, float, int] | None = None
    best_distance = float("inf")
    best_delivered = -1

    for order in permutations(cities):
        candidate = _simulate_order(list(order), city_map, distance_lookup, load_limit, time_limit, truck_speed)
        if candidate is None:
            continue

        route, delivered, distance, time_used, total_delivered = candidate
        if total_delivered > best_delivered or (
            total_delivered == best_delivered and distance < best_distance
        ):
            best = (route, delivered, distance, time_used, total_delivered)
            best_distance = distance
            best_delivered = total_delivered

    return best


def _solve_single_trip_greedy(
    cities: list[Shop],
    city_map: dict[str, Shop],
    distance_lookup: dict[tuple[str, str], float],
    load_limit: int,
    time_limit: float,
    truck_speed: float,
) -> tuple[list[str], dict[str, int], float, float, int] | None:
    remaining = cities[:]
    ordered: list[Shop] = []
    current_name = DEPOT_NAME
    current_distance = 0.0
    visited_count = 0
    remaining_load = max(0, load_limit)

    while remaining and remaining_load > 0:
        best_city: Shop | None = None
        best_key: tuple[float, float, float] | None = None

        for city in remaining:
            demand_left = max(0, city_map.get(city.name, city).demand)
            if demand_left <= 0:
                continue

            deliver_here = min(demand_left, remaining_load)
            if deliver_here <= 0:
                continue

            candidate_distance = current_distance + distance_lookup[(current_name, city.name)]
            candidate_total_distance = candidate_distance + distance_lookup[(city.name, DEPOT_NAME)]
            candidate_time = _route_time(candidate_total_distance, visited_count + 1, truck_speed)
            if candidate_time > time_limit + 1e-9:
                continue

            incremental_distance = distance_lookup[(current_name, city.name)]
            key = (
                candidate_time,
                incremental_distance / max(deliver_here, 1),
                incremental_distance,
            )
            if best_key is None or key < best_key:
                best_key = key
                best_city = city

        if best_city is None:
            break

        ordered.append(best_city)
        current_distance += distance_lookup[(current_name, best_city.name)]
        current_name = best_city.name
        visited_count += 1
        remaining_load -= min(max(0, city_map[best_city.name].demand), remaining_load)
        remaining.remove(best_city)

    return _simulate_order(ordered, city_map, distance_lookup, load_limit, time_limit, truck_speed)


def _solve_single_trip_gamspy(
    cities: list[Shop],
    city_map: dict[str, Shop],
    distance_lookup: dict[tuple[str, str], float],
    load_limit: int,
    time_limit: float,
    truck_speed: float,
) -> tuple[list[str], dict[str, int], float, float, int] | None:
    import pandas as pd

    try:
        from gamspy import Container, Equation, Model, Options, Parameter, Sense, Set, Sum, Variable
    except Exception as exc:
        logger.debug("GAMSPy import failed for TSP solver: %s", exc)
        return None

    if not cities or load_limit <= 0 or time_limit <= 0.0:
        return None

    node_names = [DEPOT_NAME] + [city.name for city in cities]
    city_names = [city.name for city in cities]

    m = Container()

    N = Set(m, name="N", records=node_names)
    C = Set(m, name="C", records=city_names)
    CI = Set(m, name="CI", records=city_names)
    CJ = Set(m, name="CJ", records=city_names)
    D = Set(m, name="D", records=[DEPOT_NAME])

    distance_records = [
        (from_name, to_name, float(distance_lookup[(from_name, to_name)]))
        for from_name in node_names
        for to_name in node_names
    ]
    dist = Parameter(m, name="dist", domain=[N, N], records=distance_records)

    demand_records = [(city.name, float(city_map[city.name].demand)) for city in cities]
    demand = Parameter(m, name="demand", domain=[C], records=demand_records)

    x = Variable(m, name="x", type="binary", domain=[N, N])
    y = Variable(m, name="y", type="binary", domain=[C])
    delivered = Variable(m, name="delivered", type="integer", domain=[C])
    u = Variable(m, name="u", type="positive", domain=[C])

    x.lo[N, N] = 0
    y.lo[C] = 0
    delivered.lo[C] = 0
    u.lo[C] = 0
    u.up[C] = float(len(cities))
    for city_name in city_names:
        delivered.up[city_name] = city_map[city_name].demand

    eq_no_self = Equation(m, name="eq_no_self", domain=[N])
    eq_no_self[N] = x[N, N] == 0

    eq_depot_out = Equation(m, name="eq_depot_out")
    eq_depot_out[...] = Sum(N, x[D, N]) == 1

    eq_depot_in = Equation(m, name="eq_depot_in")
    eq_depot_in[...] = Sum(N, x[N, D]) == 1

    eq_city_out = Equation(m, name="eq_city_out", domain=[C])
    eq_city_out[C] = Sum(N, x[C, N]) == y[C]

    eq_city_in = Equation(m, name="eq_city_in", domain=[C])
    eq_city_in[C] = Sum(N, x[N, C]) == y[C]

    eq_deliver_link = Equation(m, name="eq_deliver_link", domain=[C])
    eq_deliver_link[C] = delivered[C] <= demand[C] * y[C]

    eq_capacity = Equation(m, name="eq_capacity")
    eq_capacity[...] = Sum(C, delivered[C]) <= load_limit

    eq_order_lower = Equation(m, name="eq_order_lower", domain=[C])
    eq_order_lower[C] = u[C] >= y[C]

    eq_order_upper = Equation(m, name="eq_order_upper", domain=[C])
    eq_order_upper[C] = u[C] <= float(len(cities)) * y[C]

    eq_mtz = Equation(m, name="eq_mtz", domain=[CI, CJ])
    eq_mtz[CI, CJ] = u[CI] - u[CJ] + float(len(cities)) * x[CI, CJ] <= float(len(cities)) - 1.0

    route_distance = Sum((N, N), dist[N, N] * x[N, N])
    route_time = route_distance / max(truck_speed, 0.1) + LOAD_TIME + UNLOAD_TIME * Sum(C, y[C])

    eq_time = Equation(m, name="eq_time")
    eq_time[...] = route_time <= time_limit

    obj_var = Variable(m, name="obj_var")
    obj_eq = Equation(m, name="obj_eq")
    obj_eq[...] = obj_var == (
        1_000_000.0 * Sum(C, delivered[C])
        - 1_000.0 * route_distance
        - 10.0 * Sum(C, y[C])
    )

    model = Model(
        m,
        name="distribution_tsp_trip_mip",
        equations=m.getEquations(),
        problem="MIP",
        sense=Sense.MAX,
        objective=obj_var,
    )

    try:
        model.solve(options=Options(time_limit=max(1.0, min(float(time_limit), 15.0))))
    except Exception:
        model.solve()

    delivered_map: dict[str, int] = {name: 0 for name in city_names}
    if delivered.records is not None:
        value_columns = [column for column in delivered.records.columns if column != "level"]
        key_column = value_columns[0] if value_columns else None
        for _, row in delivered.records.iterrows():
            if key_column is None:
                continue
            name = str(row[key_column])
            delivered_map[name] = max(0, int(round(float(row["level"]))))

    chosen_arcs: dict[str, str] = {}
    if x.records is not None:
        index_columns = [column for column in x.records.columns if column != "level"]
        if len(index_columns) < 2:
            return None
        chosen_df = x.records[x.records["level"] > 0.5]
        for _, row in chosen_df.iterrows():
            from_name = str(row[index_columns[0]])
            to_name = str(row[index_columns[1]])
            chosen_arcs[from_name] = to_name

    route: list[str] = [DEPOT_NAME]
    current = DEPOT_NAME
    visited_guard: set[str] = set()
    while current in chosen_arcs:
        nxt = chosen_arcs[current]
        route.append(nxt)
        if nxt == DEPOT_NAME:
            break
        if nxt in visited_guard:
            break
        visited_guard.add(nxt)
        current = nxt

    if route[-1] != DEPOT_NAME:
        route.append(DEPOT_NAME)

    total_delivered = sum(delivered_map.values())
    if total_delivered <= 0:
        return None

    total_distance = _route_distance(route, distance_lookup)
    total_time = _route_time(total_distance, max(0, len(route) - 2), truck_speed)

    return route, delivered_map, total_distance, total_time, total_delivered


def _solve_repeated_trips(
    req: TSPRequest,
    use_gamspy: bool,
) -> TSPResponse:
    cities = [city for city in req.shops if city.demand > 0]
    if not cities:
        return TSPResponse(
            optimal_distance=0.0,
            optimal_route=[DEPOT_NAME, DEPOT_NAME],
            optimal_deliveries=0,
            trip_routes=[],
            trip_count=0,
            total_time_used=0.0,
            city_deliveries={},
            solver="none",
        )

    city_map = _city_map(cities)
    distance_lookup = _build_distance_lookup(req, cities)
    remaining_demands = {city.name: city.demand for city in cities}
    initial_load = _resolve_start_load(req)
    remaining_time = float(req.time_remaining)
    truck_speed = float(req.truck_speed)
    elapsed_time = 0.0

    trip_models: list[RouteTrip] = []
    trip_delivery_maps: list[dict[str, int]] = []
    flat_route: list[str] = []
    total_distance = 0.0
    total_time_used = 0.0
    total_delivered = 0

    solver_name = "gamspy" if use_gamspy else "greedy"

    while remaining_time > 0.0 and any(value > 0 for value in remaining_demands.values()):
        trip_load = _resolve_trip_load(
            req,
            initial_load,
            elapsed_time,
            sum(remaining_demands.values()),
        )
        if trip_load <= 0:
            break

        remaining_cities = [
            Shop(name=name, position=city_map[name].position, demand=remaining_demands[name])
            for name in city_map
            if remaining_demands.get(name, 0) > 0
        ]

        if not remaining_cities:
            break

        trip_result = None
        if use_gamspy:
            trip_result = _solve_single_trip_gamspy(
                remaining_cities,
                city_map,
                distance_lookup,
                trip_load,
                remaining_time,
                truck_speed,
            )

        if trip_result is None:
            trip_result = _solve_single_trip_exact(
                remaining_cities,
                city_map,
                distance_lookup,
                trip_load,
                remaining_time,
                truck_speed,
            )
            if trip_result is None:
                trip_result = _solve_single_trip_greedy(
                    remaining_cities,
                    city_map,
                    distance_lookup,
                    trip_load,
                    remaining_time,
                    truck_speed,
                )
                solver_name = "greedy"

        if trip_result is None:
            break

        route, delivered_map, distance, time_used, delivered_count = trip_result
        if delivered_count <= 0 or len(route) < 2:
            break

        trip_models.append(
            RouteTrip(
                route=route,
                distance=round(distance, 1),
                time_used=round(time_used, 1),
                delivered=delivered_count,
            )
        )
        trip_delivery_maps.append(delivered_map)

        if not flat_route:
            flat_route.extend(route)
        else:
            flat_route.extend(route[1:])

        for city_name, amount in delivered_map.items():
            if amount <= 0:
                continue
            remaining_demands[city_name] = max(0, remaining_demands.get(city_name, 0) - amount)

        total_distance += distance
        total_time_used += time_used
        total_delivered += delivered_count
        remaining_time = max(0.0, remaining_time - time_used)
        elapsed_time += time_used

    if not trip_models:
        return TSPResponse(
            optimal_distance=0.0,
            optimal_route=[DEPOT_NAME, DEPOT_NAME],
            optimal_deliveries=0,
            trip_routes=[],
            trip_count=0,
            total_time_used=0.0,
            city_deliveries={name: 0 for name in city_map},
            solver=solver_name,
        )

    city_deliveries = {name: 0 for name in city_map}
    for delivery_map in trip_delivery_maps:
        for city_name, amount in delivery_map.items():
            if amount > 0:
                city_deliveries[city_name] = city_deliveries.get(city_name, 0) + amount

    return TSPResponse(
        optimal_distance=round(total_distance, 1),
        optimal_route=flat_route or [DEPOT_NAME, DEPOT_NAME],
        optimal_deliveries=total_delivered,
        trip_routes=trip_models,
        trip_count=len(trip_models),
        total_time_used=round(total_time_used, 1),
        city_deliveries=city_deliveries,
        solver=solver_name,
    )


def solve_tsp(req: TSPRequest) -> TSPResponse:
    if req.time_remaining <= 0.0:
        return TSPResponse(
            optimal_distance=0.0,
            optimal_route=[DEPOT_NAME, DEPOT_NAME],
            optimal_deliveries=0,
            trip_routes=[],
            trip_count=0,
            total_time_used=0.0,
            city_deliveries={city.name: 0 for city in req.shops if city.demand > 0},
            solver="none",
        )

    try:
        return _solve_repeated_trips(req, use_gamspy=True)
    except Exception as exc:
        logger.exception("GAMSPy TSP solve failed, falling back to pure Python: %s", exc)
        return _solve_repeated_trips(req, use_gamspy=False)

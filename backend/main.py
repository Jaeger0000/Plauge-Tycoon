import math
from itertools import permutations
from typing import Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Wood Works Solver")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Models ───────────────────────────────────────────────────────────────────


class Forest(BaseModel):
    name: str
    capacity: int
    regen_rate: float
    position: list[float]


class Truck(BaseModel):
    type: str
    speed: float
    capacity: int


class TransportRequest(BaseModel):
    forests: list[Forest]
    factory_position: list[float]
    trucks: list[Truck]
    time_remaining: float


class TruckAssignment(BaseModel):
    truck: str
    forest: str
    trips: int
    wood: int


class TransportResponse(BaseModel):
    optimal_wood_delivered: int
    assignments: list[TruckAssignment]


class AssignmentRequest(BaseModel):
    machines: dict[str, Optional[str]]
    furniture_queue: list[str]
    time_remaining: float


class FurnitureAssignment(BaseModel):
    furniture: str
    cutting_machine: str
    assembly_machine: str
    packaging_machine: str
    total_time: float


class AssignmentResponse(BaseModel):
    optimal_throughput: int
    optimal_assignments: list[FurnitureAssignment]


class Shop(BaseModel):
    name: str
    position: list[float]
    demand: int


class TSPRequest(BaseModel):
    depot: list[float]
    shops: list[Shop]
    truck_capacity: int
    available_crates: int


class TSPResponse(BaseModel):
    optimal_distance: float
    optimal_route: list[str]
    optimal_deliveries: int


# ── Machine speed lookup ─────────────────────────────────────────────────────

MACHINE_SPEEDS: dict[str, float] = {
    "Alpha": 1.0,
    "Beta": 1.2,
    "Gamma": 1.5,
    "Basic": 2.0,
}

FURNITURE_BASE_TIMES: dict[str, dict[str, float]] = {
    "Chair":  {"cutting": 1.0, "assembly": 1.5, "packaging": 1.0},
    "Table":  {"cutting": 2.0, "assembly": 2.5, "packaging": 1.5},
    "Shelf":  {"cutting": 1.5, "assembly": 2.0, "packaging": 1.0},
    "Stool":  {"cutting": 0.8, "assembly": 1.0, "packaging": 0.8},
    "Desk":   {"cutting": 2.5, "assembly": 3.0, "packaging": 2.0},
    "Bed":    {"cutting": 3.0, "assembly": 3.5, "packaging": 2.5},
}

LOAD_TIME = 0.5
UNLOAD_TIME = 0.3


# ── Endpoints ────────────────────────────────────────────────────────────────


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/solve/transport", response_model=TransportResponse)
def solve_transport(req: TransportRequest):
    if not req.trucks or not req.forests:
        return TransportResponse(optimal_wood_delivered=0, assignments=[])

    # Estimate available wood per forest
    forest_available = {
        f.name: min(f.capacity, f.regen_rate * req.time_remaining)
        for f in req.forests
    }

    # Build forest position lookup
    forest_pos = {f.name: f.position for f in req.forests}
    forest_cap = {f.name: f.capacity for f in req.forests}

    assignments: list[TruckAssignment] = []
    remaining_wood = dict(forest_available)

    for truck in req.trucks:
        best_forest = None
        best_throughput = 0.0
        best_trips = 0
        best_wood = 0

        for forest in req.forests:
            dist = math.dist(forest.position, req.factory_position)
            round_trip = 2 * dist / truck.speed + LOAD_TIME + UNLOAD_TIME
            if round_trip <= 0:
                continue

            trips = int(req.time_remaining // round_trip)
            if trips <= 0:
                continue

            wood_per_trip = min(truck.capacity, int(remaining_wood.get(forest.name, 0)))
            if wood_per_trip <= 0:
                continue

            total_wood = min(trips * wood_per_trip, int(remaining_wood.get(forest.name, 0)))
            actual_trips = math.ceil(total_wood / wood_per_trip) if wood_per_trip > 0 else 0

            throughput = total_wood / (actual_trips * round_trip) if actual_trips > 0 else 0

            if throughput > best_throughput:
                best_throughput = throughput
                best_forest = forest.name
                best_trips = actual_trips
                best_wood = total_wood

        if best_forest is not None:
            remaining_wood[best_forest] = max(0, remaining_wood[best_forest] - best_wood)
            assignments.append(TruckAssignment(
                truck=truck.type,
                forest=best_forest,
                trips=best_trips,
                wood=best_wood,
            ))

    total_delivered = sum(a.wood for a in assignments)
    return TransportResponse(optimal_wood_delivered=total_delivered, assignments=assignments)


@app.post("/solve/assignment", response_model=AssignmentResponse)
def solve_assignment(req: AssignmentRequest):
    if not req.furniture_queue:
        return AssignmentResponse(optimal_throughput=0, optimal_assignments=[])

    # Gather machines per stage
    stages = ["cutting", "assembly", "packaging"]
    machines_per_stage: dict[str, list[str]] = {s: [] for s in stages}

    for slot_key, machine_name in req.machines.items():
        if machine_name is None:
            continue
        for stage in stages:
            if stage in slot_key:
                machines_per_stage[stage].append(machine_name)
                break

    # Pick best machine per stage (lowest speed multiplier)
    best_machine: dict[str, str] = {}
    for stage in stages:
        available = machines_per_stage[stage]
        if available:
            best_machine[stage] = min(available, key=lambda m: MACHINE_SPEEDS.get(m, 2.0))
        else:
            best_machine[stage] = "Basic"

    # Compute assignments
    assignments: list[FurnitureAssignment] = []
    total_time_used = 0.0

    for item in req.furniture_queue:
        base = FURNITURE_BASE_TIMES.get(item, {"cutting": 1.5, "assembly": 2.0, "packaging": 1.0})
        total_time = 0.0
        for stage in stages:
            machine = best_machine[stage]
            speed_mult = MACHINE_SPEEDS.get(machine, 2.0)
            total_time += base[stage] * speed_mult

        if total_time_used + total_time > req.time_remaining:
            break

        total_time_used += total_time
        assignments.append(FurnitureAssignment(
            furniture=item,
            cutting_machine=best_machine["cutting"],
            assembly_machine=best_machine["assembly"],
            packaging_machine=best_machine["packaging"],
            total_time=round(total_time, 2),
        ))

    # Theoretical throughput: average time per item
    if assignments:
        avg_time = total_time_used / len(assignments)
        theoretical = int(req.time_remaining // avg_time) if avg_time > 0 else 0
    else:
        theoretical = 0

    return AssignmentResponse(optimal_throughput=theoretical, optimal_assignments=assignments)


@app.post("/solve/tsp", response_model=TSPResponse)
def solve_tsp(req: TSPRequest):
    shops_with_demand = [s for s in req.shops if s.demand > 0]

    if not shops_with_demand:
        return TSPResponse(optimal_distance=0.0, optimal_route=["Depot", "Depot"], optimal_deliveries=0)

    depot = req.depot

    # Brute force all permutations
    best_distance = float("inf")
    best_order: list[Shop] = []

    for perm in permutations(shops_with_demand):
        dist = 0.0
        prev = depot
        for shop in perm:
            dist += math.dist(prev, shop.position)
            prev = shop.position
        dist += math.dist(prev, depot)

        if dist < best_distance:
            best_distance = dist
            best_order = list(perm)

    # Compute deliveries
    total_demand = sum(s.demand for s in best_order)
    optimal_deliveries = min(total_demand, req.available_crates, req.truck_capacity)

    optimal_route = ["Depot"] + [s.name for s in best_order] + ["Depot"]

    return TSPResponse(
        optimal_distance=round(best_distance, 1),
        optimal_route=optimal_route,
        optimal_deliveries=optimal_deliveries,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

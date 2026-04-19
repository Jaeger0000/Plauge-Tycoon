from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


TRANSPORT_REQUEST_EXAMPLE = {
    "forests": [
        {
            "name": "Pine",
            "capacity": 40,
            "regen_rate": 0.8,
            "position": [100.0, 200.0],
            "current_stock": 12,
        },
        {
            "name": "Oak",
            "capacity": 35,
            "regen_rate": 0.7,
            "position": [400.0, 300.0],
        },
    ],
    "factory_position": [900.0, 500.0],
    "budget": 250,
    "owned_trucks": {"Small": 1},
    "trucks": [
        {"type": "Medium", "speed": 200.0, "capacity": 4, "cost": 150},
        {"type": "Large", "speed": 120.0, "capacity": 8, "cost": 250},
    ],
    "time_remaining": 180.0,
}

MACHINE_PLACEMENT_REQUEST_EXAMPLE = {
    "budget": 1000,
    "time_remaining": 180.0,
    "corpse_count": 6,
}

PACKING_REQUEST_EXAMPLE = {
    "crate_size": [6, 6],
    "items": [
        {"id": 1, "type": "Chair", "w": 2, "h": 2},
        {"id": 2, "type": "Table", "w": 3, "h": 2},
        {"id": 3, "type": "Stool", "w": 1, "h": 1},
        {"id": 4, "type": "Shelf", "w": 3, "h": 1},
    ],
    "time_remaining": 180.0,
    "budget_remaining": 600,
    "packaging_cost_per_crate": 50,
}

TSP_REQUEST_EXAMPLE = {
    "depot": [100.0, 100.0],
    "shops": [
        {"name": "Market", "position": [500.0, 200.0], "demand": 3},
        {"name": "Boutique", "position": [800.0, 250.0], "demand": 2},
        {"name": "Office", "position": [600.0, 600.0], "demand": 2},
    ],
    "truck_capacity": 10,
    "available_crates": 6,
    "depot_restock_rate": 1.0,
    "truck_speed": 200.0,
    "time_remaining": 180.0,
    "budget": 0,
    "truck_load": 6,
}

FULL_SOLVE_REQUEST_EXAMPLE = {
    "budget": 1000,
    "transport_forests": [
        {
            "name": "Pine",
            "capacity": 5000,
            "regen_rate": 3.0,
            "position": [120.0, 220.0],
            "current_stock": 18,
        },
        {
            "name": "Oak",
            "capacity": 5000,
            "regen_rate": 100.0,
            "position": [380.0, 140.0],
            "current_stock": 10,
        },
    ],
    "factory_position": [900.0, 500.0],
    "owned_trucks": {"Small": 1},
    "trucks": [
        {"type": "Medium", "speed": 200.0, "capacity": 4, "cost": 150},
        {"type": "Large", "speed": 200.0, "capacity": 8, "cost": 250},
    ],
    "crate_size": [6, 6],
    "items": [
        {"id": 0, "type": "Chair", "w": 5, "h": 1},
        {"id": 1, "type": "Table", "w": 5, "h": 2},
        {"id": 2, "type": "Shelf", "w": 4, "h": 3},
    ],
    "depot": [100.0, 100.0],
    "shops": [
        {"name": "Market", "position": [500.0, 200.0], "demand": 3},
        {"name": "Boutique", "position": [800.0, 250.0], "demand": 2},
        {"name": "Office", "position": [600.0, 600.0], "demand": 2},
    ],
    "truck_capacity": 10,
    "truck_speed": 200.0,
    "time_remaining": 180.0,
    "packaging_cost_per_crate": 50,
    "item_arrival_interval": 2.0,
}

# ---------------------------------------------------------------------------
# Legacy transport models (kept for Godot compatibility)
# ---------------------------------------------------------------------------

class Forest(BaseModel):
    name: str
    capacity: int
    regen_rate: float
    position: list[float]
    current_stock: int | None = None


class Truck(BaseModel):
    type: str
    speed: float
    capacity: int
    cost: int = 0


class TransportRequest(BaseModel):
    model_config = ConfigDict(json_schema_extra={"example": TRANSPORT_REQUEST_EXAMPLE})

    forests: list[Forest]
    factory_position: list[float]
    budget: int = Field(default=0, ge=0)
    owned_trucks: dict[str, int] = Field(default_factory=lambda: {"Small": 1})
    trucks: list[Truck] = Field(default_factory=list)
    time_remaining: float


class TruckAssignment(BaseModel):
    truck: str
    forest: str
    trips: int
    wood: int


class TransportResponse(BaseModel):
    optimal_wood_delivered: int
    assignments: list[TruckAssignment]
    purchased_assignments: list[TruckAssignment] = Field(default_factory=list)
    total_truck_cost: int = 0
    trucks_to_buy: dict[str, int] = Field(default_factory=lambda: {"Small": 0, "Medium": 0, "Large": 0})
    solve_time_ms: float = 0.0
    solver: str = "bruteforce"
    purchase_decision_note: str = ""


# ---------------------------------------------------------------------------
# Supply optimisation models (GAMSPy MIP: buy trucks + assign to forests)
# ---------------------------------------------------------------------------

class ForestInput(BaseModel):
    """Single forest node as seen by the supply optimiser."""
    name: str
    capacity: int           # maximum harvestable wood units
    regen_rate: float       # wood units regenerated per second
    distance: float         # distance (pixels / units) to the factory entrance


class SupplyRequest(BaseModel):
    """
    Decide which trucks to buy and where to send them so that wood delivered
    is maximised while staying within ``budget``.

    ``owned_trucks`` maps truck type → count of trucks already in the player's
    fleet (default: 1 Small truck, the free starting truck).
    """
    model_config = ConfigDict(json_schema_extra={"example": TRANSPORT_REQUEST_EXAMPLE})

    budget: int = Field(default=0, ge=0)
    time_remaining: float = Field(default=300.0, ge=0.0)
    forests: list[ForestInput] = Field(default_factory=list)
    owned_trucks: dict[str, int] = Field(default_factory=lambda: {"Small": 1})


class SupplyAssignment(BaseModel):
    truck: str          # truck type name ("Small", "Medium", "Large")
    forest: str         # forest name
    assigned_count: int # how many trucks of this type go to this forest
    trips: int          # round-trips a single truck can complete in time_remaining
    wood: int           # total wood this group will deliver


class SupplyResponse(BaseModel):
    total_wood_delivered: int
    total_truck_cost: int
    trucks_to_buy: dict[str, int]   # e.g. {"Small": 0, "Medium": 1, "Large": 0}
    assignments: list[SupplyAssignment]
    solver: str = "gamspy"


# ---------------------------------------------------------------------------
# Packing models
# ---------------------------------------------------------------------------

class PackingItem(BaseModel):
    id: int
    type: str
    w: int = Field(gt=0)
    h: int = Field(gt=0)
    color: list[float] | None = None


class PackingRequest(BaseModel):
    model_config = ConfigDict(json_schema_extra={"example": PACKING_REQUEST_EXAMPLE})

    crate_size: list[int] = Field(default_factory=lambda: [6, 6])
    items: list[PackingItem] = Field(default_factory=list)
    time_remaining: float = Field(default=300.0, ge=0.0)
    # Budget constraint: when provided, limits how many crates can be packaged.
    budget_remaining: Optional[int] = None
    # Alias budget field for clients that send `budget` instead of `budget_remaining`.
    budget: Optional[int] = Field(default=None, ge=0)
    # New field: packaging cost is applied per filled crate.
    packaging_cost_per_crate: Optional[int] = Field(default=None, ge=0)
    # Backward-compat alias (old name in some clients).
    packaging_cost_per_item: Optional[int] = Field(default=None, ge=0)

    @field_validator("items")
    @classmethod
    def no_duplicate_ids(cls, items: list[PackingItem]) -> list[PackingItem]:
        seen: set[int] = set()
        dupes = [item.id for item in items if item.id in seen or seen.add(item.id)]  # type: ignore[func-returns-value]
        if dupes:
            raise ValueError(f"Duplicate item ids: {sorted(set(dupes))}")
        return items

    @field_validator("crate_size", mode="before")
    @classmethod
    def normalize_crate_size(cls, value: list[int] | None) -> list[int]:
        if not value or len(value) < 2:
            return [6, 6]
        w = int(value[0]) if value[0] is not None else 6
        h = int(value[1]) if value[1] is not None else 6
        if w <= 0 or h <= 0:
            return [6, 6]
        return [w, h]


class PackedItem(BaseModel):
    id: int
    type: str
    grid_x: int
    grid_y: int
    w: int
    h: int
    crate_index: int = 0
    color: list[float] | None = None


class PackedCrate(BaseModel):
    crate_index: int
    selected_count: int
    used_cells: int
    unused_cells: int
    fill_ratio: float
    packed_items: list[PackedItem]
    matrix: list[list[int]]


class PackingResponse(BaseModel):
    crate_size: list[int]
    selected_count: int
    unused_cells: int
    fill_ratio: float
    packed_items: list[PackedItem]
    rejected_item_ids: list[int]
    total_packing_cost: int = 0
    crates_used: int = 0
    crates: list[PackedCrate] = Field(default_factory=list)
    solver: str = "backtrack"


# ---------------------------------------------------------------------------
# Legacy factory assignment models (kept for Godot compatibility)
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Machine placement optimisation models (new)
# ---------------------------------------------------------------------------

class MachinePlacementRequest(BaseModel):
    """
    Optimise machine counts for each stage using only budget, time remaining,
    and incoming body count.
    """
    model_config = ConfigDict(json_schema_extra={"example": MACHINE_PLACEMENT_REQUEST_EXAMPLE})

    budget: int = Field(default=1000, ge=0)
    time_remaining: float = Field(default=300.0, ge=0.0)
    corpse_count: int = Field(default=0, ge=0)


class SlotAssignment(BaseModel):
    slot_index: int
    stage: str
    machine: str
    machine_cost: int


class MachinePlacementResponse(BaseModel):
    total_machine_cost: int
    remaining_budget: int
    stage_machine_counts: dict[str, dict[str, int]]
    stage_assignments: dict[str, list[str]]
    slot_assignments: list[SlotAssignment]
    predicted_throughput: int
    total_packages_output: int
    items_budget_limit: int   # max items the remaining budget can pay for
    items_time_limit: int     # max items that fit within the time window
    items_processable: list[str]   # ordered furniture types that will be produced
    total_processing_time: float
    solver: str = "gamspy"


# ---------------------------------------------------------------------------
# Delivery / TSP models
# ---------------------------------------------------------------------------

class Shop(BaseModel):
    name: str
    position: list[float]
    demand: int


class TSPRequest(BaseModel):
    model_config = ConfigDict(json_schema_extra={"example": TSP_REQUEST_EXAMPLE})

    depot: list[float]
    shops: list[Shop] = Field(default_factory=list)
    truck_capacity: int = Field(default=0, ge=0)
    available_crates: int = Field(default=0, ge=0)
    depot_restock_rate: float = Field(default=1.0, ge=0.0)
    truck_speed: float = Field(default=200.0, gt=0.0)
    time_remaining: float = Field(default=300.0, ge=0.0)
    budget: int = Field(default=0, ge=0)
    truck_load: Optional[int] = Field(default=None, ge=0)
    distance_matrix: Optional[list[list[float]]] = None


class RouteTrip(BaseModel):
    route: list[str]
    distance: float
    time_used: float
    delivered: int


class TSPResponse(BaseModel):
    optimal_distance: float
    optimal_route: list[str]
    optimal_deliveries: int
    trip_routes: list[RouteTrip] = Field(default_factory=list)
    trip_count: int = 0
    total_time_used: float = 0.0
    city_deliveries: dict[str, int] = Field(default_factory=dict)
    solver: str = "exact"


# ---------------------------------------------------------------------------
# Full chained solve models
# ---------------------------------------------------------------------------

class FullSolveRequest(BaseModel):
    """
    Single request that chains all three optimisations:
      1. transport           →  buys/assigns trucks and produces raw output
      2. machine placement   →  converts output into processable packages
      3. crate packing       →  packs the user-provided items
      4. delivery routing    →  delivers packed crates to shops
    """
    model_config = ConfigDict(json_schema_extra={"example": FULL_SOLVE_REQUEST_EXAMPLE})

    budget: int = Field(default=1000, ge=0)
    transport_forests: list[Forest] = Field(default_factory=list)
    factory_position: list[float] = Field(default_factory=lambda: [0.0, 0.0])
    owned_trucks: dict[str, int] = Field(default_factory=lambda: {"Small": 1})
    trucks: list[Truck] = Field(default_factory=list)
    crate_size: list[int] = Field(default_factory=lambda: [6, 6])
    items: list[PackingItem] = Field(default_factory=list)
    furniture_queue: list[str] = Field(default_factory=list)
    depot: list[float]
    shops: list[Shop] = Field(default_factory=list)
    truck_capacity: int = Field(default=0, ge=0)
    truck_speed: float = Field(default=200.0, gt=0.0)
    time_remaining: float = Field(default=300.0, ge=0.0)
    packaging_cost_per_crate: Optional[int] = Field(default=None, ge=0)
    # Backward-compat alias for older clients.
    packaging_cost_per_item: Optional[int] = Field(default=None, ge=0)
    item_arrival_interval: float = Field(default=2.0, gt=0.0)


class FullSolveResponse(BaseModel):
    transport: TransportResponse
    machine_placement: MachinePlacementResponse
    packing: PackingResponse
    delivery: TSPResponse
    total_items_estimated: int
    budget_flow: dict[str, float]
    derived_values: dict[str, float]
    pipeline_warnings: list[str] = Field(default_factory=list)
    score_breakdown: dict[str, float]

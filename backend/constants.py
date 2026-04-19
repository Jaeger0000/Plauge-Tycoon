MACHINE_DEFS: dict[str, dict] = {
    "Basic": {
        "cost": 100,
        "cutting_speed": 1.0,
        "assembly_speed": 1.0,
        "packaging_speed": 1.0,
    },
    "Alpha": {
        "cost": 150,
        "cutting_speed": 0.5,
        "assembly_speed": 1.2,
        "packaging_speed": 1.5,
    },
    "Beta": {
        "cost": 150,
        "cutting_speed": 1.5,
        "assembly_speed": 0.5,
        "packaging_speed": 1.2,
    },
    "Gamma": {
        "cost": 150,
        "cutting_speed": 1.2,
        "assembly_speed": 1.5,
        "packaging_speed": 0.5,
    },
    "Omega": {
        "cost": 300,
        "cutting_speed": 0.7,
        "assembly_speed": 0.7,
        "packaging_speed": 0.7,
    },
}

# Backward-compat alias used by old assignment solver
MACHINE_SPEEDS: dict[str, float] = {k: v["cutting_speed"] for k, v in MACHINE_DEFS.items()}

FURNITURE_BASE_TIMES: dict[str, dict[str, float]] = {
    "Chair": {"cutting": 3.0, "assembly": 4.0, "packaging": 2.0},
    "Table": {"cutting": 5.0, "assembly": 6.0, "packaging": 3.0},
    "Shelf": {"cutting": 2.0, "assembly": 3.0, "packaging": 2.0},
    "Stool": {"cutting": 2.0, "assembly": 2.0, "packaging": 1.0},
}

# Footprint of each furniture type inside the 6×6 packing crate
FURNITURE_DIMENSIONS: dict[str, dict[str, int]] = {
    "Chair": {"w": 2, "h": 2},
    "Table": {"w": 3, "h": 2},
    "Shelf": {"w": 3, "h": 1},
    "Stool": {"w": 1, "h": 1},
}

GAME_DURATION: float = 300.0          # total session time in seconds
ITEM_ARRIVAL_INTERVAL: float = 2.0    # raw-material arrives every ~2 s
PACKAGING_COST_PER_ITEM: int = 50     # coins deducted per packaged item
DEFAULT_BUDGET: int = 1000            # starting budget in coins

LOAD_TIME = 0.5
UNLOAD_TIME = 0.3

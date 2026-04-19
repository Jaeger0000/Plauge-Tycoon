import json
from models import TransportRequest, Forest
from solvers.transport import solve_transport

req = TransportRequest(
    forests=[
        Forest(name="Pine",  capacity=20, regen_rate=3.0,  position=[100.0, 200.0], current_stock=12),
        Forest(name="Oak",   capacity=30, regen_rate=4.0, position=[300.0, 100.0], current_stock=18),
    ],
    factory_position=[500.0, 500.0],
    budget=400,
    owned_trucks={"Small": 1},
    trucks=[
        {"type": "Medium", "speed": 200.0, "capacity": 4, "cost": 150},
        {"type": "Large", "speed": 120.0, "capacity": 8, "cost": 250},
    ],
    time_remaining=120.0,
)

try:
    res = solve_transport(req)
    print("OK:", json.loads(res.model_dump_json(indent=2)))
except Exception as e:
    print("HATA:", type(e).__name__, e)

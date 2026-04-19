from models import ForestInput, SupplyRequest
from solvers.supply_optimizer import solve_supply

req = SupplyRequest(
    budget=400,
    time_remaining=120.0,
    forests=[
        ForestInput(name="Pine",  capacity=20, regen_rate=0.1, distance=350.0),
        ForestInput(name="Oak",   capacity=30, regen_rate=0.05, distance=500.0),
        ForestInput(name="Birch", capacity=15, regen_rate=0.08, distance=200.0),
    ],
    owned_trucks={"Small": 1},
)

res = solve_supply(req)
import json
print(json.loads(res.model_dump_json(indent=2)))

print("\n--- Senaryo 2: Büyük orman, tek küçük truck yetersiz ---")
req2 = SupplyRequest(
    budget=400,
    time_remaining=60.0,
    forests=[
        ForestInput(name="Pine",  capacity=100, regen_rate=2.0, distance=800.0),
        ForestInput(name="Oak",   capacity=100, regen_rate=2.0, distance=600.0),
    ],
    owned_trucks={"Small": 1},
)
res2 = solve_supply(req2)
print(f"  Solver: {res2.solver}")
print(f"  Satın alınan: {res2.trucks_to_buy}  |  Harcama: {res2.total_truck_cost} coin")
print(f"  Toplam odun: {res2.total_wood_delivered}")
for a in res2.assignments:
    print(f"    {a.truck} x{a.assigned_count} → {a.forest}: {a.trips} sefer, {a.wood} odun")

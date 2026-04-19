from models import ForestInput, SupplyRequest
from solvers.supply_optimizer import solve_supply

print("=== Senaryo 1: Küçük ormanlar, 1 Small truck yeterli ===")
req1 = SupplyRequest(
    budget=400,
    time_remaining=120.0,
    forests=[
        ForestInput(name="Pine",  capacity=20, regen_rate=0.1,  distance=350.0),
        ForestInput(name="Oak",   capacity=30, regen_rate=0.05, distance=500.0),
        ForestInput(name="Birch", capacity=15, regen_rate=0.08, distance=200.0),
    ],
    owned_trucks={"Small": 1},
)
r1 = solve_supply(req1)
print(f"  Solver     : {r1.solver}")
print(f"  Satın alınan: {r1.trucks_to_buy}  (Small alınamaz!)")
print(f"  Harcama    : {r1.total_truck_cost} coin")
print(f"  Odun       : {r1.total_wood_delivered}")
for a in r1.assignments:
    print(f"    {a.truck} x{a.assigned_count} → {a.forest}: {a.trips} sefer, {a.wood} odun")

print()
print("=== Senaryo 2: Büyük ormanlar, bütçeyle truck satın alınması gerekiyor ===")
req2 = SupplyRequest(
    budget=400,
    time_remaining=60.0,
    forests=[
        ForestInput(name="Pine",  capacity=100, regen_rate=2.0, distance=800.0),
        ForestInput(name="Oak",   capacity=100, regen_rate=2.0, distance=600.0),
    ],
    owned_trucks={"Small": 1},
)
r2 = solve_supply(req2)
print(f"  Solver     : {r2.solver}")
print(f"  Satın alınan: {r2.trucks_to_buy}  (Small alınamaz!)")
print(f"  Harcama    : {r2.total_truck_cost} coin")
print(f"  Odun       : {r2.total_wood_delivered}")
for a in r2.assignments:
    print(f"    {a.truck} x{a.assigned_count} → {a.forest}: {a.trips} sefer, {a.wood} odun")

import asyncio
from models import PackingRequest, PackingItem
from solvers.packing import solve_packing

req = PackingRequest(
    crate_size=[6, 6],
    items=[
        PackingItem(id=1, type="A", w=2, h=2),
        PackingItem(id=2, type="B", w=3, h=3)
    ],
    time_remaining=300,
    budget_remaining=100,
    packaging_cost_per_item=50
)

res = solve_packing(req)
print(res.model_dump_json(indent=2))

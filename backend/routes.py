import math
import logging
from time import perf_counter

from fastapi import APIRouter, HTTPException

from constants import FURNITURE_DIMENSIONS
from models import (
    AssignmentRequest,
    AssignmentResponse,
    FullSolveRequest,
    FullSolveResponse,
    MachinePlacementRequest,
    MachinePlacementResponse,
    PackingItem,
    PackingRequest,
    PackingResponse,
    SupplyRequest,
    SupplyResponse,
    TransportRequest,
    TransportResponse,
    TSPRequest,
    TSPResponse,
)
from solvers.assignment import solve_assignment
from solvers.machine_placement import solve_machine_placement
from solvers.packing import solve_packing
from solvers.supply_optimizer import solve_supply
from solvers.transport import solve_transport
from solvers.tsp import solve_tsp

router = APIRouter()
logger = logging.getLogger(__name__)


def _fallback_machine_placement(req: MachinePlacementRequest, solver: str = "error") -> MachinePlacementResponse:
    return MachinePlacementResponse(
        total_machine_cost=0,
        remaining_budget=req.budget,
        stage_machine_counts={"cutting": {}, "assembly": {}, "packaging": {}},
        stage_assignments={"cutting": [], "assembly": [], "packaging": []},
        slot_assignments=[],
        predicted_throughput=0,
        total_packages_output=0,
        items_budget_limit=0,
        items_time_limit=0,
        items_processable=[],
        total_processing_time=0.0,
        solver=solver,
    )


def _fallback_packing(req: PackingRequest, solver: str = "error") -> PackingResponse:
    crate_area = 0
    if len(req.crate_size) >= 2:
        crate_area = max(0, int(req.crate_size[0])) * max(0, int(req.crate_size[1]))

    return PackingResponse(
        crate_size=req.crate_size,
        selected_count=0,
        unused_cells=crate_area,
        fill_ratio=0.0,
        packed_items=[],
        rejected_item_ids=[item.id for item in req.items],
        total_packing_cost=0,
        solver=solver,
    )


def _fallback_tsp(solver: str = "error") -> TSPResponse:
    return TSPResponse(
        optimal_distance=0.0,
        optimal_route=["Depot", "Depot"],
        optimal_deliveries=0,
        trip_routes=[],
        trip_count=0,
        total_time_used=0.0,
        city_deliveries={},
        solver=solver,
    )


def _fallback_transport(solver: str = "error") -> TransportResponse:
    return TransportResponse(
        optimal_wood_delivered=0,
        assignments=[],
        purchased_assignments=[],
        total_truck_cost=0,
        trucks_to_buy={"Small": 0, "Medium": 0, "Large": 0},
        solve_time_ms=0.0,
        solver=solver,
        purchase_decision_note="Solver failed; fallback response returned.",
    )


def _fallback_assignment() -> AssignmentResponse:
    return AssignmentResponse(optimal_throughput=0, optimal_assignments=[])


# ---------------------------------------------------------------------------
# Individual solvers  (all usable independently)
# ---------------------------------------------------------------------------

@router.post(
    "/solve/machine_placement",
    response_model=MachinePlacementResponse,
    summary="Optimise multi-machine placement per factory stage",
    description=(
        "GAMSPy MIP: choose machine counts for cutting, assembly, and packaging "
        "using budget + time_remaining + corpse_count. Stages are sequential and "
        "output returns machine plan and total package count."
    ),
)
def route_machine_placement(req: MachinePlacementRequest) -> MachinePlacementResponse:
    if req.corpse_count <= 0:
        raise HTTPException(
            status_code=422,
            detail="corpse_count must be greater than 0",
        )

    started = perf_counter()
    try:
        result = solve_machine_placement(req)
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.info("/solve/machine_placement solved in %.2f ms", elapsed_ms)
        return result
    except Exception as exc:
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.exception("/solve/machine_placement failed after %.2f ms: %s", elapsed_ms, exc)
        return _fallback_machine_placement(req)


# @router.post(
#     "/solve/packing",
#     response_model=PackingResponse,
#     summary="Optimise crate packing (6×6 grid)",
#     description=(
#         "GAMSPy MIP: maximise items packed into one crate. "
#         "Pass budget_remaining + packaging_cost_per_item to enforce the coin cap."
#     ),
# )
@router.post(
    "/packing",
    response_model=PackingResponse,
    summary="Optimise crate packing (6×6 grid) - Alias",
)
def route_packing(req: PackingRequest) -> PackingResponse:
    started = perf_counter()
    try:
        result = solve_packing(req)
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.info("/solve/packing solved in %.2f ms", elapsed_ms)
        return result
    except Exception as exc:
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.exception("/solve/packing failed after %.2f ms: %s", elapsed_ms, exc)
        return _fallback_packing(req)


@router.post(
    "/solve/tsp",
    response_model=TSPResponse,
    summary="Optimise delivery route (TSP with capacity)",
)
def route_tsp(req: TSPRequest) -> TSPResponse:
    started = perf_counter()
    try:
        result = solve_tsp(req)
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.info("/solve/tsp solved in %.2f ms", elapsed_ms)
        return result
    except Exception as exc:
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.exception("/solve/tsp failed after %.2f ms: %s", elapsed_ms, exc)
        return _fallback_tsp()



@router.post(
    "/solve/transport",
    response_model=TransportResponse,
    summary="Optimise wood transport from forests",
)
def route_transport(req: TransportRequest) -> TransportResponse:
    started = perf_counter()
    try:
        result = solve_transport(req)
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.info("/solve/transport solved in %.2f ms", elapsed_ms)
        return result
    except Exception as exc:
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.exception("/solve/transport failed after %.2f ms: %s", elapsed_ms, exc)
        return _fallback_transport()


# ---------------------------------------------------------------------------
# Supply optimisation  (GAMSPy MIP: buy trucks + assign to forests)
# ---------------------------------------------------------------------------

# @router.post(
#     "/solve/supply",
#     response_model=SupplyResponse,
#     summary="Optimise wood supply: buy & assign trucks to forests (GAMSPy MIP)",
#     description=(
#         "Maximises total wood delivered to the factory within the given budget.\n\n"
#         "The solver decides:\n"
#         "- how many of each truck type to **purchase** (Medium 150 coins, Large 250 coins)\n"
#         "- which forest to assign each truck to\n\n"
#         "Truck catalogue (mirrors `TRUCK_DATA` in `supply_zone.gd`):\n"
#         "- **Small** – speed 300, capacity 2, cost 0 (always 1 free)\n"
#         "- **Medium** – speed 200, capacity 4, cost 150\n"
#         "- **Large** – speed 120, capacity 8, cost 250"
#     ),
# )
# @router.post(
#     "/supply",
#     response_model=SupplyResponse,
#     summary="Optimise wood supply - Alias",
# )
def route_supply(req: SupplyRequest) -> SupplyResponse:
    started = perf_counter()
    try:
        result = solve_supply(req)
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.info("/solve/supply solved in %.2f ms (solver=%s)", elapsed_ms, result.solver)
        return result
    except Exception as exc:
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.exception("/solve/supply failed after %.2f ms: %s", elapsed_ms, exc)
        return SupplyResponse(
            total_wood_delivered=0,
            total_truck_cost=0,
            trucks_to_buy={t: 0 for t in ("Small", "Medium", "Large")},
            assignments=[],
            solver="error",
        )


# Legacy alias kept for Godot client compatibility
# @router.post(
#     "/solve/assignment",
#     response_model=AssignmentResponse,
#     summary="(Legacy) Simulate factory assignment for already-placed machines",
# )
def route_assignment(req: AssignmentRequest) -> AssignmentResponse:
    started = perf_counter()
    try:
        result = solve_assignment(req)
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.info("/solve/assignment solved in %.2f ms", elapsed_ms)
        return result
    except Exception as exc:
        elapsed_ms = (perf_counter() - started) * 1000.0
        logger.exception("/solve/assignment failed after %.2f ms: %s", elapsed_ms, exc)
        return _fallback_assignment()


# ---------------------------------------------------------------------------
# Chained full solve
# ---------------------------------------------------------------------------

@router.post(
    "/solve/full",
    response_model=FullSolveResponse,
    summary="Chained optimisation: machine placement → crate packing → delivery",
    description=(
        "Runs three GAMSPy optimisations in sequence, feeding the best result of "
        "each stage into the next:\n\n"
        "1. **Machine placement** – picks the optimal machine for each slot given "
        "the budget (1000 coins) and packaging cost (50 coins/crate).\n"
        "2. **Crate packing** – arranges the processable items inside a 6×6 crate "
        "to maximise fill, respecting the remaining budget.\n"
        "3. **Delivery routing** – finds the optimal truck route to maximise "
        "furniture delivered to shops given the available crates."
    ),
)
def route_full(req: FullSolveRequest) -> FullSolveResponse:
    route_started = perf_counter()
    errors: list[str] = []
    solve_times_ms: dict[str, float] = {
        "machine_placement": 0.0,
        "packing": 0.0,
        "delivery": 0.0,
        "total": 0.0,
    }

    # ── Step 1: machine placement ─────────────────────────────────────────────
    mp_req = MachinePlacementRequest(
        budget=req.budget,
        time_remaining=req.time_remaining,
        corpse_count=len(req.furniture_queue),
    )
    mp_started = perf_counter()
    try:
        mp_result = solve_machine_placement(mp_req)
    except Exception as exc:
        logger.exception("/solve/full machine placement failed: %s", exc)
        mp_result = _fallback_machine_placement(mp_req, solver="error-full")
        errors.append("machine_placement_failed")
    solve_times_ms["machine_placement"] = (perf_counter() - mp_started) * 1000.0

    # ── Step 2: crate packing with processable items ──────────────────────────
    packing_items: list[PackingItem] = []
    for idx, ftype in enumerate(req.furniture_queue[: mp_result.predicted_throughput]):
        dims = FURNITURE_DIMENSIONS.get(ftype, {"w": 1, "h": 1})
        packing_items.append(
            PackingItem(id=idx, type=ftype, w=dims["w"], h=dims["h"])
        )

    pack_req = PackingRequest(
        crate_size=req.crate_size,
        items=packing_items,
        time_remaining=req.time_remaining,
        budget_remaining=mp_result.remaining_budget,
        packaging_cost_per_crate=req.packaging_cost_per_crate,
        packaging_cost_per_item=req.packaging_cost_per_item,
    )
    pack_started = perf_counter()
    try:
        pack_result = solve_packing(pack_req)
    except Exception as exc:
        logger.exception("/solve/full packing failed: %s", exc)
        pack_result = _fallback_packing(pack_req, solver="error-full")
        errors.append("packing_failed")
    solve_times_ms["packing"] = (perf_counter() - pack_started) * 1000.0

    # Estimate total crates produced across the full session
    items_per_crate = pack_result.selected_count
    n_processable = mp_result.predicted_throughput
    if items_per_crate > 0 and n_processable > 0:
        total_crates = math.ceil(n_processable / items_per_crate)
    else:
        total_crates = 0

    # ── Step 3: delivery routing ──────────────────────────────────────────────
    tsp_req = TSPRequest(
        depot=req.depot,
        shops=req.shops,
        truck_capacity=req.truck_capacity,
        available_crates=total_crates,
    )
    tsp_started = perf_counter()
    try:
        delivery_result = solve_tsp(tsp_req)
    except Exception as exc:
        logger.exception("/solve/full delivery failed: %s", exc)
        delivery_result = _fallback_tsp(solver="error-full")
        errors.append("delivery_failed")
    solve_times_ms["delivery"] = (perf_counter() - tsp_started) * 1000.0
    solve_times_ms["total"] = (perf_counter() - route_started) * 1000.0

    score_breakdown: dict[str, float] = {
        "machine_cost_coins": float(mp_result.total_machine_cost),
        "items_processed": float(mp_result.predicted_throughput),
        "packing_fill_ratio": float(pack_result.fill_ratio),
        "total_crates_estimated": float(total_crates),
        "optimal_deliveries": float(delivery_result.optimal_deliveries),
        "total_packing_cost_coins": float(pack_result.total_packing_cost),
        "total_route_distance": float(delivery_result.optimal_distance),
        "time_machine_placement_ms": round(solve_times_ms["machine_placement"], 2),
        "time_packing_ms": round(solve_times_ms["packing"], 2),
        "time_delivery_ms": round(solve_times_ms["delivery"], 2),
        "time_total_ms": round(solve_times_ms["total"], 2),
        "error_count": float(len(errors)),
    }

    if errors:
        logger.warning("/solve/full completed with %d fallback error(s): %s", len(errors), ",".join(errors))
    else:
        logger.info(
            "/solve/full solved in %.2f ms (mp=%.2f, pack=%.2f, tsp=%.2f)",
            solve_times_ms["total"],
            solve_times_ms["machine_placement"],
            solve_times_ms["packing"],
            solve_times_ms["delivery"],
        )

    return FullSolveResponse(
        machine_placement=mp_result,
        packing=pack_result,
        delivery=delivery_result,
        total_items_estimated=mp_result.predicted_throughput,
        score_breakdown=score_breakdown,
    )

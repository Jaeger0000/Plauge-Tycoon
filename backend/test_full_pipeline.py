from models import (
    Forest,
    FullSolveRequest,
    MachinePlacementResponse,
    PackedItem,
    PackingResponse,
    PackingItem,
    RouteTrip,
    Shop,
    TSPResponse,
    TransportResponse,
    Truck,
)

import routes


def _base_request() -> FullSolveRequest:
    return FullSolveRequest(
        budget=1000,
        transport_forests=[
            Forest(name="Pine", capacity=5000, regen_rate=3.0, position=[120, 220], current_stock=18),
            Forest(name="Oak", capacity=5000, regen_rate=100.0, position=[380, 140], current_stock=10),
        ],
        factory_position=[900, 500],
        owned_trucks={"Small": 1},
        trucks=[
            Truck(type="Medium", speed=200.0, capacity=4, cost=150),
            Truck(type="Large", speed=200.0, capacity=8, cost=250),
        ],
        crate_size=[6, 6],
        items=[
            PackingItem(id=0, type="A", w=5, h=1),
            PackingItem(id=1, type="B", w=5, h=2),
            PackingItem(id=2, type="C", w=5, h=3),
            PackingItem(id=3, type="D", w=5, h=4),
            PackingItem(id=4, type="E", w=5, h=5),
            PackingItem(id=5, type="F", w=5, h=6),
            PackingItem(id=6, type="G", w=4, h=1),
            PackingItem(id=7, type="H", w=4, h=2),
            PackingItem(id=8, type="I", w=4, h=3),
        ],
        depot=[100, 100],
        shops=[
            Shop(name="Market", position=[500, 200], demand=3),
            Shop(name="Boutique", position=[800, 250], demand=2),
            Shop(name="Office", position=[600, 600], demand=2),
        ],
        truck_capacity=10,
        truck_speed=200.0,
        time_remaining=180.0,
        packaging_cost_per_crate=50,
    )


def test_full_pipeline_budget_flow(monkeypatch):
    transport_response = TransportResponse(
        optimal_wood_delivered=89,
        assignments=[],
        purchased_assignments=[],
        total_truck_cost=250,
        trucks_to_buy={"Small": 0, "Medium": 0, "Large": 1},
        solve_time_ms=1.0,
        solver="gamspy",
        purchase_decision_note="ok",
    )
    machine_response = MachinePlacementResponse(
        total_machine_cost=450,
        remaining_budget=300,
        stage_machine_counts={"cutting": {"Alpha": 1}, "assembly": {"Beta": 1}, "packaging": {"Gamma": 1}},
        stage_assignments={"cutting": ["Alpha"], "assembly": ["Beta"], "packaging": ["Gamma"]},
        slot_assignments=[],
        predicted_throughput=9,
        total_packages_output=9,
        items_budget_limit=9,
        items_time_limit=9,
        items_processable=["Body"] * 9,
        total_processing_time=251.0,
        solver="brute",
    )
    packing_response = PackingResponse(
        crate_size=[6, 6],
        selected_count=5,
        unused_cells=10,
        fill_ratio=0.77,
        packed_items=[
            PackedItem(id=0, type="A", grid_x=0, grid_y=0, w=5, h=1, crate_index=0),
        ],
        rejected_item_ids=[1, 2, 3],
        total_packing_cost=150,
        crates_used=3,
        crates=[],
        solver="gamspy-multicrate",
    )
    tsp_response = TSPResponse(
        optimal_distance=1234.5,
        optimal_route=["Depot", "Market", "Depot"],
        optimal_deliveries=5,
        trip_routes=[RouteTrip(route=["Depot", "Market", "Depot"], distance=1234.5, time_used=20.0, delivered=5)],
        trip_count=1,
        total_time_used=20.0,
        city_deliveries={"Market": 5},
        solver="exact",
    )

    monkeypatch.setattr(routes, "solve_transport", lambda req: transport_response)
    monkeypatch.setattr(routes, "solve_machine_placement", lambda req: machine_response)
    monkeypatch.setattr(routes, "solve_packing", lambda req: packing_response)
    monkeypatch.setattr(routes, "solve_tsp", lambda req: tsp_response)

    result = routes.route_full(_base_request())

    assert result.transport.total_truck_cost == 250
    assert result.machine_placement.total_machine_cost == 450
    assert result.packing.selected_count == 5
    assert result.delivery.optimal_deliveries == 5

    assert result.budget_flow["initial_budget"] == 1000.0
    assert result.budget_flow["transport_spent"] == 250.0
    assert result.budget_flow["after_transport"] == 750.0
    assert result.budget_flow["machine_spent"] == 450.0
    assert result.budget_flow["after_machine"] == 300.0
    assert result.budget_flow["packing_spent"] == 150.0
    assert result.budget_flow["after_packing"] == 150.0

    assert result.derived_values["tsp_available_crates"] == 5.0
    assert result.derived_values["depot_restock_rate"] == 9.0 / 251.0
    assert result.score_breakdown["transport_wood_delivered"] == 89.0
    assert result.score_breakdown["total_crates_estimated"] == 5.0


def test_full_pipeline_handles_zero_transport_output(monkeypatch):
    transport_response = TransportResponse(
        optimal_wood_delivered=0,
        assignments=[],
        purchased_assignments=[],
        total_truck_cost=0,
        trucks_to_buy={"Small": 0, "Medium": 0, "Large": 0},
        solve_time_ms=1.0,
        solver="none",
        purchase_decision_note="No forests provided.",
    )
    packing_response = PackingResponse(
        crate_size=[6, 6],
        selected_count=0,
        unused_cells=36,
        fill_ratio=0.0,
        packed_items=[],
        rejected_item_ids=[],
        total_packing_cost=0,
        crates_used=0,
        crates=[],
        solver="gamspy-multicrate",
    )
    tsp_response = TSPResponse(
        optimal_distance=0.0,
        optimal_route=["Depot", "Depot"],
        optimal_deliveries=0,
        trip_routes=[],
        trip_count=0,
        total_time_used=0.0,
        city_deliveries={},
        solver="exact",
    )

    monkeypatch.setattr(routes, "solve_transport", lambda req: transport_response)
    monkeypatch.setattr(routes, "solve_machine_placement", lambda req: (_ for _ in ()).throw(AssertionError("should not run")))
    monkeypatch.setattr(routes, "solve_packing", lambda req: packing_response)
    monkeypatch.setattr(routes, "solve_tsp", lambda req: tsp_response)

    req = _base_request().model_copy(update={"transport_forests": [], "items": []})
    result = routes.route_full(req)

    assert result.machine_placement.total_machine_cost == 0
    assert result.packing.selected_count == 0
    assert result.delivery.optimal_deliveries == 0
    assert "machine_placement_skipped_due_to_zero_transport_output" in result.pipeline_warnings

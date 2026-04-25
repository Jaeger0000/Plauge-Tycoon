extends Node2D

signal game_over

const ZONE_WIDTH := 1920.0
const MAP_WIDTH := 5760.0
const MAP_HEIGHT := 1080.0
const CAMERA_Y := 540.0
const PAN_SPEED := 5.0
const STARTING_BUDGET := 1000

var furniture_delivered: int = 0
var time_remaining: float = 300.0
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var target_camera_x: float = 960.0

# Solver tracking
var _pending_solvers: int = 0

@onready var camera: Camera2D = $Camera2D
@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var zone_label: Label = %ZoneLabel
@onready var left_arrow: Button = %LeftArrow
@onready var right_arrow: Button = %RightArrow
@onready var game_timer: Timer = %GameTimer
@onready var supply_zone: Control = %SupplyZone
@onready var factory_zone: Control = %FactoryZone
@onready var distribution_zone: Control = %DistributionZone

var zone_names: Array[String] = ["Supply Zone", "Factory Zone", "Distribution Zone"]


func _ready() -> void:
	GameManager.reset_stats()
	camera.position = Vector2(960.0, CAMERA_Y)
	target_camera_x = camera.position.x

	left_arrow.pressed.connect(_on_left_arrow_pressed)
	right_arrow.pressed.connect(_on_right_arrow_pressed)
	game_timer.timeout.connect(_on_timer_timeout)
	supply_zone.wood_delivered.connect(_on_wood_delivered)
	supply_zone.purchase_requested.connect(_on_supply_purchase)
	factory_zone.crate_ready.connect(_on_crate_ready)
	distribution_zone.furniture_delivered.connect(add_furniture)

	_update_score_label()
	_update_zone_label()
	_update_arrow_visibility()

	game_timer.start()


func _process(delta: float) -> void:
	# Smooth camera panning
	camera.position.x = lerpf(camera.position.x, target_camera_x, PAN_SPEED * delta)
	camera.position.x = clampf(camera.position.x, 960.0, MAP_WIDTH - 960.0)

	# Update timer display
	if !game_timer.is_stopped():
		time_remaining = game_timer.time_left
		_update_timer_label()

	_update_zone_label()
	_update_arrow_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_dragging = true
				drag_start = mb.position
			else:
				is_dragging = false

	if event is InputEventMouseMotion and is_dragging:
		var mm := event as InputEventMouseMotion
		target_camera_x -= mm.relative.x
		target_camera_x = clampf(target_camera_x, 960.0, MAP_WIDTH - 960.0)


func _on_left_arrow_pressed() -> void:
	var current_zone := _get_current_zone()
	if current_zone > 0:
		target_camera_x = (current_zone - 1) * ZONE_WIDTH + ZONE_WIDTH / 2.0


func _on_right_arrow_pressed() -> void:
	var current_zone := _get_current_zone()
	if current_zone < 2:
		target_camera_x = (current_zone + 1) * ZONE_WIDTH + ZONE_WIDTH / 2.0


func _on_timer_timeout() -> void:
	_gather_player_stats()
	game_over.emit()
	_request_all_optimal_solutions()


# --- Player stat collection ---

func _gather_player_stats() -> void:
	GameManager.furniture_delivered = furniture_delivered
	GameManager.player_wood_delivered = supply_zone.total_wood_delivered
	GameManager.player_deliveries = distribution_zone.total_delivered
	GameManager.player_budget_spent = STARTING_BUDGET - factory_zone.budget

	# Truck cost = sum of costs of all purchased trucks (non-free ones)
	var truck_cost := 0
	for truck in supply_zone.active_trucks + supply_zone.pool_trucks:
		var tdata: Dictionary = supply_zone.TRUCK_DATA.get(truck.truck_type, {})
		truck_cost += tdata.get("cost", 0)
	GameManager.player_truck_cost = truck_cost

	# Items processed = factory production count (crates shipped × items)
	GameManager.player_items_processed = factory_zone.production_count

	# Machine cost = STARTING_BUDGET - budget - truck_cost - packing_cost
	# Count machines placed in work spots
	var machine_cost := 0
	for spot in factory_zone.sterilize_spots + factory_zone.cutting_spots + factory_zone.packaging_spots:
		if spot.worker_type != "":
			var mdata: Dictionary = FactoryData.MACHINES.get(spot.worker_type, {})
			machine_cost += mdata.get("cost", 0)
	GameManager.player_machine_cost = machine_cost

	# Crates packed = depot crate count + crates already delivered
	GameManager.player_crates_packed = distribution_zone.depot.crate_count + _count_delivered_crates()

	# Packing cost = 50 per crate shipped
	GameManager.player_packing_cost = GameManager.player_crates_packed * 50


func _count_delivered_crates() -> int:
	# Each crate_ready call sends 1 crate to distribution, so count from distribution
	# total_delivered counts individual furniture, but we need crate count
	# crate_pool tracks per-crate furniture counts, delivered ones are gone
	# Best approximation: production_count items shipped in crates
	return 0  # Depot already tracks what it has; delivered crates are counted via trips


# --- Optimal solution requests ---

func _request_all_optimal_solutions() -> void:
	SolverClient.solution_received.connect(_on_solver_result)
	SolverClient.request_failed.connect(_on_solver_failed)
	_pending_solvers = 4

	# 1. Transport
	var forests: Array = []
	for forest in [supply_zone.pine_forest, supply_zone.oak_forest, supply_zone.birch_forest]:
		forests.append({
			"name": forest.forest_name,
			"capacity": forest.max_stock,
			"regen_rate": forest.regen_rate,
			"position": forest.global_position,
			"current_stock": forest.current_stock,
		})

	var owned_trucks: Dictionary = {}
	for truck in supply_zone.active_trucks + supply_zone.pool_trucks:
		var t_type: String = truck.truck_type
		if not owned_trucks.has(t_type):
			owned_trucks[t_type] = 0
		owned_trucks[t_type] += 1

	var truck_catalog: Array = []
	for tname in supply_zone.TRUCK_DATA:
		var tdata: Dictionary = supply_zone.TRUCK_DATA[tname]
		truck_catalog.append({
			"type": tname,
			"speed": tdata["speed"],
			"capacity": tdata["capacity"],
			"cost": tdata["cost"],
		})

	var factory_pos: Vector2 = supply_zone.factory_entrance.global_position + Vector2(50, 60)

	SolverClient.solve_transport(
		forests, factory_pos, STARTING_BUDGET,
		owned_trucks, truck_catalog, GameManager.game_time
	)

	# 2. Machine placement
	SolverClient.solve_machine_placement(
		STARTING_BUDGET,
		GameManager.game_time,
		maxi(supply_zone.total_wood_delivered, 1)
	)

	# 3. Packing — gather all items (queue + placed)
	var packing_items: Array = []
	var pack_id := 0
	for idata in factory_zone.packing_area.item_queue:
		packing_items.append({
			"id": pack_id,
			"type": idata["type"],
			"w": idata["w"],
			"h": idata["h"],
		})
		pack_id += 1
	for idata in factory_zone.packing_area.placed_items:
		packing_items.append({
			"id": pack_id,
			"type": idata["type"],
			"w": idata["w"],
			"h": idata["h"],
		})
		pack_id += 1

	SolverClient.solve_packing(
		[6, 6], packing_items,
		factory_zone.budget, 50
	)

	# 4. TSP
	# For optimal TSP, use the total items available for packing as potential crates
	# (the packing solver will determine how many crates can be made optimally)
	# Estimate: each item occupies at least w*h cells in a 6x6 grid (36 cells)
	var total_item_area := 0
	for item in packing_items:
		total_item_area += item["w"] * item["h"]
	var estimated_crates := maxi(int(ceil(float(total_item_area) / 36.0)), distribution_zone.depot.crate_count)

	var depot_pos: Vector2 = distribution_zone.depot.global_position + distribution_zone.depot.size / 2.0
	var shop_data: Array = []
	for shop in distribution_zone.shops:
		shop_data.append({
			"name": shop.shop_name,
			"position": shop.global_position + shop.size / 2.0,
			"demand": shop.demand,
		})

	SolverClient.solve_tsp(
		depot_pos, shop_data,
		distribution_zone.TRUCK_CAPACITY,
		estimated_crates
	)


func _on_solver_result(endpoint: String, result: Dictionary) -> void:
	GameManager.solver_results[endpoint] = result

	match endpoint:
		"/solve/transport":
			GameManager.optimal_wood_delivered = result.get("optimal_wood_delivered", 0)
		"/solve/machine_placement":
			GameManager.optimal_items_processed = result.get("predicted_throughput", 0)
		"/solve/packing":
			GameManager.optimal_crates_packed = result.get("selected_count", 0)
		"/solve/tsp":
			GameManager.optimal_deliveries = result.get("optimal_deliveries", 0)
			GameManager.optimal_route_distance = result.get("optimal_distance", 0.0)

	_pending_solvers -= 1
	if _pending_solvers <= 0:
		_finish_solvers()


func _on_solver_failed(endpoint: String, _error: String) -> void:
	push_warning("Solver failed: %s — %s" % [endpoint, _error])
	_pending_solvers -= 1
	if _pending_solvers <= 0:
		_finish_solvers()


func _finish_solvers() -> void:
	if SolverClient.solution_received.is_connected(_on_solver_result):
		SolverClient.solution_received.disconnect(_on_solver_result)
	if SolverClient.request_failed.is_connected(_on_solver_failed):
		SolverClient.request_failed.disconnect(_on_solver_failed)
	get_tree().change_scene_to_file("res://scenes/results/results.tscn")


func _on_crate_ready(furniture_count: int) -> void:
	distribution_zone.add_crate(furniture_count)


func add_furniture() -> void:
	furniture_delivered += 1
	GameManager.furniture_delivered = furniture_delivered
	_update_score_label()


func _get_current_zone() -> int:
	var cam_x := camera.position.x
	if cam_x < ZONE_WIDTH:
		return 0
	elif cam_x < ZONE_WIDTH * 2.0:
		return 1
	else:
		return 2


func _update_timer_label() -> void:
	var minutes := int(time_remaining) / 60
	var seconds := int(time_remaining) % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]


func _update_score_label() -> void:
	score_label.text = "Parts Delivered: %d" % furniture_delivered


func _update_zone_label() -> void:
	var zone_index := _get_current_zone()
	zone_label.text = zone_names[zone_index]


func _on_wood_delivered(count: int) -> void:
	var ProductionItemScene: PackedScene = preload("res://scenes/factory/production_item.tscn")
	for i in range(count):
		var types := FactoryData.FURNITURE.keys()
		var type_name: String = types[randi() % types.size()]
		var item = ProductionItemScene.instantiate()
		item.setup(type_name, FactoryData.STAGE_RAW)
		factory_zone.input_conveyor.add_item(item)


func _on_supply_purchase(cost: int) -> void:
	factory_zone.budget -= cost
	factory_zone._update_budget_label()


func _update_arrow_visibility() -> void:
	var zone := _get_current_zone()
	left_arrow.visible = zone > 0
	right_arrow.visible = zone < 2

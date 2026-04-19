extends Node2D

signal game_over

const ZONE_WIDTH := 1920.0
const MAP_WIDTH := 5760.0
const MAP_HEIGHT := 1080.0
const CAMERA_Y := 540.0
const PAN_SPEED := 5.0

var furniture_delivered: int = 0
var time_remaining: float = 300.0
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var target_camera_x: float = 960.0

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
	# Start drag with middle or right mouse button
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_dragging = true
				drag_start = mb.position
			else:
				is_dragging = false

	# Handle drag motion
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
	GameManager.furniture_delivered = furniture_delivered
	game_over.emit()
	_request_optimal_solution()


func _request_optimal_solution() -> void:
	# Gather supply data
	var forests: Array = []
	for forest in [supply_zone.pine_forest, supply_zone.oak_forest, supply_zone.birch_forest]:
		forests.append({
			"name": forest.forest_name,
			"capacity": forest.max_stock,
			"regen_rate": forest.regen_rate,
			"position": forest.global_position,
		})

	var trucks: Array = []
	for truck in supply_zone.active_trucks + supply_zone.pool_trucks:
		trucks.append({
			"type": truck.truck_type,
			"speed": truck.speed,
			"capacity": truck.capacity,
		})

	var factory_pos: Vector2 = supply_zone.factory_entrance.global_position + Vector2(50, 60)

	# Gather distribution data
	var depot_pos: Vector2 = distribution_zone.depot.global_position + distribution_zone.depot.size / 2.0
	var shop_data: Array = []
	for shop in distribution_zone.shops:
		shop_data.append({
			"name": shop.shop_name,
			"position": shop.global_position + shop.size / 2.0,
			"demand": shop.demand,
		})

	# Call TSP solver (most visible result)
	SolverClient.solution_received.connect(_on_solution_received, CONNECT_ONE_SHOT)
	SolverClient.request_failed.connect(_on_solution_failed, CONNECT_ONE_SHOT)
	SolverClient.solve_tsp(depot_pos, shop_data, 10, distribution_zone.depot.crate_count)


func _on_solution_received(_endpoint: String, result: Dictionary) -> void:
	if SolverClient.request_failed.is_connected(_on_solution_failed):
		SolverClient.request_failed.disconnect(_on_solution_failed)
	GameManager.optimal_deliveries = result.get("optimal_deliveries", 0)
	get_tree().change_scene_to_file("res://scenes/results/results.tscn")


func _on_solution_failed(_endpoint: String, _error: String) -> void:
	if SolverClient.solution_received.is_connected(_on_solution_received):
		SolverClient.solution_received.disconnect(_on_solution_received)
	GameManager.optimal_deliveries = 0
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
	score_label.text = "Furniture Delivered: %d" % furniture_delivered


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

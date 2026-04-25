extends Control

signal furniture_delivered

const TRUCK_CAPACITY := 10

var total_delivered: int = 0

var route_points: Array[Vector2] = []
var route_nodes: Array = []
var is_building_route: bool = false

var shops: Array = []
var depot = null
var truck = null

var TruckScene: PackedScene = preload("res://scenes/distribution/delivery_truck.tscn")

@onready var crate_label: Label = %CrateLabel
@onready var delivered_label: Label = %DeliveredLabel
@onready var route_label: Label = %RouteLabel
@onready var send_button: Button = %SendButton
@onready var clear_button: Button = %ClearButton
@onready var route_draw: Control = %RouteDraw


func _ready() -> void:
	depot = %Depot
	depot.clicked.connect(_on_depot_clicked)

	shops = [%Market, %Boutique, %FurnitureStore, %OfficeSupply, %HomeDepot, %CornerShop]
	for shop in shops:
		shop.clicked.connect(_on_shop_clicked)

	truck = TruckScene.instantiate()
	truck.delivery_complete.connect(_on_delivery_complete)
	add_child(truck)

	send_button.pressed.connect(_on_send_pressed)
	clear_button.pressed.connect(_on_clear_pressed)

	route_draw.zone = self
	_update_labels()


func add_crate(furniture_count: int) -> void:
	depot.add_crate(furniture_count)
	_update_labels()


func _on_depot_clicked(_d) -> void:
	if truck.is_moving:
		return

	if !is_building_route:
		is_building_route = true
		route_points.clear()
		route_nodes.clear()
		route_points.append(depot.get_center_position())
		route_nodes.append(null)
	else:
		route_points.append(depot.get_center_position())
		route_nodes.append(null)
		is_building_route = false

	route_draw.queue_redraw()
	_update_labels()


func _on_shop_clicked(shop) -> void:
	if !is_building_route or truck.is_moving:
		return
	if shop in route_nodes:
		return

	route_points.append(shop.get_center_position())
	route_nodes.append(shop)
	route_draw.queue_redraw()
	_update_labels()


func _on_send_pressed() -> void:
	if truck.is_moving:
		return
	if route_points.size() < 3:
		return
	if route_nodes[0] != null or route_nodes[-1] != null:
		return
	if depot.crate_count <= 0:
		return

	var crates_to_load := mini(depot.crate_count, TRUCK_CAPACITY)
	var taken: Array[int] = depot.take_crates(crates_to_load)

	truck.start_route(route_points.duplicate(), route_nodes.duplicate(), taken)
	_update_labels()


func _on_clear_pressed() -> void:
	if truck.is_moving:
		return
	route_points.clear()
	route_nodes.clear()
	is_building_route = false
	route_draw.queue_redraw()
	_update_labels()


func _on_delivery_complete(furniture_count: int) -> void:
	total_delivered += furniture_count
	for i in range(furniture_count):
		furniture_delivered.emit()

	route_points.clear()
	route_nodes.clear()
	is_building_route = false
	route_draw.queue_redraw()
	_update_labels()


func _get_total_route_distance() -> float:
	var total := 0.0
	for i in range(route_points.size() - 1):
		total += route_points[i].distance_to(route_points[i + 1])
	return total / 10.0


func _update_labels() -> void:
	if depot:
		crate_label.text = "Available Crates: %d (%d furniture)" % [depot.crate_count, depot.get_total_furniture()]
	delivered_label.text = "Parts Delivered: %d" % total_delivered

	if route_points.size() >= 2:
		var dist := _get_total_route_distance()
		var shops_count := route_nodes.filter(func(n): return n != null).size()
		route_label.text = "Route: %d shops, %.0f km" % [shops_count, dist]
	elif is_building_route:
		route_label.text = "Click shops to add to route..."
	else:
		route_label.text = "Click DEPOT to start route"

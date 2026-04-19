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

var ShopScene: PackedScene = preload("res://scenes/distribution/shop_node.tscn")
var DepotScene: PackedScene = preload("res://scenes/distribution/depot_node.tscn")
var TruckScene: PackedScene = preload("res://scenes/distribution/delivery_truck.tscn")

@onready var crate_label: Label = %CrateLabel
@onready var delivered_label: Label = %DeliveredLabel
@onready var route_label: Label = %RouteLabel
@onready var send_button: Button = %SendButton
@onready var clear_button: Button = %ClearButton

const SHOP_DATA := [
	{"name": "Market", "pos": Vector2(500, 200), "demand": 3, "color": Color(0.9, 0.3, 0.3)},
	{"name": "Boutique", "pos": Vector2(900, 150), "demand": 2, "color": Color(0.9, 0.5, 0.8)},
	{"name": "Furniture Store", "pos": Vector2(1400, 300), "demand": 4, "color": Color(0.3, 0.6, 0.9)},
	{"name": "Office Supply", "pos": Vector2(600, 700), "demand": 2, "color": Color(0.9, 0.8, 0.2)},
	{"name": "Home Depot", "pos": Vector2(1100, 600), "demand": 3, "color": Color(0.3, 0.8, 0.4)},
	{"name": "Corner Shop", "pos": Vector2(1600, 800), "demand": 1, "color": Color(0.7, 0.5, 0.3)},
]


func _ready() -> void:
	depot = DepotScene.instantiate()
	depot.position = Vector2(150, 460)
	depot.clicked.connect(_on_depot_clicked)
	add_child(depot)

	for data in SHOP_DATA:
		var shop = ShopScene.instantiate()
		shop.position = data["pos"]
		shop.shop_name = data["name"]
		shop.demand = data["demand"]
		shop.shop_color = data["color"]
		shop.clicked.connect(_on_shop_clicked)
		add_child(shop)
		shops.append(shop)

	truck = TruckScene.instantiate()
	truck.delivery_complete.connect(_on_delivery_complete)
	add_child(truck)

	send_button.pressed.connect(_on_send_pressed)
	clear_button.pressed.connect(_on_clear_pressed)

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

	queue_redraw()
	_update_labels()


func _on_shop_clicked(shop) -> void:
	if !is_building_route or truck.is_moving:
		return
	if shop in route_nodes:
		return

	route_points.append(shop.get_center_position())
	route_nodes.append(shop)
	queue_redraw()
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
	queue_redraw()
	_update_labels()


func _on_delivery_complete(furniture_count: int) -> void:
	total_delivered += furniture_count
	for i in range(furniture_count):
		furniture_delivered.emit()

	route_points.clear()
	route_nodes.clear()
	is_building_route = false
	queue_redraw()
	_update_labels()


func _draw() -> void:
	# Road grid
	var grid_color := Color(0.25, 0.25, 0.35, 0.3)
	for x in range(0, 1921, 120):
		draw_line(Vector2(x, 0), Vector2(x, 970), grid_color, 1.0)
	for y in range(0, 971, 120):
		draw_line(Vector2(0, y), Vector2(1920, y), grid_color, 1.0)

	# Route lines
	if route_points.size() < 2:
		return

	for i in range(route_points.size() - 1):
		var from := route_points[i]
		var to := route_points[i + 1]
		draw_line(from, to, Color(1, 0.8, 0, 0.8), 3.0)

		var mid := (from + to) / 2.0
		var dist := from.distance_to(to) / 10.0
		var font := ThemeDB.fallback_font
		draw_string(font, mid + Vector2(5, -5), "%.0f km" % dist,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.7))

	for pt in route_points:
		draw_circle(pt, 6.0, Color(1, 0.8, 0))


func _get_total_route_distance() -> float:
	var total := 0.0
	for i in range(route_points.size() - 1):
		total += route_points[i].distance_to(route_points[i + 1])
	return total / 10.0


func _update_labels() -> void:
	if depot:
		crate_label.text = "Available Crates: %d (%d furniture)" % [depot.crate_count, depot.get_total_furniture()]
	delivered_label.text = "Furniture Delivered: %d" % total_delivered

	if route_points.size() >= 2:
		var dist := _get_total_route_distance()
		var shops_count := route_nodes.filter(func(n): return n != null).size()
		route_label.text = "Route: %d shops, %.0f km" % [shops_count, dist]
	elif is_building_route:
		route_label.text = "Click shops to add to route..."
	else:
		route_label.text = "Click DEPOT to start route"

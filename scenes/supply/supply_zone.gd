extends Control

signal wood_delivered(count: int)
signal purchase_requested(cost: int)

const TRUCK_DATA := {
	"Small": {"speed": 300.0, "capacity": 2, "cost": 0, "color": Color(0.9, 0.85, 0.2)},
	"Medium": {"speed": 200.0, "capacity": 4, "cost": 150, "color": Color(0.9, 0.55, 0.15)},
	"Large": {"speed": 120.0, "capacity": 8, "cost": 250, "color": Color(0.85, 0.25, 0.2)},
}

var SupplyTruckScene: PackedScene = preload("res://scenes/supply/supply_truck.tscn")

var total_wood_delivered: int = 0
var active_trucks: Array = []  # Trucks assigned to forests
var pool_trucks: Array = []    # Trucks in the pool (unassigned)

@onready var pine_forest: Control = %PineForest
@onready var oak_forest: Control = %OakForest
@onready var birch_forest: Control = %BirchForest
@onready var factory_entrance: Control = %FactoryEntrance
@onready var delivered_label: Label = %DeliveredLabel
@onready var truck_pool: HBoxContainer = %TruckPool
@onready var shop_list: VBoxContainer = %ShopList
@onready var routes_node: Control = %RoutesNode


func _ready() -> void:
	# Connect forest signals
	pine_forest.truck_assigned.connect(_on_truck_assigned.bind(pine_forest))
	oak_forest.truck_assigned.connect(_on_truck_assigned.bind(oak_forest))
	birch_forest.truck_assigned.connect(_on_truck_assigned.bind(birch_forest))

	_build_shop()
	_update_delivered_label()

	# Start with 1 free Small truck
	_create_truck("Small")


func _build_shop() -> void:
	for truck_name in TRUCK_DATA:
		var tdata: Dictionary = TRUCK_DATA[truck_name]
		if tdata["cost"] == 0:
			continue  # Don't show free trucks in shop

		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0, 70)
		var style := StyleBoxFlat.new()
		style.bg_color = tdata["color"].darkened(0.5)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 8
		vbox.offset_top = 4
		vbox.offset_right = -8
		vbox.offset_bottom = -4
		panel.add_child(vbox)

		var name_lbl := Label.new()
		name_lbl.text = "%s Truck" % truck_name
		#name_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(name_lbl)

		var info_lbl := Label.new()
		info_lbl.text = "Speed: %d | Cap: %d" % [int(tdata["speed"]), tdata["capacity"]]
		#info_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(info_lbl)

		var buy_btn := Button.new()
		buy_btn.position.x = 200
		buy_btn.size.y = 30
		buy_btn.text = "Buy — %d coins" % tdata["cost"]
		buy_btn.pressed.connect(_on_buy_truck.bind(truck_name))
		vbox.add_child(buy_btn)

		shop_list.add_child(panel)


func _create_truck(truck_name: String) -> void:
	var tdata: Dictionary = TRUCK_DATA[truck_name]
	var truck: Control = SupplyTruckScene.instantiate()
	truck.truck_type = truck_name
	truck.speed = tdata["speed"]
	truck.capacity = tdata["capacity"]
	truck.truck_color = tdata["color"]
	truck.delivered.connect(_on_truck_delivered)
	truck_pool.add_child(truck)
	pool_trucks.append(truck)


func _on_buy_truck(truck_name: String) -> void:
	var tdata: Dictionary = TRUCK_DATA[truck_name]
	purchase_requested.emit(tdata["cost"])
	_create_truck(truck_name)


func _on_truck_assigned(truck: Control, forest: Control) -> void:
	# Remove from pool
	if truck in pool_trucks:
		pool_trucks.erase(truck)
		truck_pool.remove_child(truck)
	elif truck in active_trucks:
		active_trucks.erase(truck)

	# Reparent to routes node for free positioning
	if truck.get_parent():
		truck.get_parent().remove_child(truck)
	routes_node.add_child(truck)

	var factory_pos := factory_entrance.global_position + Vector2(50, 60)
	truck.assign_to_forest(forest, factory_pos)
	active_trucks.append(truck)
	routes_node.queue_redraw()


func _return_truck_to_pool(truck: Control) -> void:
	if truck in active_trucks:
		active_trucks.erase(truck)
	if truck.get_parent():
		truck.get_parent().remove_child(truck)
	truck.position = Vector2.ZERO
	truck.visible = true
	truck_pool.add_child(truck)
	pool_trucks.append(truck)
	routes_node.queue_redraw()


func _on_truck_delivered(count: int) -> void:
	total_wood_delivered += count
	wood_delivered.emit(count)
	_update_delivered_label()


func _update_delivered_label() -> void:
	delivered_label.text = "Wood Delivered: %d" % total_wood_delivered

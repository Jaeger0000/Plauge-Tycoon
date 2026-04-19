extends Control

signal truck_assigned(truck: Control)

@export var forest_name: String = "Forest"
@export var max_stock: int = 10
@export var regen_rate: float = 3.0
@export var forest_color: Color = Color(0.2, 0.5, 0.2)

var current_stock: int = 0

@onready var stock_label: Label = %StockLabel
@onready var regen_timer: Timer = %RegenTimer
@onready var bg_rect: ColorRect = %BgRect


func _ready() -> void:
	current_stock = max_stock
	bg_rect.color = forest_color
	regen_timer.wait_time = regen_rate
	regen_timer.timeout.connect(_on_regen)
	regen_timer.start()
	_update_label()


func _on_regen() -> void:
	if current_stock < max_stock:
		current_stock += 1
		_update_label()


func take_wood(amount: int) -> int:
	var taken := mini(amount, current_stock)
	current_stock -= taken
	_update_label()
	return taken


func _update_label() -> void:
	stock_label.text = "%s: %d/%d" % [forest_name, current_stock, max_stock]
	# Dim color when stock is low
	var ratio := float(current_stock) / float(max_stock) if max_stock > 0 else 0.0
	var dim := lerpf(0.4, 1.0, ratio)
	bg_rect.color = forest_color * Color(dim, dim, dim, 1.0)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "supply_truck"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.get("type") == "supply_truck":
		var truck: Control = data["truck"]
		truck_assigned.emit(truck)

extends Control

signal clicked(shop: Control)

@export var shop_name: String = "Shop"
@export var demand: int = 2
@export var shop_color: Color = Color(0.4, 0.6, 0.9)

var fulfilled: bool = false
var _hover: bool = false

@onready var bg: ColorRect = $BG
@onready var name_label: Label = $NameLabel
@onready var demand_label: Label = $DemandLabel
@onready var regen_timer: Timer = $RegenTimer


func _ready() -> void:
	bg.color = shop_color
	name_label.text = shop_name
	demand_label.text = "Demand: %d" % demand
	regen_timer.timeout.connect(_on_regen_timeout)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if !fulfilled:
				clicked.emit(self)
			accept_event()


func _on_mouse_entered() -> void:
	_hover = true
	_update_visual()


func _on_mouse_exited() -> void:
	_hover = false
	_update_visual()


func fulfill_demand(crates: int) -> int:
	var delivered := mini(crates, demand)
	demand -= delivered
	if demand <= 0:
		fulfilled = true
		demand = 0
		regen_timer.start()
	_update_visual()
	return delivered


func _on_regen_timeout() -> void:
	demand = randi_range(1, 4)
	fulfilled = false
	_update_visual()


func _update_visual() -> void:
	if fulfilled:
		bg.color = shop_color.darkened(0.5)
		demand_label.text = "✓"
	else:
		bg.color = shop_color.lightened(0.2) if _hover else shop_color
		demand_label.text = "Demand: %d" % demand


func get_center_position() -> Vector2:
	return position + size / 2.0

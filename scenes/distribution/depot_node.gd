extends Control

signal clicked(depot: Control)

var crate_pool: Array[int] = []
var crate_count: int:
	get: return crate_pool.size()
var _hover: bool = false

@onready var bg: ColorRect = $BG
@onready var name_label: Label = $NameLabel
@onready var crate_label: Label = $CrateLabel


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_label()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()


func _on_mouse_entered() -> void:
	_hover = true
	bg.color = Color(0.3, 0.7, 0.3)


func _on_mouse_exited() -> void:
	_hover = false
	bg.color = Color(0.2, 0.6, 0.2)


func add_crate(furniture_count: int) -> void:
	crate_pool.append(furniture_count)
	_update_label()


func take_crates(count: int) -> Array[int]:
	var taken_count := mini(count, crate_pool.size())
	var taken: Array[int] = []
	for i in range(taken_count):
		taken.append(crate_pool[i])
	crate_pool = crate_pool.slice(taken_count)
	_update_label()
	return taken


func get_total_furniture() -> int:
	var total := 0
	for c in crate_pool:
		total += c
	return total

func _update_label() -> void:
	crate_label.text = "Crates: %d (%d pcs)" % [crate_count, get_total_furniture()]


func get_center_position() -> Vector2:
	return position + size / 2.0

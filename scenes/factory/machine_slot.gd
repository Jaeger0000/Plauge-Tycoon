class_name MachineSlot
extends Panel

signal machine_ejected(machine_name: String)

var machine_type: String = ""
var stage_name: String = ""
var input_belt: ConveyorBelt = null
var output_belt: ConveyorBelt = null
var factory_zone: Control = null

var is_processing: bool = false
var current_item: Control = null
var process_time: float = 0.0
var elapsed_time: float = 0.0

@onready var name_label: Label = $VBox/NameLabel
@onready var status_label: Label = $VBox/StatusLabel
@onready var progress_bar: ProgressBar = $VBox/ProgressBar
@onready var type_label: Label = $VBox/TypeLabel


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_display()


func install_machine(type: String) -> void:
	machine_type = type
	_update_display()


func eject_machine() -> String:
	if is_processing:
		return ""
	var old_type := machine_type
	machine_type = ""
	_update_display()
	return old_type


func _update_display() -> void:
	if not is_inside_tree():
		return
	if machine_type.is_empty():
		name_label.text = "EMPTY SLOT"
		status_label.text = "Drag machine here"
		type_label.text = ""
		progress_bar.value = 0
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.3, 0.3, 0.3, 0.5)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		add_theme_stylebox_override("panel", style)
	else:
		var mdata: Dictionary = FactoryData.MACHINES[machine_type]
		name_label.text = machine_type
		type_label.text = "Ster:x%.1f Cut:x%.1f Pkg:x%.1f" % [
			mdata["sterilize_speed"], mdata["cutting_speed"], mdata["packaging_speed"]
		]
		var style := StyleBoxFlat.new()
		style.bg_color = mdata["color"].darkened(0.6)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = mdata["color"].darkened(0.2)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		add_theme_stylebox_override("panel", style)
		if not is_processing:
			status_label.text = "Idle"
		progress_bar.value = 0


func _process(delta: float) -> void:
	if machine_type.is_empty():
		return

	if is_processing:
		elapsed_time += delta
		if process_time > 0:
			progress_bar.value = (elapsed_time / process_time) * 100.0
		if elapsed_time >= process_time:
			_finish_processing()
		else:
			var remaining := maxf(process_time - elapsed_time, 0.0)
			status_label.text = "Processing... %.1fs" % remaining
	else:
		# Try to pick an item from input belt
		if input_belt and input_belt.has_items():
			var item: Control = input_belt.take_item()
			_start_processing(item)


func _start_processing(item: Control) -> void:
	current_item = item
	item.visible = false
	add_child(item)
	process_time = FactoryData.get_process_time(
		item.furniture_type, stage_name, machine_type
	)
	elapsed_time = 0.0
	is_processing = true
	progress_bar.value = 0
	status_label.text = "Processing %s..." % item.furniture_type


func _finish_processing() -> void:
	is_processing = false
	var item := current_item
	current_item = null
	elapsed_time = 0.0
	progress_bar.value = 0
	status_label.text = "Idle"

	item.advance_stage()
	item.visible = true
	remove_child(item)

	if output_belt:
		output_belt.add_item(item)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("type") != "machine":
		return false
	if not machine_type.is_empty():
		return false
	# Check budget
	if factory_zone:
		return factory_zone.budget >= data.get("machine_cost", 0)
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var cost: int = data.get("machine_cost", 0)
	if factory_zone:
		factory_zone.budget -= cost
		factory_zone._update_budget_label()
	install_machine(data["machine_name"])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not machine_type.is_empty() and not is_processing:
				var ejected := eject_machine()
				if factory_zone and not ejected.is_empty():
					# Refund half the cost
					var refund: int = FactoryData.MACHINES[ejected]["cost"] / 2
					factory_zone.budget += refund
					factory_zone._update_budget_label()
				machine_ejected.emit(ejected)

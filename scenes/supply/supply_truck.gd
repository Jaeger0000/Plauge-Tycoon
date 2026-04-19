extends Control

signal delivered(count: int)

enum State { IDLE, DRIVING_TO_FOREST, LOADING, DRIVING_TO_FACTORY, UNLOADING }

@export var truck_type: String = "Small"
@export var speed: float = 300.0
@export var capacity: int = 2
@export var truck_color: Color = Color(0.9, 0.85, 0.2)

var assigned_forest: Control = null
var factory_target: Vector2 = Vector2(1700, 540)
var forest_target: Vector2 = Vector2.ZERO
var cargo: int = 0
var state: int = State.IDLE
var load_timer: float = 0.0

const LOAD_TIME := 0.5
const UNLOAD_TIME := 0.3

@onready var bg_rect: ColorRect = %BgRect
@onready var cargo_label: Label = %CargoLabel


func _ready() -> void:
	bg_rect.color = truck_color
	_update_label()


func assign_to_forest(forest: Control, factory_pos: Vector2) -> void:
	assigned_forest = forest
	factory_target = factory_pos
	forest_target = forest.global_position + Vector2(60, 50)
	state = State.DRIVING_TO_FOREST
	visible = true


func unassign() -> void:
	assigned_forest = null
	state = State.IDLE
	cargo = 0
	_update_label()


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			return
		State.DRIVING_TO_FOREST:
			_move_toward(forest_target, delta)
			if global_position.distance_to(forest_target) < 5.0:
				state = State.LOADING
				load_timer = LOAD_TIME
		State.LOADING:
			load_timer -= delta
			if load_timer <= 0.0:
				if assigned_forest and assigned_forest.has_method("take_wood"):
					cargo = assigned_forest.take_wood(capacity)
				_update_label()
				if cargo > 0:
					state = State.DRIVING_TO_FACTORY
				else:
					# No wood available, wait a moment and retry
					load_timer = 0.5
		State.DRIVING_TO_FACTORY:
			_move_toward(factory_target, delta)
			if global_position.distance_to(factory_target) < 5.0:
				state = State.UNLOADING
				load_timer = UNLOAD_TIME
		State.UNLOADING:
			load_timer -= delta
			if load_timer <= 0.0:
				if cargo > 0:
					delivered.emit(cargo)
					cargo = 0
					_update_label()
				state = State.DRIVING_TO_FOREST


func _move_toward(target: Vector2, delta: float) -> void:
	var dir := (target - global_position).normalized()
	var dist := speed * delta
	if global_position.distance_to(target) <= dist:
		global_position = target
	else:
		global_position += dir * dist


func _update_label() -> void:
	if cargo_label:
		cargo_label.text = "%d" % cargo if cargo > 0 else ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if state != State.IDLE and state != State.DRIVING_TO_FOREST and state != State.LOADING:
		# Only allow drag when idle or near forest
		pass
	# Create drag preview
	var preview := ColorRect.new()
	preview.size = Vector2(50, 30)
	preview.color = truck_color
	preview.modulate.a = 0.7
	set_drag_preview(preview)
	return {"type": "supply_truck", "truck": self}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			unassign()
			get_parent().get_parent()._return_truck_to_pool(self)

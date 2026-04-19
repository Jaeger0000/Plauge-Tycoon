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

const TRUCK_SHEETS := {
	"Small": "res://sprites/truck_1.png",
	"Medium": "res://sprites/truck_2.png",
	"Large": "res://sprites/truck_3.png",
}
const FRAME_SIZE := 192
const ANIM_FPS := 6.0
const DOT_RADIUS := 6.0
const SPRITE_SCALE := 0.45

var _frames: Array[AtlasTexture] = []
var _frame_index: int = 0
var _anim_timer: float = 0.0

@onready var cargo_label: Label = %CargoLabel


func _ready() -> void:
	# Load spritesheet frames
	var sheet_path: String = TRUCK_SHEETS.get(truck_type, TRUCK_SHEETS["Small"])
	var sheet: Texture2D = load(sheet_path)
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		_frames.append(atlas)
	_update_label()


func _draw() -> void:
	# Draw bordered dot at bottom center
	var dot_center := Vector2(size.x / 2.0, size.y - DOT_RADIUS - 1.0)
	draw_circle(dot_center, DOT_RADIUS, truck_color)
	draw_arc(dot_center, DOT_RADIUS, 0, TAU, 24, Color.WHITE, 1.5)

	# Draw animated sprite above the dot, bottom center aligned
	if _frames.size() > 0:
		var tex: AtlasTexture = _frames[_frame_index]
		var draw_size := Vector2(FRAME_SIZE * SPRITE_SCALE, FRAME_SIZE * SPRITE_SCALE)
		var draw_pos := Vector2(
			dot_center.x - draw_size.x / 2.0,
			dot_center.y - DOT_RADIUS - draw_size.y
		)
		draw_texture_rect(tex, Rect2(draw_pos, draw_size), false)


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


func _get_dot_global_pos() -> Vector2:
	return global_position + Vector2(size.x / 2.0, size.y - DOT_RADIUS - 1.0)


func _process(delta: float) -> void:
	# Animate sprite
	if state != State.IDLE and _frames.size() > 0:
		_anim_timer += delta
		if _anim_timer >= 1.0 / ANIM_FPS:
			_anim_timer -= 1.0 / ANIM_FPS
			_frame_index = (_frame_index + 1) % _frames.size()
			queue_redraw()

	match state:
		State.IDLE:
			return
		State.DRIVING_TO_FOREST:
			_move_toward(forest_target, delta)
			if _get_dot_global_pos().distance_to(forest_target) < 5.0:
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
			if _get_dot_global_pos().distance_to(factory_target) < 5.0:
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
	# Offset so the dot (bottom-center) sits on the target point
	var dot_offset := Vector2(size.x / 2.0, size.y - DOT_RADIUS - 1.0)
	var adjusted_target := target - dot_offset
	var dir := (adjusted_target - global_position).normalized()
	var dist := speed * delta
	if global_position.distance_to(adjusted_target) <= dist:
		global_position = adjusted_target
	else:
		global_position += dir * dist


func _update_label() -> void:
	if cargo_label:
		cargo_label.text = "%d" % cargo if cargo > 0 else ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if state != State.IDLE and state != State.DRIVING_TO_FOREST and state != State.LOADING:
		# Only allow drag when idle or near forest
		pass
	# Create drag preview — small dot
	var preview := ColorRect.new()
	preview.size = Vector2(16, 16)
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

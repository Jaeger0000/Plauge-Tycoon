extends Control

signal delivery_complete(total_delivered: int)

var route: Array = []
var route_shops: Array = []
var current_waypoint: int = 0
var is_moving: bool = false
var speed: float = 200.0
var cargo: Array[int] = []
var total_furniture_delivered: int = 0
var stop_timer: float = 0.0

const STOP_DURATION := 0.5
const FRAME_SIZE := 192
const ANIM_FPS := 6.0
const DOT_RADIUS := 6.0
const SPRITE_SCALE := 0.45
const TRUCK_COLOR := Color(0.85, 0.25, 0.2)

var _frames: Array[AtlasTexture] = []
var _frame_index: int = 0
var _anim_timer: float = 0.0


func _ready() -> void:
	visible = false
	var sheet: Texture2D = load("res://sprites/truck_3.png")
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		_frames.append(atlas)


func _draw() -> void:
	# Draw bordered dot at bottom center
	var dot_center := Vector2(size.x / 2.0, size.y - DOT_RADIUS - 1.0)
	draw_circle(dot_center, DOT_RADIUS, TRUCK_COLOR)
	draw_arc(dot_center, DOT_RADIUS, 0, TAU, 24, Color.WHITE, 1.5)

	# Draw animated sprite above the dot
	if _frames.size() > 0:
		var tex: AtlasTexture = _frames[_frame_index]
		var draw_size := Vector2(FRAME_SIZE * SPRITE_SCALE, FRAME_SIZE * SPRITE_SCALE)
		var draw_pos := Vector2(
			dot_center.x - draw_size.x / 2.0,
			dot_center.y - DOT_RADIUS - draw_size.y
		)
		draw_texture_rect(tex, Rect2(draw_pos, draw_size), false)


func _get_dot_offset() -> Vector2:
	return Vector2(size.x / 2.0, size.y - DOT_RADIUS - 1.0)


func start_route(waypoints: Array, shops: Array, crates: Array[int]) -> void:
	if waypoints.size() < 2:
		return
	route = waypoints
	route_shops = shops
	cargo = crates.duplicate()
	total_furniture_delivered = 0
	is_moving = true
	visible = true
	position = route[0] - _get_dot_offset()
	current_waypoint = 1
	stop_timer = 0.0


func _process(delta: float) -> void:
	if !is_moving or route.is_empty():
		return

	# Animate sprite while moving
	if _frames.size() > 0:
		_anim_timer += delta
		if _anim_timer >= 1.0 / ANIM_FPS:
			_anim_timer -= 1.0 / ANIM_FPS
			_frame_index = (_frame_index + 1) % _frames.size()
			queue_redraw()

	if stop_timer > 0.0:
		stop_timer -= delta
		return

	if current_waypoint >= route.size():
		_finish_route()
		return

	var dot_offset := _get_dot_offset()
	var target: Vector2 = route[current_waypoint] - dot_offset
	var dir := (target - position).normalized()
	var dist := position.distance_to(target)
	var move_dist := speed * delta

	if move_dist >= dist:
		position = target
		_arrive_at_waypoint()
	else:
		position += dir * move_dist


func _arrive_at_waypoint() -> void:
	if current_waypoint < route_shops.size() and route_shops[current_waypoint] != null:
		var shop = route_shops[current_waypoint]
		if shop.has_method("fulfill_demand") and cargo.size() > 0:
			var crate_demand: int = shop.fulfill_demand(cargo.size())
			for i in range(crate_demand):
				total_furniture_delivered += cargo[0]
				cargo.remove_at(0)
			stop_timer = STOP_DURATION
	current_waypoint += 1


func _finish_route() -> void:
	is_moving = false
	visible = false
	delivery_complete.emit(total_furniture_delivered)

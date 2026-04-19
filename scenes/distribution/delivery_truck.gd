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


func _ready() -> void:
	visible = false


func start_route(waypoints: Array, shops: Array, crates: Array[int]) -> void:
	if waypoints.size() < 2:
		return
	route = waypoints
	route_shops = shops
	cargo = crates.duplicate()
	total_furniture_delivered = 0
	is_moving = true
	visible = true
	position = route[0] - size / 2.0
	current_waypoint = 1
	stop_timer = 0.0


func _process(delta: float) -> void:
	if !is_moving or route.is_empty():
		return

	if stop_timer > 0.0:
		stop_timer -= delta
		return

	if current_waypoint >= route.size():
		_finish_route()
		return

	var target: Vector2 = route[current_waypoint] - size / 2.0
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

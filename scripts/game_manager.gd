extends Node

var scores := {
	"supply": -1,
	"factory_assignment": -1,
	"factory_binpacking": -1,
	"distribution": -1,
}

var furniture_delivered: int = 0
var game_time: float = 300.0
var optimal_deliveries: int = 0

var backend_url := "http://localhost:8000"

# --- Player stats ---
var player_wood_delivered: int = 0
var player_truck_cost: int = 0
var player_items_processed: int = 0    # items through all 3 factory stages
var player_machine_cost: int = 0
var player_crates_packed: int = 0
var player_packing_cost: int = 0
var player_deliveries: int = 0
var player_route_distance: float = 0.0
var player_budget_spent: int = 0

# --- Optimal stats (from solvers) ---
var optimal_wood_delivered: int = 0
var optimal_items_processed: int = 0
var optimal_crates_packed: int = 0
var optimal_route_distance: float = 0.0

# --- Per-solver raw results ---
var solver_results: Dictionary = {}  # endpoint -> result dict


func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func calculate_score(player_cost: float, optimal_cost: float) -> int:
	if player_cost <= 0:
		return 0
	return int(clampf((optimal_cost / player_cost) * 100.0, 0.0, 100.0))


func get_stars(score: int) -> int:
	if score >= 100:
		return 3
	elif score >= 80:
		return 2
	elif score >= 60:
		return 1
	return 0


func reset_stats() -> void:
	furniture_delivered = 0
	player_wood_delivered = 0
	player_truck_cost = 0
	player_items_processed = 0
	player_machine_cost = 0
	player_crates_packed = 0
	player_packing_cost = 0
	player_deliveries = 0
	player_route_distance = 0.0
	player_budget_spent = 0
	optimal_wood_delivered = 0
	optimal_items_processed = 0
	optimal_crates_packed = 0
	optimal_deliveries = 0
	optimal_route_distance = 0.0
	solver_results.clear()

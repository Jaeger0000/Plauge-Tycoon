extends Node

var scores := {
	"supply": -1,
	"factory_assignment": -1,
	"factory_binpacking": -1,
	"distribution": -1,
}

var furniture_delivered: int = 0
var game_time: float = 300.0
var optimal_deliveries: int = 0  # populated by GAMSPy later

var backend_url := "http://localhost:8000"

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

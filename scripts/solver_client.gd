extends Node

## Singleton for communicating with the Python backend solver.

const BASE_URL := "http://localhost:8000"

signal solution_received(endpoint: String, result: Dictionary)
signal request_failed(endpoint: String, error: String)

var _http: HTTPRequest = null


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)


func solve_transport(forests: Array, factory_pos: Vector2, trucks: Array, time_remaining: float) -> void:
	var forest_data: Array = []
	for f in forests:
		forest_data.append({
			"name": f["name"],
			"capacity": f["capacity"],
			"regen_rate": f["regen_rate"],
			"position": [f["position"].x, f["position"].y],
		})

	var truck_data: Array = []
	for t in trucks:
		truck_data.append({
			"type": t["type"],
			"speed": t["speed"],
			"capacity": t["capacity"],
		})

	var body := {
		"forests": forest_data,
		"factory_position": [factory_pos.x, factory_pos.y],
		"trucks": truck_data,
		"time_remaining": time_remaining,
	}

	_post("/solve/transport", body)


func solve_assignment(machines: Dictionary, furniture_queue: Array, time_remaining: float) -> void:
	var body := {
		"machines": machines,
		"furniture_queue": furniture_queue,
		"time_remaining": time_remaining,
	}

	_post("/solve/assignment", body)


func solve_tsp(depot_pos: Vector2, shops: Array, truck_capacity: int, available_crates: int) -> void:
	var shop_data: Array = []
	for s in shops:
		shop_data.append({
			"name": s["name"],
			"position": [s["position"].x, s["position"].y],
			"demand": s["demand"],
		})

	var body := {
		"depot": [depot_pos.x, depot_pos.y],
		"shops": shop_data,
		"truck_capacity": truck_capacity,
		"available_crates": available_crates,
	}

	_post("/solve/tsp", body)


func _post(endpoint: String, body: Dictionary) -> void:
	var json_body := JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := BASE_URL + endpoint

	# Disconnect any previous signal
	if _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.disconnect(_on_request_completed)

	var current_endpoint := endpoint
	_http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
		_on_request_completed(result, response_code, _headers, body_bytes, current_endpoint)
		, CONNECT_ONE_SHOT
	)

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		request_failed.emit(endpoint, "HTTP request failed: %d" % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray, endpoint: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(endpoint, "Request error: %d" % result)
		return

	if response_code != 200:
		request_failed.emit(endpoint, "HTTP %d" % response_code)
		return

	var json := JSON.new()
	var parse_err := json.parse(body_bytes.get_string_from_utf8())
	if parse_err != OK:
		request_failed.emit(endpoint, "JSON parse error")
		return

	solution_received.emit(endpoint, json.data)

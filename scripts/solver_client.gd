extends Node

## Singleton for communicating with the Python backend solver.

const BASE_URL := "http://localhost:8000"

signal solution_received(endpoint: String, result: Dictionary)
signal request_failed(endpoint: String, error: String)

var _http: HTTPRequest = null
var _request_queue: Array = []  # [{endpoint, body}]
var _is_busy: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)


func solve_transport(forests: Array, factory_pos: Vector2, budget: int, owned_trucks: Dictionary, trucks: Array, time_remaining: float) -> void:
	var forest_data: Array = []
	for f in forests:
		forest_data.append({
			"name": f["name"],
			"capacity": f["capacity"],
			"regen_rate": f["regen_rate"],
			"position": [f["position"].x, f["position"].y],
			"current_stock": f.get("current_stock", 0),
		})

	var truck_data: Array = []
	for t in trucks:
		truck_data.append({
			"type": t["type"],
			"speed": t["speed"],
			"capacity": t["capacity"],
			"cost": t.get("cost", 0),
		})

	var body := {
		"forests": forest_data,
		"factory_position": [factory_pos.x, factory_pos.y],
		"budget": budget,
		"owned_trucks": owned_trucks,
		"trucks": truck_data,
		"time_remaining": time_remaining,
	}

	_enqueue("/solve/transport", body)


func solve_machine_placement(budget: int, time_remaining: float, corpse_count: int) -> void:
	var body := {
		"budget": budget,
		"time_remaining": time_remaining,
		"corpse_count": corpse_count,
	}

	_enqueue("/solve/machine_placement", body)


func solve_packing(crate_size: Array, items: Array, budget_remaining: int, packaging_cost_per_crate: int) -> void:
	var body := {
		"crate_size": crate_size,
		"items": items,
		"budget_remaining": budget_remaining,
		"packaging_cost_per_crate": packaging_cost_per_crate,
	}

	_enqueue("/solve/packing", body)


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

	_enqueue("/solve/tsp", body)


func _enqueue(endpoint: String, body: Dictionary) -> void:
	_request_queue.append({"endpoint": endpoint, "body": body})
	if not _is_busy:
		_process_next()


func _process_next() -> void:
	if _request_queue.is_empty():
		_is_busy = false
		return

	_is_busy = true
	var req: Dictionary = _request_queue.pop_front()
	_post(req["endpoint"], req["body"])


func _post(endpoint: String, body: Dictionary) -> void:
	var json_body := JSON.stringify(body)
	print("[SolverClient] POST %s" % endpoint)
	print("[SolverClient] Body: %s" % json_body)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := BASE_URL + endpoint

	var current_endpoint := endpoint
	_http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
		_on_request_completed(result, response_code, _headers, body_bytes, current_endpoint)
		, CONNECT_ONE_SHOT
	)

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		print("[SolverClient] ERROR sending %s: %d" % [endpoint, err])
		request_failed.emit(endpoint, "HTTP request failed: %d" % err)
		_process_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray, endpoint: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[SolverClient] FAIL %s: request error %d" % [endpoint, result])
		request_failed.emit(endpoint, "Request error: %d" % result)
		_process_next()
		return

	if response_code != 200:
		print("[SolverClient] FAIL %s: HTTP %d — %s" % [endpoint, response_code, body_bytes.get_string_from_utf8().left(300)])
		request_failed.emit(endpoint, "HTTP %d" % response_code)
		_process_next()
		return

	var json := JSON.new()
	var parse_err := json.parse(body_bytes.get_string_from_utf8())
	if parse_err != OK:
		print("[SolverClient] FAIL %s: JSON parse error" % endpoint)
		request_failed.emit(endpoint, "JSON parse error")
		_process_next()
		return

	print("[SolverClient] OK %s: %s" % [endpoint, JSON.stringify(json.data).left(300)])
	solution_received.emit(endpoint, json.data)
	_process_next()

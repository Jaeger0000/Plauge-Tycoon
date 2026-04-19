extends Control

var zone = null


func _draw() -> void:
	if zone == null:
		return

	# Road grid
	var grid_color := Color(0.25, 0.25, 0.35, 0.3)
	for x in range(0, 1921, 120):
		draw_line(Vector2(x, 0), Vector2(x, 970), grid_color, 1.0)
	for y in range(0, 971, 120):
		draw_line(Vector2(0, y), Vector2(1920, y), grid_color, 1.0)

	# Route lines
	if zone.route_points.size() < 2:
		return

	for i in range(zone.route_points.size() - 1):
		var from: Vector2 = zone.route_points[i]
		var to: Vector2 = zone.route_points[i + 1]
		draw_line(from, to, Color(1, 0.8, 0, 0.8), 3.0)

		var mid := (from + to) / 2.0
		var dist := from.distance_to(to) / 10.0
		var font := ThemeDB.fallback_font
		draw_string(font, mid + Vector2(5, -5), "%.0f km" % dist,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.7))

	for pt in zone.route_points:
		draw_circle(pt, 6.0, Color(1, 0.8, 0))

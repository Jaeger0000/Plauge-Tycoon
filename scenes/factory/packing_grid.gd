extends Control

var packing_area = null  # PackingArea reference
var _tex_cache: Dictionary = {}


func _get_cached_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = load(path)
	_tex_cache[path] = tex
	return tex


func _draw() -> void:
	# Crate background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.1, 1))

	var cs: int = PackingArea.CELL_SIZE
	var gs: int = PackingArea.GRID_SIZE

	# Grid lines
	for i in range(gs + 1):
		var x := float(i * cs)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.3, 0.3, 0.35, 0.7), 1.0)
		var y := float(i * cs)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.3, 0.3, 0.35, 0.7), 1.0)

	# Placed items
	if packing_area:
		for item in packing_area.placed_items:
			var rect := Rect2(
				Vector2(item["grid_x"] * cs + 2, item["grid_y"] * cs + 2),
				Vector2(item["w"] * cs - 4, item["h"] * cs - 4)
			)
			var sprite_path: String = item.get("sprite", "")
			var tex: Texture2D = _get_cached_texture(sprite_path)
			if tex:
				draw_texture_rect(tex, rect, false)
			else:
				draw_rect(rect, item["color"])
			draw_rect(rect, Color(1, 1, 1, 0.3), false, 1.0)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type") != "packing_item":
		return false
	if not packing_area:
		return false
	var cs: int = PackingArea.CELL_SIZE
	var gx := int(at_position.x) / cs
	var gy := int(at_position.y) / cs
	if not packing_area.has_queue_item(data["item_id"]):
		return false
	return packing_area.can_place(gx, gy, data["w"], data["h"])


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not packing_area:
		return
	var cs: int = PackingArea.CELL_SIZE
	var gx := int(at_position.x) / cs
	var gy := int(at_position.y) / cs
	packing_area.place_item_by_id(gx, gy, data["item_id"])

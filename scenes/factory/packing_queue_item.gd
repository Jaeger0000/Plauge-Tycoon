extends Control

var queue_index: int = 0
var item_data: Dictionary = {}


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_data.get("id", -1) < 0:
		return null
	var data := {
		"type": "packing_item",
		"item_id": item_data.get("id", -1),
		"queue_index": queue_index,
		"w": item_data.get("w", 1),
		"h": item_data.get("h", 1),
		"color": item_data.get("color", Color.WHITE),
		"furniture_type": item_data.get("type", ""),
		"sprite": item_data.get("sprite", ""),
	}

	# Preview using sprite
	var cell_px := 30
	var preview_size := Vector2(data["w"] * cell_px, data["h"] * cell_px)
	var sprite_path: String = data["sprite"]
	var preview: Control
	if not sprite_path.is_empty():
		var tex_preview := TextureRect.new()
		tex_preview.texture = load(sprite_path)
		tex_preview.custom_minimum_size = preview_size
		tex_preview.size = preview_size
		tex_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview = tex_preview
	else:
		var color_preview := ColorRect.new()
		color_preview.custom_minimum_size = preview_size
		color_preview.size = preview_size
		color_preview.color = data["color"]
		preview = color_preview
	set_drag_preview(preview)

	return data

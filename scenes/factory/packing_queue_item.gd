extends Panel

var queue_index: int = 0
var item_data: Dictionary = {}


func _get_drag_data(_at_position: Vector2) -> Variant:
	var data := {
		"type": "packing_item",
		"item_id": item_data.get("id", -1),
		"queue_index": queue_index,
		"w": item_data.get("w", 1),
		"h": item_data.get("h", 1),
		"color": item_data.get("color", Color.WHITE),
		"furniture_type": item_data.get("type", ""),
	}

	# Preview showing piece dimensions
	var cell_px := 30
	var preview := ColorRect.new()
	preview.custom_minimum_size = Vector2(data["w"] * cell_px, data["h"] * cell_px)
	preview.size = preview.custom_minimum_size
	preview.color = data["color"]
	var lbl := Label.new()
	lbl.text = data["furniture_type"]
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	preview.add_child(lbl)
	set_drag_preview(preview)

	return data

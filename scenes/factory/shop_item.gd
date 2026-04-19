extends Panel

var machine_name: String = ""
var machine_cost: int = 0
var factory_zone: Control = null


func _get_drag_data(_at_position: Vector2) -> Variant:
	if factory_zone and factory_zone.budget < machine_cost:
		return null

	var data := {
		"type": "worker",
		"machine_name": machine_name,
		"machine_cost": machine_cost,
	}

	# Drag preview — card sprite + name
	var preview := VBoxContainer.new()
	preview.add_theme_constant_override("separation", 2)

	var icon := TextureRect.new()
	var mdata: Dictionary = FactoryData.MACHINES[machine_name]
	var card_path: String = mdata.get("card", "")
	if not card_path.is_empty():
		icon.texture = load(card_path)
	else:
		var sprite_path: String = mdata.get("sprite", "")
		if not sprite_path.is_empty():
			var sheet: Texture2D = load(sprite_path)
			if sheet:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(0, 0, 96, 96)
				icon.texture = atlas
		else:
			icon.texture = preload("res://icon.svg")
			icon.modulate = mdata["color"]
	icon.custom_minimum_size = Vector2(64, 64)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(icon)

	var lbl := Label.new()
	lbl.text = machine_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_child(lbl)

	set_drag_preview(preview)

	return data

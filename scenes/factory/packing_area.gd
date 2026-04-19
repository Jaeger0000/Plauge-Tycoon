class_name PackingArea
extends Control

signal crate_shipped(furniture_count: int)

const GRID_SIZE := 6
const CELL_SIZE := 50
const GRID_PIXELS := GRID_SIZE * CELL_SIZE  # 300

var grid: Array = []
var placed_items: Array = []
var item_queue: Array = []
var _next_id: int = 0
var _queue_slots: Dictionary = {}  # furniture_type -> {slot, count_label}

@onready var grid_panel: Control = %GridPanel
@onready var queue_container: HBoxContainer = %QueueContainer
@onready var ship_button: Button = %ShipButton
@onready var crate_label: Label = %CrateLabel


func _ready() -> void:
	_init_grid()
	grid_panel.packing_area = self
	ship_button.pressed.connect(_on_ship_pressed)
	_build_queue_slots()


func _init_grid() -> void:
	grid.clear()
	for y in range(GRID_SIZE):
		var row: Array = []
		for x in range(GRID_SIZE):
			row.append(false)
		grid.append(row)


func add_packaged_item(furniture_type: String) -> void:
	var fdata: Dictionary = FactoryData.FURNITURE[furniture_type]
	var sprites: Array = fdata.get("sprites", [])
	var sprite_path: String = ""
	if sprites.size() > 0:
		sprite_path = sprites[randi() % sprites.size()]
	var item_data := {
		"id": _next_id,
		"type": furniture_type,
		"w": int(fdata["grid_w"]),
		"h": int(fdata["grid_h"]),
		"color": FactoryData.get_stage_color(FactoryData.STAGE_PACKAGED, furniture_type),
		"sprite": sprite_path,
	}
	_next_id += 1
	item_queue.append(item_data)
	_rebuild_queue_display()


func _rebuild_queue_display() -> void:
	_update_queue_counts()


func _build_queue_slots() -> void:
	for furniture_type in FactoryData.FURNITURE:
		var fdata: Dictionary = FactoryData.FURNITURE[furniture_type]
		var sprites: Array = fdata.get("sprites", [])
		var w: int = int(fdata["grid_w"])
		var h: int = int(fdata["grid_h"])

		var slot := Control.new()
		slot.custom_minimum_size = Vector2(w * CELL_SIZE, h * CELL_SIZE)
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# Grid background
		var bg := ColorRect.new()
		bg.color = Color(0.08, 0.08, 0.1, 1)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)

		# Sprite
		var icon := TextureRect.new()
		if sprites.size() > 0:
			icon.texture = load(sprites[0])
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 2
		icon.offset_top = 2
		icon.offset_right = -2
		icon.offset_bottom = -2
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		# Count badge at bottom right
		var count_lbl := Label.new()
		count_lbl.text = "x0"
		count_lbl.add_theme_font_size_override("font_size", 13)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_lbl.offset_left = -40
		count_lbl.offset_top = -20
		count_lbl.offset_right = -4
		count_lbl.offset_bottom = -2
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count_lbl)

		# Attach draggable script
		slot.set_script(preload("res://scenes/factory/packing_queue_item.gd"))
		slot.item_data = {
			"id": -1,
			"type": furniture_type,
			"w": w,
			"h": h,
			"color": fdata["color"],
			"sprite": sprites[0] if sprites.size() > 0 else "",
		}
		slot.queue_index = 0

		queue_container.add_child(slot)
		_queue_slots[furniture_type] = {"slot": slot, "count_label": count_lbl}

	_update_queue_counts()


func _update_queue_counts() -> void:
	# Count items per type
	var type_counts: Dictionary = {}
	var type_first_id: Dictionary = {}
	for idata in item_queue:
		var t: String = idata["type"]
		if not type_counts.has(t):
			type_counts[t] = 0
			type_first_id[t] = idata["id"]
		type_counts[t] += 1

	for furniture_type in _queue_slots:
		var slot_data: Dictionary = _queue_slots[furniture_type]
		var count: int = type_counts.get(furniture_type, 0)
		slot_data["count_label"].text = "x%d" % count
		# Update the item_data id to the first available item of this type
		var slot: Control = slot_data["slot"]
		if count > 0:
			slot.item_data["id"] = type_first_id[furniture_type]
			slot.modulate.a = 1.0
		else:
			slot.item_data["id"] = -1
			slot.modulate.a = 0.5


func has_queue_item(item_id: int) -> bool:
	for item in item_queue:
		if item["id"] == item_id:
			return true
	return false


func can_place(grid_x: int, grid_y: int, w: int, h: int) -> bool:
	if grid_x < 0 or grid_y < 0:
		return false
	if grid_x + w > GRID_SIZE or grid_y + h > GRID_SIZE:
		return false
	for cy in range(grid_y, grid_y + h):
		for cx in range(grid_x, grid_x + w):
			if grid[cy][cx]:
				return false
	return true


func place_item_by_id(grid_x: int, grid_y: int, item_id: int) -> void:
	var idx := -1
	for i in range(item_queue.size()):
		if item_queue[i]["id"] == item_id:
			idx = i
			break
	if idx < 0:
		return

	var idata: Dictionary = item_queue[idx]
	var w: int = idata["w"]
	var h: int = idata["h"]

	if not can_place(grid_x, grid_y, w, h):
		return

	# Mark grid cells
	for cy in range(grid_y, grid_y + h):
		for cx in range(grid_x, grid_x + w):
			grid[cy][cx] = true

	placed_items.append({
		"type": idata["type"],
		"grid_x": grid_x,
		"grid_y": grid_y,
		"w": w,
		"h": h,
		"color": idata["color"],
		"sprite": idata.get("sprite", ""),
	})

	item_queue.remove_at(idx)
	_rebuild_queue_display()
	grid_panel.queue_redraw()


func _on_ship_pressed() -> void:
	var count := placed_items.size()
	if count == 0:
		return
	placed_items.clear()
	_init_grid()
	grid_panel.queue_redraw()
	crate_shipped.emit(count)

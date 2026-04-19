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

@onready var grid_panel: Control = %GridPanel
@onready var queue_container: VBoxContainer = %QueueContainer
@onready var ship_button: Button = %ShipButton
@onready var crate_label: Label = %CrateLabel


func _ready() -> void:
	_init_grid()
	grid_panel.packing_area = self
	ship_button.pressed.connect(_on_ship_pressed)


func _init_grid() -> void:
	grid.clear()
	for y in range(GRID_SIZE):
		var row: Array = []
		for x in range(GRID_SIZE):
			row.append(false)
		grid.append(row)


func add_packaged_item(furniture_type: String) -> void:
	var fdata: Dictionary = FactoryData.FURNITURE[furniture_type]
	var item_data := {
		"id": _next_id,
		"type": furniture_type,
		"w": int(fdata["grid_w"]),
		"h": int(fdata["grid_h"]),
		"color": FactoryData.get_stage_color(FactoryData.STAGE_PACKAGED, furniture_type),
	}
	_next_id += 1
	item_queue.append(item_data)
	_rebuild_queue_display()


func _rebuild_queue_display() -> void:
	for child in queue_container.get_children():
		child.queue_free()

	for i in range(item_queue.size()):
		var idata: Dictionary = item_queue[i]
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0, 48)

		var pstyle := StyleBoxFlat.new()
		pstyle.bg_color = idata["color"]
		pstyle.corner_radius_top_left = 4
		pstyle.corner_radius_top_right = 4
		pstyle.corner_radius_bottom_left = 4
		pstyle.corner_radius_bottom_right = 4
		pstyle.content_margin_left = 10
		pstyle.content_margin_right = 10
		pstyle.content_margin_top = 4
		pstyle.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", pstyle)

		var lbl := Label.new()
		lbl.text = "%s  (%dx%d)" % [idata["type"], idata["w"], idata["h"]]
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.offset_left = 10
		lbl.offset_right = -10
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		panel.add_child(lbl)

		# Attach draggable script
		panel.set_script(preload("res://scenes/factory/packing_queue_item.gd"))
		panel.queue_index = i
		panel.item_data = idata
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		queue_container.add_child(panel)


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

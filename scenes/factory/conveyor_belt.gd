class_name ConveyorBelt
extends Control

var items: Array = []
var item_spacing := 34.0

# Band animation
var _band_frames: Array[AtlasTexture] = []
var _band_frame_index: int = 0
var _band_timer: float = 0.0
const BAND_FPS := 8.0
const BAND_FRAME_W := 48
const BAND_FRAME_H := 96


func _ready() -> void:
	clip_contents = true
	var sheet := preload("res://sprites/band.png")
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * BAND_FRAME_W, 0, BAND_FRAME_W, BAND_FRAME_H)
		_band_frames.append(atlas)


func _draw() -> void:
	if _band_frames.is_empty():
		return
	var tex: AtlasTexture = _band_frames[_band_frame_index]
	var tile_h := size.x * (float(BAND_FRAME_H) / float(BAND_FRAME_W))
	var count := int(ceil(size.y / tile_h))
	for i in count:
		var r := Rect2(0, i * tile_h, size.x, tile_h)
		draw_texture_rect(tex, r, false)


func add_item(item: Control) -> void:
	items.append(item)
	add_child(item)
	item.position = Vector2((size.x - item.size.x) / 2.0, -item.size.y)


func take_item() -> Control:
	if items.is_empty():
		return null
	var item: Control = items.pop_front()
	remove_child(item)
	return item


func has_items() -> bool:
	return not items.is_empty()


func item_count() -> int:
	return items.size()


func _process(delta: float) -> void:
	# Advance band animation
	_band_timer += delta
	if _band_timer >= 1.0 / BAND_FPS:
		_band_timer -= 1.0 / BAND_FPS
		_band_frame_index = (_band_frame_index + 1) % _band_frames.size()
		queue_redraw()

	# Stack items from bottom to top, oldest at bottom
	var y_cursor := size.y
	for i in range(items.size()):
		var item: Control = items[i]
		var center_x := (size.x - item.size.x) / 2.0
		y_cursor -= item.size.y
		var target_y := y_cursor
		y_cursor -= 4.0  # gap between items
		item.position.x = lerpf(item.position.x, center_x, delta * 8.0)
		item.position.y = lerpf(item.position.y, target_y, delta * 8.0)

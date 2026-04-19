class_name ConveyorBelt
extends Control

var items: Array = []
var item_spacing := 34.0


func _ready() -> void:
	clip_contents = true


func _draw() -> void:
	# Belt background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.22, 0.18, 0.9))
	# Belt stripes
	var stripe_count := int(size.y / 20.0) + 1
	for i in range(stripe_count):
		var y := float(i) * 20.0
		draw_line(Vector2(2, y), Vector2(size.x - 2, y), Color(0.35, 0.3, 0.25, 0.5), 1.0)


func add_item(item: Control) -> void:
	items.append(item)
	add_child(item)
	item.position = Vector2((size.x - 30.0) / 2.0, -30.0)


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
	var center_x := (size.x - 30.0) / 2.0
	for i in range(items.size()):
		var item: Control = items[i]
		# Stack from bottom, oldest (index 0) at bottom
		var target_y := size.y - 34.0 - float(i) * item_spacing
		target_y = maxf(target_y, float(i) * item_spacing)
		item.position.x = lerpf(item.position.x, center_x, delta * 8.0)
		item.position.y = lerpf(item.position.y, target_y, delta * 8.0)

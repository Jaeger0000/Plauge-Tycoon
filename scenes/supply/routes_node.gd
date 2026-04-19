extends Control

# Draws route lines from assigned trucks' forests to factory entrance

func _draw() -> void:
	var supply_zone: Control = get_parent()
	if not supply_zone:
		return
	var factory_entrance: Control = supply_zone.get_node_or_null("%FactoryEntrance")
	if not factory_entrance:
		return
	var factory_pos := factory_entrance.position + Vector2(50, 60)

	for truck in get_children():
		if not truck.has_method("assign_to_forest"):
			continue
		if truck.assigned_forest == null:
			continue
		var forest_pos: Vector2 = truck.assigned_forest.position + Vector2(60, 50)
		var line_color: Color = truck.truck_color
		line_color.a = 0.35
		draw_line(forest_pos, factory_pos, line_color, 2.0)

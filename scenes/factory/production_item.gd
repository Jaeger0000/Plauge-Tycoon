class_name ProductionItem
extends ColorRect

var furniture_type: String = "Chair"
var current_stage: int = FactoryData.STAGE_RAW


func _ready() -> void:
	custom_minimum_size = Vector2(30, 30)
	size = Vector2(30, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_color()


func setup(type: String, stage: int = FactoryData.STAGE_RAW) -> void:
	furniture_type = type
	current_stage = stage
	_update_color()


func advance_stage() -> void:
	current_stage += 1
	_update_color()


func _update_color() -> void:
	color = FactoryData.get_stage_color(current_stage, furniture_type)

class_name ProductionItem
extends TextureRect

var furniture_type: String = "Chair"
var current_stage: int = FactoryData.STAGE_RAW

const STAGE_SPRITES := {
	FactoryData.STAGE_RAW: "res://sprites/body_1.png",
	FactoryData.STAGE_STERILIZED: "res://sprites/body_2.png",
	FactoryData.STAGE_CUT: "res://sprites/body_3.png",
	FactoryData.STAGE_PACKAGED: "res://sprites/body_4.png",
}


func _ready() -> void:
	custom_minimum_size = Vector2(54, 90)
	size = Vector2(54, 90)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_update_sprite()


func setup(type: String, stage: int = FactoryData.STAGE_RAW) -> void:
	furniture_type = type
	current_stage = stage
	_update_sprite()


func advance_stage() -> void:
	current_stage += 1
	_update_sprite()


func _update_sprite() -> void:
	var path: String = STAGE_SPRITES.get(current_stage, "")
	if not path.is_empty():
		texture = load(path)
	else:
		texture = null

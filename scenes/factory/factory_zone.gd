extends Control

signal furniture_produced
signal crate_ready(furniture_count: int)

var budget: int = 1000
var production_count: int = 0

var ProductionItemScene: PackedScene = preload("res://scenes/factory/production_item.tscn")

# Conveyors
@onready var input_conveyor: ConveyorBelt = %InputConveyor
@onready var cut_to_asm_conveyor: ConveyorBelt = %Belt1
@onready var asm_to_pkg_conveyor: ConveyorBelt = %Belt2
@onready var output_conveyor: ConveyorBelt = %OutputConveyor

# Machine slots per stage
@onready var sterilize_spots: Array = [
	$StagesArea/SterilizeGroup/SterilizeSpot0,
	$StagesArea/SterilizeGroup/SterilizeSpot1,
	$StagesArea/SterilizeGroup/SterilizeSpot2,
	$StagesArea/SterilizeGroup/SterilizeSpot3,
]
@onready var cutting_spots: Array = [
	$StagesArea/CuttingGroup/CuttingSpot0,
	$StagesArea/CuttingGroup/CuttingSpot1,
	$StagesArea/CuttingGroup/CuttingSpot2,
	$StagesArea/CuttingGroup/CuttingSpot3,
]
@onready var packaging_spots: Array = [
	$StagesArea/PackagingGroup/PackagingSpot0,
	$StagesArea/PackagingGroup/PackagingSpot1,
	$StagesArea/PackagingGroup/PackagingSpot2,
	$StagesArea/PackagingGroup/PackagingSpot3,
]

# Packing
@onready var packing_area: PackingArea = %PackingArea

@onready var budget_label: Label = %BudgetLabel
@onready var production_label: Label = %ProductionLabel
@onready var shop_list: HBoxContainer = %ShopList


func _ready() -> void:
	# Configure cutting work spots
	for spot in sterilize_spots:
		spot.stage_name = "sterilize"
		spot.input_belt = input_conveyor
		spot.output_belt = cut_to_asm_conveyor
		spot.factory_zone = self

	# Configure assembly work spots
	for spot in cutting_spots:
		spot.stage_name = "cutting"
		spot.input_belt = cut_to_asm_conveyor
		spot.output_belt = asm_to_pkg_conveyor
		spot.factory_zone = self

	# Configure packaging work spots
	for spot in packaging_spots:
		spot.stage_name = "packaging"
		spot.input_belt = asm_to_pkg_conveyor
		spot.output_belt = output_conveyor
		spot.factory_zone = self

	# Connect packing area signal
	packing_area.crate_shipped.connect(_on_crate_shipped)

	# Set workstation sprites
	var ster_tex := preload("res://sprites/table_ster.png")
	var chop_tex := preload("res://sprites/table_chop.png")
	var pack_tex := preload("res://sprites/table_pack.png")
	var ster_sheet := preload("res://sprites/table_ster_f.png")
	var chop_sheet := preload("res://sprites/table_chop_f.png")
	var pack_sheet := preload("res://sprites/table_pack_f.png")
	for spot in sterilize_spots:
		spot.set_workstation_texture(ster_tex)
		spot.set_workstation_spritesheet(ster_sheet)
	for spot in cutting_spots:
		spot.set_workstation_texture(chop_tex)
		spot.set_workstation_spritesheet(chop_sheet)
	for spot in packaging_spots:
		spot.set_workstation_texture(pack_tex)
		spot.set_workstation_spritesheet(pack_sheet)

	# Populate shop
	for machine_name in FactoryData.MACHINES:
		var mdata: Dictionary = FactoryData.MACHINES[machine_name]
		var card := _create_shop_item(machine_name, mdata)
		shop_list.add_child(card)

	_update_budget_label()
	_update_production_label()


func _create_shop_item(mname: String, mdata: Dictionary) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(150, 250)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = mdata["color"].darkened(0.2)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 6
	vbox.offset_right = -8
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Worker sprite placeholder — Godot icon tinted with worker color
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(icon_container)

	var worker_icon := TextureRect.new()
	var sprite_path: String = mdata.get("sprite", "")
	if not sprite_path.is_empty():
		var sheet: Texture2D = load(sprite_path)
		if sheet:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(0, 0, 96, 96)
			worker_icon.texture = atlas
	else:
		worker_icon.texture = preload("res://icon.svg")
		worker_icon.modulate = mdata["color"]
	worker_icon.custom_minimum_size = Vector2(72, 72)
	worker_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	worker_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(worker_icon)

	# Worker name
	var name_lbl := Label.new()
	name_lbl.text = mname
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	vbox.add_child(name_lbl)

	# Cost
	var cost_lbl := Label.new()
	cost_lbl.text = "%d coins" % mdata["cost"]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(cost_lbl)

	# Speed stats
	var speed_lbl := Label.new()
	speed_lbl.text = "Ster: x%.1f\nCut: x%.1f\nPkg: x%.1f" % [
		mdata["sterilize_speed"], mdata["cutting_speed"], mdata["packaging_speed"]
	]
	speed_lbl.add_theme_font_size_override("font_size", 11)
	speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(speed_lbl)

	# Attach draggable shop_item script
	panel.set_script(preload("res://scenes/factory/shop_item.gd"))
	panel.machine_name = mname
	panel.machine_cost = mdata["cost"]
	panel.factory_zone = self
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	return panel


# --- Runtime ---

func _process(_delta: float) -> void:
	# Drain output conveyor → packing area
	while output_conveyor and output_conveyor.has_items():
		var item: Control = output_conveyor.take_item()
		if packing_area:
			packing_area.add_packaged_item(item.furniture_type)
		item.queue_free()


func _on_crate_shipped(count: int) -> void:
	if budget < 50:
		push_warning("Factory budget low (%d) — shipping crate anyway" % budget)
	budget -= 50
	crate_ready.emit(count)
	for i in range(count):
		production_count += 1
		furniture_produced.emit()
	_update_budget_label()
	_update_production_label()


func _update_budget_label() -> void:
	budget_label.text = "Budget: %d coins" % budget


func _update_production_label() -> void:
	production_label.text = "Delivered: %d" % production_count

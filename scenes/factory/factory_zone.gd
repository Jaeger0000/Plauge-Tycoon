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
	var card: Control = preload("res://scenes/factory/shop_card.tscn").instantiate()

	var is_legend := mname == "Omega"
	var card_w := 128 if is_legend else 108
	var card_h := 228 if is_legend else 204
	card.custom_minimum_size = Vector2(card_w + 16, card_h + 50)

	# Set card sprite
	var card_path: String = mdata.get("card", "")
	if not card_path.is_empty():
		var card_sprite: TextureRect = card.get_node("%CardSprite")
		card_sprite.texture = load(card_path)
		# Omega's card_legend.png has a glare in top-left, visual center is at (72,124)
		# in a 126x228 image. Offset sprite to compensate: shift left 9px, up 10px.
		if is_legend:
			card_sprite.offset_left = -9
			card_sprite.offset_top = -10
			card_sprite.offset_right = -9
			card_sprite.offset_bottom = -10

	# Set text overlays
	card.get_node("%NameLabel").text = mname
	card.get_node("%CostLabel").text = "%d coins" % mdata["cost"]
	card.get_node("%SpeedLabel").text = "S:x%.1f C:x%.1f P:x%.1f" % [
		mdata["sterilize_speed"], mdata["cutting_speed"], mdata["packaging_speed"]
	]

	# Transparent panel background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	card.add_theme_stylebox_override("panel", style)

	# Set shop_item script properties
	card.machine_name = mname
	card.machine_cost = mdata["cost"]
	card.factory_zone = self

	return card


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

extends Control

@onready var title_label: Label = %TitleLabel
@onready var breakdown_container: VBoxContainer = %BreakdownContainer
@onready var total_score_label: Label = %TotalScoreLabel
@onready var stars_label: Label = %StarsLabel
@onready var back_button: Button = %BackButton

const STAGE_COLORS := {
	"supply": Color(0.3, 0.7, 0.3),
	"factory": Color(0.4, 0.5, 0.8),
	"packing": Color(0.7, 0.5, 0.2),
	"delivery": Color(0.8, 0.3, 0.3),
}


func _ready() -> void:
	title_label.text = "Time's Up!"

	var gm := GameManager
	var stage_scores: Array[int] = []

	# --- Supply Stage ---
	var supply_score := _add_stage("Supply — Wood Transport", STAGE_COLORS["supply"], [
		["Wood Delivered", str(gm.player_wood_delivered), str(gm.optimal_wood_delivered)],
		["Truck Cost", "%d coins" % gm.player_truck_cost, "—"],
	], gm.player_wood_delivered, gm.optimal_wood_delivered)
	stage_scores.append(supply_score)

	# --- Factory Stage ---
	var factory_score := _add_stage("Factory — Machine Placement", STAGE_COLORS["factory"], [
		["Items Processed", str(gm.player_items_processed), str(gm.optimal_items_processed)],
		["Machine Cost", "%d coins" % gm.player_machine_cost, "—"],
	], gm.player_items_processed, gm.optimal_items_processed)
	stage_scores.append(factory_score)

	# --- Packing Stage ---
	var packing_score := _add_stage("Packing — Crate Filling", STAGE_COLORS["packing"], [
		["Items Packed", str(gm.player_crates_packed), str(gm.optimal_crates_packed)],
		["Packing Cost", "%d coins" % gm.player_packing_cost, "—"],
	], gm.player_crates_packed, gm.optimal_crates_packed)
	stage_scores.append(packing_score)

	# --- Delivery Stage ---
	var delivery_score := _add_stage("Delivery — Route Optimization", STAGE_COLORS["delivery"], [
		["Furniture Delivered", str(gm.player_deliveries), str(gm.optimal_deliveries)],
	], gm.player_deliveries, gm.optimal_deliveries)
	stage_scores.append(delivery_score)

	# --- Budget Summary ---
	_add_budget_row(gm.player_budget_spent)

	# --- Overall Score ---
	var valid_scores: Array[int] = []
	for s in stage_scores:
		if s >= 0:
			valid_scores.append(s)

	if valid_scores.is_empty():
		total_score_label.text = "Overall Score: --"
		stars_label.text = ""
	else:
		var total := 0
		for s in valid_scores:
			total += s
		var avg := total / valid_scores.size()
		total_score_label.text = "Overall Score: %d%%" % avg
		var stars := GameManager.get_stars(avg)
		stars_label.text = "★".repeat(stars) + "☆".repeat(3 - stars)

	back_button.pressed.connect(_on_back_pressed)


func _add_stage(title: String, color: Color, rows: Array, player_val: int, optimal_val: int) -> int:
	# Stage header
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", color)
	breakdown_container.add_child(header)

	# Stat rows
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	breakdown_container.add_child(grid)

	# Column headers
	for col_name in ["", "You", "Optimal"]:
		var lbl := Label.new()
		lbl.text = col_name
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if col_name != "" else HORIZONTAL_ALIGNMENT_LEFT
		lbl.custom_minimum_size.x = 180 if col_name == "" else 100
		grid.add_child(lbl)

	for row in rows:
		for i in range(3):
			var lbl := Label.new()
			lbl.text = row[i]
			lbl.add_theme_font_size_override("font_size", 18)
			if i == 0:
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			else:
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(lbl)

	# Score for this stage
	var score := -1
	if optimal_val > 0:
		score = mini(int((float(player_val) / float(optimal_val)) * 100.0), 100)
		var score_lbl := Label.new()
		score_lbl.text = "  Stage Score: %d%%" % score
		score_lbl.add_theme_font_size_override("font_size", 16)
		score_lbl.add_theme_color_override("font_color", _score_color(score))
		breakdown_container.add_child(score_lbl)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	breakdown_container.add_child(sep)

	return score


func _add_budget_row(spent: int) -> void:
	var lbl := Label.new()
	lbl.text = "Total Budget Spent: %d / 1000 coins" % spent
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	breakdown_container.add_child(lbl)


func _score_color(score: int) -> Color:
	if score >= 80:
		return Color(0.3, 0.9, 0.3)
	elif score >= 50:
		return Color(0.9, 0.8, 0.2)
	return Color(0.9, 0.3, 0.3)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

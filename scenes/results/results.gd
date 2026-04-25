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

const STAGE_NAMES := {
	"sterilize": "Sterilize",
	"cutting": "Cutting",
	"packaging": "Packaging",
}

# Backend machine-placement solver currently reports stages as:
# cutting -> assembly -> packaging
# Game UI uses: sterilize -> cutting -> packaging
const BACKEND_STAGE_TO_UI_STAGE := {
	"cutting": "sterilize",
	"assembly": "cutting",
	"packaging": "packaging",
	"sterilize": "sterilize",
}

const MACHINE_COLORS := {
	"Basic": Color(0.6, 0.6, 0.8),
	"Butcher": Color(0.8, 0.6, 0.4),
	"Legend": Color(0.9, 0.8, 0.3),
	"Omega": Color(0.9, 0.4, 0.4),
}


func _ready() -> void:
	title_label.text = "Time's Up!"

	var gm := GameManager
	var stage_scores: Array[int] = []

	# --- Supply Stage ---
	var supply_score := _add_stage("Supply — Robot Part Transport", STAGE_COLORS["supply"], [
		["Robot Parts Delivered", str(gm.player_wood_delivered), str(gm.optimal_wood_delivered)],
		["Truck Cost", "%d coins" % gm.player_truck_cost, "—"],
	], gm.player_wood_delivered, gm.optimal_wood_delivered)
	stage_scores.append(supply_score)

	# --- Factory Stage ---
	var factory_score := _add_stage("Factory — Machine Placement", STAGE_COLORS["factory"], [
		["Items Processed", str(gm.player_items_processed), str(gm.optimal_items_processed)],
		["Machine Cost", "%d coins" % gm.player_machine_cost, "—"],
	], gm.player_items_processed, gm.optimal_items_processed)
	stage_scores.append(factory_score)
	
	# Add machine placement visualization
	_add_machine_placement_comparison()

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
		var avg := int(round(float(total) / float(valid_scores.size())))
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


func _add_machine_placement_comparison() -> void:
	"""Show visual comparison of player placement vs optimal placement."""
	
	# Get optimal placement from backend
	var mp_result = GameManager.solver_results.get("/solve/machine_placement", {})
	if mp_result.is_empty():
		return
	
	var optimal_assignments = mp_result.get("slot_assignments", [])
	if optimal_assignments.is_empty():
		return
	
	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	breakdown_container.add_child(sep)
	
	# Title
	var title := Label.new()
	title.text = "Optimal Machine Placement Strategy"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", STAGE_COLORS["factory"])
	breakdown_container.add_child(title)
	
	# Info text
	var info := Label.new()
	info.text = "This is the best machine configuration based on your items and budget."
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	breakdown_container.add_child(info)
	
	# Create comparison container
	var comparison_container := HBoxContainer.new()
	comparison_container.add_theme_constant_override("separation", 30)
	breakdown_container.add_child(comparison_container)
	
	# Left side: Stage breakdown
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 12)
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison_container.add_child(left_vbox)
	
	# Group assignments by stage
	var stages_data = {
		"sterilize": [],
		"cutting": [],
		"packaging": [],
	}
	
	for assignment in optimal_assignments:
		var backend_stage = assignment.get("stage", "")
		var ui_stage = BACKEND_STAGE_TO_UI_STAGE.get(backend_stage, backend_stage)
		if ui_stage in stages_data:
			stages_data[ui_stage].append(assignment)
	
	# Display each stage with visual representation
	for stage_key in ["sterilize", "cutting", "packaging"]:
		var stage_frame := PanelContainer.new()
		stage_frame.add_theme_stylebox_override("panel", _create_stage_style(stage_key))
		left_vbox.add_child(stage_frame)
		
		var stage_vbox := VBoxContainer.new()
		stage_vbox.add_theme_constant_override("separation", 8)
		stage_frame.add_child(stage_vbox)
		
		var stage_label := Label.new()
		stage_label.text = "■ %s Stage" % STAGE_NAMES.get(stage_key, stage_key).to_upper()
		stage_label.add_theme_font_size_override("font_size", 14)
		stage_label.add_theme_color_override("font_color", Color.WHITE)
		stage_vbox.add_child(stage_label)
		
		var assignments = stages_data[stage_key]
		if assignments.is_empty():
			var none_label := Label.new()
			none_label.text = "No machines needed"
			none_label.add_theme_font_size_override("font_size", 11)
			none_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			stage_vbox.add_child(none_label)
		else:
			# Create a machine list with visual boxes
			var machines_hbox := HBoxContainer.new()
			machines_hbox.add_theme_constant_override("separation", 6)
			stage_vbox.add_child(machines_hbox)
			
			for slot_data in assignments:
				var machine = slot_data.get("machine", "?")
				var cost = slot_data.get("machine_cost", 0)
				
				# Create machine box
				var machine_box := PanelContainer.new()
				machine_box.custom_minimum_size = Vector2(120, 60)
				var machine_style = _create_machine_style(machine)
				machine_box.add_theme_stylebox_override("panel", machine_style)
				machines_hbox.add_child(machine_box)
				
				var machine_content := VBoxContainer.new()
				machine_content.alignment = BoxContainer.ALIGNMENT_CENTER
				machine_box.add_child(machine_content)
				
				var machine_lbl := Label.new()
				machine_lbl.text = machine
				machine_lbl.add_theme_font_size_override("font_size", 13)
				machine_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				machine_lbl.add_theme_color_override("font_color", Color.WHITE)
				machine_content.add_child(machine_lbl)
				
				var cost_lbl := Label.new()
				cost_lbl.text = "%d💰" % cost
				cost_lbl.add_theme_font_size_override("font_size", 10)
				cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
				machine_content.add_child(cost_lbl)
	
	# Right side: Statistics
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 15)
	right_vbox.custom_minimum_size.x = 300
	comparison_container.add_child(right_vbox)
	
	# Stats title
	var stats_title := Label.new()
	stats_title.text = "Performance Metrics"
	stats_title.add_theme_font_size_override("font_size", 16)
	stats_title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	right_vbox.add_child(stats_title)
	
	# Stats items
	var stats_items = [
		["Total Machine Cost", "%d coins" % mp_result.get("total_machine_cost", 0), Color(0.9, 0.8, 0.2)],
		["Expected Output", "%d items" % mp_result.get("predicted_throughput", 0), Color(0.3, 0.8, 0.8)],
		["Processing Time", "%.1f sec" % mp_result.get("total_processing_time", 0.0), Color(0.8, 0.8, 0.3)],
		["Budget Remaining", "%d coins" % mp_result.get("remaining_budget", 0), Color(0.3, 0.8, 0.3)],
	]
	
	for stat_item in stats_items:
		var stat_hbox := HBoxContainer.new()
		stat_hbox.add_theme_constant_override("separation", 10)
		right_vbox.add_child(stat_hbox)
		
		var stat_name := Label.new()
		stat_name.text = stat_item[0]
		stat_name.add_theme_font_size_override("font_size", 12)
		stat_name.custom_minimum_size.x = 150
		stat_hbox.add_child(stat_name)
		
		var stat_value := Label.new()
		stat_value.text = stat_item[1]
		stat_value.add_theme_font_size_override("font_size", 12)
		stat_value.add_theme_color_override("font_color", stat_item[2])
		stat_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_hbox.add_child(stat_value)
	
	# Recommendation
	var rec_sep := HSeparator.new()
	rec_sep.add_theme_constant_override("separation", 8)
	right_vbox.add_child(rec_sep)
	
	var recommendation := Label.new()
	recommendation.text = "💡 Use this strategy in your next game to maximize efficiency!"
	recommendation.add_theme_font_size_override("font_size", 11)
	recommendation.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	recommendation.autowrap_mode = TextServer.AUTOWRAP_WORD
	right_vbox.add_child(recommendation)


func _create_stage_style(stage: String) -> StyleBox:
	"""Create a styled panel for a stage."""
	var style := StyleBoxFlat.new()
	match stage:
		"sterilize":
			style.bg_color = Color(0.2, 0.3, 0.2, 0.4)
			style.border_color = Color(0.4, 0.7, 0.4)
		"cutting":
			style.bg_color = Color(0.3, 0.2, 0.2, 0.4)
			style.border_color = Color(0.7, 0.4, 0.4)
		"packaging":
			style.bg_color = Color(0.3, 0.3, 0.2, 0.4)
			style.border_color = Color(0.7, 0.7, 0.4)
	
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	
	return style


func _create_machine_style(machine: String) -> StyleBox:
	"""Create a styled panel for a machine box."""
	var style := StyleBoxFlat.new()
	var color = MACHINE_COLORS.get(machine, Color(0.5, 0.5, 0.5))
	style.bg_color = color.darkened(0.3)
	style.border_color = color
	
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	
	return style

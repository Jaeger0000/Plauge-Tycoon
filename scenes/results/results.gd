extends Control

@onready var title_label: Label = %TitleLabel
@onready var delivered_label: Label = %DeliveredLabel
@onready var optimal_label: Label = %OptimalLabel
@onready var score_label: Label = %ResultScoreLabel
@onready var back_button: Button = %BackButton


func _ready() -> void:
	var delivered := GameManager.furniture_delivered
	var optimal := GameManager.optimal_deliveries

	title_label.text = "Time's Up!"
	delivered_label.text = "You delivered %d furniture" % delivered
	optimal_label.text = "Optimal solution could deliver %d furniture" % optimal

	if optimal > 0:
		var pct := int((float(delivered) / float(optimal)) * 100.0)
		score_label.text = "Score: %d%%" % pct
	else:
		score_label.text = "Score: --"

	back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

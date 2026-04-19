extends Control

func _ready() -> void:
	%StartButton.pressed.connect(func(): GameManager.change_scene("res://scenes/game_map/game_map.tscn"))
	%QuitButton.pressed.connect(func(): get_tree().quit())

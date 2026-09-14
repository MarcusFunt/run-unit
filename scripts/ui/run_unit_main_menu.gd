class_name RunUnitMainMenu
extends MainMenu

func _ready() -> void:
	super._ready()
	new_game_button.custom_minimum_size = Vector2(260.0, 54.0)
	options_button.custom_minimum_size = Vector2(260.0, 54.0)
	credits_button.custom_minimum_size = Vector2(260.0, 54.0)
	exit_button.custom_minimum_size = Vector2(260.0, 54.0)
	new_game_button.text = "START NEW RUN"
	options_button.text = "SYSTEM SETTINGS"
	credits_button.text = "CREDITS / INTEL"
	exit_button.text = "SHUT DOWN"

func new_game() -> void:
	SceneLoader.load_scene("res://scenes/level_selector.tscn")

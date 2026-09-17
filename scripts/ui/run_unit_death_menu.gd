class_name RunUnitDeathMenu
extends CanvasLayer

@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var restart_button: Button = %RestartButton
@onready var main_menu_button: Button = %MainMenuButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	hide()

func open_with_scores(distance: float, best: float) -> void:
	title_label.text = "UNIT OFFLINE"
	description_label.text = "%s TERMINATED\n\nRUN DISTANCE  %05dm\nBEST DISTANCE  %05dm\n\nSelect a recovery action." % [_get_route_title(), int(distance), int(best)]
	restart_button.text = "RETRY ROUTE"
	main_menu_button.text = "SECTOR SELECT"
	show()
	get_tree().paused = true
	restart_button.grab_focus()

func open_completed_with_scores(distance: float, best: float) -> void:
	title_label.text = "ROUTE COMPLETE"
	description_label.text = "%s CERTIFIED\n\nRUN DISTANCE  %05dm\nBEST DISTANCE  %05dm\n\nRoute traversal complete." % [_get_route_title(), int(distance), int(best)]
	restart_button.text = "REDEPLOY ROUTE"
	main_menu_button.text = "SECTOR SELECT"
	show()
	get_tree().paused = true
	restart_button.grab_focus()

func close() -> void:
	hide()

func _get_route_title() -> String:
	return RunUnitCampaign.get_title(RunUnitSession.selected_level_index)

func _on_restart_pressed() -> void:
	get_tree().paused = false
	SceneLoader.reload_current_scene()

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	SceneLoader.load_scene("res://scenes/level_selector.tscn")

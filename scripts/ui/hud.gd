class_name RunUnitHud
extends CanvasLayer

@onready var distance_label: Label = %DistanceLabel
@onready var best_label: Label = %BestLabel
@onready var score_progress_bar: ProgressBar = %ScoreProgressBar
@onready var status_label: Label = %StatusLabel
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var game_over_label: Label = %GameOverLabel

var _game_over_tween: Tween = null
var _level_length: float = 1.0

func _ready() -> void:
	score_progress_bar.max_value = _level_length
	game_over_panel.hide()

func set_scores(distance: float, best: float) -> void:
	var safe_distance: float = maxf(distance, 0.0)
	distance_label.text = "%05d" % int(safe_distance)
	score_progress_bar.value = clampf(safe_distance, 0.0, _level_length)
	best_label.text = "BEST  %05d" % int(best)

func set_level_length(length: float) -> void:
	_level_length = maxf(length, 1.0)
	score_progress_bar.max_value = _level_length

func set_status(text_value: String) -> void:
	status_label.text = text_value

func show_game_over(distance: float, best: float) -> void:
	game_over_label.text = "UNIT OFFLINE\n\nDISTANCE  %dm\nBEST  %dm\n\n[R] RESTART" % [int(distance), int(best)]
	game_over_panel.show()
	if _game_over_tween != null:
		_game_over_tween.kill()
	game_over_panel.offset_transform_enabled = true
	game_over_panel.offset_transform_scale = Vector2(0.78, 0.78)
	game_over_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_game_over_tween = create_tween().set_parallel(true)
	_game_over_tween.tween_property(game_over_panel, "offset_transform_scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_game_over_tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.14)

func hide_game_over() -> void:
	if _game_over_tween != null:
		_game_over_tween.kill()
	game_over_panel.offset_transform_scale = Vector2.ONE
	game_over_panel.modulate = Color.WHITE
	game_over_panel.hide()

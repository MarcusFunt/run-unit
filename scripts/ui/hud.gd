class_name RunUnitHud
extends CanvasLayer

@onready var distance_label: Label = %DistanceLabel
@onready var best_label: Label = %BestLabel
@onready var score_progress_bar: ProgressBar = %ScoreProgressBar
@onready var status_label: Label = %StatusLabel

var _level_length: float = 1.0

func _ready() -> void:
	score_progress_bar.max_value = _level_length

func set_scores(distance: float, best: float) -> void:
	var safe_distance: float = maxf(distance, 0.0)
	distance_label.text = "%04dm" % int(safe_distance)
	score_progress_bar.value = clampf(safe_distance, 0.0, _level_length)
	best_label.text = "BEST  %04dm" % int(best)

func set_level_length(length: float) -> void:
	_level_length = maxf(length, 1.0)
	score_progress_bar.max_value = _level_length

func set_status(text_value: String) -> void:
	status_label.text = text_value

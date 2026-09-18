class_name RunUnitHud
extends CanvasLayer

@onready var distance_label: Label = %DistanceLabel
@onready var best_label: Label = %BestLabel
@onready var score_progress_bar: ProgressBar = %ScoreProgressBar
@onready var _health_cells: Array[CanvasItem] = [
	$HealthDisplay/HealthCell1,
	$HealthDisplay/HealthCell2,
	$HealthDisplay/HealthCell3,
]

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

func set_health(current_health: int, maximum_health: int) -> void:
	var safe_maximum: int = maxi(maximum_health, 0)
	var safe_current: int = clampi(current_health, 0, safe_maximum)
	for index: int in range(_health_cells.size()):
		_health_cells[index].visible = index < safe_current

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

@onready var _health_frame: Panel = $HealthFrame
var _level_length: float = 1.0
var _last_health: int = 3
var _damage_flash: float = 0.0

func _process(delta: float) -> void:
	_damage_flash = maxf(_damage_flash - delta, 0.0)
	_health_frame.modulate = Color(1.0, 0.55, 0.45) if _damage_flash > 0.0 else Color.WHITE

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
	if safe_current < _last_health:
		_damage_flash = 0.3
	_last_health = safe_current
	for index: int in range(_health_cells.size()):
		var cell: ColorRect = _health_cells[index] as ColorRect
		cell.visible = true
		cell.color = Color(0.32, 0.88, 0.94, 1.0) if index < safe_current else Color(0.075, 0.22, 0.26, 1.0)

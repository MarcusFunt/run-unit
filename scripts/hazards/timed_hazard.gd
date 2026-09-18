class_name RunUnitTimedHazard
extends RunUnitHazardArea

@export_range(0.05, 60.0, 0.05) var cycle_seconds: float = 2.0
@export_range(0.0, 60.0, 0.05) var active_seconds: float = 1.0
@export_range(0.0, 60.0, 0.05) var phase_offset_seconds: float = 0.0

var _cycle_elapsed_seconds: float = 0.0

func _ready() -> void:
	super._ready()
	reset_level_state()

func _physics_process(delta: float) -> void:
	_cycle_elapsed_seconds += delta
	_apply_cycle_state()

func reset_level_state() -> void:
	_cycle_elapsed_seconds = 0.0
	_clear_exposures()
	_apply_cycle_state()

func _apply_cycle_state() -> void:
	var safe_cycle_seconds: float = maxf(cycle_seconds, 0.05)
	var safe_active_seconds: float = clampf(active_seconds, 0.0, safe_cycle_seconds)
	if safe_active_seconds <= 0.0:
		set_active(false)
		return
	if safe_active_seconds >= safe_cycle_seconds:
		set_active(true)
		return

	var phase_seconds: float = fposmod(phase_offset_seconds + _cycle_elapsed_seconds, safe_cycle_seconds)
	set_active(phase_seconds < safe_active_seconds)

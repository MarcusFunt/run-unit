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

## Lets the scripted B-roll controller reason about a visible warning cycle
## without peeking at physics state. The generous time margins live in the
## controller, so this stays a simple deterministic query of the authored cycle.
func get_cycle_phase_seconds(seconds_from_now: float = 0.0) -> float:
	var safe_cycle_seconds: float = maxf(cycle_seconds, 0.05)
	return fposmod(
		phase_offset_seconds + _cycle_elapsed_seconds + maxf(seconds_from_now, 0.0),
		safe_cycle_seconds
	)

func is_active_at_offset(seconds_from_now: float) -> bool:
	var safe_cycle_seconds: float = maxf(cycle_seconds, 0.05)
	var safe_active_seconds: float = clampf(active_seconds, 0.0, safe_cycle_seconds)
	if safe_active_seconds <= 0.0:
		return false
	if safe_active_seconds >= safe_cycle_seconds:
		return true
	var phase_seconds: float = fposmod(
		phase_offset_seconds + _cycle_elapsed_seconds + maxf(seconds_from_now, 0.0),
		safe_cycle_seconds
	)
	return phase_seconds < safe_active_seconds

func is_active_during_window(start_seconds: float, end_seconds: float) -> bool:
	var start_time: float = maxf(start_seconds, 0.0)
	var end_time: float = maxf(end_seconds, start_time)
	var sample_step: float = minf(0.05, maxf(cycle_seconds, 0.05) / 24.0)
	var t: float = start_time
	while t < end_time:
		if is_active_at_offset(t):
			return true
		t += sample_step
	return is_active_at_offset(end_time)

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

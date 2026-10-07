class_name RunUnitAmbientPulse
extends CanvasItem

@export_range(0.1, 20.0, 0.1) var period_seconds: float = 2.0
@export_range(0.0, 1.0, 0.01) var dim_factor: float = 0.7
@export_range(-20.0, 20.0, 0.01) var phase_offset_seconds: float = 0.0

var _authored_modulate: Color
var _elapsed_seconds: float = 0.0


func _ready() -> void:
	_authored_modulate = modulate
	_elapsed_seconds = 0.0
	_apply_pulse()


func _process(delta: float) -> void:
	_elapsed_seconds += delta
	_apply_pulse()


func reset_level_state() -> void:
	_elapsed_seconds = 0.0
	_apply_pulse()


func _apply_pulse() -> void:
	var safe_period: float = maxf(period_seconds, 0.1)
	var phase: float = fposmod(_elapsed_seconds + phase_offset_seconds, safe_period) / safe_period
	var pulse: float = 0.5 + 0.5 * sin(phase * TAU)
	var opacity_factor: float = lerpf(clampf(dim_factor, 0.0, 1.0), 1.0, pulse)
	var pulsed_modulate: Color = _authored_modulate
	pulsed_modulate.a = _authored_modulate.a * opacity_factor
	modulate = pulsed_modulate

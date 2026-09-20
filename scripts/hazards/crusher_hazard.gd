class_name RunUnitCrusherHazard
extends RunUnitTimedHazard

## The damaging detector covers the entire strike zone, while the visible ram
## physically moves through it. This makes the timing legible before contact.
@export var rest_offset_y: float = -118.0
@export var warning_offset_y: float = -58.0
@export_range(0.05, 1.0, 0.05) var warning_seconds: float = 0.45
@export_range(0.05, 0.5, 0.01) var strike_visual_seconds: float = 0.10

var _piston: Node2D = null
var _warning_visual: CanvasItem = null

func _ready() -> void:
	_piston = get_node_or_null("PistonAssembly") as Node2D
	_warning_visual = get_node_or_null("WarningVisual") as CanvasItem
	super._ready()
	_update_crusher_visual()
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_crusher_visual()

func reset_level_state() -> void:
	super.reset_level_state()
	if is_inside_tree():
		_update_crusher_visual()

func _update_crusher_visual() -> void:
	if _piston == null:
		return
	var phase: float = get_cycle_phase_seconds()
	var safe_cycle: float = maxf(cycle_seconds, 0.05)
	var safe_active: float = clampf(active_seconds, 0.0, safe_cycle)
	var warning_start: float = maxf(safe_cycle - warning_seconds, safe_active)

	if phase < safe_active:
		var slam_t: float = clampf(phase / maxf(strike_visual_seconds, 0.01), 0.0, 1.0)
		_piston.position.y = lerpf(warning_offset_y, 0.0, _ease_out_quart(slam_t))
	elif phase >= warning_start:
		var warn_t: float = inverse_lerp(warning_start, safe_cycle, phase)
		_piston.position.y = lerpf(rest_offset_y, warning_offset_y, warn_t)
	else:
		_piston.position.y = rest_offset_y

	if _warning_visual != null:
		_warning_visual.visible = phase >= warning_start and phase >= safe_active

func _ease_out_quart(value: float) -> float:
	var inv: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inv * inv * inv * inv

class_name RunUnitCrusherHazard
extends RunUnitTimedHazard

## The damaging detector covers the entire strike zone, while the visible ram
## physically moves through it. This makes the timing legible before contact.
@export var rest_offset_y: float = -118.0
@export var warning_offset_y: float = -58.0
@export_range(0.05, 0.5, 0.01) var strike_visual_seconds: float = 0.10

var _piston: Node2D = null
var _warning_lamp: Polygon2D = null
var _swept_channel: Polygon2D = null
var _strike_limit: Polygon2D = null

func _ready() -> void:
	_piston = get_node_or_null("PistonAssembly") as Node2D
	_warning_lamp = get_node_or_null("WarningVisual/Lamp") as Polygon2D
	_swept_channel = get_node_or_null("SweptChannel") as Polygon2D
	_strike_limit = get_node_or_null("StrikeLimit") as Polygon2D
	_configure_travel_marks()
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
	var hazard_phase: int = get_hazard_phase()
	if _warning_lamp != null:
		var warning: bool = hazard_phase == HazardPhase.WARNING
		var pulse: float = 0.42 + 0.58 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.018))
		_warning_lamp.color = Color(1.0, 0.36, 0.08, 1.0) if warning else Color(1.0, 0.12, 0.035, 1.0) if active else Color(0.22, 0.31, 0.34, 0.82)
		_warning_lamp.modulate.a = pulse if warning or active else 0.82
	if _swept_channel != null:
		var channel_alpha: float = 0.34 if active else 0.27 if hazard_phase == HazardPhase.WARNING else 0.18
		_swept_channel.color = Color(1.0, 0.12, 0.035, channel_alpha)
	if _strike_limit != null:
		_strike_limit.modulate.a = 0.7 + 0.3 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.014)) if hazard_phase != HazardPhase.INACTIVE else 0.62
	if phase < safe_active:
		var slam_t: float = clampf(phase / maxf(strike_visual_seconds, 0.01), 0.0, 1.0)
		_piston.position.y = lerpf(warning_offset_y, 0.0, _ease_out_quart(slam_t))
	elif get_hazard_phase() == HazardPhase.WARNING:
		var warn_t: float = inverse_lerp(safe_cycle - warning_seconds, safe_cycle, phase)
		_piston.position.y = lerpf(rest_offset_y, warning_offset_y, warn_t)
	else:
		_piston.position.y = rest_offset_y


func _configure_travel_marks() -> void:
	if _swept_channel == null:
		return
	_swept_channel.polygon = PackedVector2Array([
		Vector2(-56.0, -118.0),
		Vector2(56.0, -118.0),
		Vector2(56.0, 44.0),
		Vector2(-56.0, 44.0),
	])
	var marks: Node2D = Node2D.new()
	marks.name = "TravelWarningMarks"
	marks.z_index = 4
	add_child(marks)
	for index: int in range(6):
		var mark_y: float = -104.0 + float(index) * 27.0
		for side: int in [-1, 1]:
			var stripe: Polygon2D = Polygon2D.new()
			stripe.name = "SweepMark%d_%d" % [index, side]
			stripe.position = Vector2(float(side) * 43.0, mark_y)
			stripe.polygon = PackedVector2Array([
				Vector2(-5.0, 8.0),
				Vector2(1.0, 8.0),
				Vector2(9.0, -8.0),
				Vector2(3.0, -8.0),
			])
			stripe.color = Color(1.0, 0.26, 0.05, 0.62)
			marks.add_child(stripe)


func _ease_out_quart(value: float) -> float:
	var inv: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inv * inv * inv * inv

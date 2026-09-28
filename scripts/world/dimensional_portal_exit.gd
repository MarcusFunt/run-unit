class_name RunUnitDimensionalPortalExit
extends RunUnitRouteExit

const FRAME_COUNT: int = 6
const IDLE_SCALE: Vector2 = Vector2(2.0, 2.0)
const HALO_SCALE: Vector2 = Vector2(2.55, 2.55)

@export_range(1.0, 24.0, 0.5) var animation_fps: float = 10.0
@export_range(0.1, 1.0, 0.05) var transport_duration: float = 0.42

@onready var portal: Sprite2D = $Portal
@onready var halo: Sprite2D = $Halo
@onready var blackout: ColorRect = $BlackoutLayer/Blackout

var _frame_clock: float = 0.0
var _transition_tween: Tween = null

func _process(delta: float) -> void:
	_frame_clock = fmod(_frame_clock + delta * animation_fps, float(FRAME_COUNT))
	var frame_index: int = int(_frame_clock) % FRAME_COUNT
	portal.frame = frame_index
	halo.frame = frame_index

func reset_transition() -> void:
	super()
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_frame_clock = 0.0
	portal.frame = 0
	portal.scale = IDLE_SCALE
	portal.modulate = Color.WHITE
	halo.frame = 0
	halo.scale = HALO_SCALE
	halo.modulate = Color(0.58, 1.0, 0.7, 0.18)
	var blackout_color: Color = blackout.color
	blackout_color.a = 0.0
	blackout.color = blackout_color

func begin_transition() -> void:
	if transition_started:
		return
	transition_started = true
	var surge_duration: float = transport_duration * 0.55
	var fade_duration: float = transport_duration - surge_duration
	_transition_tween = create_tween()
	_transition_tween.tween_property(portal, "scale", Vector2.ONE * 2.7, surge_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transition_tween.parallel().tween_property(halo, "scale", Vector2.ONE * 3.35, surge_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.parallel().tween_property(halo, "modulate:a", 0.5, surge_duration)
	if not next_scene_path.is_empty():
		_transition_tween.tween_property(blackout, "color:a", 1.0, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_transition_tween.parallel().tween_property(portal, "modulate:a", 0.0, fade_duration)
		_transition_tween.parallel().tween_property(halo, "modulate:a", 0.0, fade_duration)
	else:
		_transition_tween.tween_interval(fade_duration)
	_transition_tween.tween_callback(finish_transition)

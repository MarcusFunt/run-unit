class_name RunUnitRobotVisual
extends Node2D

## Transform-only presentation rig for the articulated single-wheel player.
## Scaled so the wheel's visual diameter (WHEEL_RADIUS_SOURCE_PX * 2 *
## art_scale) matches the 50 px collision body's width -- the robot was
## previously sized to a 24x30 collision body that read as tiny against the
## 32 px tile grid, making the shaft ceilings and the crouch gate look
## wildly oversized relative to the robot and forcing an absurdly high jump
## arc just to clear ordinary gaps. The collision body and this rig are
## scaled up together so the world reads at a believable size without
## touching level geometry or jump physics.
@export var art_scale: float = 0.357143
@export var body_to_wheel_offset: Vector2 = Vector2(-3.089, -27.428)
## The wheel's visual bottom matches the 64 px player collision body's bottom.
@export var wheel_anchor: Vector2 = Vector2(7.68, 6.4)

@export_category("Idle")
@export_range(0.2, 1.5, 0.05) var idle_frequency_hz: float = 0.70
@export_range(0.0, 3.0, 0.1) var idle_upper_amplitude_deg: float = 1.2
@export_range(0.0, 5.0, 0.1) var idle_knee_amplitude_deg: float = 2.4
@export_range(0.0, 2.0, 0.1) var idle_body_lean_deg: float = 0.6

@export_category("Driving Motion")
## A wheel has no gait, so driving only leans the body toward speed; it does
## not add a walk-cycle-style suspension wobble (see idle sway for that).
@export_range(0.0, 10.0, 0.1) var max_drive_body_lean_deg: float = 5.5

@export_category("Antenna")
@export_range(1.0, 30.0, 0.5) var antenna_max_lag_deg: float = 14.0
@export var antenna_acceleration_for_max_lag: float = 2200.0
@export_range(0.5, 8.0, 0.1) var antenna_spring_frequency_hz: float = 3.2
@export_range(0.1, 2.0, 0.01) var antenna_damping_ratio: float = 0.72
@export_range(0.0, 4.0, 0.1) var antenna_idle_sway_deg: float = 1.2
@export_range(0.1, 2.0, 0.05) var antenna_idle_sway_hz: float = 0.55

const UPPER_LINK_LENGTH: float = 110.0
const LOWER_LINK_LENGTH: float = 145.0
## Visible outside radius of the wheel artwork, in source SVG pixels.
const WHEEL_RADIUS_SOURCE_PX: float = 70.0
## Antenna spring integration never advances by more than this, so a large
## frame-time spike (a hitch, a debugger pause) can't destabilize it.
const ANTENNA_MAX_SUBSTEP: float = 1.0 / 120.0

@onready var body_pivot: Node2D = $BodyPivot
@onready var upper_link_pivot: Node2D = $UpperLinkPivot
@onready var knee_pivot: Node2D = $UpperLinkPivot/KneePivot
@onready var wheel_pivot: Node2D = $UpperLinkPivot/KneePivot/WheelPivot
@onready var eye: Sprite2D = $BodyPivot/Eye
@onready var antenna_pivot: Node2D = $BodyPivot/AntennaPivot
@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor

var _wheel_spin: float = 0.0
var _jump_extension: float = 0.0
var _landing_compression: float = 0.0
var _facing_left: bool = true
## Accumulated delta time driving all presentation animation. Never wall-clock
## time, so behavior stays identical regardless of render framerate.
var _visual_time: float = 0.0
var _smoothed_body_lean: float = 0.0
var _antenna_angle: float = 0.0
var _antenna_velocity: float = 0.0
var _previous_velocity_x: float = 0.0

func _ready() -> void:
	body_pivot.position = body_to_wheel_offset
	upper_link_pivot.position = body_to_wheel_offset
	body_pivot.scale = Vector2.ONE * art_scale
	upper_link_pivot.scale = Vector2.ONE * art_scale
	if player != null:
		player.jumped.connect(_on_player_jumped)
		player.landed.connect(_on_player_landed)

func _process(delta: float) -> void:
	_update_facing()
	_advance_visual_clock(delta)

	if player == null:
		_update_eye()
		_apply_pose(25.0, 105.0, 0.0, 0.0)
		return

	_jump_extension = maxf(_jump_extension - delta * 3.7, 0.0)
	_landing_compression = maxf(_landing_compression - delta * 3.4, 0.0)

	_update_wheel_spin(delta)

	var pose: Dictionary = _build_base_pose()

	_apply_idle_motion(pose)
	_apply_landing_response(pose)
	_apply_body_lean(pose, delta)

	_update_antenna_motion(delta)
	_update_eye()

	_apply_pose(pose["upper_deg"], pose["knee_deg"], pose["body_lean"], _wheel_spin)

func _update_facing() -> void:
	if player == null:
		return
	if absf(player.velocity.x) > 8.0:
		_facing_left = player.velocity.x < 0.0
	scale.x = 1.0 if _facing_left else -1.0

func _advance_visual_clock(delta: float) -> void:
	_visual_time += delta

## Unsigned local travel ratio in [0, 1], independent of facing/direction so
## every downstream animation channel stays symmetric under mirroring.
func _speed_ratio() -> float:
	if player == null or player.max_run_speed <= 0.001:
		return 0.0
	return clampf(absf(player.velocity.x) / player.max_run_speed, 0.0, 1.0)

func _build_base_pose() -> Dictionary:
	var pose: Dictionary = {
		"upper_deg": 25.0,
		"knee_deg": 105.0,
		"body_lean": 0.0,
	}
	if player == null:
		return pose
	if player.is_charging():
		# The motor owns charge state; this rig only visualizes it. As charge
		# builds, the linkage folds and pulls the wheel closer to the body.
		var charge: float = player.charge_ratio
		pose["upper_deg"] = lerpf(25.0, 15.0, charge)
		pose["knee_deg"] = lerpf(105.0, 140.0, charge)
	elif player.is_crouching():
		var crouch: float = player.crouch_ratio
		pose["upper_deg"] = lerpf(25.0, 15.0, crouch)
		pose["knee_deg"] = lerpf(105.0, 140.0, crouch)
	elif not player.is_on_floor():
		# In air: extend the suspension. The actual collision remains unchanged.
		pose["upper_deg"] = lerpf(25.0, 35.0, _jump_extension)
		pose["knee_deg"] = lerpf(105.0, 80.0, _jump_extension)
	return pose

func _is_idle_eligible() -> bool:
	if player == null or not player.is_on_floor():
		return false
	if player.is_charging() or player.is_crouching():
		return false
	if _landing_compression > 0.05:
		return false
	return true

func _idle_weight() -> float:
	if not _is_idle_eligible():
		return 0.0
	return 1.0 - smoothstep(0.0, 0.12, _speed_ratio())

func _apply_idle_motion(pose: Dictionary) -> void:
	var idle_weight: float = _idle_weight()
	if idle_weight <= 0.0:
		return
	var idle_phase: float = _visual_time * TAU * idle_frequency_hz
	var idle_wave: float = sin(idle_phase)
	pose["upper_deg"] += idle_wave * idle_upper_amplitude_deg * idle_weight
	pose["knee_deg"] -= idle_wave * idle_knee_amplitude_deg * idle_weight
	pose["body_lean"] += deg_to_rad(cos(idle_phase) * idle_body_lean_deg * idle_weight)

func _apply_landing_response(pose: Dictionary) -> void:
	if player == null or not player.is_on_floor():
		return
	if player.is_charging() or player.is_crouching():
		return
	if _landing_compression <= 0.0:
		return
	pose["upper_deg"] = lerpf(pose["upper_deg"], 15.0, _landing_compression)
	pose["knee_deg"] = lerpf(pose["knee_deg"], 140.0, _landing_compression)
	pose["body_lean"] += 0.045 * _landing_compression

func _apply_body_lean(pose: Dictionary, delta: float) -> void:
	var target_body_lean: float = deg_to_rad(-max_drive_body_lean_deg) * _speed_ratio()
	var response: float = 1.0 - exp(-10.0 * delta)
	_smoothed_body_lean = lerpf(_smoothed_body_lean, target_body_lean, response)
	pose["body_lean"] += _smoothed_body_lean

func get_wheel_radius_world() -> float:
	return WHEEL_RADIUS_SOURCE_PX * art_scale

## World-space forward speed expressed in the authored left-facing frame:
## positive means travelling in whichever world direction the rig is
## currently facing, regardless of mirroring.
func _forward_velocity() -> float:
	if player == null:
		return 0.0
	var facing_world_sign: float = -1.0 if _facing_left else 1.0
	return player.velocity.x * facing_world_sign

func _update_wheel_spin(delta: float) -> void:
	var radius: float = get_wheel_radius_world()
	if radius <= 0.001:
		return
	var angular_delta: float = _forward_velocity() * delta / radius
	# fmod (not fposmod) keeps the sign of the accumulator so a short burst of
	# forward travel always yields a spin magnitude equal to the angle rolled,
	# rather than wrapping into the [0, TAU) range and inflating the magnitude.
	_wheel_spin = fmod(_wheel_spin - angular_delta, TAU)

func _player_acceleration_x(delta: float) -> float:
	if player == null:
		return 0.0
	var safe_delta: float = maxf(delta, 0.0001)
	var acceleration_x: float = (player.velocity.x - _previous_velocity_x) / safe_delta
	_previous_velocity_x = player.velocity.x
	return acceleration_x

func _local_forward_acceleration(acceleration_x: float) -> float:
	var facing_sign: float = -1.0 if _facing_left else 1.0
	return acceleration_x * facing_sign

func _antenna_target(local_forward_accel: float, idle_weight: float) -> float:
	var accel_ratio: float = clampf(local_forward_accel / antenna_acceleration_for_max_lag, -1.0, 1.0)
	var target: float = deg_to_rad(accel_ratio * antenna_max_lag_deg)
	target += deg_to_rad(antenna_idle_sway_deg) * sin(_visual_time * TAU * antenna_idle_sway_hz) * idle_weight
	return target

func _step_antenna_spring(target: float, delta: float) -> void:
	var omega: float = TAU * antenna_spring_frequency_hz
	var angular_acceleration: float = (
		omega * omega * (target - _antenna_angle)
		- 2.0 * antenna_damping_ratio * omega * _antenna_velocity
	)
	_antenna_velocity += angular_acceleration * delta
	_antenna_angle += _antenna_velocity * delta

	var limit: float = deg_to_rad(antenna_max_lag_deg)
	_antenna_angle = clampf(_antenna_angle, -limit, limit)
	antenna_pivot.rotation = _antenna_angle

func _update_antenna(target: float, delta: float) -> void:
	var remaining: float = delta
	while remaining > 0.0:
		var step: float = minf(remaining, ANTENNA_MAX_SUBSTEP)
		_step_antenna_spring(target, step)
		remaining -= step

func _update_antenna_motion(delta: float) -> void:
	var acceleration_x: float = _player_acceleration_x(delta)
	var local_forward_accel: float = _local_forward_acceleration(acceleration_x)
	var target: float = _antenna_target(local_forward_accel, _idle_weight())
	_update_antenna(target, delta)

func _update_eye() -> void:
	var pulse: float = 0.88 + 0.12 * sin(_visual_time * TAU * 0.9)
	var charge_boost: float = 0.0
	if player != null and player.is_charging():
		charge_boost = player.charge_ratio * 0.15
	eye.modulate = Color(1.0, 1.0, 1.0, clampf(pulse + charge_boost, 0.0, 1.0))

func _apply_pose(upper_degrees: float, knee_degrees: float, body_lean: float, wheel_spin: float) -> void:
	var lower_world_degrees: float = upper_degrees + knee_degrees
	var upper_radians: float = deg_to_rad(upper_degrees)
	var lower_radians: float = deg_to_rad(lower_world_degrees)
	var link_offset: Vector2 = Vector2(
		cos(upper_radians) * UPPER_LINK_LENGTH + cos(lower_radians) * LOWER_LINK_LENGTH,
		sin(upper_radians) * UPPER_LINK_LENGTH + sin(lower_radians) * LOWER_LINK_LENGTH
	) * art_scale
	# Keep the cosmetic wheel planted on the collision baseline while links articulate.
	var mount_position: Vector2 = wheel_anchor - link_offset
	body_pivot.position = mount_position
	upper_link_pivot.position = mount_position
	body_pivot.rotation = body_lean if _facing_left else -body_lean
	upper_link_pivot.rotation = deg_to_rad(upper_degrees)
	knee_pivot.rotation = deg_to_rad(knee_degrees)
	# Counter-rotate the wheel against the two links, then apply its visible spin.
	wheel_pivot.rotation = -upper_link_pivot.rotation - knee_pivot.rotation + wheel_spin

func _on_player_jumped() -> void:
	_jump_extension = 1.0
	_antenna_velocity -= deg_to_rad(45.0)

func _on_player_landed() -> void:
	if player == null:
		return
	var impact_ratio: float = clampf(player.last_landing_speed / player.max_fall_speed, 0.0, 1.0)
	_landing_compression = lerpf(0.35, 0.75, impact_ratio)
	_antenna_velocity += deg_to_rad(100.0) * impact_ratio

func get_visual_wheel_anchor() -> Vector2:
	return wheel_anchor

func apply_pose_for_test(upper_degrees: float, knee_degrees: float, body_lean: float, wheel_spin: float) -> void:
	_apply_pose(upper_degrees, knee_degrees, body_lean, wheel_spin)

func set_facing_left_for_test(value: bool) -> void:
	_facing_left = value

func update_wheel_for_test(delta: float) -> void:
	_update_wheel_spin(delta)

func get_wheel_spin_for_test() -> float:
	return _wheel_spin

func advance_visual_time_for_test(delta: float) -> void:
	_advance_visual_clock(delta)

func get_visual_time_for_test() -> float:
	return _visual_time

func run_process_for_test(delta: float) -> void:
	_process(delta)

func get_body_mount_position_for_test() -> Vector2:
	return body_pivot.position

func get_wheel_local_position_for_test() -> Vector2:
	return to_local(wheel_pivot.global_position)

func set_previous_velocity_for_test(value: float) -> void:
	_previous_velocity_x = value

func update_antenna_motion_for_test(delta: float) -> void:
	_update_antenna_motion(delta)

func apply_jump_impulse_for_test() -> void:
	_on_player_jumped()

func apply_landing_impulse_for_test() -> void:
	_on_player_landed()

func is_idle_eligible_for_test() -> bool:
	return _is_idle_eligible()

class_name RunUnitRobotVisual
extends Node2D

## Transform-only presentation rig for the articulated single-wheel player.
@export var art_scale: float = 0.36
@export var body_to_wheel_offset: Vector2 = Vector2(-7.0, -43.5)
## The wheel's visual bottom matches the 30 px player collision body's bottom.
@export var wheel_anchor: Vector2 = Vector2(3.6, -10.2)

const UPPER_LINK_LENGTH: float = 110.0
const LOWER_LINK_LENGTH: float = 145.0
## Visible outside radius of the wheel artwork, in source SVG pixels.
const WHEEL_RADIUS_SOURCE_PX: float = 70.0

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

func _ready() -> void:
	body_pivot.position = body_to_wheel_offset
	upper_link_pivot.position = body_to_wheel_offset
	body_pivot.scale = Vector2.ONE * art_scale
	upper_link_pivot.scale = Vector2.ONE * art_scale
	if player != null:
		player.jumped.connect(_on_player_jumped)
		player.landed.connect(_on_player_landed)

func _process(delta: float) -> void:
	if player == null:
		_apply_pose(25.0, 105.0, 0.0, 0.0)
		return
	var speed_ratio: float = clampf(player.velocity.x / player.max_run_speed, -1.0, 1.0)
	if absf(player.velocity.x) > 8.0:
		_facing_left = player.velocity.x < 0.0
	scale.x = 1.0 if _facing_left else -1.0
	_jump_extension = maxf(_jump_extension - delta * 3.7, 0.0)
	_landing_compression = maxf(_landing_compression - delta * 3.4, 0.0)
	_update_wheel_spin(delta)

	# Authored left-facing driving stance. Flipping RobotVisual on X gives the
	# mirrored right-driving pose without detaching the linkage from the body.
	var upper_degrees: float = 25.0
	var knee_degrees: float = 105.0
	var body_lean: float = speed_ratio * 0.10
	var bob: float = sin(Time.get_ticks_msec() * 0.005) * 0.012
	if player.is_charging():
		# The motor owns charge state; this rig only visualizes it. As charge
		# builds, the linkage folds and pulls the wheel closer to the body.
		var crouch_ratio: float = player.charge_ratio
		upper_degrees = lerpf(25.0, 15.0, crouch_ratio)
		knee_degrees = lerpf(105.0, 140.0, crouch_ratio)
		body_lean += 0.035 * crouch_ratio
	elif player.is_crouching():
		var manual_crouch_ratio: float = player.crouch_ratio
		upper_degrees = lerpf(25.0, 15.0, manual_crouch_ratio)
		knee_degrees = lerpf(105.0, 140.0, manual_crouch_ratio)
	elif not player.is_on_floor():
		# In air: extend the suspension. The actual collision remains unchanged.
		upper_degrees = lerpf(25.0, 35.0, _jump_extension)
		knee_degrees = lerpf(105.0, 80.0, _jump_extension)
	elif _landing_compression > 0.0:
		upper_degrees = lerpf(25.0, 15.0, _landing_compression)
		knee_degrees = lerpf(105.0, 140.0, _landing_compression)
		body_lean += 0.045 * _landing_compression
	else:
		body_lean += bob
	_apply_pose(upper_degrees, knee_degrees, body_lean, _wheel_spin)

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
	var blink: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
	eye.modulate = Color(1.0, 1.0, 1.0, blink)

func _on_player_jumped() -> void:
	_jump_extension = 1.0

func _on_player_landed() -> void:
	if player == null:
		return
	var impact_ratio: float = clampf(player.last_landing_speed / player.max_fall_speed, 0.0, 1.0)
	_landing_compression = lerpf(0.35, 0.75, impact_ratio)

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

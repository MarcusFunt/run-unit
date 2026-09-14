class_name RunUnitPlayerMotor
extends CharacterBody2D

signal landed
signal jumped

@export_category("Movement")
@export var max_run_speed: float = 285.0
@export var ground_acceleration: float = 2200.0
@export var ground_deceleration: float = 2600.0
@export var air_acceleration: float = 1400.0
@export var gravity: float = 1550.0
@export var jump_velocity: float = -650.0
@export var max_fall_speed: float = 850.0
@export_category("Spring Jump")
@export var min_jump_velocity: float = -360.0
@export_range(0.1, 1.2, 0.01) var max_charge_time: float = 0.36
@export_range(0.25, 1.0, 0.01) var charge_power_curve: float = 0.62
@export_range(1.0, 2.5, 0.05) var fall_gravity_multiplier: float = 1.20
@export_range(0.05, 0.30, 0.01) var jump_press_buffer_time: float = 0.12
@export_category("Crouch")
@export_range(0.1, 1.0, 0.05) var crouch_speed_multiplier: float = 0.45
@export_range(0.08, 0.50, 0.01) var crouch_transition_time: float = 0.18
@export_range(12.0, 30.0, 1.0) var crouch_collision_height: float = 20.0
@export_category("Jump Assist")
@export var coyote_time: float = 0.11
@export var jump_buffer_time: float = 0.12

var _action: RunUnitPlayerAction = RunUnitPlayerAction.new()
var _coyote_remaining: float = 0.0
var _release_buffer_remaining: float = 0.0
var _jump_press_buffer_remaining: float = 0.0
var _released_charge_ratio: float = 0.0
var _was_on_floor: bool = false
var _is_charging: bool = false
var charge_ratio: float = 0.0
var last_launch_velocity: float = 0.0
var last_landing_speed: float = 0.0
var _is_crouching: bool = false
var crouch_ratio: float = 0.0
var _standing_collision_height: float = 0.0
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	var rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D
	if rectangle != null:
		_standing_collision_height = rectangle.size.y

func set_action(action: RunUnitPlayerAction) -> void:
	_action = action.duplicate_action()

func reset_motor() -> void:
	velocity = Vector2.ZERO
	_action = RunUnitPlayerAction.new()
	_coyote_remaining = 0.0
	_release_buffer_remaining = 0.0
	_jump_press_buffer_remaining = 0.0
	_released_charge_ratio = 0.0
	_was_on_floor = false
	_is_charging = false
	charge_ratio = 0.0
	last_launch_velocity = 0.0
	last_landing_speed = 0.0
	_is_crouching = false
	crouch_ratio = 0.0
	_update_crouch_collision()

func is_charging() -> bool:
	return _is_charging

func is_crouching() -> bool:
	return _is_crouching

func _physics_process(delta: float) -> void:
	var started_on_floor: bool = is_on_floor()
	if started_on_floor:
		_coyote_remaining = coyote_time
	else:
		_coyote_remaining = maxf(_coyote_remaining - delta, 0.0)

	if _action.jump_pressed:
		_jump_press_buffer_remaining = jump_press_buffer_time
	else:
		_jump_press_buffer_remaining = maxf(_jump_press_buffer_remaining - delta, 0.0)

	# A held press starts charging the first physics frame that a landing is valid.
	# A released buffered tap instead becomes an immediate short spring below.
	if _action.jump_held and _coyote_remaining > 0.0:
		_is_charging = true
		charge_ratio = minf(charge_ratio + delta / max_charge_time, 1.0)
	if _action.jump_released and _is_charging:
		_release_buffer_remaining = jump_buffer_time
		_released_charge_ratio = charge_ratio
		_is_charging = false
		charge_ratio = 0.0
	else:
		_release_buffer_remaining = maxf(_release_buffer_remaining - delta, 0.0)
	if _jump_press_buffer_remaining > 0.0 and not _action.jump_held and not _is_charging and _coyote_remaining > 0.0:
		_release_buffer_remaining = jump_buffer_time
		_released_charge_ratio = 0.0
		_jump_press_buffer_remaining = 0.0

	_is_crouching = _action.crouch_held and started_on_floor and not _action.jump_held
	var target_crouch_ratio: float = 1.0 if _is_crouching else 0.0
	crouch_ratio = move_toward(crouch_ratio, target_crouch_ratio, delta / crouch_transition_time)
	_update_crouch_collision()

	var speed_multiplier: float = crouch_speed_multiplier if _is_crouching else 1.0
	var target_speed: float = _action.movement * max_run_speed * speed_multiplier
	var acceleration: float = ground_acceleration if started_on_floor else air_acceleration
	if is_zero_approx(_action.movement):
		var braking: float = ground_deceleration if started_on_floor else air_acceleration * 0.35
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)
	else:
		velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)

	if _release_buffer_remaining > 0.0 and _coyote_remaining > 0.0:
		var launch_ratio: float = pow(_released_charge_ratio, charge_power_curve)
		velocity.y = lerpf(min_jump_velocity, jump_velocity, launch_ratio)
		last_launch_velocity = velocity.y
		_release_buffer_remaining = 0.0
		_jump_press_buffer_remaining = 0.0
		_coyote_remaining = 0.0
		jumped.emit()

	if not started_on_floor:
		var applied_gravity: float = gravity
		if velocity.y > 0.0:
			applied_gravity *= fall_gravity_multiplier
		velocity.y = minf(velocity.y + applied_gravity * delta, max_fall_speed)
	else:
		velocity.y = minf(velocity.y, 40.0)

	var landing_speed: float = maxf(velocity.y, 0.0)
	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		last_landing_speed = landing_speed
		landed.emit()
	_was_on_floor = is_on_floor()

func _update_crouch_collision() -> void:
	if _collision_shape == null or _standing_collision_height <= 0.0:
		return
	var rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return
	var height: float = lerpf(_standing_collision_height, crouch_collision_height, crouch_ratio)
	rectangle.size = Vector2(rectangle.size.x, height)
	_collision_shape.position.y = (_standing_collision_height - height) * 0.5

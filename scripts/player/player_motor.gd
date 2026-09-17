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
@export_range(12.0, 64.0, 1.0) var crouch_collision_height: float = 36.0
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
var _standing_collision_position: Vector2 = Vector2.ZERO
var _hitstun_remaining: float = 0.0
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	var rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D
	if rectangle != null:
		# The .tscn sub-resource is shared across every instance of this scene;
		# without duplicating it, one player's crouch resize would mutate the
		# collision shape of every other Player instance in the process.
		rectangle = rectangle.duplicate()
		_collision_shape.shape = rectangle
		_standing_collision_height = rectangle.size.y
		_standing_collision_position = _collision_shape.position

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
	_hitstun_remaining = 0.0
	_update_crouch_collision()

func is_charging() -> bool:
	return _is_charging

func is_crouching() -> bool:
	return _is_crouching

func is_in_hitstun() -> bool:
	return _hitstun_remaining > 0.0

func apply_knockback(impulse: Vector2, hitstun_seconds: float = 0.15) -> void:
	velocity = impulse
	_hitstun_remaining = maxf(hitstun_seconds, 0.0)
	_is_charging = false
	charge_ratio = 0.0
	_release_buffer_remaining = 0.0
	_jump_press_buffer_remaining = 0.0
	_released_charge_ratio = 0.0

func _physics_process(delta: float) -> void:
	var started_on_floor: bool = is_on_floor()
	var in_hitstun: bool = _hitstun_remaining > 0.0
	if started_on_floor:
		_coyote_remaining = coyote_time
	else:
		_coyote_remaining = maxf(_coyote_remaining - delta, 0.0)

	if not in_hitstun:
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
	else:
		_release_buffer_remaining = 0.0
		_jump_press_buffer_remaining = 0.0

	var wants_to_crouch: bool = not in_hitstun and _action.crouch_held and started_on_floor and not _action.jump_held
	_update_crouch_state(wants_to_crouch, delta)

	if not in_hitstun:
		var speed_multiplier: float = crouch_speed_multiplier if _is_crouching else 1.0
		var target_speed: float = _action.movement * max_run_speed * speed_multiplier
		var acceleration: float = ground_acceleration if started_on_floor else air_acceleration
		if is_zero_approx(_action.movement):
			var braking: float = ground_deceleration if started_on_floor else air_acceleration * 0.35
			velocity.x = move_toward(velocity.x, 0.0, braking * delta)
		else:
			velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)

	if not in_hitstun and _release_buffer_remaining > 0.0 and _coyote_remaining > 0.0:
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
	_hitstun_remaining = maxf(_hitstun_remaining - delta, 0.0)

func _update_crouch_collision() -> void:
	if _collision_shape == null or _standing_collision_height <= 0.0:
		return
	var rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return
	var height: float = lerpf(_standing_collision_height, crouch_collision_height, crouch_ratio)
	rectangle.size = Vector2(rectangle.size.x, height)
	_collision_shape.position = _standing_collision_position + Vector2(0.0, (_standing_collision_height - height) * 0.5)

func _update_crouch_state(wants_to_crouch: bool, delta: float) -> void:
	var target_crouch_ratio: float = 1.0 if wants_to_crouch else 0.0
	var next_crouch_ratio: float = move_toward(crouch_ratio, target_crouch_ratio, delta / crouch_transition_time)
	if next_crouch_ratio < crouch_ratio and not _can_expand_to(next_crouch_ratio):
		next_crouch_ratio = crouch_ratio
	crouch_ratio = next_crouch_ratio
	_is_crouching = crouch_ratio > 0.001
	_update_crouch_collision()

func _can_expand_to(target_crouch_ratio: float) -> bool:
	if _collision_shape == null or _standing_collision_height <= 0.0:
		return true
	var rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return true
	var current_height: float = rectangle.size.y
	var target_height: float = lerpf(_standing_collision_height, crouch_collision_height, target_crouch_ratio)
	if target_height <= current_height + 0.001:
		return true

	# Only query the strip that would be added above the current collider. This
	# avoids treating the floor beneath the already-safe body as a ceiling.
	var extension_height: float = target_height - current_height
	var extension_shape: RectangleShape2D = RectangleShape2D.new()
	extension_shape.size = Vector2(rectangle.size.x, extension_height)
	var strip_center_y: float = _standing_collision_position.y + _standing_collision_height * 0.5 - (target_height + current_height) * 0.5
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = extension_shape
	query.transform = global_transform * Transform2D(0.0, Vector2(0.0, strip_center_y))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.0
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	return space_state.intersect_shape(query, 1).is_empty()
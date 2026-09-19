class_name RunUnitScriptedController
extends Node

## A deliberately modest bot that proves non-human actions share the motor.
@export var player_path: NodePath
@export var world_path: NodePath
## How far ahead of the player, in pixels, the bot checks for a crouch gate
## so it is already ducked by the time it arrives instead of walking into it.
const CROUCH_LOOKAHEAD_DISTANCE: float = 64.0
const HAZARD_LOOKAHEAD_DISTANCE: float = 240.0
## The motor's standing body is 50 px wide. Keeping its centre this far from
## an edge/hazard lets the jump release late without clipping the obstacle.
const EDGE_BODY_CLEARANCE: float = 27.0
const HAZARD_BODY_CLEARANCE: float = 60.0
## Charge starts early enough to reach the desired spring compression, but the
## release is governed by position so the bot no longer launches ~60 px early.
const CHARGE_START_PADDING: float = 14.0
const RELEASE_WINDOW: float = 10.0

var active: bool = false
var _motor: RunUnitPlayerMotor = null
var _world: RunUnitStaticWorld = null
var _jump_held_last_frame: bool = false
var _active_takeoff_x: float = NAN
var _active_charge_ratio: float = 0.0
var _active_plan_reason: String = ""

func _ready() -> void:
	_motor = get_node(player_path) as RunUnitPlayerMotor
	_world = get_node(world_path) as RunUnitStaticWorld

func reset_controller() -> void:
	_jump_held_last_frame = false
	_active_takeoff_x = NAN
	_active_charge_ratio = 0.0
	_active_plan_reason = ""

func _physics_process(_delta: float) -> void:
	if not active or _motor == null or _world == null:
		return
	var wants_to_crouch: bool = _should_crouch()
	var should_hold_jump: bool = not wants_to_crouch and _should_hold_jump()
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = 0.0 if _should_brake_for_hazard_charge() else 1.0
	action.crouch_held = wants_to_crouch
	action.jump_held = should_hold_jump
	action.jump_pressed = should_hold_jump and not _jump_held_last_frame
	action.jump_released = not should_hold_jump and _jump_held_last_frame
	_jump_held_last_frame = should_hold_jump
	if action.jump_released:
		_active_takeoff_x = NAN
		_active_charge_ratio = 0.0
		_active_plan_reason = ""
	_motor.set_action(action)

## Ducks a crouch gate before reaching it (lookahead probe) and stays ducked
## until clear of it (a zero-distance probe at the player's own position),
## rather than only reacting after the standing collision already stopped it.
func _should_crouch() -> bool:
	if not _motor.is_on_floor() or _motor.is_charging():
		return false
	return _motor.has_low_clearance_ahead(0.0) or _motor.has_low_clearance_ahead(CROUCH_LOOKAHEAD_DISTANCE)

func _should_hold_jump() -> bool:
	if not _motor.is_on_floor():
		return false

	if _jump_held_last_frame and not is_nan(_active_takeoff_x):
		var release_x: float = _active_takeoff_x - RELEASE_WINDOW
		if _motor.global_position.x < release_x:
			return true
		# Position owns the release timing. If acceleration made the bot reach
		# the mark slightly undercharged, allow only a few extra pixels to catch
		# up rather than launching tens of pixels early.
		if _motor.charge_ratio + 0.02 < _active_charge_ratio:
			if _active_plan_reason == "hazard":
				return true
			if _motor.global_position.x < _active_takeoff_x + 4.0:
				return true
		return false

	var plan: Dictionary = _build_jump_plan()
	if plan.is_empty():
		_active_takeoff_x = NAN
		_active_charge_ratio = 0.0
		_active_plan_reason = ""
		return false

	var takeoff_x: float = float(plan.get("takeoff_x", INF))
	var charge_ratio: float = clampf(float(plan.get("charge_ratio", 0.0)), 0.0, 1.0)
	var planning_speed: float = maxf(absf(_motor.velocity.x), _motor.max_run_speed * 0.8)
	var charge_distance: float = planning_speed * _motor.max_charge_time * charge_ratio
	var start_x: float = takeoff_x - charge_distance - CHARGE_START_PADDING
	if _motor.global_position.x < start_x:
		return false

	_active_takeoff_x = takeoff_x
	_active_charge_ratio = charge_ratio
	_active_plan_reason = str(plan.get("reason", ""))
	return true

func _should_brake_for_hazard_charge() -> bool:
	if _active_plan_reason != "hazard" or is_nan(_active_takeoff_x):
		return false
	if _motor.charge_ratio + 0.02 >= _active_charge_ratio:
		return false
	return _motor.global_position.x >= _active_takeoff_x - RELEASE_WINDOW

func _build_jump_plan() -> Dictionary:
	var platform: Dictionary = _world.get_platform_below_position(_motor.global_position)
	if platform.is_empty():
		return {}

	var best: Dictionary = {}
	var hazard: Dictionary = _world.get_nearest_hazard_ahead(_motor.global_position, HAZARD_LOOKAHEAD_DISTANCE)
	if not hazard.is_empty():
		var preferred_takeoff_x: float = float(hazard.get("start_x", INF)) - HAZARD_BODY_CLEARANCE
		# A low-clearance gate can hide the ideal launch point until the robot has
		# already passed it. Do not discard the hazard in that case: brake at once,
		# charge in place, and jump from the earliest still-possible position.
		var hazard_takeoff_x: float = maxf(preferred_takeoff_x, _motor.global_position.x)
		best = {
			"takeoff_x": hazard_takeoff_x,
			"charge_ratio": _hazard_charge_ratio(float(hazard.get("width", 0.0))),
			"reason": "hazard",
		}

	var edge_plan: Dictionary = _edge_jump_plan(platform)
	if best.is_empty() or float(edge_plan.get("takeoff_x", INF)) < float(best.get("takeoff_x", INF)):
		best = edge_plan
	return best

func _edge_jump_plan(platform: Dictionary) -> Dictionary:
	var end_x: int = int(platform.get("end_x", 0))
	# Preserve the old bot's proven strategy of jumping at every authored
	# platform end. The correction is geometric: end_x is a tile centre, so the
	# physical ledge is (end_x + 1) tiles from the origin. The old controller
	# treated end_x + 0.5 as the edge and released about 60 px too early.
	var physical_edge_x: float = _world.to_global(Vector2(float(end_x + 1) * _world.tile_size, 0.0)).x
	return {
		"takeoff_x": physical_edge_x - EDGE_BODY_CLEARANCE,
		"charge_ratio": 0.70,
		"reason": "edge",
	}

func _hazard_charge_ratio(width: float) -> float:
	# Hazards get more vertical margin than ordinary gaps. A merely survivable
	# tap can still brush a floor arc on the way down even when the horizontal
	# range is sufficient.
	if width <= 48.0:
		return 0.25
	if width <= 96.0:
		return 0.50
	if width <= 160.0:
		return 0.65
	return 0.85

class_name RunUnitScriptedController
extends Node

## A deliberately modest bot that proves non-human actions share the motor.
@export var player_path: NodePath
@export var world_path: NodePath
## Human-looking input is time-based rather than tied to one magic distance:
## at higher speed UNIT-07 ducks earlier, while a slow approach stays compact.
const CROUCH_LOOKAHEAD_SECONDS: float = 0.28
const CROUCH_LOOKAHEAD_MIN: float = 40.0
const CROUCH_LOOKAHEAD_MAX: float = 96.0
const HAZARD_LOOKAHEAD_DISTANCE: float = 280.0
## The motor's standing body is 50 px wide. Keeping its centre this far from
## an edge/hazard lets the jump release late without clipping the obstacle.
const EDGE_BODY_CLEARANCE: float = 27.0
const HAZARD_BODY_CLEARANCE: float = 60.0
## Charge starts early enough to reach the desired spring compression, but the
## release is governed by position so the bot no longer launches ~60 px early.
const CHARGE_START_PADDING: float = 14.0
const RELEASE_WINDOW: float = 10.0
## Never slam horizontal input to zero simply to finish a charge. A competent
## player feathers the approach, so the controller keeps a small amount of
## forward input while the motor's own acceleration/deceleration smooths it.
const MIN_APPROACH_INPUT: float = 0.22
const HAZARD_TIME_MARGIN: float = 0.10
const LANDING_DEPTH_MIN: float = 24.0
const LANDING_DEPTH_MAX: float = 52.0

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
	action.movement = _movement_input_for_plan()
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
	var lookahead: float = clampf(
		absf(_motor.velocity.x) * CROUCH_LOOKAHEAD_SECONDS,
		CROUCH_LOOKAHEAD_MIN,
		CROUCH_LOOKAHEAD_MAX
	)
	return _motor.has_low_clearance_ahead(0.0) or _motor.has_low_clearance_ahead(lookahead)

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

func _movement_input_for_plan() -> float:
	if is_nan(_active_takeoff_x) or _active_charge_ratio <= 0.0:
		return 1.0
	var remaining_charge: float = maxf(_active_charge_ratio - _motor.charge_ratio, 0.0)
	if remaining_charge <= 0.02:
		return 1.0
	var distance_to_takeoff: float = maxf(_active_takeoff_x - _motor.global_position.x, 0.0)
	var speed: float = maxf(absf(_motor.velocity.x), _motor.max_run_speed * 0.35)
	var charge_time_remaining: float = remaining_charge * _motor.max_charge_time
	var distance_needed_at_current_speed: float = speed * charge_time_remaining
	var usable_distance: float = maxf(distance_to_takeoff - RELEASE_WINDOW, 0.0)
	if distance_needed_at_current_speed <= usable_distance:
		return 1.0
	# Scale down continuously as the charge would otherwise overrun the mark.
	# Keeping a non-zero target speed looks like a human feathering the key and
	# also avoids the old run-stop-jump cadence.
	var overshoot: float = distance_needed_at_current_speed - usable_distance
	return clampf(1.0 - overshoot / 90.0, MIN_APPROACH_INPUT, 1.0)

func _build_jump_plan() -> Dictionary:
	var platform: Dictionary = _world.get_platform_below_position(_motor.global_position)
	if platform.is_empty():
		return {}

	var best: Dictionary = {}
	var hazard: Dictionary = _world.get_nearest_hazard_ahead(_motor.global_position, HAZARD_LOOKAHEAD_DISTANCE)
	if not hazard.is_empty() and not _can_run_through_hazard(hazard):
		var preferred_takeoff_x: float = float(hazard.get("start_x", INF)) - HAZARD_BODY_CLEARANCE
		var platform_id: int = int(platform.get("platform_id", 0))
		preferred_takeoff_x += _stable_variation(platform_id + 17, 2.5)
		# If a low gate hid the ideal launch point, keep moving slowly while the
		# spring finishes charging instead of stopping dead on the spot.
		var hazard_takeoff_x: float = maxf(preferred_takeoff_x, _motor.global_position.x)
		best = {
			"takeoff_x": hazard_takeoff_x,
			"charge_ratio": _hazard_charge_ratio(float(hazard.get("width", 0.0))),
			"reason": "hazard",
		}

	var edge_plan: Dictionary = _edge_jump_plan(platform)
	if not edge_plan.is_empty() and (best.is_empty() or float(edge_plan.get("takeoff_x", INF)) < float(best.get("takeoff_x", INF))):
		best = edge_plan
	return best

func _can_run_through_hazard(hazard: Dictionary) -> bool:
	var node: Node = hazard.get("node") as Node
	if not node is RunUnitTimedHazard:
		return false
	var timed: RunUnitTimedHazard = node as RunUnitTimedHazard
	var speed: float = maxf(absf(_motor.velocity.x), _motor.max_run_speed * 0.72)
	var start_x: float = float(hazard.get("start_x", _motor.global_position.x))
	var width: float = float(hazard.get("width", 0.0))
	var arrival_seconds: float = maxf(start_x - _motor.global_position.x - 18.0, 0.0) / speed
	var crossing_seconds: float = (width + HAZARD_BODY_CLEARANCE) / speed
	var window_start: float = maxf(arrival_seconds - HAZARD_TIME_MARGIN, 0.0)
	var window_end: float = arrival_seconds + crossing_seconds + HAZARD_TIME_MARGIN
	return not timed.is_active_during_window(window_start, window_end)

func _edge_jump_plan(platform: Dictionary) -> Dictionary:
	var end_x: int = int(platform.get("end_x", 0))
	var physical_edge_x: float = _world.to_global(Vector2(float(end_x + 1) * _world.tile_size, 0.0)).x
	var next_platform: Dictionary = _next_landing_platform(platform)
	if next_platform.is_empty():
		# Keep the old safe fallback for malformed/final geometry where there is
		# no obvious authored landing surface ahead.
		return {
			"takeoff_x": physical_edge_x - EDGE_BODY_CLEARANCE,
			"charge_ratio": 0.70,
			"reason": "edge",
		}

	var gap_tiles: int = maxi(int(next_platform.get("start_x", end_x + 1)) - end_x - 1, 0)
	var rise_pixels: float = float(int(platform.get("height", 0)) - int(next_platform.get("height", 0))) * _world.tile_size
	# Adjacent flat/downhill surfaces do not need a ceremonial hop. Running off
	# the lip and continuing looks much more like an ordinary clean playthrough.
	if gap_tiles == 0 and rise_pixels <= 8.0:
		return {}

	var landing_width: float = float(next_platform.get("width", 1)) * _world.tile_size
	var landing_depth: float = clampf(landing_width * 0.22, LANDING_DEPTH_MIN, LANDING_DEPTH_MAX)
	var required_range: float = EDGE_BODY_CLEARANCE + float(gap_tiles) * _world.tile_size + landing_depth
	var charge_ratio: float = _required_charge_ratio(required_range, rise_pixels)
	var platform_id: int = int(platform.get("platform_id", 0))
	charge_ratio = clampf(charge_ratio + _stable_variation(platform_id, 0.025), 0.02, 0.95)
	return {
		"takeoff_x": physical_edge_x - EDGE_BODY_CLEARANCE + _stable_variation(platform_id + 5, 2.5),
		"charge_ratio": charge_ratio,
		"reason": "edge",
	}

func _next_landing_platform(platform: Dictionary) -> Dictionary:
	var current_id: int = int(platform.get("platform_id", -1))
	var current_end: int = int(platform.get("end_x", 0))
	var best: Dictionary = {}
	var best_start: int = 1 << 30
	for candidate: Dictionary in _world.get_current_plan():
		if int(candidate.get("platform_id", -2)) == current_id:
			continue
		var candidate_start: int = int(candidate.get("start_x", 0))
		var candidate_end: int = int(candidate.get("end_x", 0))
		if candidate_end <= current_end or candidate_start < current_end - 1:
			continue
		if candidate_start < best_start:
			best_start = candidate_start
			best = candidate
	return best.duplicate()

func _required_charge_ratio(horizontal_distance: float, rise_pixels: float) -> float:
	var gravity: float = maxf(_motor.gravity, 1.0)
	var fall_gravity: float = gravity * _motor.fall_gravity_multiplier
	var flight_speed: float = _motor.max_run_speed * 0.88
	var min_speed: float = absf(_motor.min_jump_velocity)
	var max_speed: float = absf(_motor.jump_velocity)
	for step: int in range(0, 51):
		var ratio: float = float(step) / 50.0
		var launch_speed: float = lerpf(min_speed, max_speed, pow(ratio, _motor.charge_power_curve))
		var apex_height: float = launch_speed * launch_speed / (2.0 * gravity)
		if apex_height < rise_pixels + 10.0:
			continue
		var up_time: float = launch_speed / gravity
		var down_distance: float = maxf(apex_height - rise_pixels, 0.0)
		var down_time: float = sqrt(2.0 * down_distance / fall_gravity)
		if flight_speed * (up_time + down_time) >= horizontal_distance + 8.0:
			return ratio
	return 0.95

func _stable_variation(key: int, amplitude: float) -> float:
	var bucket: int = posmod(key * 37 + 11, 7) - 3
	return float(bucket) / 3.0 * amplitude

func _hazard_charge_ratio(width: float) -> float:
	# Hazards keep extra vertical margin so a clean take never brushes an arc.
	if width <= 48.0:
		return 0.22
	if width <= 96.0:
		return 0.42
	if width <= 160.0:
		return 0.62
	return 0.82

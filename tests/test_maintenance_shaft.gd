extends GutTest

## Regression tests against the shipping level itself
## (scenes/world.tscn -> assets/tiled/levels/maintenance_shaft.tmj), rather
## than the small fixture map in test_tiled_static_world.gd. These catch a
## bad shipping map that still satisfies the generic tile invariants.

const WORLD_SCENE: PackedScene = preload("res://scenes/world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const DECK_Y: float = 416.0          # Platform03/04 surface the gate sits over
const GATE_LEFT_X: float = 1920.0    # jammed elevator door spans tiles 60-62
const GATE_RIGHT_X: float = 2016.0

## Every retired route name, so in-world signage cannot drift back to the
## storyline StorylineSketch.md replaced.
const RETIRED_SIGNAGE: Array[String] = ["FINAL INSPECTION", "MAINTENANCE SHAFT", "SOLAR IGNITION CORE"]


func test_tutorial_signage_uses_the_current_storyline() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	assert_null(world.get_node_or_null("ShaftTitle"), "The 'CALIBRATION // MOVEMENT TEST' facility title sign has been removed")
	var signage: PackedStringArray = PackedStringArray()
	for label: Label in _find_labels(world):
		signage.append(label.text.to_upper())
	var all_signage: String = "\n".join(signage)
	for retired: String in RETIRED_SIGNAGE:
		assert_false(all_signage.contains(retired), "Retired name '%s' must not return to tutorial signage" % retired)


func test_crouch_prompt_is_inside_the_viewport_when_approaching_the_gate() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var prompt: Node2D = world.get_node("TutorialSigns/CrouchPrompt") as Node2D
	var heading: Label = prompt.get_node("Heading") as Label
	var keys: Label = prompt.get_node("Keys") as Label
	var camera_center_x: float = (GATE_LEFT_X - 120.0) + RunUnitFollowCamera.BASE_OFFSET.x
	var viewport_left_x: float = camera_center_x - 480.0
	var viewport_right_x: float = camera_center_x + 480.0
	var prompt_left_x: float = prompt.global_position.x + minf(heading.offset_left, keys.offset_left)
	var prompt_right_x: float = prompt.global_position.x + maxf(heading.offset_right, keys.offset_right)
	assert_gt(prompt_left_x, viewport_left_x + 16.0, "The crouch instruction stays clear of the left screen edge")
	assert_lt(prompt_right_x, viewport_right_x - 16.0, "The crouch instruction stays clear of the right screen edge")


func _find_labels(node: Node) -> Array[Label]:
	var labels: Array[Label] = []
	var label: Label = node as Label
	if label != null:
		labels.append(label)
	for child: Node in node.get_children():
		labels.append_array(_find_labels(child))
	return labels



func _standing_action(movement: float, crouch: bool) -> RunUnitPlayerAction:
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = movement
	action.crouch_held = crouch
	return action


## Drives the player rightwards for a while and reports how far it got.
func _drive_through_gate(crouch: bool, crouch_height: float = 36.0) -> float:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.crouch_collision_height = crouch_height
	player.global_position = Vector2(GATE_LEFT_X - 120.0, DECK_Y - 32.0)

	for frame: int in range(150):
		player.set_action(_standing_action(1.0, crouch))
		await get_tree().physics_frame

	return player.global_position.x


func test_shipping_maintenance_shaft_has_the_expected_route() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_true(world.is_route_valid(), "The shipping level must produce a route from its Semantic layer")

	var plan: Array[Dictionary] = world.get_current_plan()
	assert_eq(plan.size(), 5, "Calibration sequences a tap, charged rise, full-charge landing, and crouch gate")

	var expected: Array[Array] = [
		[0, 17, 14],
		[21, 31, 14],
		[34, 42, 11],
		[46, 52, 7],
		[56, 68, 13],
	]
	for index: int in range(expected.size()):
		var platform: Dictionary = plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]))

	assert_eq(world.get_route_length(), 69.0, "The tutorial should stay deliberately short")


func _jump_to_full_charge_landing(charge_frames: int) -> bool:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child(world)
	add_child(player)
	var plan: Array[Dictionary] = world.get_current_plan()
	var source: Dictionary = plan[2]
	var target: Dictionary = plan[3]
	var release_x: float = (float(source["end_x"]) + 1.0) * 32.0 - 20.0
	var start_x: float = maxf(release_x - 4.75 * charge_frames - 160.0, float(source["start_x"]) * 32.0 + 26.0)
	player.global_position = Vector2(start_x, float(source["height"]) * 32.0 - 32.0)
	for frame: int in range(3):
		await get_tree().physics_frame
	var released: bool = false
	var landed: bool = false
	var target_y: float = float(target["height"]) * 32.0 - 32.0
	for frame: int in range(240):
		var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
		action.movement = 1.0
		var current_x: float = player.global_position.x
		if not released:
			if charge_frames == 0 and current_x >= release_x:
				action.jump_pressed = true
				released = true
			elif charge_frames > 0 and current_x >= release_x:
				action.jump_released = true
				released = true
			elif charge_frames > 0 and current_x >= release_x - 4.75 * charge_frames:
				action.jump_held = true
		player.set_action(action)
		await get_tree().physics_frame
		if released and player.last_launch_velocity < 0.0 and player.is_on_floor() and player.velocity.y >= 0.0 and current_x > release_x + 32.0:
			landed = floori(player.global_position.x / 32.0) >= int(target["start_x"]) and absf(player.global_position.y - target_y) < 6.0
			break
		if player.global_position.y > 900.0:
			break
	player.free()
	world.free()
	return landed


func test_calibration_upper_landing_requires_full_charge_after_the_tap_and_medium_rises() -> void:
	assert_false(await _jump_to_full_charge_landing(0), "A tap cannot reach the full-charge lesson ledge")
	assert_false(await _jump_to_full_charge_landing(16), "A medium charge clears the prior rise but not this ledge")
	assert_true(await _jump_to_full_charge_landing(24), "A full charge reaches the high ledge before the existing crouch gate")


func test_shipping_level_publishes_spawn_and_goal_markers() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_eq(world.get_spawn_position(), Vector2(128.0, 385.0), "Spawn comes from the level's Markers layer")
	assert_true(world.has_goal(), "The shipping level declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(2032.0, 352.0))

	var trigger: Area2D = world.get_node_or_null("CompletionTrigger") as Area2D
	assert_not_null(trigger, "A completion trigger should be built from the Goal marker")
	assert_eq(trigger.position, world.get_goal_position(), "The trigger sits on the Goal marker")


func test_player_lands_on_the_shipping_starting_deck() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	player.global_position = world.get_spawn_position()

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_true(player.is_on_floor(), "Spawning at the level's Spawn marker should land on the starting deck")
	assert_almost_eq(player.global_position.y, 448.0 - 32.0, 6.0, "The player settles on the tiled deck surface")


func test_calibration_crouch_prompt_precedes_the_safe_required_gate() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	var prompt: Node2D = world.get_node_or_null("TutorialSigns/CrouchPrompt") as Node2D
	assert_not_null(prompt, "Calibration labels the required crouch gate")
	if prompt == null:
		return
	assert_eq(prompt.global_position.x, 1770.0)
	assert_lt(prompt.global_position.x, GATE_LEFT_X, "The instruction appears before the real gate")

	var heading: Label = prompt.get_node_or_null("Heading") as Label
	assert_not_null(heading)
	if heading != null:
		assert_eq(heading.text, "LOW SERVICE HATCH")
	assert_null(world.get_node_or_null("ElectricalFaults"), "Calibration remains a safe teaching route")

	var full_charge_prompt: Node2D = world.get_node_or_null("TutorialSigns/FullChargePrompt") as Node2D
	assert_not_null(full_charge_prompt, "Calibration teaches a full-charge-only landing after the tap/charge comparison")
	if full_charge_prompt != null:
		var full_charge_heading: Label = full_charge_prompt.get_node_or_null("Heading") as Label
		var full_charge_keys: Label = full_charge_prompt.get_node_or_null("Keys") as Label
		assert_not_null(full_charge_heading)
		assert_not_null(full_charge_keys)
		if full_charge_heading != null:
			assert_eq(full_charge_heading.text, "ENERGY LOCK // SPRING AT LIMIT")
		if full_charge_keys != null:
			assert_eq(full_charge_keys.text, "GREEN LOCK // STORED PRESSURE MAXIMUM")


## The gate's opening clears the visible torso and antenna while remaining
## shorter than the standing body collider. Passability is pinned to the real
## shared gate tile rather than a synthetic ceiling.
func test_player_collider_is_aligned_to_the_full_robot_height() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var collision: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var rectangle: RectangleShape2D = collision.shape as RectangleShape2D
	assert_eq(rectangle.size, Vector2(50.0, 120.0))
	assert_eq(collision.position, Vector2(0.0, -28.0), "The shape keeps its feet at the existing floor anchor")


func test_shipping_crouch_gate_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(false)
	assert_true(reached_x < GATE_LEFT_X, "A standing player must be stopped by the gate, got x=%.1f" % reached_x)


func test_shipping_crouch_gate_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(true)
	assert_true(reached_x > GATE_RIGHT_X, "A crouched player must clear the gate, got x=%.1f" % reached_x)


func test_shipping_gate_allows_a_partial_crouch() -> void:
	var reached_x: float = await _drive_through_gate(true, 48.0)
	assert_true(reached_x > GATE_RIGHT_X, "A crouched body should fit below the raised torso-height gate, got x=%.1f" % reached_x)


## The game stops the player the moment the Goal trigger fires and slams the
## lift door, so the Goal has to sit where the robot is already inside it.
func test_crouched_robot_is_inside_the_lift_door_when_the_route_completes() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.global_position = Vector2(GATE_LEFT_X - 120.0, DECK_Y - 32.0)
	world.route_completed.connect(func() -> void: player.set_physics_process(false))

	for frame: int in range(300):
		if world.is_completion_triggered():
			break
		player.set_action(_standing_action(1.0, true))
		await get_tree().physics_frame
	assert_true(world.is_completion_triggered(), "Driving crouched through the lift should reach the Goal")
	await get_tree().process_frame

	var door: Sprite2D = world.get_node("ElevatorExit/ClosedDoor") as Sprite2D
	var door_rect: Rect2 = door.get_rect()
	var door_left: float = door.to_global(door_rect.position).x
	var door_right: float = door.to_global(door_rect.end).x
	for part: String in ["BodyPivot/Body", "UpperLinkPivot/KneePivot/WheelPivot/Wheel"]:
		var sprite: Sprite2D = player.get_node("RobotVisual/" + part) as Sprite2D
		var rect: Rect2 = sprite.get_rect()
		var xs: Array[float] = []
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			xs.append(sprite.to_global(corner).x)
		assert_gte(xs.min(), door_left, "%s must not stick out left of the slammed lift door" % part)
		assert_lte(xs.max(), door_right, "%s must not stick out right of the slammed lift door" % part)


func test_short_tap_jump_stays_below_the_charged_jump_pad_height() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.global_position = Vector2(800.0, 416.0)
	for frame: int in range(4):
		await get_tree().physics_frame

	var tap: RunUnitPlayerAction = RunUnitPlayerAction.new()
	tap.jump_pressed = true
	player.set_action(tap)
	await get_tree().physics_frame
	player.set_action(RunUnitPlayerAction.new())
	var minimum_y: float = player.global_position.y
	for frame: int in range(50):
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)

	assert_gt(minimum_y, 352.0, "A tap jump should not reach the upper pad's standing height")


func test_charged_jump_reaches_the_charged_jump_pad_height() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.global_position = Vector2(800.0, 416.0)
	for frame: int in range(4):
		await get_tree().physics_frame

	var charge: RunUnitPlayerAction = RunUnitPlayerAction.new()
	charge.jump_held = true
	for frame: int in range(18):
		player.set_action(charge)
		await get_tree().physics_frame
	var release: RunUnitPlayerAction = RunUnitPlayerAction.new()
	release.jump_released = true
	player.set_action(release)
	await get_tree().physics_frame
	player.set_action(RunUnitPlayerAction.new())
	var minimum_y: float = player.global_position.y
	for frame: int in range(50):
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)

	assert_lt(minimum_y, 352.0, "Holding SPACE should provide enough spring height for the upper pad")


func test_calibration_route_marks_each_lesson_without_adding_damage() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	assert_null(world.get_node_or_null("CalibrationLaneMarkers"), "The floor test-marker cues have been removed from calibration")
	assert_null(world.get_node_or_null("ElectricalFaults"), "Calibration stays a consequence-free teaching space")

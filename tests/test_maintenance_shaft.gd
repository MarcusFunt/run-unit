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
	assert_eq(plan.size(), 4, "The light calibration route should have four readable platform beats")

	var expected: Array[Array] = [
		[0, 17, 14],
		[21, 31, 14],
		[34, 45, 12],
		[46, 68, 13],
	]
	for index: int in range(expected.size()):
		var platform: Dictionary = plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]))

	assert_eq(world.get_route_length(), 69.0, "The tutorial should stay deliberately short")


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


## The gate tile's collider is shorter than its 32px cell, leaving just enough
## clearance to force a crouch, which is the whole reason the crouch lesson
## survives being put on a 32px grid. These two tests pin that behaviour to
## the real tile rather than a synthetic ceiling.
func test_shipping_crouch_gate_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(false)
	assert_true(reached_x < GATE_LEFT_X, "A standing player must be stopped by the gate, got x=%.1f" % reached_x)


func test_shipping_crouch_gate_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(true)
	assert_true(reached_x > GATE_RIGHT_X, "A crouched player must clear the gate, got x=%.1f" % reached_x)


func test_shipping_jammed_door_is_lower_than_a_partial_crouch() -> void:
	var reached_x: float = await _drive_through_gate(true, 48.0)
	assert_true(reached_x < GATE_LEFT_X, "A 48 px partial crouch must still be blocked by the lower jammed door, got x=%.1f" % reached_x)


## The game stops the player the moment the Goal trigger fires and slams the
## lift door, so the Goal has to sit where the robot is already inside it.
func test_crouched_robot_is_inside_the_lift_door_when_the_route_completes() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.global_position = Vector2(GATE_LEFT_X - 160.0, DECK_Y - 32.0)
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

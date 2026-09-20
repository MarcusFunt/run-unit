extends GutTest

## Regression coverage for scripts/player/scripted_controller.gd's crouch
## handling. Before this, the bot never set crouch_held and stalled
## permanently at the first crouch gate on every authored route.

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01_factory.tscn")
const TUTORIAL_LEVEL_SCENE: PackedScene = preload("res://scenes/world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const TRANSFER_GATE_LEFT_X: float = 992.0     # jammed conveyor, tiles 31-33 over the row-14 deck
const TRANSFER_GATE_RIGHT_X: float = 1088.0
const TRANSFER_DECK_Y: float = 448.0


func _spawn_bot_before_the_gate() -> Dictionary:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(TRANSFER_GATE_LEFT_X - 120.0, TRANSFER_DECK_Y - 32.0)

	var controller: RunUnitScriptedController = RunUnitScriptedController.new()
	controller.player_path = player.get_path()
	controller.world_path = world.get_path()
	add_child_autofree(controller)
	controller.active = true
	return {"world": world, "player": player, "controller": controller}


func test_bot_crouches_through_the_transfer_line_jam() -> void:
	var rig: Dictionary = _spawn_bot_before_the_gate()
	var player: RunUnitPlayerMotor = rig["player"]

	for frame: int in range(150):
		await get_tree().physics_frame

	assert_true(player.global_position.x > TRANSFER_GATE_RIGHT_X, "The bot must duck through the jammed conveyor instead of stalling, got x=%.1f" % player.global_position.x)


func test_bot_is_crouching_while_under_the_gate() -> void:
	var rig: Dictionary = _spawn_bot_before_the_gate()
	var player: RunUnitPlayerMotor = rig["player"]

	var was_crouching_under_the_gate: bool = false
	for frame: int in range(150):
		await get_tree().physics_frame
		if player.global_position.x > TRANSFER_GATE_LEFT_X and player.global_position.x < TRANSFER_GATE_RIGHT_X:
			was_crouching_under_the_gate = was_crouching_under_the_gate or player.is_crouching()

	assert_true(was_crouching_under_the_gate, "The bot should be crouched at some point while inside the gate's span")


func test_world_exposes_an_inactive_floor_arc_to_the_bot() -> void:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var arc: RunUnitHazardArea = world.get_node("ElectricalFaults/TransferArc") as RunUnitHazardArea
	arc.set_active(false)
	await get_tree().physics_frame
	var hazard: Dictionary = world.get_nearest_hazard_ahead(Vector2(1100.0, TRANSFER_DECK_Y - 32.0), 240.0)
	assert_false(hazard.is_empty(), "The warning plate must remain visible to the bot while a timed arc is electrically off")
	assert_eq(hazard.get("node"), arc, "The controller should be planning around the TransferArc")


func test_bot_jumps_the_factory_floor_arc_instead_of_tanking_the_hit() -> void:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(900.0, TRANSFER_DECK_Y - 32.0)
	var controller: RunUnitScriptedController = RunUnitScriptedController.new()
	controller.player_path = player.get_path()
	controller.world_path = world.get_path()
	add_child_autofree(controller)
	controller.active = true
	var health: RunUnitPlayerHealth = player.get_node("Health") as RunUnitPlayerHealth
	var jumped: Array[bool] = [false]
	player.jumped.connect(func() -> void: jumped[0] = true)

	for frame: int in range(200):
		await get_tree().physics_frame
		if player.global_position.x > 1280.0:
			break

	assert_true(jumped[0], "The bot should deliberately jump the floor arc")
	assert_gt(player.global_position.x, 1240.0, "The bot should clear the hazard and keep moving")
	assert_eq(health.current_health, health.max_health, "Hazard avoidance should prevent the floor arc from damaging the bot")


func test_bot_releases_edge_jump_close_to_the_physical_ledge() -> void:
	var world: RunUnitStaticWorld = TUTORIAL_LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = world.get_spawn_position()
	var platform: Dictionary = world.get_platform_below_position(player.global_position)
	assert_false(platform.is_empty(), "Tutorial spawn should resolve to its authored platform")
	var physical_edge_x: float = world.to_global(Vector2(float(int(platform.get("end_x", 0)) + 1) * world.tile_size, 0.0)).x
	var controller: RunUnitScriptedController = RunUnitScriptedController.new()
	controller.player_path = player.get_path()
	controller.world_path = world.get_path()
	add_child_autofree(controller)
	controller.active = true
	var launch_x: Array[float] = [NAN]
	player.jumped.connect(func() -> void:
		if is_nan(launch_x[0]):
			launch_x[0] = player.global_position.x
	)

	for frame: int in range(240):
		await get_tree().physics_frame
		if not is_nan(launch_x[0]):
			break

	assert_false(is_nan(launch_x[0]), "The bot should jump the tutorial's first gap")
	var distance_before_edge: float = physical_edge_x - launch_x[0]
	assert_lt(distance_before_edge, 45.0, "Takeoff should happen near the ledge, not roughly 60 px early")
	assert_gt(distance_before_edge, 20.0, "Takeoff should still leave the robot body safely on the platform")


func test_jump_charge_scales_with_landing_distance() -> void:
	var world: RunUnitStaticWorld = TUTORIAL_LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var controller: RunUnitScriptedController = RunUnitScriptedController.new()
	controller.player_path = player.get_path()
	controller.world_path = world.get_path()
	add_child_autofree(controller)

	var short_jump: float = controller._required_charge_ratio(105.0, 0.0)
	var long_jump: float = controller._required_charge_ratio(190.0, 0.0)
	assert_lt(short_jump, long_jump, "A short landing should use visibly less spring charge than a long landing")
	assert_lt(short_jump, 0.70, "Easy geometry should not get the old universal 70% jump")
	assert_gt(long_jump, 0.10, "A long landing should still demand meaningful charge")


func test_approach_speed_feathers_instead_of_stopping_dead() -> void:
	var world: RunUnitStaticWorld = TUTORIAL_LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = world.get_spawn_position()
	player.velocity.x = player.max_run_speed
	var controller: RunUnitScriptedController = RunUnitScriptedController.new()
	controller.player_path = player.get_path()
	controller.world_path = world.get_path()
	add_child_autofree(controller)

	controller._active_takeoff_x = player.global_position.x + 4.0
	controller._active_charge_ratio = 0.80
	player.charge_ratio = 0.0
	var movement: float = controller._movement_input_for_plan()
	assert_gt(movement, 0.0, "Finishing a charge must never command a full stop")
	assert_lt(movement, 1.0, "An undercharged late approach should visibly feather forward speed")


func test_timed_hazard_reports_active_windows_for_safe_crossing_plans() -> void:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var arc: RunUnitTimedHazard = world.get_node("ElectricalFaults/TransferArc") as RunUnitTimedHazard
	assert_not_null(arc)
	assert_true(arc.is_active_during_window(0.0, arc.cycle_seconds), "A full authored cycle must include the active phase")

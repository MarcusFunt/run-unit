extends GutTest

## Regression tests against Level 3 itself
## (scenes/levels/level_03_beacon.tscn -> assets/tiled/levels/level_03_beacon.tmj).
## They pin the authored route, the canyon crouch, the charged climbs of the
## exterior ascent, the module UNIT-07 carries in from Level 2, the checkpoints
## that keep a fall from costing the whole route, and the ending: the module's
## one and only use.

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_03_beacon.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LEVEL_3_INDEX: int = 3  # Beacon 9 in the campaign table

const CANYON_GATE_LEFT_X: float = 8192.0    # collapsed service run, tiles 256-258 over the row-24 deck
const CANYON_GATE_RIGHT_X: float = 8288.0
const CANYON_DECK_Y: float = 768.0


func _instantiate_level() -> RunUnitStaticWorld:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	return world


func _drive_through_gate(gate_left_x: float, deck_y: float, crouch: bool) -> float:
	_instantiate_level()
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(gate_left_x - 120.0, deck_y - 32.0)

	for frame: int in range(150):
		var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
		action.movement = 1.0
		action.crouch_held = crouch
		player.set_action(action)
		await get_tree().physics_frame

	return player.global_position.x


## Same jump harness as the Level 1 and 2 tests.
func _jump_to_next_platform(from_index: int, charge_frames: int) -> bool:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child(player)
	var plan: Array[Dictionary] = world.get_current_plan()
	var from: Dictionary = plan[from_index]
	var to: Dictionary = plan[from_index + 1]
	var release_x: float = (float(from["end_x"]) + 1.0) * 32.0 - 20.0
	var start_x: float = maxf(release_x - 4.75 * charge_frames - 160.0, float(from["start_x"]) * 32.0 + 26.0)
	player.global_position = Vector2(start_x, float(from["height"]) * 32.0 - 32.0)
	var target_y: float = float(to["height"]) * 32.0 - 32.0
	var released: bool = false
	var landed: bool = false

	for frame: int in range(240):
		var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
		action.movement = 1.0
		var x: float = player.global_position.x
		if not released:
			if charge_frames == 0 and x >= release_x:
				action.jump_pressed = true
				released = true
			elif charge_frames > 0 and x >= release_x:
				action.jump_released = true
				released = true
			elif charge_frames > 0 and x >= release_x - 4.75 * charge_frames:
				action.jump_held = true
		player.set_action(action)
		await get_tree().physics_frame
		if released and player.last_launch_velocity < 0.0 and player.is_on_floor() and player.velocity.y >= 0.0 and x > release_x + 32.0:
			landed = floori(player.global_position.x / 32.0) >= int(to["start_x"]) and absf(player.global_position.y - target_y) < 6.0
			if not landed:
				gut.p("charge %d came to rest at %s" % [charge_frames, player.global_position])
			break
		if player.global_position.y > world.death_y:
			gut.p("charge %d fell at x=%.1f" % [charge_frames, x])
			break

	player.free()
	world.free()
	return landed


func test_level_03_has_the_expected_route() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	assert_true(world.is_route_valid(), "Level 3 must produce a route from its Semantic layer")

	var plan: Array[Dictionary] = world.get_current_plan()
	var expected: Array[Array] = [
		[0, 26, 14],     # mission confirmation rooftop
		[31, 48, 14],    # rooftop crossing
		[53, 70, 13],
		[75, 92, 15],
		[97, 114, 14],
		[119, 136, 16],
		[141, 166, 17],  # transit viaduct
		[171, 196, 17],
		[201, 224, 18],  # station
		[229, 244, 21],  # utility canyon
		[249, 264, 24],  # collapsed service run (crouch gate)
		[269, 284, 25],
		[289, 312, 25],  # beacon maintenance perimeter
		[317, 336, 24],
		[340, 351, 22],  # exterior ascent: support truss
		[355, 366, 20],
		[370, 381, 18],
		[384, 393, 15],  # maintenance gantries
		[397, 405, 13],
		[408, 416, 10],
		[419, 426, 7],   # ignition access
		[430, 437, 5],
		[442, 469, 5],   # beacon interior
		[474, 501, 5],   # ignition chamber
	]
	assert_eq(plan.size(), expected.size(), "Level 3 should keep its twenty-four authored platform beats")
	for index: int in range(mini(plan.size(), expected.size())):
		var platform: Dictionary = plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]), "platform %d start" % (index + 1))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]), "platform %d end" % (index + 1))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]), "platform %d height" % (index + 1))


func test_level_03_publishes_spawn_goal_and_checkpoints() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()

	assert_eq(world.get_spawn_position(), Vector2(176.0, 385.0), "Spawn sits on the opening rooftop")
	assert_true(world.has_goal(), "Level 3 declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(15504.0, 96.0), "Goal sits where UNIT-07 reaches the ignition interface")

	var checkpoints: Array[Vector2] = world.get_checkpoint_positions()
	assert_eq(checkpoints.size(), 4, "The storyline asks for a few unobtrusive checkpoints on Level 3")
	for index: int in range(1, checkpoints.size()):
		assert_true(checkpoints[index].x > checkpoints[index - 1].x, "Checkpoints are published in route order")
	assert_true(checkpoints[0].x > 8000.0 and checkpoints[0].x < 9000.0, "The first checkpoint sits at the canyon floor")
	assert_true(checkpoints[3].x > 14000.0, "The last checkpoint sits at the ignition chamber entrance")


func test_shorter_routes_publish_no_checkpoints() -> void:
	var tutorial: RunUnitStaticWorld = (load("res://scenes/world.tscn") as PackedScene).instantiate() as RunUnitStaticWorld
	add_child_autofree(tutorial)
	assert_eq(tutorial.get_checkpoint_positions().size(), 0, "The tutorial is short enough to replay from its start")


func test_player_lands_on_the_opening_rooftop() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = world.get_spawn_position()

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_true(player.is_on_floor(), "Spawning at the Spawn marker should land on the rooftop")
	assert_almost_eq(player.global_position.x, 176.0, 1.0, "Nothing should push the player sideways at spawn")
	assert_almost_eq(player.global_position.y, 448.0 - 32.0, 6.0, "The player settles on the tiled rooftop surface")


func test_only_tile_layers_collide_with_the_player() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var story_zone_count: int = 0
	var pending: Array[Node] = [world]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is CollisionObject2D or node.name == &"CompletionTrigger":
			continue
		assert_true(node is Area2D, "%s must not be a physics body" % node.get_path())
		assert_eq((node as CollisionObject2D).collision_layer, 0, "%s must not occupy a collision layer" % node.get_path())
		story_zone_count += 1
	assert_eq(story_zone_count, 8, "All eight story zones should import as collision-free areas")


func test_collapsed_service_run_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(CANYON_GATE_LEFT_X, CANYON_DECK_Y, false)
	assert_true(reached_x < CANYON_GATE_LEFT_X, "A standing player must be stopped by the collapsed service run, got x=%.1f" % reached_x)


func test_collapsed_service_run_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(CANYON_GATE_LEFT_X, CANYON_DECK_Y, true)
	assert_true(reached_x > CANYON_GATE_RIGHT_X, "A crouched player must clear the collapsed service run, got x=%.1f" % reached_x)


func test_ignition_access_climb_needs_a_charged_jump() -> void:
	const GANTRY_INDEX: int = 19  # platform 20 -> platform 21, the first ignition-access climb
	assert_false(await _jump_to_next_platform(GANTRY_INDEX, 0), "A tap jump must not reach the ignition-access gantry")
	assert_true(await _jump_to_next_platform(GANTRY_INDEX, 16), "A charged jump must reach the ignition-access gantry")


func _instantiate_game_for(level_index: int) -> RunUnitGame:
	RunUnitSession.selected_level_index = level_index
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	return game


func before_each() -> void:
	RunUnitSession.clear_checkpoint()


func after_each() -> void:
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	RunUnitSession.clear_checkpoint()
	get_tree().paused = false


func test_deploying_beacon_9_plays_level_3() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_3_INDEX)

	assert_eq(game.world.scene_file_path, "res://scenes/levels/level_03_beacon.tscn", "Beacon 9 should load the Level 3 world")
	assert_eq(game.player.global_position, Vector2(176.0, 385.0), "The run should start at Level 3's Spawn marker")
	assert_not_null(game.route_exit, "Level 3 owns its ending")
	assert_true(game.route_exit is RunUnitBeaconIgnition, "Level 3's ending is the ignition chamber")


func test_unit_07_starts_level_3_carrying_the_module() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_3_INDEX)
	var carried: RunUnitCarriedModule = game.world.get_node("CarriedModule") as RunUnitCarriedModule

	assert_true(carried.is_carried(), "Level 3 opens with the module recovered in Level 2 already mounted")
	assert_true(game.player.is_ancestor_of(carried.get_mounted_module()), "The module rides on UNIT-07")


func test_passing_a_checkpoint_moves_where_a_retry_resumes() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_3_INDEX)
	var checkpoints: Array[Vector2] = game.world.get_checkpoint_positions()
	var spawn: Vector2 = game.world.get_spawn_position()
	assert_false(RunUnitSession.has_checkpoint(LEVEL_3_INDEX), "A fresh deployment starts at the route's spawn")

	game.player.global_position = checkpoints[1] + Vector2(64.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(RunUnitSession.has_checkpoint(LEVEL_3_INDEX), "Driving past a checkpoint should record it")
	assert_eq(RunUnitSession.get_resume_position(LEVEL_3_INDEX, spawn), checkpoints[1], "The furthest passed checkpoint is where a retry resumes")

	game.reset_run(0)

	assert_eq(game.player.global_position, checkpoints[1], "Restarting should resume at the checkpoint, not replay the route")
	var resumed_distance: float = game.score_manager.record_position(game.player.global_position.x)
	assert_almost_eq(resumed_distance, (checkpoints[1].x - spawn.x) / 32.0, 1.0, "Distance is still measured from the route's spawn, so resuming keeps the progress already made")


func test_completing_the_route_clears_the_checkpoint() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_3_INDEX)
	RunUnitSession.record_checkpoint(LEVEL_3_INDEX, Vector2(9000.0, 700.0))

	game.world.route_completed.emit()

	assert_false(RunUnitSession.has_checkpoint(LEVEL_3_INDEX), "Finishing a route means the next deployment starts over")


func test_installing_the_module_plays_the_activation_and_ends_the_run() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_3_INDEX)
	var ignition: RunUnitBeaconIgnition = game.route_exit as RunUnitBeaconIgnition
	var carried: RunUnitCarriedModule = game.world.get_node("CarriedModule") as RunUnitCarriedModule
	ignition.install_delay = 0.1
	ignition.stage_interval = 0.1
	ignition.hold_after_activation = 0.1
	ignition.fade_duration = 0.1
	watch_signals(ignition)

	game.world.route_completed.emit()

	assert_true(game.is_terminal(), "Reaching the interface completes the route")
	assert_true(ignition.transition_started, "Completing Level 3 hands the ending to the ignition chamber")
	await wait_for_signal(ignition.transition_finished, 5.0)

	assert_true(ignition.installed, "The module is installed into Beacon 9")
	assert_signal_emit_count(ignition, "module_installed", 1, "The module is used exactly once")
	assert_false(carried.is_carried(), "The module leaves UNIT-07 for good when it is installed")
	assert_true(ignition.seated_module.visible, "The module is visible in the interface afterwards")
	assert_eq(ignition.lit_stages, ignition.stage_paths.size(), "Activation propagates through every stage")
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_true(ignition.next_scene_path.is_empty(), "The ending stays in the game rather than cutting to another scene")
	assert_eq(ignition.blackout.color.a, 0.0, "With nothing to cut to, the ending holds on the restored beacon")
	assert_true(game.death_menu.visible, "The run finishes on the results screen")
	assert_true(game.death_menu.description_label.text.contains("Beacon 9 ignition restored"), "Results copy should come from Level 3")


func test_restarting_level_3_puts_the_module_back_on_the_robot() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_3_INDEX)
	var ignition: RunUnitBeaconIgnition = game.route_exit as RunUnitBeaconIgnition
	var carried: RunUnitCarriedModule = game.world.get_node("CarriedModule") as RunUnitCarriedModule
	carried.stow()
	assert_false(carried.is_carried())

	game.reset_run(0)

	assert_true(carried.is_carried(), "A restart hands UNIT-07 its module back")
	assert_false(ignition.installed, "A restart puts the ending back before the installation")
	assert_false(ignition.transition_started)
	assert_eq(ignition.lit_stages, 0, "The activation stages go dark again")

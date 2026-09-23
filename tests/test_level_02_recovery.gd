extends GutTest

## Regression tests against Level 2 itself
## (scenes/levels/level_02_recovery.tscn -> assets/tiled/levels/level_02_recovery.tmj).
## They pin the authored route, both crouch gates (the jammed maintenance
## hatch and the emergency shutter), the core-access charged climb, the
## single-use module acquisition, and that only Semantic/Obstacles collide.

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_02_recovery.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LEVEL_2_INDEX: int = 2  # Recovery in the campaign table

const HATCH_GATE_LEFT_X: float = 4800.0     # jammed maintenance hatch, tiles 150-152 over the row-14 gantry
const HATCH_GATE_RIGHT_X: float = 4896.0
const HATCH_DECK_Y: float = 448.0
const SHUTTER_GATE_LEFT_X: float = 9952.0   # emergency shutter, tiles 311-313 over the row-18 exit
const SHUTTER_GATE_RIGHT_X: float = 10048.0
const SHUTTER_DECK_Y: float = 576.0


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


## Same jump harness as the Level 1 tests: run off the right edge of
## `from_index` and jump, holding SPACE for `charge_frames` (0 = tap).
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


func test_level_02_has_the_expected_route() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	assert_true(world.is_route_valid(), "Level 2 must produce a route from its Semantic layer")

	var plan: Array[Dictionary] = world.get_current_plan()
	var expected: Array[Array] = [
		[0, 22, 12],     # factory breach ledge
		[26, 40, 13],    # service catwalk
		[44, 55, 15],    # first rooftop
		[59, 64, 14],
		[68, 80, 17],
		[84, 91, 19],    # balcony walkway
		[95, 99, 18],
		[103, 124, 20],  # Reserve Depot 03 sightline
		[128, 132, 19],
		[135, 139, 16],  # service platform (charged climb)
		[143, 170, 14],  # maintenance hatch (crouch gate) + upper gantry
		[174, 182, 17],  # cooling descent
		[186, 194, 20],
		[198, 207, 23],
		[211, 224, 26],  # lower machinery floor
		[227, 231, 23],  # core-access ascent
		[234, 238, 21],
		[241, 245, 18],
		[248, 252, 15],
		[256, 272, 13],  # vault perimeter
		[276, 290, 13],  # storage cradle
		[294, 302, 16],  # maintenance return
		[306, 341, 18],  # emergency shutter opens into the longer outbound deck
		[345, 358, 17],  # upper conduit span
		[362, 372, 19],  # lower city crossing
		[376, 393, 16],  # final return to the skyline
	]
	assert_eq(plan.size(), expected.size(), "Level 2 should keep its twenty-six authored platform beats")
	for index: int in range(mini(plan.size(), expected.size())):
		var platform: Dictionary = plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]), "platform %d start" % (index + 1))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]), "platform %d end" % (index + 1))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]), "platform %d height" % (index + 1))


func test_level_02_publishes_spawn_and_goal_markers() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()

	assert_eq(world.get_spawn_position(), Vector2(160.0, 321.0), "Spawn sits just above the factory breach ledge")
	assert_true(world.has_goal(), "Level 2 declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(12512.0, 448.0), "Goal sits beyond the extended outbound service route")

	var trigger: Area2D = world.get_node_or_null("CompletionTrigger") as Area2D
	assert_not_null(trigger, "A completion trigger should be built from the Goal marker")
	assert_eq(trigger.position, world.get_goal_position(), "The trigger sits on the Goal marker")


func test_player_lands_on_the_breach_ledge() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = world.get_spawn_position()

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_true(player.is_on_floor(), "Spawning at the Spawn marker should land on the breach ledge")
	assert_almost_eq(player.global_position.x, 160.0, 1.0, "Nothing in the level should push the player sideways at spawn")
	assert_almost_eq(player.global_position.y, 384.0 - 32.0, 6.0, "The player settles on the tiled ledge surface")


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
		if str(node.get_path()).contains("/StoryZones/"):
			story_zone_count += 1
	assert_eq(story_zone_count, 9, "All nine story zones should import as collision-free areas")


func test_maintenance_hatch_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(HATCH_GATE_LEFT_X, HATCH_DECK_Y, false)
	assert_true(reached_x < HATCH_GATE_LEFT_X, "A standing player must be stopped by the jammed hatch, got x=%.1f" % reached_x)


func test_maintenance_hatch_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(HATCH_GATE_LEFT_X, HATCH_DECK_Y, true)
	assert_true(reached_x > HATCH_GATE_RIGHT_X, "A crouched player must clear the jammed hatch, got x=%.1f" % reached_x)


func test_emergency_shutter_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(SHUTTER_GATE_LEFT_X, SHUTTER_DECK_Y, false)
	assert_true(reached_x < SHUTTER_GATE_LEFT_X, "A standing player must be stopped by the shutter, got x=%.1f" % reached_x)


func test_emergency_shutter_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(SHUTTER_GATE_LEFT_X, SHUTTER_DECK_Y, true)
	assert_true(reached_x > SHUTTER_GATE_RIGHT_X, "A crouched player must clear the shutter, got x=%.1f" % reached_x)


func test_core_access_climb_needs_a_charged_jump() -> void:
	const CORE_ACCESS_INDEX: int = 16  # platform 17 -> platform 18 (three rows up)
	assert_false(await _jump_to_next_platform(CORE_ACCESS_INDEX, 0), "A tap jump must not reach the next core-access gantry")
	assert_true(await _jump_to_next_platform(CORE_ACCESS_INDEX, 16), "A charged jump must reach the next core-access gantry")


func test_reaching_the_cradle_mounts_the_module_once() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var cradle: RunUnitModuleCradle = world.get_node_or_null("ModuleCradle") as RunUnitModuleCradle
	assert_not_null(cradle, "Level 2 carries the reserve module cradle")
	if cradle == null:
		return
	watch_signals(cradle)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = cradle.global_position + Vector2(-160.0, -32.0)

	for frame: int in range(90):
		var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
		action.movement = 1.0
		player.set_action(action)
		await get_tree().physics_frame

	assert_true(cradle.acquired, "Driving through the cradle should acquire the module")
	assert_signal_emit_count(cradle, "module_acquired", 1, "The module is acquired exactly once")
	assert_false(cradle.cradle_module.visible, "The module leaves its cradle")
	assert_not_null(cradle.get_mounted_module(), "The module is mounted on UNIT-07")
	assert_true(player.is_ancestor_of(cradle.get_mounted_module()), "The mounted module travels with the player")
	assert_true(cradle.acquisition_readout.visible, "The facility names the target once the module is taken")
	assert_true(cradle.acquisition_readout.text.contains("BEACON 9"), "Acquisition makes Beacon 9 the explicit target")


func test_restarting_the_run_returns_the_module_to_its_cradle() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var cradle: RunUnitModuleCradle = world.get_node_or_null("ModuleCradle") as RunUnitModuleCradle
	assert_not_null(cradle)
	if cradle == null:
		return
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	cradle.acquire_for(player)
	assert_true(cradle.acquired)

	world.reset()

	assert_false(cradle.acquired, "A restart puts the level back before the acquisition")
	assert_true(cradle.cradle_module.visible, "The module is back in its cradle")
	assert_null(cradle.get_mounted_module(), "The player no longer carries a module")
	assert_eq(player.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node.name == &"MountedModule").size(), 0, "No stale module is left on the player")
	assert_false(cradle.acquisition_readout.visible)


func _instantiate_game_for(level_index: int) -> RunUnitGame:
	RunUnitSession.selected_level_index = level_index
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	return game


func before_each() -> void:
	RunUnitSession.save_path = "user://gut_test_level_02_recovery.cfg"
	RunUnitSession.reset_campaign()
	RunUnitSession.record_route_completion(0, 60.0)
	RunUnitSession.record_route_completion(1, 60.0)

func after_each() -> void:
	RunUnitSession.save_path = "user://run_unit_campaign.cfg"
	RunUnitSession.load_campaign()
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	get_tree().paused = false


func test_deploying_recovery_plays_level_2() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)

	assert_eq(game.world.scene_file_path, "res://scenes/levels/level_02_recovery.tscn", "Recovery should load the Level 2 world")
	assert_null(game.route_exit, "Level 2 has no ending of its own")
	assert_eq(game.player.global_position, Vector2(160.0, 321.0), "The run should start at Level 2's Spawn marker")
	assert_eq(RunUnitSession.selected_level_index, LEVEL_2_INDEX, "The session should remember the deployed route for retries")
	var expected_metres: float = absf(game.world.get_goal_position().x - game.world.get_spawn_position().x) / game.world.get_tile_size()
	assert_eq(game.hud.score_progress_bar.max_value, expected_metres, "HUD progress should span Level 2's Spawn to Goal")


func test_restarting_a_recovery_run_resets_the_cradle() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	var cradle: RunUnitModuleCradle = game.world.get_node("ModuleCradle") as RunUnitModuleCradle
	cradle.acquire_for(game.player)

	game.reset_run(0)

	assert_false(cradle.acquired, "Restarting the run must return the module to the cradle")
	assert_null(cradle.get_mounted_module())


func test_completing_level_2_opens_the_results_menu() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	(game.world.get_node("ModuleCradle") as RunUnitModuleCradle).acquire_for(game.player)

	game.world.route_completed.emit()

	assert_true(game.is_terminal())
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_true(game.death_menu.visible, "Without a lift exit, completion should show the results menu")
	assert_true(game.death_menu.description_label.text.contains("02  RECOVERY"), "Results copy should name the campaign route")
	assert_true(game.death_menu.description_label.text.contains("Beacon 9"), "Results copy should come from Level 2")


func test_recovery_exit_without_module_does_not_certify_objective() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	game.world.route_completed.emit()
	assert_eq(RunUnitSession.last_run_outcome, "incomplete")
	assert_false(RunUnitSession.recovery_complete)
	assert_false(RunUnitSession.is_route_unlocked(3))
	assert_true(game.death_menu.description_label.text.contains("MODULE MISSING"))

func test_module_pickup_persists_and_completion_unlocks_beacon() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	var cradle: RunUnitModuleCradle = game.world.get_node("ModuleCradle") as RunUnitModuleCradle
	cradle.acquire_for(game.player)
	assert_true(RunUnitSession.ignition_module_acquired)
	RunUnitSession.load_campaign()
	assert_true(RunUnitSession.ignition_module_acquired, "The module survives closing the game")
	assert_false(RunUnitSession.is_route_unlocked(3), "Recovery still needs a completed run")
	game.world.route_completed.emit()
	assert_true(RunUnitSession.recovery_complete)
	assert_true(RunUnitSession.is_route_unlocked(3))

func test_recovery_adds_checkpoint_after_the_first_indoor_gate() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var checkpoints: Array[Vector2] = world.get_checkpoint_positions()
	assert_eq(checkpoints.size(), 3, "Recovery should have nodes after the hatch, before the module, and on the return")
	if checkpoints.size() == 3:
		assert_eq(checkpoints[0], Vector2(4992, 385), "Checkpoint sits just beyond the jammed maintenance hatch")


func test_recovery_combines_three_timed_faults_with_existing_platforming() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var faults: Node = world.get_node_or_null("ElectricalFaults")
	assert_not_null(faults)
	if faults == null:
		return
	assert_eq(faults.get_child_count(), 3)
	var expected: Array[Vector2] = [Vector2(1680, 480), Vector2(5248, 448), Vector2(6944, 832)]
	for index: int in range(expected.size()):
		var hazard: RunUnitTimedHazard = faults.get_child(index) as RunUnitTimedHazard
		assert_not_null(hazard)
		if hazard != null:
			assert_eq(hazard.position, expected[index])
			assert_false(hazard.lethal)

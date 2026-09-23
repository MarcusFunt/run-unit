extends GutTest

## Regression tests against Level 1 itself
## (scenes/levels/level_01_factory.tscn -> assets/tiled/levels/level_01_factory.tmj).
## They pin the authored route, the two crouch gates, the charged climb, and
## that only the Semantic/Obstacles layers can collide with the player.

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01_factory.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LEVEL_1_INDEX: int = 1  # Factory Escape in the campaign table

const TRANSFER_GATE_LEFT_X: float = 992.0     # jammed conveyor, tiles 31-33 over the row-14 deck
const TRANSFER_GATE_RIGHT_X: float = 1088.0
const TRANSFER_DECK_Y: float = 448.0
const STORAGE_GATE_LEFT_X: float = 4512.0     # hanging crate load, tiles 141-143 over the row-23 rack
const STORAGE_GATE_RIGHT_X: float = 4608.0
const STORAGE_DECK_Y: float = 736.0


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


## Runs at the edge of platform `from_index` and jumps, holding SPACE for
## `charge_frames` (0 = tap). Returns true when the player comes to rest on the
## next platform. `min_start_x` keeps the run-up clear of any crouch gate on
## `from`. The world and player are freed before returning so a second attempt
## in the same test never collides with the first attempt's robot.
func _jump_to_next_platform(from_index: int, charge_frames: int, min_start_x: float) -> bool:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child(player)
	var plan: Array[Dictionary] = world.get_current_plan()
	var from: Dictionary = plan[from_index]
	var to: Dictionary = plan[from_index + 1]
	var release_x: float = (float(from["end_x"]) + 1.0) * 32.0 - 20.0
	var start_x: float = maxf(release_x - 4.75 * charge_frames - 160.0, min_start_x)
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
		if player.global_position.y > 1180.0:
			gut.p("charge %d fell at x=%.1f" % [charge_frames, x])
			break

	player.free()
	world.free()
	return landed


func test_level_01_has_the_expected_route() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	assert_true(world.is_route_valid(), "Level 1 must produce a route from its Semantic layer")

	var plan: Array[Dictionary] = world.get_current_plan()
	var expected: Array[Array] = [
		[0, 20, 14],     # transfer lift arrival
		[24, 44, 14],    # jammed line (crouch gate)
		[48, 60, 12],    # raised transfer bed (charged hop)
		[64, 75, 14],
		[80, 95, 13],    # floor gives way
		[93, 112, 23],   # warehouse landing rack
		[116, 130, 22],
		[135, 149, 23],  # hanging crate load (crouch gate)
		[153, 164, 20],  # tall rack (charged climb)
		[170, 183, 22],
		[187, 221, 21],  # breach runway continues onto the exterior catwalk
		[225, 239, 20],  # raised service span
		[243, 254, 22],  # lower maintenance span
		[258, 269, 20],  # final exterior approach
	]
	assert_eq(plan.size(), expected.size(), "Level 1 should keep its fourteen authored platform beats")
	for index: int in range(mini(plan.size(), expected.size())):
		var platform: Dictionary = plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]), "platform %d start" % (index + 1))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]), "platform %d end" % (index + 1))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]), "platform %d height" % (index + 1))


func test_level_01_publishes_spawn_and_goal_markers() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()

	assert_eq(world.get_spawn_position(), Vector2(160.0, 385.0), "Spawn sits just above the arrival deck")
	assert_true(world.has_goal(), "Level 1 declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(8544.0, 576.0), "Goal sits at the far end of the extended exterior catwalk")

	var trigger: Area2D = world.get_node_or_null("CompletionTrigger") as Area2D
	assert_not_null(trigger, "A completion trigger should be built from the Goal marker")
	assert_eq(trigger.position, world.get_goal_position(), "The trigger sits on the Goal marker")


func test_player_lands_on_the_arrival_deck() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = world.get_spawn_position()

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_true(player.is_on_floor(), "Spawning at the Spawn marker should land on the arrival deck")
	assert_almost_eq(player.global_position.x, 160.0, 1.0, "Nothing in the level should push the player sideways at spawn")
	assert_almost_eq(player.global_position.y, TRANSFER_DECK_Y - 32.0, 6.0, "The player settles on the tiled deck surface")


## YATI turns Tiled objects of an unknown class into StaticBody2D colliders,
## which once filled the whole transfer line with invisible walls. Story zones
## must import as Areas that nothing can collide with.
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
	assert_eq(story_zone_count, 5, "All five story zones should import as collision-free areas")


func test_transfer_line_jam_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(TRANSFER_GATE_LEFT_X, TRANSFER_DECK_Y, false)
	assert_true(reached_x < TRANSFER_GATE_LEFT_X, "A standing player must be stopped by the jammed conveyor, got x=%.1f" % reached_x)


func test_transfer_line_jam_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(TRANSFER_GATE_LEFT_X, TRANSFER_DECK_Y, true)
	assert_true(reached_x > TRANSFER_GATE_RIGHT_X, "A crouched player must clear the jammed conveyor, got x=%.1f" % reached_x)


func test_hanging_crates_block_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(STORAGE_GATE_LEFT_X, STORAGE_DECK_Y, false)
	assert_true(reached_x < STORAGE_GATE_LEFT_X, "A standing player must be stopped by the hanging crates, got x=%.1f" % reached_x)


func test_hanging_crates_let_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(STORAGE_GATE_LEFT_X, STORAGE_DECK_Y, true)
	assert_true(reached_x > STORAGE_GATE_RIGHT_X, "A crouched player must clear the hanging crates, got x=%.1f" % reached_x)


func test_tall_rack_needs_a_charged_jump() -> void:
	const LOW_RACK_INDEX: int = 7  # platform 8 -> platform 9 (three rows up)
	# The low rack carries the hanging crates, so the run-up starts past them.
	var clear_of_crates: float = STORAGE_GATE_RIGHT_X + 32.0
	assert_false(await _jump_to_next_platform(LOW_RACK_INDEX, 0, clear_of_crates), "A tap jump must not reach the tall rack")
	assert_true(await _jump_to_next_platform(LOW_RACK_INDEX, 16, clear_of_crates), "A charged jump must reach the tall rack")


func _instantiate_game_for(level_index: int) -> RunUnitGame:
	RunUnitSession.selected_level_index = level_index
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	return game


func before_each() -> void:
	RunUnitSession.save_path = "user://gut_test_level_01_factory.cfg"
	RunUnitSession.reset_campaign()
	RunUnitSession.record_route_completion(0, 60.0)

func after_each() -> void:
	RunUnitSession.save_path = "user://run_unit_campaign.cfg"
	RunUnitSession.load_campaign()
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	get_tree().paused = false


func test_deploying_factory_escape_plays_level_1() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_1_INDEX)

	assert_eq(game.world.scene_file_path, "res://scenes/levels/level_01_factory.tscn", "Factory Escape should load the Level 1 world")
	assert_eq(game.get_children().filter(func(child: Node) -> bool: return child is RunUnitStaticWorld).size(), 1, "Only the selected world should be in the game")
	assert_eq(game.world.get_parent(), game)
	assert_null(game.route_exit, "Level 1 has no ending of its own")
	assert_eq(game.player.global_position, Vector2(160.0, 385.0), "The run should start at Level 1's Spawn marker")
	assert_eq(RunUnitSession.selected_level_index, LEVEL_1_INDEX, "The session should remember the deployed route for retries")
	var expected_metres: float = absf(game.world.get_goal_position().x - game.world.get_spawn_position().x) / game.world.get_tile_size()
	assert_eq(game.hud.score_progress_bar.max_value, expected_metres, "HUD progress should span Level 1's Spawn to Goal")


func test_deploying_calibration_still_plays_the_tutorial() -> void:
	var game: RunUnitGame = _instantiate_game_for(0)

	assert_eq(game.world.scene_file_path, "res://scenes/world.tscn")
	assert_not_null(game.route_exit, "The tutorial keeps its lift exit")


func test_completing_level_1_opens_the_results_menu() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_1_INDEX)

	game.world.route_completed.emit()

	assert_true(game.is_terminal())
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_true(game.death_menu.visible, "Without a lift exit, completion should show the results menu")
	assert_true(game.death_menu.description_label.text.contains("01  FACTORY ESCAPE CERTIFIED"), "Results copy should name the campaign route")
	assert_true(game.death_menu.description_label.text.contains("Exterior wall breached"), "Results copy should come from Level 1, not the tutorial")


func test_factory_escape_adds_two_readable_timed_floor_faults() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var faults: Node = world.get_node_or_null("ElectricalFaults")
	assert_not_null(faults)
	if faults == null:
		return
	assert_eq(faults.get_child_count(), 2, "Factory Escape should introduce the timed hazard language sparingly")
	var expected: Array[Vector2] = [Vector2(1200, 448), Vector2(4032, 704)]
	for index: int in range(expected.size()):
		var hazard: RunUnitTimedHazard = faults.get_child(index) as RunUnitTimedHazard
		assert_not_null(hazard)
		if hazard == null:
			continue
		assert_eq(hazard.position, expected[index])
		assert_false(hazard.lethal)
		assert_not_null(hazard.get_node_or_null("WarningPlate"))

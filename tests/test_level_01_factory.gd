extends GutTest

## Regression tests against Level 1 itself
## (scenes/levels/level_01_factory.tscn -> assets/tiled/levels/level_01_factory.tmj).
## They pin the authored route, the crouch gates, the charged climb, and
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


func _assert_clearance_treatment(world: RunUnitStaticWorld, gate_name: String, expected_position: Vector2) -> void:
	var gate: Node2D = world.get_node_or_null("ClearanceTreatments/" + gate_name) as Node2D
	assert_not_null(gate, "%s treatment must be present" % gate_name)
	if gate == null:
		return
	assert_eq(gate.global_position, expected_position, "%s treatment aligns to its authored gate" % gate_name)
	assert_false(gate is CollisionObject2D, "%s treatment must stay decorative" % gate_name)
	var bounds: Rect2 = gate.call("get_visual_bounds")
	assert_eq(bounds.size, Vector2(96.0, 32.0), "%s treatment keeps the authored gate span" % gate_name)
	assert_eq(bounds.position.y, -134.0, "%s treatment stays at the lowered, body-clearing height" % gate_name)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(expected_position.x, expected_position.y - 32.0)
	player._is_crouching = true
	player.crouch_ratio = 1.0
	var player_visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	player_visual.set_process(false)
	player_visual.run_process_for_test(0.016)
	var body: Sprite2D = player_visual.get_node("BodyPivot/Body") as Sprite2D
	var body_rect: Rect2 = body.get_rect()
	var body_top_y: float = minf(
		body.to_global(body_rect.position).y,
		body.to_global(Vector2(body_rect.end.x, body_rect.position.y)).y
	)
	assert_gt(body_top_y, gate.global_position.y + bounds.end.y, "%s leaves the crouched robot's body clear" % gate_name)


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


func test_crouch_gate_visual_treatments_are_aligned_and_non_colliding() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	_assert_clearance_treatment(world, "FactoryTransferGate", Vector2(1040.0, 448.0))
	_assert_clearance_treatment(world, "FactoryStorageGate", Vector2(4560.0, 736.0))
	_assert_clearance_treatment(world, "FactoryExteriorGate", Vector2(7920.0, 704.0))


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
		[187, 197, 21],  # short approach to the exterior service seam
		[198, 200, 22],  # lower catch before the next raised section
		[201, 210, 21],  # raised service beat
		[211, 213, 22],  # second catch ledge breaks up the rooftop run
		[214, 221, 21],
		[225, 239, 20],  # raised service span
		[243, 254, 22],  # lower maintenance span
		[258, 269, 19],  # charged escape leap onto the final approach
	]
	assert_eq(plan.size(), expected.size(), "The exterior runway should break into short, readable traversal beats")
	for index: int in range(mini(plan.size(), expected.size())):
		var platform: Dictionary = plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]), "platform %d start" % (index + 1))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]), "platform %d end" % (index + 1))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]), "platform %d height" % (index + 1))


func test_level_01_publishes_spawn_and_goal_markers() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()

	assert_eq(world.get_spawn_position(), Vector2(160.0, 385.0), "Spawn sits just above the arrival deck")
	assert_true(world.has_goal(), "Level 1 declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(8544.0, 608.0), "Goal sits at the far end of the extended exterior catwalk")

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
	var nodes_to_visit: Array[Node] = [world]
	while not nodes_to_visit.is_empty():
		var node: Node = nodes_to_visit.pop_back()
		nodes_to_visit.append_array(node.get_children())
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


func test_final_crouch_gate_leads_into_the_charged_escape_leap() -> void:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child(world)
	var crusher: RunUnitTimedHazard = world.get_node("MechanicalHazards/ExteriorCrusher") as RunUnitTimedHazard
	crusher.active_seconds = 0.0
	crusher.reset_level_state()
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child(player)
	player.global_position = Vector2(7872.0 - 120.0, 704.0 - 32.0)
	const TAKEOFF_X: float = 8140.0
	const AFTER_GATE_X: float = 8000.0
	const CHARGE_START_X: float = 8064.0
	const TARGET_FLOOR_Y: float = 19.0 * 32.0
	var jump_released: bool = false
	var landed: bool = false

	for frame: int in range(240):
		var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
		action.movement = 1.0
		var x: float = player.global_position.x
		if x < AFTER_GATE_X:
			action.crouch_held = true
		elif not jump_released and x >= CHARGE_START_X and x < TAKEOFF_X:
			action.jump_held = true
		elif not jump_released and x >= TAKEOFF_X:
			action.jump_released = true
			jump_released = true
		player.set_action(action)
		await get_tree().physics_frame
		if jump_released and player.last_launch_velocity < 0.0 and player.is_on_floor() and player.velocity.y >= 0.0 and x > TAKEOFF_X + 32.0:
			landed = floori(player.global_position.x / 32.0) >= 258 and absf(player.global_position.y - (TARGET_FLOOR_Y - 32.0)) < 6.0
			break
		if player.global_position.y > 1180.0:
			break

	assert_true(landed, "A player can crouch through the exterior gate, charge the jump, and reach the final approach")
	player.free()
	world.free()


func test_factory_history_units_render_between_background_and_foreground_art() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var units: CanvasItem = world.get_node_or_null("StorageUnits") as CanvasItem
	var background: CanvasItem = world.get_node_or_null("FactoryGeometry/ArtBackground") as CanvasItem
	var foreground: CanvasItem = world.get_node_or_null("FactoryGeometry/ArtForeground") as CanvasItem
	assert_not_null(units, "Factory Escape keeps its stored UNIT history setpiece")
	assert_not_null(background, "Factory Escape keeps its industrial background art")
	assert_not_null(foreground, "Factory Escape keeps its foreground obstacle art")
	if units != null and background != null and foreground != null:
		assert_gt(units.z_index, background.z_index, "The history units render in front of the background wall")
		assert_lt(units.z_index, foreground.z_index, "Foreground machinery stays in front of the history units")


func test_factory_removes_the_retired_tunnel_shell_strip() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var tunnel_shell: CanvasItem = world.get_node_or_null("FactoryGeometry/TunnelShell") as CanvasItem
	var background: CanvasItem = world.get_node_or_null("FactoryGeometry/ArtBackground") as CanvasItem
	assert_null(tunnel_shell, "Factory Escape must remove the retired TunnelShell layer entirely")
	assert_not_null(background, "Factory Escape keeps the current industrial background art")
	if background != null:
		assert_true(background.visible, "The current ArtBackground remains as the visual replacement")


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
	assert_not_null(game.route_exit, "Level 1 should end at the dimensional portal")
	assert_true(game.route_exit is RunUnitDimensionalPortalExit)
	assert_eq(game.route_exit.next_scene_path, "res://scenes/game.tscn")
	assert_eq(game.player.global_position, Vector2(160.0, 385.0), "The run should start at Level 1's Spawn marker")
	assert_eq(RunUnitSession.selected_level_index, LEVEL_1_INDEX, "The session should remember the deployed route for retries")
	var expected_metres: float = absf(game.world.get_goal_position().x - game.world.get_spawn_position().x) / game.world.get_tile_size()
	assert_eq(game.hud.score_progress_bar.max_value, expected_metres, "HUD progress should span Level 1's Spawn to Goal")


func test_deploying_calibration_still_plays_the_tutorial() -> void:
	var game: RunUnitGame = _instantiate_game_for(0)

	assert_eq(game.world.scene_file_path, "res://scenes/world.tscn")
	assert_not_null(game.route_exit, "The tutorial should hand off through the dimensional portal")
	assert_true(game.route_exit is RunUnitDimensionalPortalExit)


func test_completing_level_1_starts_the_portal_handoff() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_1_INDEX)

	game.world.route_completed.emit()

	assert_true(game.is_terminal())
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_false(game.death_menu.visible, "Portal completion should stay in-world instead of opening the results menu")
	assert_not_null(game.route_exit)
	if game.route_exit != null:
		assert_true(game.route_exit.transition_started, "Completing Factory Escape should activate the portal")
		assert_eq(game.route_exit.next_scene_path, "res://scenes/game.tscn")


func test_factory_escape_uses_three_spaced_readable_timed_floor_faults() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var faults: Node = world.get_node_or_null("ElectricalFaults")
	assert_not_null(faults)
	if faults == null:
		return
	assert_eq(faults.get_child_count(), 3, "Factory Escape spaces its timed hazards across the route")
	var expected: Array[Vector2] = [Vector2(1200, 448), Vector2(5600, 704), Vector2(7456, 640)]
	for index: int in range(expected.size()):
		var hazard: RunUnitTimedHazard = faults.get_child(index) as RunUnitTimedHazard
		assert_not_null(hazard)
		if hazard == null:
			continue
		assert_eq(hazard.position, expected[index])
		assert_false(hazard.lethal)
		assert_not_null(hazard.get_node_or_null("WarningPlate"))


func test_factory_final_third_combines_timing_crouch_and_an_escape_landing_without_growing() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	assert_eq(world.get_goal_position().x, 8544.0, "The final interactions use the existing route footprint")
	var faults: Node = world.get_node("ElectricalFaults")
	var late_arc_found: bool = false
	for hazard_node: Node in faults.get_children():
		var hazard: RunUnitTimedHazard = hazard_node as RunUnitTimedHazard
		if hazard != null and hazard.position.x >= world.get_goal_position().x * 0.66:
			late_arc_found = true
	assert_true(late_arc_found, "The catastrophic third combines a timed arc with the exit traversal")
	var obstacles: TileMapLayer = world.get_node_or_null("FactoryGeometry/Obstacles") as TileMapLayer
	assert_not_null(obstacles, "The final crouch gate must use the authored Tiled obstacle layer")
	if obstacles != null:
		assert_ne(obstacles.get_cell_source_id(Vector2i(247, 20)), -1, "The final-third gate occupies its authored obstacle cells")
	assert_true(world.get_current_plan().size() >= 14, "The escape leap has a distinct walkable landing")
	var crusher: RunUnitTimedHazard = world.get_node_or_null("MechanicalHazards/ExteriorCrusher") as RunUnitTimedHazard
	assert_not_null(crusher, "The late crouch point leads into an authored timed crusher")
	if crusher != null:
		assert_gte(crusher.position.x, world.get_goal_position().x * 0.66, "The crusher belongs to the catastrophic final third")
		assert_gte(crusher.warning_seconds, 0.65, "The piston telegraphs before the strike")


func _drive_through_final_gate(crouch: bool) -> float:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child(world)
	var crusher: RunUnitHazardArea = world.get_node("MechanicalHazards/ExteriorCrusher") as RunUnitHazardArea
	(crusher as RunUnitTimedHazard).active_seconds = 0.0
	crusher.reset_level_state()
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child(player)
	player.global_position = Vector2(7872.0 - 120.0, 704.0 - 32.0)
	for frame: int in range(150):
		var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
		action.movement = 1.0
		action.crouch_held = crouch
		player.set_action(action)
		await get_tree().physics_frame
	var reached_x: float = player.global_position.x
	player.free()
	world.free()
	return reached_x


func test_final_crouch_gate_blocks_standing_and_admits_the_low_profile_robot() -> void:
	assert_lt(await _drive_through_final_gate(false), 7872.0)
	assert_gt(await _drive_through_final_gate(true), 7968.0)

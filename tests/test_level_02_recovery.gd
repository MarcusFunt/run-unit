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
const DECK_SUPPORT_BRIDGE_CELLS: Array[Vector2i] = [
	Vector2i(27, 14), Vector2i(33, 14), Vector2i(39, 14),
	Vector2i(85, 20), Vector2i(90, 20),
	Vector2i(96, 19), Vector2i(98, 19),
	Vector2i(175, 18), Vector2i(181, 18),
	Vector2i(187, 21), Vector2i(193, 21),
	Vector2i(199, 24), Vector2i(205, 24), Vector2i(206, 24),
	Vector2i(228, 24), Vector2i(230, 24),
	Vector2i(235, 22), Vector2i(237, 22),
	Vector2i(242, 19),
]


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


func test_crouch_gate_visual_treatments_are_aligned_and_non_colliding() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	_assert_clearance_treatment(world, "RecoveryHatch", Vector2(4848.0, 448.0))
	_assert_clearance_treatment(world, "RecoveryShutter", Vector2(10000.0, 576.0))


func test_recovery_deck_supports_reach_the_deck_underside() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiled/levels/level_02_recovery.tmj"))
	assert_true(parsed is Dictionary, "Recovery's authored map should remain readable JSON")
	if not parsed is Dictionary:
		return
	var map_data: Dictionary = parsed as Dictionary
	var tile_layers: Array = map_data.get("layers", [])
	var art_deck: Dictionary = {}
	var art_structure: Dictionary = {}
	for layer_variant: Variant in tile_layers:
		if not layer_variant is Dictionary:
			continue
		var layer: Dictionary = layer_variant as Dictionary
		match str(layer.get("name", "")):
			"ArtDeck":
				art_deck = layer
			"ArtStructure":
				art_structure = layer
	assert_true(not art_deck.is_empty(), "Recovery keeps its decorative deck layer")
	assert_true(not art_structure.is_empty(), "Recovery keeps its structural art layer")
	if art_deck.is_empty() or art_structure.is_empty():
		return
	var width: int = int(map_data.get("width", 0))
	var tilesets: Array = map_data.get("tilesets", [])
	var industrial_first_gid: int = 0
	for tileset_variant: Variant in tilesets:
		if not tileset_variant is Dictionary:
			continue
		var tileset: Dictionary = tileset_variant as Dictionary
		if str(tileset.get("source", "")).ends_with("industrial_zone.tsj"):
			industrial_first_gid = int(tileset.get("firstgid", 0))
	assert_gt(industrial_first_gid, 0, "Recovery keeps the industrial tileset")
	var deck_data: Array = art_deck.get("data", [])
	var structure_data: Array = art_structure.get("data", [])
	for cell: Vector2i in DECK_SUPPORT_BRIDGE_CELLS:
		var index: int = cell.y * width + cell.x
		assert_true(index < deck_data.size() and index < structure_data.size(), "Support cell %s is inside the authored map" % cell)
		if index >= deck_data.size() or index >= structure_data.size():
			continue
		var deck_index: int = (cell.y - 1) * width + cell.x
		assert_true(deck_index >= 0 and deck_index < deck_data.size(), "Deck cap above support %s is inside the authored map" % cell)
		if deck_index < 0 or deck_index >= deck_data.size():
			continue
		assert_eq(int(deck_data[deck_index]), industrial_first_gid + 55, "Deck cap above support %s remains in place" % cell)
		assert_eq(int(structure_data[index]), industrial_first_gid + 60, "Support at %s touches the deck underside" % cell)


func test_level_02_has_the_expected_route() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	assert_true(world.is_route_valid(), "Level 2 must produce a route from its Semantic layer")

	var plan: Array[Dictionary] = world.get_current_plan()
	var solid_plan: Array[Dictionary] = []
	var optional_catwalk: Array[Dictionary] = []
	for platform: Dictionary in plan:
		if str(platform.get("surface_type", "solid")) == "one_way":
			optional_catwalk.append(platform)
		else:
			solid_plan.append(platform)
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
		[241, 271, 18],  # module cradle leads into the varied escape deck
		[272, 299, 19],  # shallow service dip
		[300, 302, 20],  # forgiving lower landing under the first jump gap
		[303, 333, 18],  # short step-up
		[334, 366, 19],  # second shallow dip
		[367, 369, 20],  # forgiving lower landing under the second jump gap
		[370, 393, 18],  # final step-up into the route exit
	]
	assert_eq(solid_plan.size(), expected.size(), "The post-pickup escape should include several low-risk traversal beats")
	for index: int in range(mini(solid_plan.size(), expected.size())):
		var platform: Dictionary = solid_plan[index]
		assert_eq(int(platform.get("start_x", -1)), int(expected[index][0]), "platform %d start" % (index + 1))
		assert_eq(int(platform.get("end_x", -1)), int(expected[index][1]), "platform %d end" % (index + 1))
		assert_eq(int(platform.get("height", -1)), int(expected[index][2]), "platform %d height" % (index + 1))
	assert_eq(optional_catwalk.size(), 2, "The reserve-cell return gives the player two short optional jumps")
	if optional_catwalk.size() == 2:
		assert_eq(int(optional_catwalk[0].get("start_x", -1)), 254)
		assert_eq(int(optional_catwalk[0].get("end_x", -1)), 263)
		assert_eq(int(optional_catwalk[0].get("height", -1)), 16)
		assert_eq(int(optional_catwalk[1].get("start_x", -1)), 268)
		assert_eq(int(optional_catwalk[1].get("end_x", -1)), 277)
		assert_eq(int(optional_catwalk[1].get("height", -1)), 16)


func test_level_02_publishes_spawn_and_goal_markers() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()

	assert_eq(world.get_spawn_position(), Vector2(160.0, 321.0), "Spawn sits just above the factory breach ledge")
	assert_true(world.has_goal(), "Level 2 declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(12512.0, 544.0), "Goal sits at the end of the exit deck")

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
	# Start on the final charged landing deck: the 160 px approach before this
	# pickup crosses a gap and is intentionally not a walkable starting point.
	player.global_position = cradle.global_position + Vector2(-96.0, 0.0)

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
	assert_true(cradle.acquisition_readout.text.contains("cradle is empty"), "The emptied cradle keeps its completed state")


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
	assert_not_null(game.route_exit, "Level 2 should end at the dimensional portal")
	assert_true(game.route_exit is RunUnitDimensionalPortalExit)
	assert_eq(game.route_exit.next_scene_path, "res://scenes/game.tscn")
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


func test_completing_level_2_starts_the_portal_handoff() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	(game.world.get_node("ModuleCradle") as RunUnitModuleCradle).acquire_for(game.player)

	game.world.route_completed.emit()

	assert_true(game.is_terminal())
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_false(game.death_menu.visible, "Portal completion should stay in-world instead of opening the results menu")
	assert_not_null(game.route_exit)
	if game.route_exit != null:
		assert_true(game.route_exit.transition_started, "Completing Recovery should activate the portal")
		assert_eq(game.route_exit.next_scene_path, "res://scenes/game.tscn")

func test_module_is_acquired_in_the_target_progress_band_and_leads_to_a_short_exit() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var cradle: RunUnitModuleCradle = world.get_node("ModuleCradle") as RunUnitModuleCradle
	var spawn_x: float = world.get_spawn_position().x
	var goal_x: float = world.get_goal_position().x
	var pickup_progress: float = (cradle.global_position.x - spawn_x) / (goal_x - spawn_x)
	assert_gte(pickup_progress, 0.60, "Acquisition should happen after the first half of the route")
	assert_lte(pickup_progress, 0.65, "Acquisition should leave a distinct escape section")
	assert_lte(goal_x - cradle.global_position.x, 4800.0, "The post-pickup escape stays under 150 metres and has no further jump chain")


func test_module_playtest_telemetry_reports_route_progress_and_escape_distance_in_pixels() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	var cradle: RunUnitModuleCradle = game.world.get_node("ModuleCradle") as RunUnitModuleCradle
	var metrics: Dictionary = game._module_acquisition_metrics(cradle.global_position.x)
	var route_progress: float = float(metrics.get("route_progress", -1.0))
	assert_gte(route_progress, 0.60, "The telemetry should place acquisition inside the 60–65% acceptance band")
	assert_lte(route_progress, 0.65, "The telemetry should report the authored pickup progress, not clamp it to 100%")
	assert_eq(float(metrics.get("post_pickup_distance", -1.0)), game.world.get_goal_position().x - cradle.global_position.x, "Escape distance is measured in world pixels")
	get_tree().paused = false


func test_pickup_changes_the_objective_and_keeps_the_existing_world_shutdown_reaction() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	var cradle: RunUnitModuleCradle = game.world.get_node("ModuleCradle") as RunUnitModuleCradle
	var shutdown_lighting: CanvasItem = game.world.get_node("ShutdownLighting") as CanvasItem
	var lockdown_sign: CanvasItem = game.world.get_node("RecoverySigns/LockdownSign") as CanvasItem
	var acquisition_readout: Label = cradle.get_node("AcquisitionReadout") as Label
	assert_false(shutdown_lighting.visible)
	assert_false(lockdown_sign.visible)
	cradle.acquire_for(game.player)
	var objective_label: Label = game.hud.get_node_or_null("ObjectiveFrame/ObjectiveLabel") as Label
	assert_not_null(objective_label)
	if objective_label != null:
		assert_eq(objective_label.text, "Beacon 9 needs its reserve cell.")
	assert_true(acquisition_readout.visible, "The emptied cradle keeps a visible completed state")
	assert_true(acquisition_readout.text.contains("cradle is empty"))
	assert_true(shutdown_lighting.visible, "Removing the module keeps the lighting response")
	assert_true(lockdown_sign.visible, "Removing the module keeps the lockdown signage response")
	get_tree().paused = false


func test_story_zones_emit_one_reusable_non_repeating_runtime_beat() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var director: Node = world.get_node_or_null("StoryZoneDirector")
	assert_not_null(director, "Authored story zones should be bound by the reusable world-side director")
	if director == null:
		return
	var zone: Area2D = _find_area_named(world, "ModuleAcquisition")
	assert_not_null(zone)
	if zone == null:
		return
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var count: Array[int] = [0]
	var beat_names: Array[String] = []
	var messages: Array[String] = []
	director.connect("story_beat", func(zone_name: String, cue: Dictionary) -> void:
		count[0] += 1
		beat_names.append(zone_name)
		messages.append(String(cue.get("message", "")))
	)
	zone.body_entered.emit(player)
	zone.body_entered.emit(player)
	world.reset()
	zone.body_entered.emit(player)
	assert_eq(count[0], 1, "Re-entry and checkpoint retry must not replay the same beat")
	assert_eq(beat_names, ["ModuleAcquisition"], "YATI's imported object name resolves back to its authored zone")
	assert_eq(messages, ["IGNITION ASSEMBLY // COMPATIBLE"], "The machine identifies the matching assembly")


func _find_area_named(root_node: Node, wanted_name: String) -> Area2D:
	var nodes_to_visit: Array[Node] = [root_node]
	while not nodes_to_visit.is_empty():
		var node: Node = nodes_to_visit.pop_back()
		nodes_to_visit.append_array(node.get_children())
		if String(node.name).trim_suffix(" (Area)") == wanted_name and node is Area2D:
			return node as Area2D
	return null


	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	(game.world.get_node("ModuleCradle") as RunUnitModuleCradle).acquire_for(game.player)

	game.world.route_completed.emit()

	assert_true(game.is_terminal())
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_false(game.death_menu.visible, "Portal completion should stay in-world instead of opening the results menu")
	assert_not_null(game.route_exit)
	if game.route_exit != null:
		assert_true(game.route_exit.transition_started, "Completing Recovery should activate the portal")
		assert_eq(game.route_exit.next_scene_path, "res://scenes/game.tscn")


func test_recovery_exit_without_module_does_not_certify_objective() -> void:
	var game: RunUnitGame = _instantiate_game_for(LEVEL_2_INDEX)
	game.world.route_completed.emit()
	assert_eq(RunUnitSession.last_run_outcome, "incomplete")
	assert_false(RunUnitSession.recovery_complete)
	assert_false(RunUnitSession.is_route_unlocked(3))
	assert_true(game.death_menu.description_label.text.contains("IGNITION ASSEMBLY MISSING"))

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


func test_depot_return_breaks_the_flat_run_with_staggered_safe_timing_hazards() -> void:
	var world: RunUnitStaticWorld = _instantiate_level()
	var return_arc: RunUnitTimedHazard = world.get_node_or_null("TimingHazards/ReserveReturnArc") as RunUnitTimedHazard
	var return_press: RunUnitTimedHazard = world.get_node_or_null("MechanicalHazards/ReserveReturnPress") as RunUnitTimedHazard
	assert_not_null(return_arc, "The return path introduces an electrical timing beat after the manual release")
	assert_not_null(return_press, "The final return stretch asks the player to time the depot ram")
	if return_arc != null and return_press != null:
		assert_eq(return_arc.position, Vector2(9728, 640))
		assert_eq(return_press.position, Vector2(10880, 599))
		assert_false(return_arc.lethal)
		assert_false(return_press.lethal)

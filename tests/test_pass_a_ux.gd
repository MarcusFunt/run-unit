extends GutTest

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const FACTORY_INDEX: int = 1

func before_each() -> void:
	RunUnitSession.clear_checkpoint()
	RunUnitSession.selected_level_index = FACTORY_INDEX

func after_each() -> void:
	RunUnitSession.clear_checkpoint()
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	get_tree().paused = false

func _game() -> RunUnitGame:
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause: Node = game.get_node_or_null("PauseMenuController")
	if pause != null:
		pause.free()
	add_child_autofree(game)
	return game

func test_checkpoint_needs_contact_and_is_visible_after_retry() -> void:
	var game: RunUnitGame = _game()
	var stations: Node = game.world.get_node_or_null("CheckpointStations")
	assert_not_null(stations)
	if stations == null or stations.get_child_count() == 0:
		return
	var station: RunUnitCheckpointStation = stations.get_child(0) as RunUnitCheckpointStation
	assert_false(RunUnitSession.has_checkpoint(FACTORY_INDEX))
	assert_false(station.is_active)
	game.player.global_position = station.checkpoint_position + Vector2(0, -250)
	await get_tree().physics_frame
	assert_false(RunUnitSession.has_checkpoint(FACTORY_INDEX), "Passing above a station cannot activate it")
	game.player.global_position = station.checkpoint_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(RunUnitSession.has_checkpoint(FACTORY_INDEX), "Touching a station registers the checkpoint")
	assert_eq(RunUnitSession.get_resume_position(FACTORY_INDEX, Vector2.ZERO), station.checkpoint_position)
	assert_true(station.is_active)
	game.reset_run(0)
	assert_true(station.is_active, "The node remains visibly online after retry")
	assert_eq(game.player.global_position, station.checkpoint_position)

func test_health_cells_keep_their_outline_when_depleted() -> void:
	var hud: RunUnitHud = HUD_SCENE.instantiate() as RunUnitHud
	add_child_autofree(hud)
	assert_not_null(hud.get_node_or_null("HealthFrame"))
	var last: ColorRect = hud.get_node("HealthDisplay/HealthCell3") as ColorRect
	hud.set_health(3, 3)
	var lit: Color = last.color
	hud.set_health(2, 3)
	assert_true(last.visible, "A depleted cell should remain visible as an empty socket")
	assert_lt(last.color.get_luminance(), lit.get_luminance())
	assert_gt(hud.get_node("HealthFrame").size.x, 80.0)

func test_camera_holds_steady_on_ascent_and_previews_the_drop() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var camera: RunUnitFollowCamera = player.get_node("Camera2D") as RunUnitFollowCamera
	assert_not_null(camera)
	if camera == null:
		return
	var resting: Vector2 = camera.position
	assert_almost_eq(resting.y, -72.0, 0.01, "Resting view leaves more space below the player")
	player.velocity = Vector2(285, -650)
	for frame: int in range(120):
		camera.update_lookahead(0.016)
	assert_almost_eq(camera.position.y, resting.y, 0.1, "Rising should not pull the view upward")
	assert_lt(absf(camera.position.x - resting.x), 30.0, "Running changes the horizontal frame only slightly")
	player.velocity.y = 800
	camera.update_lookahead(0.016)
	assert_gt(camera.position.y, resting.y, "Falling shows terrain below")
	assert_lt(camera.position.y - resting.y, 10.0, "The first falling frame should ease in")
	for frame: int in range(120):
		camera.update_lookahead(0.016)
	assert_gt(camera.position.y - resting.y, 75.0, "A sustained drop reveals the landing area")
	assert_lt(camera.position.y - resting.y, 95.0, "The fall preview remains bounded")
	var forward_x: float = camera.position.x
	player.velocity.x = -285
	camera.update_lookahead(0.016)
	assert_lt(absf(camera.position.x - forward_x), 10.0, "Reversing does not snap the frame")
	for frame: int in range(120):
		camera.update_lookahead(0.016)
	assert_lt(camera.position.x, resting.x, "Reversing still gives a little leftward preview")
	assert_lt(absf(camera.position.x - resting.x), 30.0, "Leftward movement cannot swing the view across the screen")
	player.velocity = Vector2.ZERO
	camera.update_lookahead(0.016)
	assert_gt(camera.position.y, resting.y + 10.0, "Landing eases the view back")
	for frame: int in range(120):
		camera.update_lookahead(0.016)
	assert_almost_eq(camera.position.y, resting.y, 0.1, "The resting frame returns after landing")

func test_charge_has_low_medium_and_locked_full_visual_states() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	player._is_charging = true
	player.charge_ratio = 0.18
	visual.run_process_for_test(0.016)
	assert_eq(visual.get_charge_stage(), 1)
	player.charge_ratio = 0.58
	visual.run_process_for_test(0.016)
	assert_eq(visual.get_charge_stage(), 2)
	player.charge_ratio = 1.0
	visual.run_process_for_test(0.016)
	assert_eq(visual.get_charge_stage(), 3)
	assert_true((visual.get_node("BodyPivot/ChargeCore") as CanvasItem).visible)
	assert_true((visual.get_node("BodyPivot/ChargeLock") as CanvasItem).visible)

func test_every_route_marks_real_walkable_edges_only() -> void:
	for path: String in ["res://scenes/world.tscn", "res://scenes/levels/level_01_factory.tscn", "res://scenes/levels/level_02_recovery.tscn", "res://scenes/levels/level_03_beacon.tscn"]:
		var world: RunUnitStaticWorld = (load(path) as PackedScene).instantiate() as RunUnitStaticWorld
		add_child_autofree(world)
		var edges: RunUnitWalkableEdges = world.get_node_or_null("WalkableEdges") as RunUnitWalkableEdges
		assert_not_null(edges, "%s needs the same walkable top-edge language" % path)
		if edges != null:
			assert_eq(edges.get_edge_count(), world.get_current_plan().size())

func test_module_cradle_identifies_the_ignition_assembly() -> void:
	var world: RunUnitStaticWorld = (load("res://scenes/levels/level_02_recovery.tscn") as PackedScene).instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var cradle: RunUnitModuleCradle = world.get_node("ModuleCradle") as RunUnitModuleCradle
	assert_true((cradle.get_node("ModuleName") as Label).text.contains("IGNITION"))
	assert_true((cradle.get_node("ObjectiveHalo") as CanvasItem).visible)
	assert_gt((cradle.cradle_module as CanvasItem).modulate.r, (cradle.cradle_module as CanvasItem).modulate.b, "Warm module lighting is distinct from cyan hazards")

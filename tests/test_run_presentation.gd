extends GutTest

## Covers the two presentation seams that only misbehave once the game is
## actually running: the paused results screen, and world-emitted sparks.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const DEATH_MENU_SCENE: PackedScene = preload("res://scenes/death_menu.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const ELECTRIC_ARC_SCENE: PackedScene = preload("res://scenes/hazards/electric_floor_arc.tscn")
const RECOVERY_SCENE: PackedScene = preload("res://scenes/levels/level_02_recovery.tscn")


func after_each() -> void:
	get_tree().paused = false
	RunUnitSession.debug_unlock_routes = false
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	RunUnitSession.clear_checkpoint()


func test_results_menu_keeps_processing_while_the_tree_is_paused() -> void:
	var menu: RunUnitDeathMenu = DEATH_MENU_SCENE.instantiate() as RunUnitDeathMenu
	add_child_autofree(menu)

	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS, "The results screen pauses the tree, so it has to keep reading input itself")
	assert_true(menu.has_method("_unhandled_key_input"), "The documented R restart shortcut must be readable while paused")


func test_results_menu_releases_the_pause_it_took() -> void:
	var menu: RunUnitDeathMenu = DEATH_MENU_SCENE.instantiate() as RunUnitDeathMenu
	add_child_autofree(menu)

	menu.open_with_scores(12.0, 20.0)
	assert_true(get_tree().paused, "Opening the results screen should pause the run")

	menu.close()

	assert_false(menu.visible)
	assert_false(get_tree().paused, "Closing the results screen must hand the run back")


func test_results_menu_leaves_a_pause_it_did_not_take() -> void:
	var menu: RunUnitDeathMenu = DEATH_MENU_SCENE.instantiate() as RunUnitDeathMenu
	add_child_autofree(menu)
	get_tree().paused = true

	menu.open_with_scores(12.0, 20.0)
	menu.close()

	assert_true(get_tree().paused, "A pause owned by the pause menu must survive the results screen closing")
	get_tree().paused = false


func test_failure_and_completion_results_have_distinct_visual_language() -> void:
	var menu: RunUnitDeathMenu = DEATH_MENU_SCENE.instantiate() as RunUnitDeathMenu
	add_child_autofree(menu)

	menu.open_with_scores(12.0, 20.0)
	var failure_glyph: String = menu.outcome_glyph.text
	var failure_eyebrow: String = menu.outcome_eyebrow.text
	var failure_accent: Color = menu.accent_bar.color
	var failure_dimmer: Color = menu.dimmer.color
	menu.close()

	menu.open_completed_with_scores(20.0, 20.0)
	assert_ne(menu.outcome_glyph.text, failure_glyph, "Success must never reuse the death symbol")
	assert_ne(menu.outcome_eyebrow.text, failure_eyebrow, "Success and death need different status language")
	assert_ne(menu.accent_bar.color, failure_accent, "Success and death need different accent colours")
	assert_ne(menu.dimmer.color, failure_dimmer, "The full-screen treatment must read differently before the player reads a word")
	assert_eq(menu.outcome_glyph.text, "ACTIVE")
	assert_eq(menu.outcome_eyebrow.text, "UNIT-07 // OPERATIONAL")
	assert_eq(menu.title_label.text, "SECTOR LOGGED")

	menu.close()


func test_feedback_effects_stay_in_world_space() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(1000.0, 200.0)
	var feedback: RunUnitPlayerFeedback = player.get_node("Feedback") as RunUnitPlayerFeedback

	assert_true(feedback.top_level, "The feedback layer must not inherit the player's transform")

	feedback.play_game_over_feedback()
	var effect: CPUParticles2D = null
	for child: Node in feedback.get_children():
		if child is CPUParticles2D:
			effect = child as CPUParticles2D
			break
	assert_not_null(effect, "The game-over feedback should spawn a world-space particle effect")
	if effect == null:
		return

	var first_position: Vector2 = effect.global_position
	assert_almost_eq(first_position.x, 1000.0, 20.0, "The effect starts at the robot's world position")

	player.global_position = Vector2(2000.0, 200.0)
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_instance_valid(effect):
		return
	assert_lt(absf(effect.global_position.x - first_position.x), 1.0, "The effect stays where it was emitted instead of travelling with the robot")

func test_failed_retry_reuses_game_and_restores_checkpoint() -> void:
	var route_index: int = 3
	var checkpoint: Vector2 = Vector2(10000.0, 544.0)
	var game: RunUnitGame = await _spawn_game_for_test(route_index)
	RunUnitSession.record_checkpoint(route_index, checkpoint)
	var game_id: int = game.get_instance_id()

	game._fail_run()
	assert_true(get_tree().paused)
	game.death_menu.restart_button.emit_signal("pressed")
	var respawn_position: Vector2 = game.player.global_position
	await get_tree().process_frame

	assert_true(is_instance_valid(game), "Retry should keep the active game instance alive")
	if not is_instance_valid(game):
		return
	assert_eq(game.get_instance_id(), game_id)
	assert_false(get_tree().paused)
	assert_false(game.is_terminal())
	assert_eq(respawn_position, checkpoint)
	assert_eq(game.player_health.current_health, game.player_health.max_health)


func test_completed_retry_redeploys_at_spawn_after_checkpoint_clear() -> void:
	var route_index: int = 1
	var checkpoint: Vector2 = Vector2(8000.0, 544.0)
	var game: RunUnitGame = await _spawn_game_for_test(route_index)
	game.route_exit = null
	RunUnitSession.record_checkpoint(route_index, checkpoint)
	var game_id: int = game.get_instance_id()
	var spawn_position: Vector2 = game.world.get_spawn_position()

	game._complete_run()
	assert_true(game.death_menu.visible)
	assert_false(RunUnitSession.has_checkpoint(route_index))
	game.death_menu.restart_button.emit_signal("pressed")
	var respawn_position: Vector2 = game.player.global_position
	await get_tree().process_frame

	assert_true(is_instance_valid(game), "Redeploy should keep the active game instance alive")
	if not is_instance_valid(game):
		return
	assert_eq(game.get_instance_id(), game_id)
	assert_false(get_tree().paused)
	assert_false(game.is_terminal())
	assert_eq(respawn_position, spawn_position)


func _spawn_game_for_test(route_index: int) -> RunUnitGame:
	RunUnitSession.debug_unlock_routes = true
	RunUnitSession.selected_level_index = route_index
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	await get_tree().process_frame
	return game

func test_ambient_pulse_changes_only_alpha_and_resets_to_authored_phase() -> void:
	var pulse_path: String = "res://scripts/world/ambient_pulse.gd"
	if not ResourceLoader.exists(pulse_path):
		assert_true(false, "The reusable ambient pulse script should be available")
		return
	var authored_color: Color = Color(0.9, 0.5, 0.2, 0.8)
	var light: Polygon2D = Polygon2D.new()
	light.modulate = authored_color
	var pulse_script: Script = load(pulse_path) as Script
	assert_not_null(pulse_script, "The reusable ambient pulse script should be available")
	if pulse_script == null:
		return
	light.set_script(pulse_script)
	light.set("period_seconds", 0.10)
	light.set("dim_factor", 0.2)
	add_child_autofree(light)
	var authored_phase_alpha: float = light.modulate.a

	await get_tree().create_timer(0.035).timeout

	assert_ne(light.modulate.a, authored_phase_alpha, "The pulse should visibly change opacity")
	assert_almost_eq(light.modulate.r, authored_color.r, 0.001)
	assert_almost_eq(light.modulate.g, authored_color.g, 0.001)
	assert_almost_eq(light.modulate.b, authored_color.b, 0.001)
	light.call("reset_level_state")
	assert_almost_eq(light.modulate.a, authored_phase_alpha, 0.001, "Reset should restore the authored pulse phase")


func test_electric_floor_arc_pulse_art_is_resettable_and_non_colliding() -> void:
	var hazard: Node = ELECTRIC_ARC_SCENE.instantiate()
	add_child_autofree(hazard)
	var warning_stripe: Node = hazard.get_node_or_null("WarningStripe")
	var glow: Node = hazard.get_node_or_null("ActiveVisual/Glow")

	assert_not_null(warning_stripe)
	assert_not_null(glow)
	if warning_stripe == null or glow == null:
		return
	assert_true(warning_stripe.has_method("reset_level_state"))
	assert_true(glow.has_method("reset_level_state"))
	assert_false(warning_stripe is CollisionObject2D)
	assert_false(glow is CollisionObject2D)


func test_recovery_monitor_pulse_resets_with_the_world() -> void:
	var recovery: RunUnitStaticWorld = RECOVERY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(recovery)
	var status: CanvasItem = recovery.get_node_or_null("AssemblyMonitor/Status") as CanvasItem
	assert_not_null(status)
	if status == null:
		return
	assert_true(status.has_method("reset_level_state"))
	assert_false(status is CollisionObject2D)
	var authored_phase_alpha: float = status.modulate.a
	status.modulate = Color(status.modulate.r, status.modulate.g, status.modulate.b, 0.1)

	recovery.reset()

	assert_almost_eq(status.modulate.a, authored_phase_alpha, 0.001, "World reset should restore the monitor pulse to its authored phase")

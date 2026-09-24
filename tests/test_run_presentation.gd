extends GutTest

## Covers the two presentation seams that only misbehave once the game is
## actually running: the paused results screen, and world-emitted sparks.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const DEATH_MENU_SCENE: PackedScene = preload("res://scenes/death_menu.tscn")


func after_each() -> void:
	get_tree().paused = false


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
	assert_eq(menu.outcome_glyph.text, "CLEAR")
	assert_eq(menu.outcome_eyebrow.text, "MISSION SUCCESS")
	assert_eq(menu.title_label.text, "ROUTE COMPLETE")

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

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


func test_sparks_are_emitted_into_the_world_not_carried_by_the_robot() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(1000.0, 200.0)
	var feedback: RunUnitPlayerFeedback = player.get_node("Feedback") as RunUnitPlayerFeedback

	assert_true(feedback.top_level, "The spark layer must not inherit the player's transform")

	feedback.play_game_over_feedback()
	var spawned: Array = feedback.get("_particles")
	assert_gt(spawned.size(), 0, "The game-over burst should have spawned sparks")
	var first_position: Vector2 = (spawned[0] as Dictionary)["position"] as Vector2
	assert_almost_eq(first_position.x, 1000.0, 20.0, "Sparks spawn at the robot's world position")

	player.global_position = Vector2(2000.0, 200.0)
	await get_tree().process_frame
	await get_tree().process_frame

	var moved: Array = feedback.get("_particles")
	if moved.is_empty():
		return
	var later_position: Vector2 = (moved[0] as Dictionary)["position"] as Vector2
	assert_lt(absf(later_position.x - first_position.x), 100.0, "Sparks must stay where they were emitted instead of travelling with the robot")

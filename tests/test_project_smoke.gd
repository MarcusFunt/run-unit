extends GutTest

func test_main_menu_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/main_menu.tscn") as PackedScene
	assert_not_null(scene, "Main menu scene should load")

func test_level_selector_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/level_selector.tscn") as PackedScene
	assert_not_null(scene, "Level selector scene should load")

func test_game_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/game.tscn") as PackedScene
	assert_not_null(scene, "Game scene should load")

func test_run_session_starts_at_first_sector() -> void:
	assert_eq(RunUnitSession.selected_level_index, 0, "A new run should start at sector 01")

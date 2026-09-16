extends GutTest

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LEVEL_SELECTOR_SCENE: PackedScene = preload("res://scenes/level_selector.tscn")
const OPTIONS_SCENE: PackedScene = preload("res://menus/scenes/menus/options_menu/master_options_menu_with_tabs.tscn")

func test_level_selector_marks_only_the_authored_route_playable() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	assert_not_null(selector, "The route selector should instantiate")
	add_child_autofree(selector)
	var sector_grid: GridContainer = selector.get_node_or_null("Margin/Layout/Body/SectorPanel/SectorMargin/SectorLayout/SectorGrid") as GridContainer
	assert_not_null(sector_grid, "The route grid should be present")
	var sector_buttons: Array[Button] = []
	for child: Node in sector_grid.get_children():
		var sector_button: Button = child as Button
		if sector_button != null:
			sector_buttons.append(sector_button)
	assert_eq(sector_buttons.size(), 8, "The selector should show the available route and future route slots")
	assert_false(sector_buttons[0].disabled, "The authored route should be playable")
	for index: int in range(1, sector_buttons.size()):
		assert_true(sector_buttons[index].disabled, "Future route %d should be clearly unavailable" % (index + 1))
	var hint: Label = selector.get_node_or_null("Margin/Layout/Footer/Hint") as Label
	assert_eq(hint.text, "ARROWS SELECT   ENTER / SPACE DEPLOY   ESC BACK")
	assert_true(selector.selected_sector.text.contains("FINAL INSPECTION"), "The playable route should use the current factory narrative")
	assert_true(selector.description.text.contains("stalled transfer line"), "Route briefing should explain the broken factory transfer")
	assert_false(selector.description.text.contains("Solar Ignition Core"), "Retired Last Light Protocol copy must not return")

func test_player_options_list_only_live_gameplay_actions() -> void:
	var options: TabContainer = autofree(OPTIONS_SCENE.instantiate()) as TabContainer
	assert_not_null(options, "The options menu should instantiate")
	var input_list: Control = options.get_node_or_null("Controls/VBoxContainer/InputMappingContainer/InputActionsList") as Control
	assert_not_null(input_list, "The player control list should be present")
	assert_false(bool(input_list.get("show_all_actions")), "Developer actions must not leak into player settings")
	var action_names: Array = input_list.get("input_action_names") as Array
	assert_eq(action_names, [&"move_left", &"move_right", &"jump", &"crouch", &"restart"])

func test_game_scene_has_one_pre_run_flow() -> void:
	var game: Node = autofree(GAME_SCENE.instantiate()) as Node
	assert_not_null(game, "The game scene should instantiate")
	assert_null(game.get_node_or_null("TitleScreen"), "The retired duplicate route briefing must not be loaded into gameplay")

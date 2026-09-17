extends GutTest

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LEVEL_SELECTOR_SCENE: PackedScene = preload("res://scenes/level_selector.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const OPTIONS_SCENE: PackedScene = preload("res://menus/scenes/menus/options_menu/master_options_menu_with_tabs.tscn")

func test_main_menu_has_drifting_city_parallax_background() -> void:
	var menu: Node = autofree(MAIN_MENU_SCENE.instantiate()) as Node
	assert_not_null(menu, "The main menu should instantiate")
	var background: Node = menu.get_node_or_null("MenuBackground")
	assert_not_null(background, "The menu should mount the generated city parallax background")
	if background != null:
		assert_true(background.has_method("_process"), "The menu background should drive continuous drift")
		assert_gt(float(background.get("drift_pixels_per_second")), 0.0, "The city should drift automatically")

func test_main_menu_uses_refined_thin_terminal_buttons() -> void:
	var menu: Node = autofree(MAIN_MENU_SCENE.instantiate()) as Node
	assert_not_null(menu, "The main menu should instantiate")
	add_child_autofree(menu)
	var button_path := "MenuContainer/MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer/NewGameButton"
	var button: Button = menu.get_node_or_null(button_path) as Button
	assert_not_null(button, "The primary menu button should exist")
	if button == null:
		return
	var normal_style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	var focus_style: StyleBoxFlat = button.get_theme_stylebox("focus") as StyleBoxFlat
	assert_not_null(normal_style, "Thin Terminal should use a programmatic StyleBoxFlat")
	assert_not_null(focus_style, "Thin Terminal should expose an amber focus rail")
	if normal_style != null:
		assert_eq(normal_style.border_width_left, 1, "Idle Thin Terminal border should stay visually light")
		assert_true(normal_style.bg_color.a < 0.70, "Idle button should preserve the glass/translucent treatment")
		assert_true(normal_style.border_color.b > normal_style.border_color.r, "Idle border should remain cyan/blue")
	if focus_style != null:
		assert_eq(focus_style.border_width_left, 3, "Controller focus should use a narrow left-side status rail")
		assert_eq(focus_style.border_width_top, 0, "Focus should not draw a full amber box")
		assert_true(focus_style.border_color.r > focus_style.border_color.b, "Focus rail should be amber")
	assert_eq(button.custom_minimum_size, Vector2(280.0, 50.0), "Thin Terminal buttons should be lower and slightly wider")
	var box: BoxContainer = menu.get_node("MenuContainer/MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer") as BoxContainer
	assert_eq(box.get_theme_constant("separation"), 10, "Terminal controls should use tighter vertical spacing")
	assert_almost_eq(box.anchor_left, 0.45, 0.001, "Thin Terminal controls should sit slightly left of screen center")
	assert_almost_eq(box.anchor_right, 0.45, 0.001, "Thin Terminal controls should preserve their width while shifted left")

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
	assert_true(selector.description.text.contains("mobility, spring, and clearance"), "Route briefing should describe the calibration checks actually in the tutorial")
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

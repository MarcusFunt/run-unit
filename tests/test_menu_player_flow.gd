extends GutTest

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const LEVEL_SELECTOR_SCENE: PackedScene = preload("res://scenes/level_selector.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const OPTIONS_SCENE: PackedScene = preload("res://menus/scenes/menus/options_menu/master_options_menu_with_tabs.tscn")

## The selector opens on RunUnitSession.selected_level_index, so each test
## starts from the tutorial unless it says otherwise.
func before_each() -> void:
	RunUnitSession.save_path = "user://gut_selector_campaign.cfg"
	RunUnitSession.reset_campaign()
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX

func after_each() -> void:
	RunUnitSession.save_path = "user://run_unit_campaign.cfg"
	RunUnitSession.load_campaign()
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX

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
	assert_almost_eq(box.anchor_left, 0.5, 0.001, "Thin Terminal controls should be centered on screen")
	assert_almost_eq(box.anchor_right, 0.5, 0.001, "Thin Terminal controls should preserve their width while centered")

func test_main_menu_scrims_stretch_across_the_full_screen_width() -> void:
	var menu: Node = autofree(MAIN_MENU_SCENE.instantiate()) as Node
	assert_not_null(menu, "The main menu should instantiate")
	add_child_autofree(menu)
	var header_scrim: TextureRect = menu.get_node_or_null("HeaderScrim") as TextureRect
	var bottom_scrim: TextureRect = menu.get_node_or_null("BottomScrim") as TextureRect
	assert_not_null(header_scrim, "The header readability scrim should exist")
	assert_not_null(bottom_scrim, "The footer readability scrim should exist")
	if header_scrim != null:
		assert_eq(header_scrim.stretch_mode, TextureRect.STRETCH_SCALE, "The header scrim must scale to fill its box, not keep the square gradient texture's aspect ratio")
	if bottom_scrim != null:
		assert_eq(bottom_scrim.stretch_mode, TextureRect.STRETCH_SCALE, "The footer scrim must scale to fill its box, not keep the square gradient texture's aspect ratio")

func test_level_selector_lists_the_storyline_campaign_routes() -> void:
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
	assert_eq(sector_buttons.size(), 4, "The selector should list the four campaign routes from StorylineSketch.md")
	var expected_names: Array[String] = ["TUTORIAL ROUTE", "FACTORY ESCAPE", "RECOVERY", "BEACON 9"]
	for index: int in sector_buttons.size():
		assert_true(sector_buttons[index].text.contains(expected_names[index]), "Route %d should be %s in campaign order" % [index, expected_names[index]])
	assert_false(sector_buttons[0].disabled, "Calibration is authored and playable")
	for index: int in range(1, sector_buttons.size()):
		assert_false(sector_buttons[index].disabled, "Locked routes stay inspectable")
		assert_true(sector_buttons[index].text.contains("LOCKED"), "A fresh campaign locks later routes")
	var hint: Label = selector.get_node_or_null("Margin/Layout/Footer/Hint") as Label
	assert_eq(hint.text, "CLICK / ARROWS SELECT   ENTER / SPACE DEPLOY   ESC BACK")

func test_level_selector_hides_the_stale_dev_status_chrome() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	assert_null(selector.get_node_or_null("Margin/Layout/Header/TitleBlock/Subtitle"), "The 'CAMPAIGN ROUTE SELECTOR // UNIT-07' subtitle should be removed")
	assert_null(selector.get_node_or_null("Margin/Layout/Body/SectorPanel/SectorMargin/SectorLayout/Heading"), "The 'ROUTE DEPLOYMENT' heading should be removed")
	assert_null(selector.get_node_or_null("Margin/Layout/Body/SectorPanel/SectorMargin/SectorLayout/Caption"), "The stale 'still in development' caption should be removed")
	assert_null(selector.get_node_or_null("Margin/Layout/Body/BriefingPanel/BriefingMargin/Briefing/SeedLabel"), "The 'AUTHORED ROUTE // AVAILABLE' label should be removed")
	assert_null(selector.get_node_or_null("Margin/Layout/Body/BriefingPanel/BriefingMargin/Briefing/DifficultyLabel"), "The 'EST. RUNTIME' label should be removed")
	assert_null(selector.get_node_or_null("Margin/Layout/Body/BriefingPanel/BriefingMargin/Briefing/RouteStatus"), "The 'ROUTE ONLINE // READY TO DEPLOY' label should be removed")

func test_level_selector_briefs_the_calibration_tutorial() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	assert_true(selector.selected_sector.text.contains("TUTORIAL ROUTE"), "The selector should open on the Calibration tutorial")
	assert_false(selector.selected_sector.text.contains("FINAL INSPECTION"), "Retired Final Inspection route naming must not return")
	assert_true(selector.description.text.contains("calibration tunnel"), "Route summary should describe the calibration checks actually in the tutorial")
	assert_false(selector.description.text.contains("Solar Ignition Core"), "Retired Last Light Protocol copy must not return")

func test_level_selector_briefs_factory_escape() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)

	RunUnitSession.record_route_completion(0, 42.0)
	selector._on_sector_focused(1)

	assert_eq(RunUnitSession.selected_level_index, 1, "Focusing Factory Escape should select it for deployment")
	assert_eq(selector.selected_sector.text, "01  FACTORY ESCAPE")
	assert_true(selector.description.text.contains("breach"), "Factory Escape's briefing should describe Level 1")

	selector._on_sector_focused(3)
	assert_true(selector.selected_sector.text.contains("BEACON 9"), "Locked Beacon remains inspectable")
	assert_true(selector.deploy_button.disabled, "Beacon cannot deploy before Recovery and the module")
	assert_eq(RunUnitSession.selected_level_index, 1, "Locked route focus must not arm a deployment")

func test_level_selector_reopens_on_the_last_selected_route() -> void:
	RunUnitSession.record_route_completion(0, 42.0)
	RunUnitSession.selected_level_index = 1
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	assert_eq(selector.selected_sector.text, "01  FACTORY ESCAPE", "Returning from a run should land on the route that was just played")

func test_level_selector_previews_a_route_without_arming_it() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	selector._on_sector_hovered(3)
	assert_true(selector.selected_sector.text.contains("TUTORIAL ROUTE"), "Hovering alone should not change selection")
	selector._on_sector_unhovered()
	assert_true(selector.selected_sector.text.contains("TUTORIAL ROUTE"), "Leaving a route keeps the selected briefing")
	assert_eq(RunUnitSession.selected_level_index, RunUnitCampaign.PLAYABLE_INDEX, "Hovering must not arm a route for deployment")

func test_clicking_available_route_selects_without_clearing_the_checkpoint() -> void:
	RunUnitSession.record_route_completion(0, 42.0)
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	RunUnitSession.record_checkpoint(0, Vector2(512.0, 360.0))
	selector._on_sector_pressed(1)
	assert_eq(RunUnitSession.selected_level_index, 1)
	assert_true(selector.selected_sector.text.contains("FACTORY ESCAPE"))
	assert_true(selector.deploy_button.disabled == false)
	assert_true(RunUnitSession.has_checkpoint(0), "Click only selects; deployment clears the checkpoint")

func test_clicking_locked_route_selects_its_briefing_without_deploying() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	selector._on_sector_pressed(3)
	assert_true(selector.selected_sector.text.contains("BEACON 9"))
	assert_true(selector.description.text.contains("Recovery"), "Briefing explains the missing prerequisite")
	assert_true(selector.deploy_button.disabled)
	assert_eq(RunUnitSession.selected_level_index, 0)

func test_completed_route_is_labeled_and_remains_selectable() -> void:
	RunUnitSession.record_route_completion(0, 42.0)
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	var route_button: Button = selector.sector_grid.get_child(0) as Button
	assert_true(route_button.text.contains("COMPLETE"))
	assert_false(selector.deploy_button.disabled)
	selector._on_sector_focused(1)
	assert_false(selector.deploy_button.disabled)

func test_project_theme_focus_label_differs_from_hover_label() -> void:
	var selector: RunUnitLevelSelector = LEVEL_SELECTOR_SCENE.instantiate() as RunUnitLevelSelector
	add_child_autofree(selector)
	var sector_grid: GridContainer = selector.get_node_or_null("Margin/Layout/Body/SectorPanel/SectorMargin/SectorLayout/SectorGrid") as GridContainer
	assert_not_null(sector_grid, "The route grid should be present")
	var route_button: Button = sector_grid.get_child(0) as Button
	assert_not_null(route_button, "The route grid should contain a themed button")
	var focus_color: Color = route_button.get_theme_color("font_focus_color")
	var hover_color: Color = route_button.get_theme_color("font_hover_color")
	assert_ne(focus_color, hover_color, "Keyboard/controller focus must read differently from mouse hover")
	var project_theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom")) as Theme
	assert_not_null(project_theme, "The project-wide theme should load")
	assert_ne(project_theme.get_color("font_focus_color", "Button"), project_theme.get_color("font_hover_color", "Button"), "Project theme focus and hover labels must stay distinct for the pause menu and windows")

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

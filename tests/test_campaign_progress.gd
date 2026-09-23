extends GutTest

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const SAVE_PATH: String = "user://gut_campaign_progress.cfg"

func before_each() -> void:
	RunUnitSession.save_path = SAVE_PATH
	RunUnitSession.reset_campaign()
	RunUnitSession.demo_mode = false

func after_each() -> void:
	RunUnitSession.demo_mode = false
	RunUnitSession.debug_unlock_routes = false
	RunUnitSession.save_path = "user://run_unit_campaign.cfg"
	RunUnitSession.load_campaign()
	RunUnitSession.selected_level_index = 0
	RunUnitSession.clear_checkpoint()

func test_fresh_save_only_unlocks_calibration() -> void:
	assert_true(RunUnitSession.is_route_unlocked(0))
	for route_index: int in range(1, 4):
		assert_false(RunUnitSession.is_route_unlocked(route_index))
	assert_eq(RunUnitSession.highest_unlocked_route, 0)

func test_route_completion_unlocks_next_and_preserves_replays() -> void:
	assert_false(RunUnitSession.record_route_completion(1, 37.0))
	assert_true(RunUnitSession.record_route_completion(0, 41.0))
	assert_true(RunUnitSession.is_route_unlocked(1))
	assert_true(RunUnitSession.record_route_completion(1, 150.0))
	assert_true(RunUnitSession.is_route_unlocked(2))
	assert_true(RunUnitSession.record_route_completion(0, 38.0))
	assert_true(RunUnitSession.is_route_unlocked(2))
	assert_almost_eq(RunUnitSession.get_best_time(0), 38.0, 0.01)

func test_recovery_needs_its_module_before_beacon_unlocks() -> void:
	RunUnitSession.record_route_completion(0, 42.0)
	RunUnitSession.record_route_completion(1, 145.0)
	assert_false(RunUnitSession.record_route_completion(2, 160.0))
	assert_false(RunUnitSession.is_route_unlocked(3))
	RunUnitSession.record_module_acquired()
	assert_true(RunUnitSession.record_route_completion(2, 162.0))
	assert_true(RunUnitSession.is_route_unlocked(3))
	assert_true(RunUnitSession.record_route_completion(3, 180.0))
	assert_true(RunUnitSession.beacon_complete)

func test_progress_and_best_times_survive_reload() -> void:
	RunUnitSession.record_route_completion(0, 50.0)
	RunUnitSession.record_route_completion(1, 120.0)
	RunUnitSession.record_module_acquired()
	RunUnitSession.record_route_completion(2, 200.0)
	RunUnitSession.load_campaign()
	assert_true(RunUnitSession.calibration_complete)
	assert_true(RunUnitSession.factory_complete)
	assert_true(RunUnitSession.recovery_complete)
	assert_true(RunUnitSession.ignition_module_acquired)
	assert_eq(RunUnitSession.highest_unlocked_route, 3)
	assert_almost_eq(RunUnitSession.get_best_time(1), 120.0, 0.01)

func test_corrupt_and_inconsistent_save_cannot_unlock_beacon() -> void:
	var invalid: ConfigFile = ConfigFile.new()
	invalid.set_value("campaign", "version", "unknown")
	invalid.set_value("campaign", "calibration_complete", true)
	invalid.save(SAVE_PATH)
	RunUnitSession.load_campaign()
	assert_eq(RunUnitSession.highest_unlocked_route, 0)
	var forged: ConfigFile = ConfigFile.new()
	forged.set_value("campaign", "version", 1)
	forged.set_value("campaign", "highest_unlocked_route", 3)
	forged.set_value("campaign", "beacon_complete", true)
	forged.save(SAVE_PATH)
	RunUnitSession.load_campaign()
	assert_false(RunUnitSession.is_route_unlocked(3))
	assert_false(RunUnitSession.beacon_complete)

func test_demo_bypass_does_not_write_campaign_progress() -> void:
	RunUnitSession.demo_mode = true
	assert_true(RunUnitSession.is_route_unlocked(3))
	assert_false(RunUnitSession.record_route_completion(3, 50.0))
	RunUnitSession.demo_mode = false
	assert_false(RunUnitSession.is_route_unlocked(3))
	assert_false(RunUnitSession.beacon_complete)

func test_direct_game_scene_cannot_enter_locked_beacon() -> void:
	RunUnitSession.selected_level_index = 3
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	assert_eq(game.world.scene_file_path, "res://scenes/world.tscn")
	assert_eq(RunUnitSession.selected_level_index, 0)

func test_settings_bootstrap_is_registered() -> void:
	assert_eq(ProjectSettings.get_setting("autoload/PlayerSettings"), "*res://addons/maaacks_menus_template/base/nodes/config/start_up/start_up.tscn")

func test_debug_unlock_is_ephemeral() -> void:
	RunUnitSession.debug_unlock_routes = true
	assert_true(RunUnitSession.is_route_unlocked(3))
	RunUnitSession.record_module_acquired()
	assert_false(RunUnitSession.record_route_completion(3, 25.0))
	RunUnitSession.debug_unlock_routes = false
	RunUnitSession.load_campaign()
	assert_false(RunUnitSession.ignition_module_acquired)
	assert_false(RunUnitSession.is_route_unlocked(3))

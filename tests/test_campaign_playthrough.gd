extends GutTest

const SAVE_PATH: String = "user://gut_fresh_campaign_playthrough.cfg"


func before_each() -> void:
	RunUnitSession.save_path = SAVE_PATH
	RunUnitSession.demo_mode = false
	RunUnitSession.debug_unlock_routes = false
	RunUnitSession.reset_campaign()


func after_each() -> void:
	RunUnitSession.demo_mode = false
	RunUnitSession.debug_unlock_routes = false
	RunUnitSession.save_path = "user://run_unit_campaign.cfg"
	RunUnitSession.load_campaign()
	RunUnitSession.selected_level_index = 0
	RunUnitSession.clear_checkpoint()


func test_fresh_campaign_unlocks_each_handoff_and_persists_to_the_ending() -> void:
	assert_eq(RunUnitSession.highest_unlocked_route, 0)
	assert_true(RunUnitSession.is_route_unlocked(0))
	for route_index: int in range(1, RunUnitCampaign.route_count()):
		assert_false(RunUnitSession.is_route_unlocked(route_index))

	# Calibration -> Factory Escape.
	assert_true(RunUnitSession.record_route_completion(0, 60.0))
	RunUnitSession.load_campaign()
	assert_eq(RunUnitSession.highest_unlocked_route, 1)
	assert_true(RunUnitSession.is_route_unlocked(1))

	# Factory Escape -> Recovery.
	assert_true(RunUnitSession.record_route_completion(1, 300.0))
	RunUnitSession.load_campaign()
	assert_eq(RunUnitSession.highest_unlocked_route, 2)
	assert_true(RunUnitSession.is_route_unlocked(2))
	assert_false(RunUnitSession.is_route_unlocked(3), "Recovery and the module are still required")

	# Recovery cannot complete or unlock Beacon 9 until its module is acquired.
	assert_false(RunUnitSession.record_route_completion(2, 420.0))
	assert_false(RunUnitSession.is_route_unlocked(3))
	RunUnitSession.record_module_acquired()
	RunUnitSession.load_campaign()
	assert_true(RunUnitSession.ignition_module_acquired)
	assert_true(RunUnitSession.record_route_completion(2, 420.0))
	RunUnitSession.load_campaign()
	assert_eq(RunUnitSession.highest_unlocked_route, 3)
	assert_true(RunUnitSession.is_route_unlocked(3))

	# Beacon 9 completion remains saved after the campaign-ending handoff.
	assert_true(ResourceLoader.exists("res://scenes/ending.tscn"))
	assert_true(RunUnitSession.record_route_completion(3, 480.0))
	RunUnitSession.load_campaign()
	assert_true(RunUnitSession.beacon_complete)
	assert_true(RunUnitSession.is_route_completed(3))

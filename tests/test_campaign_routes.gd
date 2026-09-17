extends GutTest

const STORYLINE_PATH: String = "res://StorylineSketch.md"
const RETIRED_COPY: Array[String] = ["Solar Ignition Core", "Beacon 9 delivery contract", "FINAL INSPECTION", "MAINTENANCE SHAFT"]

func _read_storyline() -> String:
	var file: FileAccess = FileAccess.open(STORYLINE_PATH, FileAccess.READ)
	assert_not_null(file, "StorylineSketch.md should ship with the project")
	if file == null:
		return ""
	return file.get_as_text()

func test_campaign_follows_the_storyline_order() -> void:
	var expected_names: Array[String] = ["CALIBRATION", "FACTORY ESCAPE", "RECOVERY", "BEACON 9"]
	assert_eq(RunUnitCampaign.route_count(), expected_names.size(), "The campaign is Calibration -> Factory Escape -> Recovery -> Beacon 9")
	for index: int in expected_names.size():
		assert_eq(RunUnitCampaign.get_route_name(index), expected_names[index], "Route %d should be %s" % [index, expected_names[index]])

func test_only_the_authored_calibration_route_is_available() -> void:
	assert_eq(RunUnitCampaign.PLAYABLE_INDEX, 0, "Calibration is the authored playable route")
	assert_true(RunUnitCampaign.is_available(RunUnitCampaign.PLAYABLE_INDEX), "Calibration should be deployable")
	for index: int in range(1, RunUnitCampaign.route_count()):
		assert_false(RunUnitCampaign.is_available(index), "%s is not in the current build" % RunUnitCampaign.get_route_name(index))

func test_every_route_carries_player_facing_copy() -> void:
	for index: int in RunUnitCampaign.route_count():
		assert_false(RunUnitCampaign.get_code(index).is_empty(), "Route %d needs a campaign code" % index)
		assert_false(RunUnitCampaign.get_summary(index).is_empty(), "Route %d needs a one-line summary" % index)
		assert_false(RunUnitCampaign.get_briefing(index).is_empty(), "Route %d needs a briefing" % index)
		assert_true(RunUnitCampaign.get_runtime(index).ends_with("MIN"), "Route %d should carry its target first-play runtime" % index)

func test_route_names_exist_in_the_storyline_sketch() -> void:
	var storyline: String = _read_storyline()
	if storyline.is_empty():
		return
	for index: int in RunUnitCampaign.route_count():
		var route_name: String = RunUnitCampaign.get_route_name(index)
		assert_true(storyline.to_upper().contains(route_name), "%s should still be part of StorylineSketch.md" % route_name)

func test_route_copy_drops_the_retired_storyline() -> void:
	for index: int in RunUnitCampaign.route_count():
		var copy: String = "%s %s %s" % [RunUnitCampaign.get_title(index), RunUnitCampaign.get_summary(index), RunUnitCampaign.get_briefing(index)]
		for retired: String in RETIRED_COPY:
			assert_false(copy.to_upper().contains(retired.to_upper()), "Retired copy '%s' must not return to route %d" % [retired, index])

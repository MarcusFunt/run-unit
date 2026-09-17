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

func test_routes_are_available_exactly_when_they_have_an_authored_world() -> void:
	assert_eq(RunUnitCampaign.PLAYABLE_INDEX, 0, "Calibration is the route the selector opens on")
	var expected_available: Array[bool] = [true, true, true, true]
	for index: int in RunUnitCampaign.route_count():
		var route_name: String = RunUnitCampaign.get_route_name(index)
		assert_eq(RunUnitCampaign.is_available(index), expected_available[index], "%s availability" % route_name)
		assert_eq(not RunUnitCampaign.get_world_scene(index).is_empty(), expected_available[index], "%s should be playable exactly when it has a world scene" % route_name)

func test_authored_worlds_exist_on_disk() -> void:
	for index: int in RunUnitCampaign.route_count():
		var world_scene: String = RunUnitCampaign.get_world_scene(index)
		if world_scene.is_empty():
			continue
		assert_true(ResourceLoader.exists(world_scene), "%s points at a missing world scene: %s" % [RunUnitCampaign.get_route_name(index), world_scene])

func test_every_route_carries_player_facing_copy() -> void:
	for index: int in RunUnitCampaign.route_count():
		assert_false(RunUnitCampaign.get_code(index).is_empty(), "Route %d needs a campaign code" % index)
		assert_false(RunUnitCampaign.get_summary(index).is_empty(), "Route %d needs a one-line summary" % index)
		assert_false(RunUnitCampaign.get_briefing(index).is_empty(), "Route %d needs a briefing" % index)
		assert_false(RunUnitCampaign.get_completion(index).is_empty(), "Route %d needs a completion line for the results menu" % index)
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

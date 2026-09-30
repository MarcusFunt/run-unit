extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const JUMP_DUST_SCENE: PackedScene = preload("res://assets/vfx/godot_vfx_library/run_unit_jump_dust.tscn")
const METAL_SPARK_SCENE: PackedScene = preload("res://assets/vfx/godot_vfx_library/run_unit_metal_sparks.tscn")

func test_feedback_uses_small_semantic_effects() -> void:
	var dust: CPUParticles2D = JUMP_DUST_SCENE.instantiate() as CPUParticles2D
	var sparks: CPUParticles2D = METAL_SPARK_SCENE.instantiate() as CPUParticles2D
	add_child_autofree(dust)
	add_child_autofree(sparks)
	assert_true(dust.one_shot)
	assert_true(sparks.one_shot)
	assert_true(dust.amount <= 8, "Movement dust stays small enough to leave the robot readable")
	assert_true(sparks.amount <= 8, "Metal contact cannot turn back into a confetti explosion")
	assert_true(dust.lifetime < 0.5)
	assert_true(sparks.lifetime < 0.5)

func test_only_hard_landings_emit_sparks() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var feedback: RunUnitPlayerFeedback = player.get_node("Feedback") as RunUnitPlayerFeedback
	assert_not_null(feedback)
	if feedback == null:
		return
	assert_eq(feedback.landing_tier_for_ratio(0.25), RunUnitPlayerFeedback.LANDING_TIER_SOFT)
	assert_eq(feedback.landing_tier_for_ratio(0.55), RunUnitPlayerFeedback.LANDING_TIER_MEDIUM)
	assert_eq(feedback.landing_tier_for_ratio(0.85), RunUnitPlayerFeedback.LANDING_TIER_HARD)
	assert_false(feedback.should_emit_landing_sparks_for_ratio(0.55))
	assert_true(feedback.should_emit_landing_sparks_for_ratio(0.85))

func test_feedback_audio_assets_load() -> void:
	for path: String in [
		"res://assets/audio/feedback/mechanical_action.wav",
		"res://assets/audio/feedback/metal_clank.wav",
		"res://assets/audio/feedback/body_thud_hard.wav",
	]:
		assert_not_null(load(path), "%s should import as an audio stream" % path)

func test_robot_movement_and_charge_cues_do_not_play_sounds() -> void:
	var feedback_source: String = FileAccess.get_file_as_string("res://scripts/player/player_feedback.gd")
	for function_name: String in ["_on_player_jumped", "_on_player_landed"]:
		var body: String = _function_body(feedback_source, function_name)
		assert_false(body.is_empty(), "%s movement feedback callback should still exist" % function_name)
		assert_false(body.contains("_play_sound"), "%s must stay silent for robot movement" % function_name)
	assert_false(feedback_source.contains("func play_charge_stage("), "Charge-stage robot movement sounds are removed")
	assert_false(feedback_source.contains("func play_charge_ready("), "The full-charge lock remains visual-only")

	var visual_source: String = FileAccess.get_file_as_string("res://scripts/player/robot_visual.gd")
	assert_false(visual_source.contains("feedback.play_charge_stage"), "Charge visuals must not request robot movement audio")
	assert_false(visual_source.contains("feedback.play_charge_ready"), "The full-charge lock remains visual-only")

func _function_body(source: String, function_name: String) -> String:
	var start_marker: String = "func %s(" % function_name
	var start: int = source.find(start_marker)
	if start < 0:
		return ""
	var next_function: int = source.find("\nfunc ", start + start_marker.length())
	if next_function < 0:
		next_function = source.length()
	return source.substr(start, next_function - start)

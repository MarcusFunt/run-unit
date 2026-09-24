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
		"res://assets/audio/feedback/metal_clink.wav",
		"res://assets/audio/feedback/body_thud_soft.wav",
		"res://assets/audio/feedback/body_thud_hard.wav",
	]:
		assert_not_null(load(path), "%s should import as an audio stream" % path)

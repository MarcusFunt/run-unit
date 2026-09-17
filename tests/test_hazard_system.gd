extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

func _instantiate_player() -> RunUnitPlayerMotor:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	return player

func test_player_has_three_point_health_component() -> void:
	var player: RunUnitPlayerMotor = _instantiate_player()
	var health: Node = player.get_node_or_null("Health")
	assert_not_null(health, "Player scene must own a Health component")
	if health == null:
		return
	assert_eq(int(health.get("max_health")), 3, "Maximum health is three")
	assert_eq(int(health.get("current_health")), 3, "A fresh player starts at full health")

func test_player_motor_exposes_knockback_api() -> void:
	var player: RunUnitPlayerMotor = _instantiate_player()
	assert_true(player.has_method("apply_knockback"), "Hazards need a motor-owned knockback API")

extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")

func before_each() -> void:
	RunUnitSession.selected_level_index = 0
	RunUnitSession.clear_checkpoint()

func after_each() -> void:
	RunUnitSession.selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	RunUnitSession.clear_checkpoint()
	get_tree().paused = false

func _instantiate_player() -> RunUnitPlayerMotor:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	return player

func _health(player: RunUnitPlayerMotor) -> RunUnitPlayerHealth:
	return player.get_node("Health") as RunUnitPlayerHealth

func _instantiate_game() -> RunUnitGame:
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	return game

func test_player_has_three_point_health_component() -> void:
	var player: RunUnitPlayerMotor = _instantiate_player()
	var health: RunUnitPlayerHealth = _health(player)
	assert_not_null(health, "Player scene must own a Health component")
	assert_eq(health.max_health, 3, "Maximum health is three")
	assert_eq(health.current_health, 3, "A fresh player starts at full health")

func test_normal_damage_costs_one_hp_and_immediate_repeat_is_rejected() -> void:
	var health: RunUnitPlayerHealth = _health(_instantiate_player())
	assert_true(health.damage(1), "The first hit should be accepted")
	assert_eq(health.current_health, 2, "One normal hit removes one HP")
	assert_false(health.damage(1), "Global i-frames reject an immediate second hit")
	assert_eq(health.current_health, 2, "Rejected damage must not change HP")

func test_normal_damage_is_accepted_again_after_iframes() -> void:
	var health: RunUnitPlayerHealth = _health(_instantiate_player())
	health.invulnerability_seconds = 0.02
	assert_true(health.damage(1))
	for frame: int in range(4):
		await get_tree().physics_frame
	assert_true(health.damage(1), "A later exposure can damage again after global i-frames")
	assert_eq(health.current_health, 1)

func test_lethal_damage_depletes_immediately_and_reset_restores_full_health() -> void:
	var health: RunUnitPlayerHealth = _health(_instantiate_player())
	assert_true(health.damage(1, true), "A lethal hazard should always be accepted while alive")
	assert_eq(health.current_health, 0, "Lethal damage bypasses normal HP attrition")
	health.reset_health()
	assert_eq(health.current_health, 3, "Retry/reset restores full health")
	assert_false(health.is_invulnerable(), "Reset clears transient invulnerability")

func test_knockback_survives_held_input_and_gravity_keeps_running() -> void:
	var player: RunUnitPlayerMotor = _instantiate_player()
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = 1.0
	player.set_action(action)
	player.apply_knockback(Vector2(-300.0, -120.0), 0.08)
	await get_tree().physics_frame
	assert_almost_eq(player.velocity.x, -300.0, 1.0, "Held movement must not immediately erase knockback")
	assert_true(player.velocity.y > -120.0, "Gravity must continue while the player is in hitstun")
	assert_true(player.is_in_hitstun(), "The hit reaction should remain active for its authored duration")

func test_control_returns_after_hitstun_and_reset_clears_it() -> void:
	var player: RunUnitPlayerMotor = _instantiate_player()
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = 1.0
	player.set_action(action)
	player.apply_knockback(Vector2(-300.0, 0.0), 0.03)
	for frame: int in range(8):
		await get_tree().physics_frame
	assert_false(player.is_in_hitstun(), "Hitstun ends automatically")
	assert_true(player.velocity.x > -300.0, "Normal movement resumes after hitstun")
	player.apply_knockback(Vector2(-200.0, 0.0), 1.0)
	player.reset_motor()
	assert_false(player.is_in_hitstun(), "A run reset clears hitstun")
	assert_eq(player.velocity, Vector2.ZERO, "A run reset clears the knockback velocity")

func test_game_reset_restores_health() -> void:
	var game: RunUnitGame = _instantiate_game()
	var health: RunUnitPlayerHealth = _health(game.player)
	assert_true(health.damage(1))
	assert_eq(health.current_health, 2)
	game.reset_run(0)
	assert_eq(health.current_health, 3, "Retry must always restore three HP")

func test_health_depletion_uses_existing_game_failure_flow() -> void:
	var game: RunUnitGame = _instantiate_game()
	var health: RunUnitPlayerHealth = _health(game.player)
	assert_false(game.is_terminal(), "A fresh run is active")
	assert_true(health.damage(1, true))
	assert_true(game.is_terminal(), "Health depletion should enter the existing terminal failure path")

func test_hud_exposes_three_compact_health_cells() -> void:
	var hud: RunUnitHud = HUD_SCENE.instantiate() as RunUnitHud
	add_child_autofree(hud)
	assert_true(hud.has_method("set_health"), "HUD needs a small health update API")
	var cells: Array[Node] = [
		hud.get_node_or_null("HealthDisplay/HealthCell1"),
		hud.get_node_or_null("HealthDisplay/HealthCell2"),
		hud.get_node_or_null("HealthDisplay/HealthCell3"),
	]
	for cell: Node in cells:
		assert_not_null(cell, "HUD should present exactly three compact health cells")
	if not hud.has_method("set_health") or cells.any(func(cell: Node) -> bool: return cell == null):
		return
	hud.call("set_health", 2, 3)
	assert_true((cells[0] as CanvasItem).visible)
	assert_true((cells[1] as CanvasItem).visible)
	assert_false((cells[2] as CanvasItem).visible, "The depleted health cell should visibly turn off")

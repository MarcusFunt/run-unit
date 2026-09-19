extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const HAZARD_SCRIPT_PATH: String = "res://scripts/hazards/hazard_area.gd"
const TIMED_HAZARD_SCRIPT_PATH: String = "res://scripts/hazards/timed_hazard.gd"

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

func _instantiate_hazard(script_path: String = HAZARD_SCRIPT_PATH) -> Area2D:
	var hazard_script: Script = load(script_path) as Script
	assert_not_null(hazard_script, "%s must exist" % script_path)
	if hazard_script == null:
		return null
	var hazard: Area2D = Area2D.new()
	hazard.set_script(hazard_script)
	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(96.0, 96.0)
	collision.shape = shape
	hazard.add_child(collision)
	add_child_autofree(hazard)
	return hazard

func _settle_overlap(player: RunUnitPlayerMotor, hazard: Area2D) -> void:
	player.set_physics_process(false)
	player.global_position = hazard.global_position
	for frame: int in range(3):
		await get_tree().physics_frame

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
	# A node added this frame does not run _physics_process until the next step.
	# Without settling first, the frame awaited after the hit is one the motor
	# sits out, so velocity still reads back exactly as apply_knockback left it
	# and every assertion below passes without simulating anything.
	for frame: int in range(2):
		await get_tree().physics_frame
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

func test_active_hazard_hits_once_for_one_continuous_exposure() -> void:
	var hazard: Area2D = _instantiate_hazard()
	if hazard == null:
		return
	var player: RunUnitPlayerMotor = _instantiate_player()
	var health: RunUnitPlayerHealth = _health(player)
	health.invulnerability_seconds = 0.0
	await _settle_overlap(player, hazard)
	assert_eq(health.current_health, 2, "Entering an active hazard costs one HP")
	for frame: int in range(6):
		await get_tree().physics_frame
	assert_eq(health.current_health, 2, "Continuous overlap is still one exposure")

func test_leaving_and_reentering_hazard_creates_a_new_exposure() -> void:
	var hazard: Area2D = _instantiate_hazard()
	if hazard == null:
		return
	var player: RunUnitPlayerMotor = _instantiate_player()
	var health: RunUnitPlayerHealth = _health(player)
	health.invulnerability_seconds = 0.0
	await _settle_overlap(player, hazard)
	player.global_position = Vector2(300.0, 0.0)
	for frame: int in range(3):
		await get_tree().physics_frame
	player.global_position = hazard.global_position
	for frame: int in range(3):
		await get_tree().physics_frame
	assert_eq(health.current_health, 1, "Exit and re-entry should create a second hit exposure")

func test_reactivating_hazard_hits_player_who_remains_inside() -> void:
	var hazard: Area2D = _instantiate_hazard()
	if hazard == null:
		return
	hazard.set("active", false)
	var player: RunUnitPlayerMotor = _instantiate_player()
	var health: RunUnitPlayerHealth = _health(player)
	health.invulnerability_seconds = 0.0
	await _settle_overlap(player, hazard)
	assert_eq(health.current_health, 3, "Inactive hazards do not damage on entry")
	hazard.call("set_active", true)
	await get_tree().physics_frame
	assert_eq(health.current_health, 2, "A fresh activation is a new exposure even without body re-entry")

func test_lethal_hazard_depletes_health_immediately() -> void:
	var hazard: Area2D = _instantiate_hazard()
	if hazard == null:
		return
	hazard.set("lethal", true)
	var player: RunUnitPlayerMotor = _instantiate_player()
	await _settle_overlap(player, hazard)
	assert_eq(_health(player).current_health, 0, "Lethal hazard contact bypasses the three-hit attrition model")

func test_hazard_dispatches_authored_knockback() -> void:
	var hazard: Area2D = _instantiate_hazard()
	if hazard == null:
		return
	hazard.set("knockback", Vector2(-240.0, -80.0))
	hazard.set("hitstun_seconds", 0.2)
	var player: RunUnitPlayerMotor = _instantiate_player()
	player.set_physics_process(false)
	await _settle_overlap(player, hazard)
	assert_eq(player.velocity, Vector2(-240.0, -80.0), "Accepted hazard damage should delegate knockback to the player motor")
	assert_true(player.is_in_hitstun())

func test_timed_hazard_reset_restores_authored_phase() -> void:
	var hazard: Area2D = _instantiate_hazard(TIMED_HAZARD_SCRIPT_PATH)
	if hazard == null:
		return
	hazard.set("cycle_seconds", 1.0)
	hazard.set("active_seconds", 0.25)
	hazard.set("phase_offset_seconds", 0.5)
	hazard.call("reset_level_state")
	assert_false(bool(hazard.get("active")), "A reset into the inactive half of the cycle should be inactive")
	hazard.set("phase_offset_seconds", 0.1)
	hazard.call("reset_level_state")
	assert_true(bool(hazard.get("active")), "A reset into the active window should reproduce the authored phase")


func test_electric_floor_arc_scene_has_persistent_warning_and_switchable_arc() -> void:
	var scene: PackedScene = load("res://scenes/hazards/electric_floor_arc.tscn") as PackedScene
	assert_not_null(scene)
	if scene == null:
		return
	var hazard: RunUnitTimedHazard = scene.instantiate() as RunUnitTimedHazard
	add_child_autofree(hazard)
	assert_not_null(hazard.get_node_or_null("WarningPlate"), "A safe phase still needs a visible warning plate")
	var active_visual: CanvasItem = hazard.get_node_or_null("ActiveVisual") as CanvasItem
	assert_not_null(active_visual, "The powered arc needs an independently switchable visual")
	assert_false(hazard.lethal, "Floor arcs should cost health, not instantly kill the player")
	assert_eq(hazard.damage, 1)
	hazard.set_active(false)
	assert_false(active_visual.visible, "The electric arc should visibly switch off during the safe timing window")
	hazard.set_active(true)
	assert_true(active_visual.visible, "The electric arc should visibly switch on with the damaging phase")

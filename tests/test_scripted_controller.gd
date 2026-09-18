extends GutTest

## Regression coverage for scripts/player/scripted_controller.gd's crouch
## handling. Before this, the bot never set crouch_held and stalled
## permanently at the first crouch gate on every authored route.

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01_factory.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const TRANSFER_GATE_LEFT_X: float = 992.0     # jammed conveyor, tiles 31-33 over the row-14 deck
const TRANSFER_GATE_RIGHT_X: float = 1088.0
const TRANSFER_DECK_Y: float = 448.0


func _spawn_bot_before_the_gate() -> Dictionary:
	var world: RunUnitStaticWorld = LEVEL_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.global_position = Vector2(TRANSFER_GATE_LEFT_X - 120.0, TRANSFER_DECK_Y - 32.0)

	var controller: RunUnitScriptedController = RunUnitScriptedController.new()
	controller.player_path = player.get_path()
	controller.world_path = world.get_path()
	add_child_autofree(controller)
	controller.active = true
	return {"world": world, "player": player, "controller": controller}


func test_bot_crouches_through_the_transfer_line_jam() -> void:
	var rig: Dictionary = _spawn_bot_before_the_gate()
	var player: RunUnitPlayerMotor = rig["player"]

	for frame: int in range(150):
		await get_tree().physics_frame

	assert_true(player.global_position.x > TRANSFER_GATE_RIGHT_X, "The bot must duck through the jammed conveyor instead of stalling, got x=%.1f" % player.global_position.x)


func test_bot_is_crouching_while_under_the_gate() -> void:
	var rig: Dictionary = _spawn_bot_before_the_gate()
	var player: RunUnitPlayerMotor = rig["player"]

	var was_crouching_under_the_gate: bool = false
	for frame: int in range(150):
		await get_tree().physics_frame
		if player.global_position.x > TRANSFER_GATE_LEFT_X and player.global_position.x < TRANSFER_GATE_RIGHT_X:
			was_crouching_under_the_gate = was_crouching_under_the_gate or player.is_crouching()

	assert_true(was_crouching_under_the_gate, "The bot should be crouched at some point while inside the gate's span")

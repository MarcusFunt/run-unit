class_name RunUnitFollowCamera
extends Camera2D

## Retain the game's ahead-of-player framing, then bias it for fast travel,
## falling, and an optional stationary downward peek.
const BASE_OFFSET := Vector2(309.0, -132.0)
const HORIZONTAL_LEAD: float = 78.0
const FALL_PREVIEW: float = 130.0
const RISE_PREVIEW: float = -24.0
const DOWN_PEEK: float = 90.0
const RESPONSE: float = 5.0

@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor

func _physics_process(delta: float) -> void:
	update_lookahead(delta)

func update_lookahead(delta: float) -> void:
	if player == null:
		return
	var speed_ratio: float = clampf(player.velocity.x / maxf(player.max_run_speed, 1.0), -1.0, 1.0)
	var target: Vector2 = BASE_OFFSET
	target.x += HORIZONTAL_LEAD * maxf(speed_ratio, 0.0) - 489.0 * maxf(-speed_ratio, 0.0)
	if player.velocity.y > 140.0:
		target.y += FALL_PREVIEW * smoothstep(140.0, 750.0, player.velocity.y)
	elif player.velocity.y < -140.0 or player.is_charging():
		target.y += RISE_PREVIEW
	if absf(player.velocity.x) < 30.0 and Input.is_action_pressed("crouch") and not player.is_charging():
		target.y += DOWN_PEEK
	position = position.lerp(target, 1.0 - exp(-RESPONSE * maxf(delta, 0.0)))

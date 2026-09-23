class_name RunUnitFollowCamera
extends Camera2D

## Keep the forward framing steady while leaving room to see lower platforms.
## A small directional lead and a damped fall preview aid downward jumps.
const BASE_OFFSET := Vector2(309.0, -72.0)
const HORIZONTAL_LEAD: float = 24.0
const FALL_PREVIEW: float = 90.0
const RESPONSE: float = 4.0

@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor

func _physics_process(delta: float) -> void:
	update_lookahead(delta)

func update_lookahead(delta: float) -> void:
	if player == null:
		return
	var speed_ratio: float = clampf(player.velocity.x / maxf(player.max_run_speed, 1.0), -1.0, 1.0)
	var target: Vector2 = BASE_OFFSET
	target.x += HORIZONTAL_LEAD * speed_ratio
	if player.velocity.y > 80.0:
		target.y += FALL_PREVIEW * smoothstep(80.0, 650.0, player.velocity.y)
	position = position.lerp(target, 1.0 - exp(-RESPONSE * maxf(delta, 0.0)))

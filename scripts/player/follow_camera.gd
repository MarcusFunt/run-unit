class_name RunUnitFollowCamera
extends Camera2D

## Hold the world frame during ordinary jumps; follow sustained descents.
const BASE_OFFSET := Vector2(309.0, -72.0)
const HORIZONTAL_DEAD_ZONE: float = 20.0
const UPPER_MARGIN: float = -120.0
const LOWER_MARGIN: float = 110.0
const VERTICAL_DEAD_ZONE: float = 12.0
const FALL_PREVIEW: float = 100.0
const HORIZONTAL_RESPONSE: float = 9.0
const VERTICAL_RESPONSE: float = 8.0

@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor
var _world_center: Vector2 = Vector2.ZERO

func _ready() -> void:
	snap_to_player()

func _physics_process(delta: float) -> void:
	update_lookahead(delta)

func snap_to_player() -> void:
	if player == null:
		return
	_world_center = (player.global_position + BASE_OFFSET).round()
	position = _world_center - player.global_position
	force_update_scroll()

func update_lookahead(delta: float) -> void:
	if player == null:
		return
	var desired_x: float = player.global_position.x + BASE_OFFSET.x
	var horizontal_error: float = desired_x - _world_center.x
	if absf(horizontal_error) > HORIZONTAL_DEAD_ZONE:
		var horizontal_target: float = desired_x - signf(horizontal_error) * HORIZONTAL_DEAD_ZONE
		_world_center.x = lerpf(_world_center.x, horizontal_target, 1.0 - exp(-HORIZONTAL_RESPONSE * maxf(delta, 0.0)))

	var fall_preview: float = 0.0
	if player.velocity.y > 80.0:
		fall_preview = FALL_PREVIEW * smoothstep(80.0, 650.0, player.velocity.y)
	var desired_y: float = player.global_position.y + BASE_OFFSET.y + fall_preview
	var player_relative_y: float = player.global_position.y - _world_center.y
	var vertical_target: float = _world_center.y
	if player_relative_y > LOWER_MARGIN or (fall_preview > 0.0 and desired_y > _world_center.y + VERTICAL_DEAD_ZONE):
		vertical_target = maxf(player.global_position.y - LOWER_MARGIN, desired_y - VERTICAL_DEAD_ZONE)
	elif player_relative_y < UPPER_MARGIN:
		vertical_target = player.global_position.y - UPPER_MARGIN
	_world_center.y = lerpf(_world_center.y, vertical_target, 1.0 - exp(-VERTICAL_RESPONSE * maxf(delta, 0.0)))

	# The camera is a child of the player; cancel that motion in world space.
	position = _world_center.round() - player.global_position
	force_update_scroll()

class_name RunUnitBeaconApproach
extends Parallax2D

## Grows the skyline Beacon 9 as UNIT-07 crosses the city in Level 3.
##
## The storyline asks for the beacon to visibly grow as the player advances, so
## the drawn landmark is scaled and re-seated from the camera's progress along
## the route, then faded out once the level's own tiled beacon geometry takes
## over. A level opened without a camera (a test, or the editor) simply keeps
## the starting framing.

@export var beacon_path: NodePath = ^"Beacon9"
## Camera x positions between which the beacon grows.
@export var start_x: float = 0.0
@export var end_x: float = 9000.0
@export var start_scale: float = 0.42
@export var end_scale: float = 1.8
@export var start_offset: Vector2 = Vector2(760.0, 430.0)
@export var end_offset: Vector2 = Vector2(430.0, 880.0)
## Fraction of the approach after which the drawn landmark fades out, handing
## the frame to the beacon the player is about to stand on.
@export_range(0.5, 1.0, 0.01) var fade_from: float = 0.86

@onready var beacon: Node2D = get_node_or_null(beacon_path) as Node2D

func _process(_delta: float) -> void:
	if beacon == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var progress: float = clampf(
		inverse_lerp(start_x, end_x, camera.get_screen_center_position().x), 0.0, 1.0
	)
	beacon.scale = Vector2.ONE * lerpf(start_scale, end_scale, progress)
	scroll_offset = start_offset.lerp(end_offset, progress)
	var fade: float = clampf(inverse_lerp(fade_from, 1.0, progress), 0.0, 1.0)
	beacon.modulate.a = 1.0 - fade
	beacon.visible = fade < 1.0

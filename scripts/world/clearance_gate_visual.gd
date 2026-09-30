class_name RunUnitClearanceGateVisual
extends Node2D

## Draw-only foreground cue for a crouch gate whose collision is authored in
## the Tiled Obstacles layer. This prop deliberately contains no physics.
@export_range(32.0, 192.0, 1.0) var span_width: float = 96.0:
	set(value):
		span_width = maxf(value, 32.0)
		queue_redraw()

@export_range(12.0, 96.0, 1.0) var overhang_height: float = 32.0:
	set(value):
		overhang_height = maxf(value, 12.0)
		queue_redraw()

## The drawn edge sits just above the robot's crouched body; the semantic
## collider is slightly lower so the flexible antenna makes contact first.
## Only the authored tileset contributes collision.
@export_range(64.0, 160.0, 1.0) var clearance_from_surface: float = 102.0:
	set(value):
		clearance_from_surface = maxf(value, 64.0)
		queue_redraw()

@export var shell_color: Color = Color(0.012, 0.032, 0.04, 1.0):
	set(value):
		shell_color = value
		queue_redraw()

@export var trim_color: Color = Color(1.0, 0.62, 0.22, 0.96):
	set(value):
		trim_color = value
		queue_redraw()


func _draw() -> void:
	var half_span: float = span_width * 0.5
	var underside_y: float = -clearance_from_surface
	var shell_height: float = maxf(overhang_height - 5.0, 0.0)
	draw_rect(
		Rect2(Vector2(-half_span, underside_y - overhang_height), Vector2(span_width, shell_height)),
		shell_color
	)
	draw_rect(Rect2(Vector2(-half_span, underside_y - 4.0), Vector2(span_width, 3.0)), trim_color)

	const SIDE_MARKER_WIDTH: float = 4.0
	const SIDE_MARKER_HEIGHT: float = 7.0
	draw_rect(
		Rect2(Vector2(-half_span, underside_y - 13.0), Vector2(SIDE_MARKER_WIDTH, SIDE_MARKER_HEIGHT)),
		trim_color
	)
	draw_rect(
		Rect2(Vector2(half_span - SIDE_MARKER_WIDTH, underside_y - 13.0), Vector2(SIDE_MARKER_WIDTH, SIDE_MARKER_HEIGHT)),
		trim_color
	)


func get_visual_bounds() -> Rect2:
	return Rect2(
		Vector2(-span_width * 0.5, -clearance_from_surface - overhang_height),
		Vector2(span_width, overhang_height)
	)

class_name RunUnitWalkableEdges
extends Node2D

## Only platforms discovered in Semantic get this bright rim. Scenery, ArtDeck
## and overhangs never produce a walkable top line.
const TOP: Color = Color(0.80, 1.0, 0.92, 1.0)
const TOP_CORE: Color = Color(0.22, 0.90, 0.82, 1.0)
const SHADOW: Color = Color(0.008, 0.018, 0.024, 1.0)
const TOP_LINE_WIDTH: float = 6.0
const SHADOW_LINE_WIDTH: float = 9.0
var _segments: Array[Dictionary] = []
var _tile_size: float = 32.0

func set_segments(segments: Array[Dictionary], tile_size: float) -> void:
	_segments = segments.duplicate(true)
	_tile_size = tile_size
	queue_redraw()

func get_edge_count() -> int:
	return _segments.size()

func get_top_line_width() -> float:
	return TOP_LINE_WIDTH

func _draw() -> void:
	for segment: Dictionary in _segments:
		var y: float = float(segment["height"]) * _tile_size
		var left: float = float(segment["start_x"]) * _tile_size
		var right: float = (float(segment["end_x"]) + 1.0) * _tile_size
		draw_line(Vector2(left, y + 2), Vector2(right, y + 2), SHADOW, SHADOW_LINE_WIDTH)
		draw_line(Vector2(left, y - 1), Vector2(right, y - 1), TOP, TOP_LINE_WIDTH)
		draw_line(Vector2(left, y - 1), Vector2(right, y - 1), TOP_CORE, 1.5)

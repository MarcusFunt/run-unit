class_name RunUnitWalkableEdges
extends Node2D

## Only platforms discovered in Semantic get this bright rim. Scenery, ArtDeck
## and overhangs never produce a walkable top line.
const TOP := Color(0.42, 0.95, 0.95, 0.95)
const SHADOW := Color(0.015, 0.055, 0.07, 0.95)
var _segments: Array[Dictionary] = []
var _tile_size: float = 32.0

func set_segments(segments: Array[Dictionary], tile_size: float) -> void:
	_segments = segments.duplicate(true)
	_tile_size = tile_size
	queue_redraw()

func get_edge_count() -> int:
	return _segments.size()

func _draw() -> void:
	for segment: Dictionary in _segments:
		var y: float = float(segment["height"]) * _tile_size
		var left: float = float(segment["start_x"]) * _tile_size
		var right: float = (float(segment["end_x"]) + 1.0) * _tile_size
		draw_line(Vector2(left, y + 2), Vector2(right, y + 2), SHADOW, 6.0)
		draw_line(Vector2(left, y - 1), Vector2(right, y - 1), TOP, 3.0)

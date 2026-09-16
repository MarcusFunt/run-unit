class_name RunUnitScoreManager
extends Node

## The authored route uses a 32 px grid: one grid cell is one displayed metre.
const PIXELS_PER_METRE: float = 32.0

var distance: float = 0.0
var best_distance: float = 0.0
var _start_world_x: float = 0.0

func reset(start_world_x: float, persisted_best_distance: float = 0.0) -> void:
	_start_world_x = start_world_x
	distance = 0.0
	best_distance = maxf(persisted_best_distance, 0.0)

func record_position(world_x: float) -> float:
	var metres_from_start: float = maxf((world_x - _start_world_x) / PIXELS_PER_METRE, 0.0)
	distance = maxf(distance, metres_from_start)
	best_distance = maxf(best_distance, distance)
	return distance

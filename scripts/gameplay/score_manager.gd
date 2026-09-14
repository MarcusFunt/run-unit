class_name RunUnitScoreManager
extends Node

var distance: float = 0.0
var best_distance: float = 0.0

func reset() -> void:
	distance = 0.0

func record_position(world_x: float) -> float:
	distance = maxf(distance, maxf(world_x, 0.0))
	best_distance = maxf(best_distance, distance)
	return distance

class_name RunUnitLevelCatalog
extends RefCounted

## Playable routes, in selector order. The selector lists these, the game
## loads the selected entry's world scene, and the results menu reads its
## completion line. Slots past the end of this list show as offline.
const LEVELS: Array[Dictionary] = [
	{
		"name": "FINAL INSPECTION",
		"world_scene": "res://scenes/world.tscn",
		"description": "CALIBRATION READY\nComplete mobility, spring, and clearance checks in Final Inspection.\n\nFour checks. One short route.",
		"threat": "LOW",
		"completion": "Maintenance Shaft traversal complete.",
	},
	{
		"name": "TRANSFER & STORAGE",
		"world_scene": "res://scenes/levels/level_01_factory.tscn",
		"description": "TRANSFER LINE 03 OFFLINE\nDuck the jammed line, drop into storage, and cross the rack tops to the breach in the exterior wall.\n\nTwo clearances. Two charged climbs.",
		"threat": "MODERATE",
		"completion": "Exterior wall breached. Unit has left the factory.",
	},
]


static func count() -> int:
	return LEVELS.size()


static func has_level(level_index: int) -> bool:
	return level_index >= 0 and level_index < LEVELS.size()


static func get_level(level_index: int) -> Dictionary:
	return LEVELS[level_index] if has_level(level_index) else LEVELS[0]

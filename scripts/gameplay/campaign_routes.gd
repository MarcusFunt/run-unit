class_name RunUnitCampaign
extends RefCounted
## Campaign route table for RUN//UNIT.
##
## This mirrors the campaign structure in StorylineSketch.md
## (Calibration -> Factory Escape -> Recovery -> Beacon 9) and is the single
## source of player-facing route copy. The selector lists these routes, the
## game loads the selected route's world scene, and the results menu reads its
## completion line. A route without an authored world yet carries an empty
## world_scene and shows as locked. Update the sketch and this table together;
## do not reintroduce the retired Final Inspection / Solar Ignition Core route
## naming.

const PLAYABLE_INDEX: int = 0

const ROUTES: Array[Dictionary] = [
	{
		"code": "TUT",
		"name": "CALIBRATION",
		"title": "TUTORIAL ROUTE",
		"world_scene": "res://scenes/world.tscn",
		"runtime": "1-2 MIN",
		"summary": "Clear the factory movement checks and leave the calibration tunnel.",
		"completion": "Calibration checks complete.",
	},
	{
		"code": "01",
		"name": "FACTORY ESCAPE",
		"world_scene": "res://scenes/levels/level_01_factory.tscn",
		"runtime": "5-7 MIN",
		"summary": "Cross the stalled transfer line and leave the factory through the breached wall.",
		"completion": "Exterior wall breached. Unit has left the factory.",
	},
	{
		"code": "02",
		"name": "RECOVERY",
		"world_scene": "res://scenes/levels/level_02_recovery.tscn",
		"runtime": "7-9 MIN",
		"summary": "Cross the exterior service district and reach Reserve Depot 03.",
		"completion": "Replacement ignition module recovered. Target system: Beacon 9.",
	},
	{
		"code": "03",
		"name": "BEACON 9",
		"world_scene": "res://scenes/levels/level_03_beacon.tscn",
		"runtime": "8-11 MIN",
		"summary": "Carry the recovered assembly across the city to Beacon 9.",
		"completion": "Beacon 9 ignition restored.",
	},
]

static func route_count() -> int:
	return ROUTES.size()

static func has_route(route_index: int) -> bool:
	return route_index >= 0 and route_index < ROUTES.size()

static func get_route(route_index: int) -> Dictionary:
	if not has_route(route_index):
		return {}
	return ROUTES[route_index]

## A route is playable exactly when it has an authored world to load.
static func is_available(route_index: int) -> bool:
	return not get_world_scene(route_index).is_empty()

static func get_world_scene(route_index: int) -> String:
	return str(get_route(route_index).get("world_scene", ""))

static func get_completion(route_index: int) -> String:
	return str(get_route(route_index).get("completion", "Route traversal complete."))

static func get_code(route_index: int) -> String:
	return str(get_route(route_index).get("code", "--"))

static func get_route_name(route_index: int) -> String:
	return str(get_route(route_index).get("name", "UNKNOWN ROUTE"))

static func get_runtime(route_index: int) -> String:
	return str(get_route(route_index).get("runtime", "--"))

static func get_summary(route_index: int) -> String:
	return str(get_route(route_index).get("summary", ""))

## Most routes derive their title from code + name. A route can override this
## with an explicit "title" entry (e.g. the tutorial's "TUTORIAL ROUTE").
static func get_title(route_index: int) -> String:
	var route: Dictionary = get_route(route_index)
	if route.has("title"):
		return str(route["title"])
	return "%s  %s" % [get_code(route_index), get_route_name(route_index)]

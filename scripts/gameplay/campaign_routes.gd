class_name RunUnitCampaign
extends RefCounted
## Campaign route table for RUN//UNIT.
##
## This mirrors the campaign structure in StorylineSketch.md
## (Calibration -> Factory Escape -> Recovery -> Beacon 9) and is the single
## source of player-facing route copy. Update the sketch and this table
## together; do not reintroduce the retired Final Inspection / Solar Ignition
## Core route naming.

const PLAYABLE_INDEX: int = 0

const ROUTES: Array[Dictionary] = [
	{
		"code": "TUT",
		"name": "CALIBRATION",
		"available": true,
		"runtime": "1-2 MIN",
		"summary": "Clear the factory movement checks and leave the calibration tunnel.",
		"briefing": "CALIBRATION SEQUENCE ACTIVE\nUNIT-07 clears the mobility, hop, spring-load, and clearance checks.\n\nTransfer lift 01 has faulted. Pass beneath the door to leave calibration.",
	},
	{
		"code": "01",
		"name": "FACTORY ESCAPE",
		"available": false,
		"runtime": "5-7 MIN",
		"summary": "Cross the stalled transfer line and leave the factory through the breached wall.",
		"briefing": "TRANSFER SYSTEM OFFLINE\nCross the stalled production machinery by hand, drop into the storage warehouse, and reach the breach in the factory wall.",
	},
	{
		"code": "02",
		"name": "RECOVERY",
		"available": false,
		"runtime": "7-9 MIN",
		"summary": "Cross the exterior service district and reach Reserve Depot 03.",
		"briefing": "CRITICAL REPLACEMENT ASSEMBLY\nRESERVE DEPOT 03\n\nCross the exterior service district and recover the assembly held inside the reserve facility.",
	},
	{
		"code": "03",
		"name": "BEACON 9",
		"available": false,
		"runtime": "8-11 MIN",
		"summary": "Carry the recovered assembly across the city to Beacon 9.",
		"briefing": "BEACON 9\nIGNITION ASSEMBLY OFFLINE\n\nCarry the replacement across the failing city, climb the beacon, and install it.",
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

static func is_available(route_index: int) -> bool:
	return bool(get_route(route_index).get("available", false))

static func get_code(route_index: int) -> String:
	return str(get_route(route_index).get("code", "--"))

static func get_route_name(route_index: int) -> String:
	return str(get_route(route_index).get("name", "UNKNOWN ROUTE"))

static func get_runtime(route_index: int) -> String:
	return str(get_route(route_index).get("runtime", "--"))

static func get_summary(route_index: int) -> String:
	return str(get_route(route_index).get("summary", ""))

static func get_briefing(route_index: int) -> String:
	return str(get_route(route_index).get("briefing", ""))

static func get_title(route_index: int) -> String:
	return "%s  %s" % [get_code(route_index), get_route_name(route_index)]

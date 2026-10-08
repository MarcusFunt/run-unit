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

## Site labels shown on the selected route's field record.
const ROUTES: Array[Dictionary] = [
	{
		"code": "TUT",
		"name": "CALIBRATION",
		"title": "CALIBRATION SHAFT",
		"world_scene": "res://scenes/world.tscn",
		"runtime": "CALIBRATION SHAFT",
		"summary": "Transfer lift 01 has failed with UNIT-07 still inside the calibration shaft.",
		"objective": "Reach the manual transfer release",
		"briefing": "The lift seized between decks. Follow the service lamps to the manual release.",
		"completion": "Transfer lift released. UNIT-07 has left the shaft.",
	},
	{
		"code": "01",
		"name": "FACTORY ESCAPE",
		"world_scene": "res://scenes/levels/level_01_factory.tscn",
		"runtime": "TRANSFER HALL",
		"summary": "A failed transfer line has opened a way through the outer wall.",
		"objective": "Find a way through the breached outer wall",
		"briefing": "The service grid is failing from bay to bay. The breached wall opens onto the district below.",
		"completion": "Outer wall breached. UNIT-07 is in the service district.",
	},
	{
		"code": "02",
		"name": "RECOVERY",
		"world_scene": "res://scenes/levels/level_02_recovery.tscn",
		"runtime": "SERVICE DISTRICT",
		"summary": "A compatible ignition assembly is transmitting from Reserve Depot 03.",
		"objective": "Find the reserve cell at Depot 03",
		"briefing": "Fault current crosses the district. The assembly's markings match the dark Beacon 9 in the skyline.",
		"completion": "Reserve Depot 03 escaped. Beacon 9's replacement assembly is secured.",
	},
	{
		"code": "03",
		"name": "BEACON 9",
		"world_scene": "res://scenes/levels/level_03_beacon.tscn",
		"runtime": "CITY CROSSING",
		"summary": "Beacon 9 has gone dark. The recovered assembly bears its matching seal.",
		"objective": "Carry the reserve cell to Beacon 9",
		"briefing": "An open service spine reaches the beacon. Its upper coupler has no power.",
		"completion": "Beacon 9 is lit. The city grid is waking.",
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

## The route that follows this one in campaign order, or this one again when the
## campaign has nothing playable after it.
static func get_next_route_index(route_index: int) -> int:
	var next_index: int = route_index + 1
	return next_index if is_available(next_index) else route_index

static func get_world_scene(route_index: int) -> String:
	return str(get_route(route_index).get("world_scene", ""))

static func get_completion(route_index: int) -> String:
	return str(get_route(route_index).get("completion", "Sector telemetry archived."))

static func get_code(route_index: int) -> String:
	return str(get_route(route_index).get("code", "--"))

static func get_route_name(route_index: int) -> String:
	return str(get_route(route_index).get("name", "UNKNOWN ROUTE"))

static func get_runtime(route_index: int) -> String:
	return str(get_route(route_index).get("runtime", "--"))

static func get_summary(route_index: int) -> String:
	return str(get_route(route_index).get("summary", ""))

static func get_objective(route_index: int) -> String:
	return str(get_route(route_index).get("objective", "LOCAL SIGNAL ACTIVE"))

static func get_briefing(route_index: int) -> String:
	return str(get_route(route_index).get("briefing", ""))

## Most routes derive their title from code + name. A route can override this
## with an explicit "title" entry (e.g. the calibration shaft).
static func get_title(route_index: int) -> String:
	var route: Dictionary = get_route(route_index)
	if route.has("title"):
		return str(route["title"])
	return "%s  %s" % [get_code(route_index), get_route_name(route_index)]

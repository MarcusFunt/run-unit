class_name RunUnitStoryZoneDirector
extends Node
## Binds Tiled-authored story zones to reusable presentation cues. Each area
## can emit once per route instance; a run reset and checkpoint retry do not
## replay an already-seen beat.

signal story_beat(zone_name: String, cue: Dictionary)

const WORLD_VISUALS_SCRIPT: Script = preload("res://scripts/world/story_world_state_feedback.gd")

const CUES := {
	"TransferLine": {"message": "TRANSFER LIFT 01 // DRIVE CURRENT LOST", "ambience": "factory"},
	"Collapse": {"message": "LOAD BEARING // STRAIN DETECTED", "event": "collapse_warning", "world_change": "structure_shift"},
	"WarehouseReveal": {"message": "UNIT STORAGE // PRODUCTION HALTED", "ambience": "factory_interior"},
	"WarehouseTraversal": {"event": "hazard_warning"},
	"ExteriorBreach": {"message": "OUTER WALL // PRESSURE LOSS", "ambience": "exterior", "world_change": "route_open"},
	"FactoryExterior": {"message": "SERVICE DISTRICT // GRID FEED BELOW", "ambience": "exterior"},
	"ServiceDistrict": {"message": "LIVE CONDUIT // ARC SCARS VISIBLE", "event": "hazard_warning"},
	"DepotSightline": {"message": "RESERVE DEPOT 03 // ASSEMBLY CRADLE DETECTED", "event": "objective_cue"},
	"FacilityApproach": {"message": "SUBSTATION 03 // REPEATING FAULT", "event": "hazard_warning"},
	"CoolingDescent": {"message": "COOLANT RETURN // FLOW BELOW DECK", "ambience": "cooling"},
	"CoreAscent": {"message": "VAULT BUS // CURRENT RISING", "event": "objective_cue"},
	"VaultPerimeter": {"message": "ASSEMBLY CRADLE // SIGNAL MATCH", "event": "objective_cue"},
	"ModuleAcquisition": {"message": "IGNITION ASSEMBLY // COMPATIBLE", "event": "objective_cue"},
	"ReserveExit": {"message": "DEPOT SHUTTER // MANUAL RELEASE", "ambience": "exterior"},
	"MissionConfirmation": {"message": "BEACON 9 // CORE CURRENT: ZERO", "ambience": "exterior"},
	"RooftopCrossing": {"message": "BEACON 9 // SIGNAL STRENGTH RISING", "event": "hazard_warning"},
	"TransitViaduct": {"message": "FREIGHT SPINE // DRIVE CIRCUIT DEAD", "event": "hazard_warning"},
	"UtilityCanyon": {"message": "ARC SCARS // LINE STILL LIVE", "ambience": "cooling"},
	"BeaconPerimeter": {"message": "BEACON 9 // OUTER SERVICE RING", "ambience": "beacon_exterior"},
	"ExteriorAscent": {"message": "SERVICE SPINE // UPPER COUPLER UNPOWERED", "event": "objective_cue"},
	"BeaconInterior": {"message": "SAFETY FIELD // RESIDUAL CHARGE", "ambience": "beacon_interior", "world_change": "hazard_field_cleared"},
	"IgnitionChamber": {"message": "IGNITION SOCKET // ASSEMBLY MATCH", "event": "objective_cue"},
}

var _seen: Dictionary = {}
var _world_visuals: Node2D = null

const IMPORTED_AREA_SUFFIX := " (Area)"

func bind_zones(root: Node) -> void:
	_world_visuals = Node2D.new()
	_world_visuals.name = "WorldStateVisuals"
	_world_visuals.set_script(WORLD_VISUALS_SCRIPT)
	add_child(_world_visuals)
	_world_visuals.call("bind_world", root as Node2D)
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Area2D and String(node.get_parent().name) == "StoryZones":
			_bind_zone(node as Area2D)

func has_seen(zone_name: String) -> bool:
	return _seen.has(zone_name)

func _bind_zone(zone: Area2D) -> void:
	# YATI appends this suffix when it imports Tiled rectangle objects. Use the
	# authored Tiled name for cues, telemetry, and non-repeat tracking.
	var authored_name: String = String(zone.name).trim_suffix(IMPORTED_AREA_SUFFIX)
	zone.set_meta("story_zone_name", authored_name)
	var cue: Dictionary = CUES.get(authored_name, {})
	var world_change: String = str(cue.get("world_change", ""))
	if not world_change.is_empty() and _world_visuals != null:
		_world_visuals.call("register_zone", authored_name, world_change, zone)
	zone.collision_layer = 0
	zone.collision_mask = 1
	zone.monitoring = true
	var callback := _on_zone_body_entered.bind(zone)
	if not zone.body_entered.is_connected(callback):
		zone.body_entered.connect(callback)

func _on_zone_body_entered(body: Node2D, zone: Area2D) -> void:
	if not body is RunUnitPlayerMotor:
		return
	var zone_name: String = String(zone.get_meta("story_zone_name", String(zone.name)))
	if _seen.has(zone_name):
		return
	_seen[zone_name] = true
	var cue: Dictionary = CUES.get(zone_name, {"message": "LOCAL SIGNAL // %s" % zone_name})
	var world_change: String = str(cue.get("world_change", ""))
	if not world_change.is_empty() and _world_visuals != null:
		_world_visuals.call("apply_world_change", zone_name)
	RunUnitSession.record_playtest_event("story_zone", {"zone": zone_name})
	story_beat.emit(zone_name, cue.duplicate(true))

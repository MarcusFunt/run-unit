class_name RunUnitStoryZoneDirector
extends Node
## Binds Tiled-authored story zones to reusable presentation cues. Each area
## can emit once per route instance; a run reset and checkpoint retry do not
## replay an already-seen beat.

signal story_beat(zone_name: String, cue: Dictionary)

const CUES := {
	"TransferLine": {"message": "TRANSFER LINE // POWER IS OFFLINE", "ambience": "factory"},
	"Collapse": {"message": "STRUCTURE SHIFT // KEEP MOVING", "event": "collapse_warning"},
	"WarehouseReveal": {"message": "UNIT STORAGE // PRODUCTION HALTED", "ambience": "factory_interior"},
	"WarehouseTraversal": {"event": "hazard_warning"},
	"ExteriorBreach": {"message": "EXTERIOR BREACH // ESCAPE ROUTE OPEN", "ambience": "exterior"},
	"FactoryExterior": {"message": "FACTORY CLEAR // SERVICE DISTRICT AHEAD", "ambience": "exterior"},
	"ServiceDistrict": {"message": "POWER FAULTS // WATCH THE WARNING PLATES", "event": "hazard_warning"},
	"DepotSightline": {"message": "RESERVE DEPOT 03 // ASSEMBLY LOCATED", "event": "objective_cue"},
	"FacilityApproach": {"message": "FACILITY APPROACH // FAULT CYCLE ACTIVE", "event": "hazard_warning"},
	"CoolingDescent": {"message": "COOLING LOOP // DESCEND TO THE VAULT", "ambience": "cooling"},
	"CoreAscent": {"message": "CORE ASSEMBLY // VAULT AHEAD", "event": "objective_cue"},
	"VaultPerimeter": {"message": "VAULT PERIMETER // ASSEMBLY IN SIGHT", "event": "objective_cue"},
	"ModuleAcquisition": {"message": "ASSEMBLY CRADLE // ACCESS AHEAD", "event": "objective_cue"},
	"ReserveExit": {"message": "EXIT FACILITY // DELIVER ASSEMBLY", "ambience": "exterior"},
	"MissionConfirmation": {"message": "MISSION CONFIRMED // BEACON 9", "ambience": "exterior"},
	"RooftopCrossing": {"message": "ROOFTOP TRANSIT // BEACON MARKED", "event": "hazard_warning"},
	"TransitViaduct": {"message": "TRANSIT VIADUCT // ROUTE EXPOSED", "event": "hazard_warning"},
	"UtilityCanyon": {"message": "UTILITY CANYON // POWER ARC AHEAD", "ambience": "cooling"},
	"BeaconPerimeter": {"message": "BEACON 9 // APPROACHING THE INTERIOR", "ambience": "beacon_exterior"},
	"ExteriorAscent": {"message": "EXTERIOR ASSEMBLY // FINAL ASCENT", "event": "objective_cue"},
	"BeaconInterior": {"message": "BEACON INTERIOR // HAZARD FIELD CLEARED", "ambience": "beacon_interior"},
	"IgnitionChamber": {"message": "IGNITION CHAMBER // HOLD JUMP, RELEASE AT FULL", "event": "objective_cue"},
}

var _seen: Dictionary = {}

const IMPORTED_AREA_SUFFIX := " (Area)"

func bind_zones(root: Node) -> void:
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
	var cue: Dictionary = CUES.get(zone_name, {"message": "ROUTE EVENT // %s" % zone_name})
	RunUnitSession.record_playtest_event("story_zone", {"zone": zone_name})
	story_beat.emit(zone_name, cue.duplicate(true))

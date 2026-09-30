class_name RunUnitStoryZoneDirector
extends Node
## Binds Tiled-authored story zones to reusable presentation cues. Each area
## can emit once per route instance; a run reset and checkpoint retry do not
## replay an already-seen beat.

signal story_beat(zone_name: String, cue: Dictionary)

const CUES := {
	"TransferLine": {"message": "TRANSFER LINE // POWER IS OFFLINE"},
	"Collapse": {"message": "STRUCTURE SHIFT // KEEP MOVING"},
	"WarehouseReveal": {"message": "UNIT STORAGE // PRODUCTION HALTED"},
	"WarehouseTraversal": {"message": "TIMED HAZARD ZONE // WATCH THE CYCLE"},
	"ExteriorBreach": {"message": "EXTERIOR BREACH // ESCAPE ROUTE OPEN"},
	"FactoryExterior": {"message": "FACTORY CLEAR // SERVICE DISTRICT AHEAD"},
	"ServiceDistrict": {"message": "POWER FAULTS // WATCH THE WARNING PLATES"},
	"DepotSightline": {"message": "RESERVE DEPOT 03 // ASSEMBLY LOCATED"},
	"FacilityApproach": {"message": "FACILITY APPROACH // FAULT CYCLE ACTIVE"},
	"CoolingDescent": {"message": "COOLING LOOP // DESCEND TO THE VAULT"},
	"CoreAscent": {"message": "CORE ASSEMBLY // VAULT AHEAD"},
	"VaultPerimeter": {"message": "VAULT PERIMETER // ASSEMBLY IN SIGHT"},
	"ModuleAcquisition": {"message": "ASSEMBLY CRADLE // ACCESS AHEAD"},
	"ReserveExit": {"message": "EXIT FACILITY // DELIVER ASSEMBLY"},
	"MissionConfirmation": {"message": "MISSION CONFIRMED // BEACON 9"},
	"RooftopCrossing": {"message": "ROOFTOP TRANSIT // BEACON MARKED"},
	"TransitViaduct": {"message": "TRANSIT VIADUCT // ROUTE EXPOSED"},
	"UtilityCanyon": {"message": "UTILITY CANYON // POWER ARC AHEAD"},
	"BeaconPerimeter": {"message": "BEACON 9 // APPROACHING THE INTERIOR"},
	"ExteriorAscent": {"message": "EXTERIOR ASSEMBLY // FINAL ASCENT"},
	"BeaconInterior": {"message": "BEACON INTERIOR // HAZARD FIELD CLEARED"},
	"IgnitionChamber": {"message": "IGNITION CHAMBER // HOLD JUMP, RELEASE AT FULL"},
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

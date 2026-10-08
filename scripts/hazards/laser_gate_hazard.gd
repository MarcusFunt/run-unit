class_name RunUnitLaserGateHazard
extends RunUnitTimedHazard

const DANGER_GLOW: Color = Color(1.0, 0.16, 0.035, 0.46)
const DANGER_CORE: Color = Color(1.0, 0.22, 0.08, 1.0)

func _ready() -> void:
	super._ready()
	var beam_glow: Polygon2D = get_node_or_null("ActiveVisual/BeamGlow") as Polygon2D
	var beam_core: Polygon2D = get_node_or_null("ActiveVisual/BeamCore") as Polygon2D
	if beam_glow != null:
		beam_glow.color = DANGER_GLOW
	if beam_core != null:
		beam_core.color = DANGER_CORE

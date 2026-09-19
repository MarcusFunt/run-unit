class_name RunUnitLaserGateHazard
extends RunUnitTimedHazard

@export_range(0.05, 1.0, 0.05) var warning_seconds: float = 0.35

var _warning_visual: CanvasItem = null

func _ready() -> void:
	_warning_visual = get_node_or_null("WarningVisual") as CanvasItem
	super._ready()
	_update_warning_visual()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_warning_visual()

func reset_level_state() -> void:
	super.reset_level_state()
	if is_inside_tree():
		_update_warning_visual()

func _update_warning_visual() -> void:
	if _warning_visual == null:
		return
	var safe_cycle: float = maxf(cycle_seconds, 0.05)
	var safe_active: float = clampf(active_seconds, 0.0, safe_cycle)
	var phase: float = get_cycle_phase_seconds()
	var warning_start: float = maxf(safe_cycle - warning_seconds, safe_active)
	_warning_visual.visible = phase >= warning_start and phase >= safe_active

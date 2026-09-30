class_name RunUnitHazardArea
extends Area2D

enum HazardPhase { INACTIVE, WARNING, ACTIVE }

signal hazard_phase_changed(phase: int)

@export var active: bool = true
@export_range(1, 99, 1) var damage: int = 1
@export var lethal: bool = false
@export var knockback: Vector2 = Vector2.ZERO
@export_range(0.0, 2.0, 0.01) var hitstun_seconds: float = 0.0

var _exposed_body_ids: Dictionary = {}
var _authored_active: bool = true
var _hazard_phase: int = HazardPhase.ACTIVE

func _ready() -> void:
	_authored_active = active
	_hazard_phase = HazardPhase.ACTIVE if active else HazardPhase.INACTIVE
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_sync_active_visual()

func reset_level_state() -> void:
	_clear_exposures()
	set_active(_authored_active)

func set_active(value: bool) -> void:
	set_hazard_phase(HazardPhase.ACTIVE if value else HazardPhase.INACTIVE)

func get_hazard_phase() -> int:
	return _hazard_phase

func set_hazard_phase(value: int) -> void:
	var safe_phase: int = clampi(value, HazardPhase.INACTIVE, HazardPhase.ACTIVE)
	var changed: bool = _hazard_phase != safe_phase
	var was_active: bool = active
	_hazard_phase = safe_phase
	active = safe_phase == HazardPhase.ACTIVE
	if was_active != active:
		_clear_exposures()
	_sync_active_visual()
	if active and not was_active and is_inside_tree():
		for body: Node2D in get_overlapping_bodies():
			_attempt_hit(body)
	if changed:
		hazard_phase_changed.emit(_hazard_phase)

func _on_body_entered(body: Node2D) -> void:
	if active:
		_attempt_hit(body)

func _on_body_exited(body: Node2D) -> void:
	_exposed_body_ids.erase(body.get_instance_id())

func _attempt_hit(body: Node2D) -> void:
	var health: RunUnitPlayerHealth = body.get_node_or_null("Health") as RunUnitPlayerHealth
	if health == null:
		return

	var body_id: int = body.get_instance_id()
	if _exposed_body_ids.has(body_id):
		return
	_exposed_body_ids[body_id] = true

	var accepted: bool = health.damage(damage, lethal)
	if not accepted:
		return
	if body.has_method("apply_knockback") and (knockback != Vector2.ZERO or hitstun_seconds > 0.0):
		body.call("apply_knockback", knockback, hitstun_seconds)

func _clear_exposures() -> void:
	_exposed_body_ids.clear()

func _sync_active_visual() -> void:
	var active_visual: CanvasItem = get_node_or_null("ActiveVisual") as CanvasItem
	if active_visual != null:
		active_visual.visible = active
	var warning_visual: CanvasItem = get_node_or_null("WarningVisual") as CanvasItem
	if warning_visual != null:
		warning_visual.visible = _hazard_phase == HazardPhase.WARNING
	var warning_stripe: CanvasItem = get_node_or_null("WarningStripe") as CanvasItem
	if warning_stripe != null:
		warning_stripe.modulate.a = 1.0 if _hazard_phase == HazardPhase.WARNING else 0.42

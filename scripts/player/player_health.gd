class_name RunUnitPlayerHealth
extends Node

signal damaged(current_health: int, max_health: int)
signal depleted

@export_range(1, 20, 1) var max_health: int = 3
@export_range(0.0, 3.0, 0.05) var invulnerability_seconds: float = 0.75

var current_health: int = 3
var _invulnerability_remaining: float = 0.0

func _ready() -> void:
	current_health = max_health

func _physics_process(delta: float) -> void:
	_invulnerability_remaining = maxf(_invulnerability_remaining - delta, 0.0)

func damage(amount: int = 1, lethal: bool = false) -> bool:
	if current_health <= 0:
		return false
	if not lethal and _invulnerability_remaining > 0.0:
		return false

	if lethal:
		current_health = 0
	else:
		var applied_amount: int = maxi(amount, 0)
		if applied_amount <= 0:
			return false
		current_health = maxi(current_health - applied_amount, 0)
		_invulnerability_remaining = invulnerability_seconds

	damaged.emit(current_health, max_health)
	if current_health <= 0:
		depleted.emit()
	return true

func reset_health() -> void:
	current_health = max_health
	_invulnerability_remaining = 0.0

func is_invulnerable() -> bool:
	return _invulnerability_remaining > 0.0

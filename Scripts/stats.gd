extends Resource
class_name Stats

enum StatScaling {
	MAX_HEALTH,
	DEFENSE,
	ATTACK,
	POISE,
	INTELLIGENCE,
	STAMINA,
	FOCUS,
}

const STAT_CURVES: Dictionary[StatScaling, Curve] = {
	StatScaling.MAX_HEALTH: preload("uid://db5pg2wpcsnsk"),
	StatScaling.DEFENSE: preload("uid://ctvgbjw58b6lw"),
	StatScaling.ATTACK: preload("uid://c7a5433c88af8"),
	StatScaling.POISE: preload("uid://6kqpjlxokse7"),
	StatScaling.INTELLIGENCE: preload("uid://cwr64ug1tdolb"),
	StatScaling.STAMINA: preload("uid://by4hsg8fygtxf"),
	StatScaling.FOCUS: preload("uid://cpqlplu55nqoc"),
}

const BASE_LEVEL_XP: float = 100.0

signal health_depleted
signal health_changed(cur_health: float, max_health: float)
signal level_changed(old_level: int, new_level: int)

@export var max_level: int = 60

@export var USE_MASTERY: bool = true
@export var mastery_max: int = 5
@export var mastery_unarmed: int = 0
@export var mastery_innerorbit: int = 0
@export var mastery_midorbit: int = 0
@export var mastery_outerorbit: int = 0
@export var mastery_bonus_per_level: float = 0.01

@export_group("Damage Scaling Coefficients")
@export var coeff_main: float = 0.010
@export var coeff_minor: float = 0.006

@export var base_max_health: float = 100.0
@export var base_defense: float = 10.0
@export var base_attack: float = 10.0
@export var base_poise: float = 5.0
@export var base_intelligence: float = 5.0
@export var base_stamina: float = 10.0
@export var base_focus: float = 10.0

@export var experience: float = 0.0: set = _on_experience_set

var level: float:
	get():
		var lv: float = floor(max(1.0, sqrt(maxf(0.0, experience) / BASE_LEVEL_XP) + 0.5))
		return clampf(lv, 1.0, float(max_level))

var current_max_health: float = 100.0
var current_defense: float = 10.0
var current_attack: float = 10.0
var current_poise: float = 5.0
var current_intelligence: float = 5.0
var current_stamina: float = 10.0
var current_focus: float = 10.0

var current_health: float = 0.0: set = _on_health_set

func _init() -> void:
	recalculate_stats()
	current_health = current_max_health

func setup_stats() -> void:
	recalculate_stats()
	current_health = current_max_health

func recalculate_stats() -> void:
	var t: float = 0.0
	if max_level > 1:
		t = (float(level) - 1.0) / float(max_level - 1)
	t = clampf(t, 0.0, 1.0)

	var old_max: float = current_max_health
	var old_hp: float = current_health

	current_max_health = base_max_health * _curve(StatScaling.MAX_HEALTH, t)
	current_defense = base_defense * _curve(StatScaling.DEFENSE, t)
	current_attack = base_attack * _curve(StatScaling.ATTACK, t)
	current_poise = base_poise * _curve(StatScaling.POISE, t)
	current_intelligence = base_intelligence * _curve(StatScaling.INTELLIGENCE, t)
	current_stamina = base_stamina * _curve(StatScaling.STAMINA, t)
	current_focus = base_focus * _curve(StatScaling.FOCUS, t)

	current_health = clampf(old_hp + (current_max_health - old_max), 0.0, current_max_health)
	health_changed.emit(current_health, current_max_health)

func _curve(stat: StatScaling, t: float) -> float:
	var c: Curve = STAT_CURVES.get(stat, null)
	return 1.0 if c == null else maxf(0.0, c.sample(t))

func _on_health_set(new_value: float) -> void:
	current_health = clampf(new_value, 0.0, current_max_health)
	health_changed.emit(current_health, current_max_health)
	if current_health <= 0.0:
		health_depleted.emit()

func _on_experience_set(new_value: float) -> void:
	var old_level: int = int(level)
	experience = maxf(0.0, new_value)
	var new_level: int = int(level)

	if old_level != new_level:
		recalculate_stats()
		level_changed.emit(old_level, new_level)

func softcap_points(stat_value: float) -> float:
	var s: float = clampf(stat_value, 1.0, 99.0)
	if s <= 20.0:
		return s
	if s <= 40.0:
		return 20.0 + (s - 20.0) * 0.6
	if s <= 60.0:
		return 20.0 + 20.0 * 0.6 + (s - 40.0) * 0.3
	return 20.0 + 20.0 * 0.6 + 20.0 * 0.3 + (s - 60.0) * 0.15

func compute_attack_rating(attack_type: int, base_damage: int) -> float:
	var main_stat: float
	var minor_stat: float

	match attack_type:
		0:
			main_stat = current_attack
			minor_stat = current_poise
		2:
			main_stat = current_focus
			minor_stat = current_attack
		3:
			main_stat = current_intelligence
			minor_stat = current_focus
		_:
			main_stat = current_attack
			minor_stat = current_stamina

	var main_scale: float = softcap_points(main_stat) * coeff_main
	var minor_scale: float = softcap_points(minor_stat) * coeff_minor
	var mastery_scale: float = float(_get_mastery_for_type(attack_type)) * mastery_bonus_per_level if USE_MASTERY else 0.0

	return maxf(1.0, float(base_damage) * (1.0 + main_scale + minor_scale + mastery_scale))

func _get_mastery_for_type(attack_type: int) -> int:
	match attack_type:
		0: return clampi(mastery_unarmed, 0, mastery_max)
		1: return clampi(mastery_innerorbit, 0, mastery_max)
		2: return clampi(mastery_midorbit, 0, mastery_max)
		3: return clampi(mastery_outerorbit, 0, mastery_max)
	return 0

func add_mastery(attack_type: int, amount: int) -> void:
	if not USE_MASTERY:
		return
	amount = maxi(0, amount)
	if amount == 0:
		return

	match attack_type:
		0: mastery_unarmed = clampi(mastery_unarmed + amount, 0, mastery_max)
		1: mastery_innerorbit = clampi(mastery_innerorbit + amount, 0, mastery_max)
		2: mastery_midorbit = clampi(mastery_midorbit + amount, 0, mastery_max)
		3: mastery_outerorbit = clampi(mastery_outerorbit + amount, 0, mastery_max)

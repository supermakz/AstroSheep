extends Resource
class_name Stats

# ASSUMPTIONS:
# - Deine "experience -> level" Logik bleibt bestehen (minimal invasiv),
#   ABER wir implementieren Softcaps und Damage-Scaling über die existierenden Stats.
# - Level “soft-locked” (Sekiro-ish): clamp via max_level (Inspector).
# - Mastery ist optional (USE_MASTERY) und unabhängig von experience.

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
signal level_changed(old_level: int, new_level: int) # ADDED:

# ADDED: soft lock
@export var max_level: int = 60 # ADDED: Sekiro-ish clear limit

# -----------------------------
# OPTIONAL: Mastery / Proficiency
# -----------------------------
@export var USE_MASTERY: bool = true # ADDED:
@export var mastery_max: int = 10 # ADDED:

# Mastery per AttackType (matches AttackSystem.AttackType order)
@export var mastery_unarmed: int = 0 # ADDED:
@export var mastery_innerorbit: int = 0 # ADDED:
@export var mastery_midorbit: int = 0 # ADDED:
@export var mastery_outerorbit: int = 0 # ADDED:

# Mastery bonus tuning
@export var mastery_bonus_per_level: float = 0.015 # ADDED: +1.5% AR per mastery level

# -----------------------------

# Damage scaling tuning (AAA tweakables)
@export_group("Damage Scaling Coefficients")
@export var coeff_main: float = 0.010 # ADDED:
@export var coeff_minor: float = 0.006 # ADDED:

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
		# CHANGED: fully typed expression, no Variant-returning min()
		var xp: float = float(experience) # CHANGED:
		var base_xp: float = float(BASE_LEVEL_XP) # CHANGED:
		var raw: float = sqrt(xp / base_xp) + 0.5 # CHANGED:
		var lv: float = floor(max(1.0, raw)) # CHANGED:
		var cap: float = float(max_level) # CHANGED:
		return clampf(lv, 1.0, cap)

var current_max_health: float = 100.0
var current_defense: float = 10.0
var current_attack: float = 10.0
var current_poise: float = 5.0
var current_intelligence: float = 5.0
var current_stamina: float = 10.0
var current_focus: float = 10.0

var current_health: float = 0.0: set = _on_health_set

func _init() -> void:
	# CHANGED: deterministic init (no deferred needed)
	recalculate_stats()
	current_health = current_max_health

func setup_stats() -> void:
	# CHANGED: keep for compatibility
	recalculate_stats()
	current_health = current_max_health

func recalculate_stats() -> void:
	# CHANGED: safe curve sampling 0..1
	var lv: float = float(level)
	var t: float = (lv - 1.0) / float(max(1, max_level - 1)) # ADDED: scale to max_level
	t = clampf(t, 0.0, 1.0)

	var old_max: float = current_max_health
	var old_hp: float = current_health

	current_max_health = base_max_health * _sample_curve(StatScaling.MAX_HEALTH, t) # CHANGED:
	current_defense = base_defense * _sample_curve(StatScaling.DEFENSE, t) # CHANGED:
	current_attack = base_attack * _sample_curve(StatScaling.ATTACK, t) # CHANGED:
	current_poise = base_poise * _sample_curve(StatScaling.POISE, t) # CHANGED:
	current_intelligence = base_intelligence * _sample_curve(StatScaling.INTELLIGENCE, t) # CHANGED:
	current_stamina = base_stamina * _sample_curve(StatScaling.STAMINA, t) # CHANGED:
	current_focus = base_focus * _sample_curve(StatScaling.FOCUS, t) # CHANGED:

	# CHANGED: preserve HP feel on max HP changes
	var delta: float = current_max_health - old_max
	if delta > 0.0:
		current_health = old_hp + delta
	else:
		current_health = old_hp

	current_health = clampf(current_health, 0.0, current_max_health)
	health_changed.emit(current_health, current_max_health) # ADDED:

func _sample_curve(stat: StatScaling, t: float) -> float: # ADDED:
	var c: Curve = STAT_CURVES.get(stat, null)
	if c == null:
		return 1.0
	return max(0.0, c.sample(clampf(t, 0.0, 1.0)))

func _on_health_set(new_value: float) -> void:
	# CHANGED: float-safe clamp
	current_health = clampf(new_value, 0.0, current_max_health)
	health_changed.emit(current_health, current_max_health) # ADDED:
	if current_health <= 0.0:
		health_depleted.emit()

func _on_experience_set(new_value: float) -> void:
	var old_level: int = int(level) # CHANGED:
	experience = maxf(0.0, new_value) # CHANGED:
	var new_level: int = int(level) # ADDED:

	if old_level != new_level: # CHANGED:
		recalculate_stats()
		level_changed.emit(old_level, new_level) # ADDED:

# -----------------------------------------------------------
# ADDED: Souls-like softcaps (exact piecewise spec from you)
# -----------------------------------------------------------
func softcap_points(stat_value: float) -> float: # ADDED:
	# We interpret stat_value as "points-like" (your current_* floats).
	# Clamp to keep tuning stable.
	var s: float = clampf(stat_value, 1.0, 99.0)

	var p: float = 0.0
	# 1–20: 1.0 per point
	var a: float = minf(s, 20.0)
	p += a * 1.0
	if s <= 20.0:
		return p

	# 21–40: 0.6 per point
	var b: float = minf(s, 40.0) - 20.0
	p += b * 0.6
	if s <= 40.0:
		return p

	# 41–60: 0.3 per point
	var c: float = minf(s, 60.0) - 40.0
	p += c * 0.3
	if s <= 60.0:
		return p

	# 61+: 0.15 per point
	var d: float = s - 60.0
	p += d * 0.15
	return p

# -----------------------------------------------------------
# ADDED: Damage API for AttackSystem (minimal invasive)
# Scaling mapping (as requested):
# - Unarmed: Main = ATTACK, Minor = POISE
# - Inner/Melee Orbit: Main = ATTACK, Minor = STAMINA
# - Midrange Orbit: Main = FOCUS, Minor = ATTACK
# - OuterOrbit: Main = INTELLIGENCE, Minor = FOCUS
# -----------------------------------------------------------
func compute_attack_rating(attack_type: int, base_damage: int) -> float: # ADDED:
	var main_stat: float = 0.0
	var minor_stat: float = 0.0

	match attack_type:
		0: # UNARMED
			main_stat = current_attack
			minor_stat = current_poise
		1: # INNERORBIT (melee)
			main_stat = current_attack
			minor_stat = current_stamina
		2: # MIDORBIT (midrange)
			main_stat = current_focus
			minor_stat = current_attack
		3: # OUTERORBIT (ranged/cc)
			main_stat = current_intelligence
			minor_stat = current_focus
		_:
			main_stat = current_attack
			minor_stat = current_stamina

	var main_pts: float = softcap_points(main_stat)
	var minor_pts: float = softcap_points(minor_stat)

	var main_scale: float = main_pts * coeff_main
	var minor_scale: float = minor_pts * coeff_minor

	var mastery_scale: float = 0.0
	if USE_MASTERY:
		mastery_scale = float(_get_mastery_for_type(attack_type)) * mastery_bonus_per_level

	# AR_type = BaseDamage * (1 + MainScale + MinorScale [+ mastery])
	var ar: float = float(base_damage) * (1.0 + main_scale + minor_scale + mastery_scale)
	return maxf(1.0, ar)

func _get_mastery_for_type(attack_type: int) -> int: # ADDED:
	match attack_type:
		0:
			return clampi(mastery_unarmed, 0, mastery_max)
		1:
			return clampi(mastery_innerorbit, 0, mastery_max)
		2:
			return clampi(mastery_midorbit, 0, mastery_max)
		3:
			return clampi(mastery_outerorbit, 0, mastery_max)
	return 0

func add_mastery(attack_type: int, amount: int) -> void: # ADDED:
	# Sekiro-ish progression hook. Call from gameplay events, NOT via stat points.
	if not USE_MASTERY:
		return
	amount = maxi(0, amount)
	match attack_type:
		0:
			mastery_unarmed = clampi(mastery_unarmed + amount, 0, mastery_max)
		1:
			mastery_innerorbit = clampi(mastery_innerorbit + amount, 0, mastery_max)
		2:
			mastery_midorbit = clampi(mastery_midorbit + amount, 0, mastery_max)
		3:
			mastery_outerorbit = clampi(mastery_outerorbit + amount, 0, mastery_max)

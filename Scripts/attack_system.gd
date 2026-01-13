class_name AttackSystem
extends Node2D

# ASSUMPTIONS:
# - Input/Control für AttackType-Swap wird im PlayerController gehandhabt.
# - "take_damage(amount, from_position)" bleibt Enemy-API (du nutzt das bereits).
# - Animationen können (müssen aber nicht) pro AttackType existieren:
#   attack_unarmed1..n, attack_innerorbit1..n, attack_midorbit1..n, attack_outerorbit1..n
#   Falls nicht vorhanden -> Fallback auf attack_innerorbit.

signal attack_started
signal attack_finished
# ADDED: Hit hook für Style/Power/TargetSwap-System (keine harte Coupling)
signal attack_hit(target_id: int, attack_type: AttackType, final_damage: int)

enum AttackType { UNARMED, INNERORBIT, MIDORBIT, OUTERORBIT }

@onready var combo_timer: Timer = $ComboTimer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var effect_sprite: Node2D = $EffectSprite

# CHANGED: Base damages pro AttackType (AAA tuning, kein Magic)
@export var base_damage_unarmed: int = 8 # ADDED:
@export var base_damage_innerorbit: int = 10 # ADDED:
@export var base_damage_midorbit: int = 9 # ADDED:
@export var base_damage_outerorbit: int = 7 # ADDED:

# ADDED: Motion values pro ComboStep (Soulslike tuning)
@export var motion_values: Array[float] = [1.00, 1.05, 1.10, 1.20]

# ADDED: Stats ref (Resource). Wird vom PlayerController gesetzt.
@export var stats: Stats # ADDED:

# ADDED: Wird vom PlayerController gespeist (Style/Power multiplier)
var power_multiplier: float = 1.0 # ADDED:
var hitbox_active: bool = false
var combo_requested: bool = false
var current_facing: Vector2 = Vector2.DOWN
var current_attack_type: AttackType = AttackType.INNERORBIT
var combo_step: int = 0
var can_attack: bool = true

func _ready() -> void:
	set_melee_hitbox_active(false) # CHANGED: hard-disable incl. flag + collisionshape
	melee_hitbox.monitoring = false
	combo_timer.timeout.connect(_on_combo_timeout)

	# ADDED: ensure signals are connected (Editor connections can fail silently)
	if not animation_player.animation_finished.is_connected(_on_animation_player_animation_finished): # ADDED:
		animation_player.animation_finished.connect(_on_animation_player_animation_finished) # ADDED:

	if not melee_hitbox.area_entered.is_connected(_on_melee_hitbox_area_entered):
		melee_hitbox.area_entered.connect(_on_melee_hitbox_area_entered)

func request_attack(facing_dir: Vector2) -> void:
	if not can_attack:
		combo_requested = true
		return

	if facing_dir != Vector2.ZERO:
		rotation = facing_dir.angle() + (PI / 2.0)

	current_facing = facing_dir
	can_attack = false
	emit_signal("attack_started")

	_play_combo_animation()

func _play_combo_animation() -> void:
	# CHANGED: Anim prefix abhängig vom AttackType, fallback innerorbit
	var prefix: String = _get_anim_prefix() # ADDED:
	var anim_name: String = "%s%d" % [prefix, (combo_step + 1)] # CHANGED:

	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
	else:
		# CHANGED: Fallback, um nicht zu “breaken”, wenn neue Animations fehlen
		var fallback: String = "attack_innerorbit%d" % (combo_step + 1)
		if animation_player.has_animation(fallback):
			animation_player.play(fallback)
		else:
			push_warning("Missing Combo Animation: %s (fallback also missing: %s)" % [anim_name, fallback])

	combo_timer.start()

func _get_anim_prefix() -> String: # ADDED:
	match current_attack_type:
		AttackType.UNARMED:
			return "attack_unarmed"
		AttackType.INNERORBIT:
			return "attack_innerorbit"
		AttackType.MIDORBIT:
			return "attack_midorbit"
		AttackType.OUTERORBIT:
			return "attack_outerorbit"
	return "attack_innerorbit"

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	# CHANGED: akzeptiere alle attack_* prefixes
	if anim_name.begins_with("attack_"):
		combo_step += 1

		if combo_step >= 4:
			combo_step = 0

		can_attack = true

		set_melee_hitbox_active(false)

		emit_signal("attack_finished")
		if combo_requested:
			combo_requested = false
			request_attack(current_facing)

func _on_combo_timeout() -> void:
	combo_step = 0
	set_melee_hitbox_active(false)
	
# Wird per AnimationPlayer (Call Method Track) aufgerufen
func set_melee_hitbox_active(active: bool) -> void:
	hitbox_active = active # ADDED: critical gate
	melee_hitbox.monitoring = active
	$MeleeHitbox/CollisionShape2D.set_deferred("disabled", !active)

func _on_melee_hitbox_area_entered(area: Area2D) -> void:
	if not hitbox_active: # ADDED: prevents “running into enemy = hit”
		return
	var target: Node = area.get_parent() # Da Hitbox direkt unter Enemy liegt
	if target and target.has_method("take_damage"):
		# CHANGED: Damage Pipeline (Souls scaling + motion + power)
		var base_damage: int = _get_base_damage_for_type(current_attack_type) # ADDED:
		var motion: float = _get_motion_value() # ADDED:
		var attack_rating: float = float(base_damage)

		# ADDED: Stats-driven attack rating
		if stats != null and stats.has_method("compute_attack_rating"):
			attack_rating = stats.compute_attack_rating(current_attack_type, base_damage)

		var final_damage_f: float = attack_rating * motion * maxf(0.0, power_multiplier) # CHANGED:
		var final_damage: int = int(max(1.0, round(final_damage_f))) # ADDED: never 0 dmg

		target.take_damage(final_damage, global_position)
		emit_signal("attack_hit", target.get_instance_id(), current_attack_type, final_damage) # ADDED:

func _get_base_damage_for_type(t: AttackType) -> int: # ADDED:
	match t:
		AttackType.UNARMED:
			return base_damage_unarmed
		AttackType.INNERORBIT:
			return base_damage_innerorbit
		AttackType.MIDORBIT:
			return base_damage_midorbit
		AttackType.OUTERORBIT:
			return base_damage_outerorbit
	return base_damage_innerorbit

func _get_motion_value() -> float: # ADDED:
	if motion_values.is_empty():
		return 1.0
	var idx: int = clampi(combo_step, 0, motion_values.size() - 1)
	return float(motion_values[idx])

func set_attack_type(type: AttackType) -> void:
	current_attack_type = type
	combo_step = 0

func set_power_multiplier(value: float) -> void: # ADDED:
	power_multiplier = clampf(value, 0.0, 10.0)

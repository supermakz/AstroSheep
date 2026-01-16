class_name AttackSystem
extends Node2D

# ASSUMPTIONS:
# - Input/Control für AttackType-Swap wird im PlayerController gehandhabt.
# - "take_damage(amount, from_position)" bleibt Enemy-API.
# - Animationen existieren pro AttackType: attack_unarmed1..n, attack_innerorbit1..n, attack_midorbit1..n, attack_outerorbit1..n
# - Kein Fallback: Fehlende Animations -> Angriff wird sauber abgebrochen.

signal attack_started
signal attack_finished
signal attack_hit(target_id: int, attack_type: AttackType, final_damage: int)

# ADDED: fired ONLY when an attack actually begins (animation started)
signal attack_committed

# ADDED: fired when a combo fully completes (used by your swap->combo reward)
signal combo_completed(attack_type: AttackType)

enum AttackType { UNARMED, INNERORBIT, MIDORBIT, OUTERORBIT }

@onready var combo_timer: Timer = $ComboTimer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var effect_sprite: Node2D = $EffectSprite

# Base damages pro AttackType
@export var base_damage_unarmed: int = 8
@export var base_damage_innerorbit: int = 10
@export var base_damage_midorbit: int = 9
@export var base_damage_outerorbit: int = 7

@export var motion_values: Array[float] = [1.00, 1.05, 1.10, 1.20]
@export var stats: Stats

@export_group("Combo")
@export var combo_max_unarmed: int = 3
@export var combo_max_innerorbit: int = 4
@export var combo_max_midorbit: int = 2
@export var combo_max_outerorbit: int = 1

@export_group("Cooldown After Combo")
@export var combo_cooldown_unarmed: float = 0.15
@export var combo_cooldown_innerorbit: float = 0.60
@export var combo_cooldown_midorbit: float = 3.50
@export var combo_cooldown_outerorbit: float = 7.00

@export_group("Input Timing")
@export var allow_input_buffer: bool = true
@export var input_buffer_window_sec: float = 0.12
@export var input_buffer_max_age_sec: float = 0.18

@export_group("Debug")
@export var debug_attack_type_print: bool = true

# Runtime
var power_multiplier: float = 1.0
var hitbox_active: bool = false
var current_facing: Vector2 = Vector2.DOWN
var current_attack_type: AttackType = AttackType.INNERORBIT
var combo_step: int = 0
var can_attack: bool = true

# Input buffer (single-slot)
var buffered_attack: bool = false
var buffered_attack_time: float = -999.0
var last_anim_start_time: float = -999.0
var current_anim_length: float = 0.0

# Combo timer doubles as cooldown timer
enum ComboTimerMode { COMBO_RESET, COOLDOWN }
var combo_timer_mode: ComboTimerMode = ComboTimerMode.COMBO_RESET

func _ready() -> void:
	set_melee_hitbox_active(false)
	melee_hitbox.monitoring = false
	combo_timer.timeout.connect(_on_combo_timeout)

	if not animation_player.animation_finished.is_connected(_on_animation_player_animation_finished):
		animation_player.animation_finished.connect(_on_animation_player_animation_finished)

	if not melee_hitbox.area_entered.is_connected(_on_melee_hitbox_area_entered):
		melee_hitbox.area_entered.connect(_on_melee_hitbox_area_entered)

func request_attack(facing_dir: Vector2) -> void:
	if not can_attack:
		_try_buffer_attack()
		return

	if facing_dir != Vector2.ZERO:
		rotation = facing_dir.angle() + (PI / 2.0)

	current_facing = facing_dir

	# CHANGED: only commit state/emit start when we actually start an animation
	if _play_combo_animation():
		attack_started.emit()
		attack_committed.emit()

func _try_buffer_attack() -> void:
	if not allow_input_buffer or buffered_attack:
		return
	if current_anim_length <= 0.0:
		return

	var t: float = _now_sec()
	var remaining: float = current_anim_length - (t - last_anim_start_time)
	if remaining <= input_buffer_window_sec:
		buffered_attack = true
		buffered_attack_time = t

func _play_combo_animation() -> bool:
	var anim_name: String = "%s%d" % [_get_anim_prefix(), (combo_step + 1)]

	if not animation_player.has_animation(anim_name):
		push_warning("Missing Combo Animation (no fallback): %s" % anim_name)
		# CHANGED: do NOT emit attack_finished here; attack never started.
		can_attack = true
		buffered_attack = false
		set_melee_hitbox_active(false)
		return false

	# CHANGED: lock only when we really start
	can_attack = false
	animation_player.play(anim_name)

	# track timing for input buffer window
	last_anim_start_time = _now_sec()
	current_anim_length = animation_player.get_animation(anim_name).length

	# watchdog reset timer
	combo_timer_mode = ComboTimerMode.COMBO_RESET
	combo_timer.start()
	return true

func _get_anim_prefix() -> String:
	match current_attack_type:
		AttackType.UNARMED: return "attack_unarmed"
		AttackType.INNERORBIT: return "attack_innerorbit"
		AttackType.MIDORBIT: return "attack_midorbit"
		AttackType.OUTERORBIT: return "attack_outerorbit"
	return "attack_innerorbit"

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if not anim_name.begins_with("attack_"):
		return

	set_melee_hitbox_active(false)

	combo_step += 1
	var max_steps: int = _get_combo_max_steps()

	if combo_step >= max_steps:
		# combo end -> reset + cooldown lockout
		combo_step = 0
		buffered_attack = false

		# ADDED: combo completed event (your Player expects it)
		combo_completed.emit(current_attack_type)

		attack_finished.emit()

		var cd: float = _get_combo_cooldown()
		if cd > 0.0:
			can_attack = false
			combo_timer_mode = ComboTimerMode.COOLDOWN
			combo_timer.start(cd)
		else:
			can_attack = true
		return

	# continue combo
	can_attack = true
	attack_finished.emit()

	_consume_buffered_attack()

func _consume_buffered_attack() -> void:
	if not buffered_attack:
		return
	var age: float = _now_sec() - buffered_attack_time
	buffered_attack = false
	if age <= input_buffer_max_age_sec:
		request_attack(current_facing)

func _on_combo_timeout() -> void:
	set_melee_hitbox_active(false)

	if combo_timer_mode == ComboTimerMode.COOLDOWN:
		can_attack = true
		return

	# combo reset watchdog
	combo_step = 0
	buffered_attack = false

# Wird per AnimationPlayer (Call Method Track) aufgerufen
func set_melee_hitbox_active(active: bool) -> void:
	hitbox_active = active
	melee_hitbox.monitoring = active
	$MeleeHitbox/CollisionShape2D.set_deferred("disabled", !active)

func _on_melee_hitbox_area_entered(area: Area2D) -> void:
	if not hitbox_active:
		return

	var target: Node = area.get_parent()
	if not (target and target.has_method("take_damage")):
		return

	var base_damage: int = _get_base_damage_for_type(current_attack_type)
	var motion: float = _get_motion_value()
	var attack_rating: float = float(base_damage)

	if stats != null and stats.has_method("compute_attack_rating"):
		attack_rating = stats.compute_attack_rating(current_attack_type, base_damage)

	var final_damage: int = int(max(1.0, round(attack_rating * motion * maxf(0.0, power_multiplier))))
	target.take_damage(final_damage, global_position)
	attack_hit.emit(target.get_instance_id(), current_attack_type, final_damage)

func _get_base_damage_for_type(t: AttackType) -> int:
	match t:
		AttackType.UNARMED: return base_damage_unarmed
		AttackType.INNERORBIT: return base_damage_innerorbit
		AttackType.MIDORBIT: return base_damage_midorbit
		AttackType.OUTERORBIT: return base_damage_outerorbit
	return base_damage_innerorbit

func _get_motion_value() -> float:
	if motion_values.is_empty():
		return 1.0
	return float(motion_values[clampi(combo_step, 0, motion_values.size() - 1)])

func _get_combo_max_steps() -> int:
	match current_attack_type:
		AttackType.UNARMED: return max(1, combo_max_unarmed)
		AttackType.INNERORBIT: return max(1, combo_max_innerorbit)
		AttackType.MIDORBIT: return max(1, combo_max_midorbit)
		AttackType.OUTERORBIT: return max(1, combo_max_outerorbit)
	return 4

func _get_combo_cooldown() -> float:
	match current_attack_type:
		AttackType.UNARMED: return maxf(0.0, combo_cooldown_unarmed)
		AttackType.INNERORBIT: return maxf(0.0, combo_cooldown_innerorbit)
		AttackType.MIDORBIT: return maxf(0.0, combo_cooldown_midorbit)
		AttackType.OUTERORBIT: return maxf(0.0, combo_cooldown_outerorbit)
	return 0.0

func set_attack_type(type: AttackType) -> void:
	current_attack_type = type
	combo_step = 0
	buffered_attack = false
	set_melee_hitbox_active(false)

	if debug_attack_type_print:
		print("[AttackSystem] AttackType:", _attack_type_to_string(current_attack_type))

func set_power_multiplier(value: float) -> void:
	power_multiplier = clampf(value, 0.0, 10.0)

func _attack_type_to_string(t: AttackType) -> String:
	match t:
		AttackType.UNARMED: return "UNARMED"
		AttackType.INNERORBIT: return "INNERORBIT"
		AttackType.MIDORBIT: return "MIDORBIT"
		AttackType.OUTERORBIT: return "OUTERORBIT"
	return "UNKNOWN"

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

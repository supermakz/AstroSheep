extends Node
class_name FoxAI

@export var target_path: NodePath
@export var moveset_path: NodePath = NodePath("Fox_Moveset")

@onready var enemy: EnemyBase = get_parent().get_parent() as EnemyBase
@onready var moveset: Fox_Moveset = get_node_or_null(moveset_path) as Fox_Moveset
@onready var target: Node2D = _resolve_target()

@export_group("Awareness")
@export var aggro_range: float = 220.0
@export var disengage_range: float = 320.0
@export var tick_rate_hz: float = 10.0

@export_group("Movement")
@export var move_speed: float = 95.0
@export var approach_speed_mult: float = 1.15
@export var strafe_speed_mult: float = 0.85
@export var desired_range: float = 78.0
@export var range_tolerance: float = 18.0
@export var circle_bias: float = 0.85
@export var circle_dir_change_min: float = 1.1
@export var circle_dir_change_max: float = 2.6
@export var min_personal_space: float = 36.0 # hard push-out radius so we never "face-stick"

@export_group("Attack Windows")
@export var scratch_range: float = 70.0
@export var pounce_min_range: float = 110.0
@export var pounce_max_range: float = 210.0
@export var attack_cooldown: float = 1.1
@export var pounce_bonus_cd: float = 0.35
@export var attack_chance: float = 0.55

@export_group("Recovery / Reposition")
@export var post_attack_reposition_time: float = 0.55

# NEW: during windup we are allowed to close distance slightly (commitment feel)
@export_group("Attack Approach")
@export var windup_close_time: float = 0.18
@export var windup_close_speed_mult: float = 0.65

enum AIState { IDLE, ENGAGE, STRAFE, ATTACK, RECOVER }
var state: AIState = AIState.IDLE

var _tick_accum := 0.0
var _next_circle_flip_t := 0.0
var _circle_sign := 1.0
var _attack_cd := 0.0
var _state_timer := 0.0

# NEW: prevent instant pounce on spawn and allow controlled windup approach
var _alive_time := 0.0
var _windup_close_timer := 0.0

func _ready() -> void:
	_schedule_circle_flip()

func _physics_process(delta: float) -> void:
	if enemy == null or enemy.dead:
		return

	_alive_time += delta

	if moveset == null:
		push_error("FoxAI: Missing Fox_Moveset node at path '%s'." % [str(moveset_path)])
		enemy.velocity = Vector2.ZERO
		return

	if target == null:
		target = _resolve_target()
		if target == null:
			enemy.velocity = Vector2.ZERO
			return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_state_timer = maxf(0.0, _state_timer - delta)
	_windup_close_timer = maxf(0.0, _windup_close_timer - delta)

	_tick_accum += delta
	var tick_interval := 1.0 / maxf(1.0, tick_rate_hz)
	if _tick_accum >= tick_interval:
		_tick_accum = 0.0
		_ai_tick()

	_apply_movement()

func _ai_tick() -> void:
	var to_t := target.global_position - enemy.global_position
	var dist := to_t.length()

	match state:
		AIState.IDLE:
			if dist <= aggro_range:
				state = AIState.ENGAGE

		AIState.ENGAGE:
			if dist > disengage_range:
				state = AIState.IDLE
				return
			if absf(dist - desired_range) <= range_tolerance:
				state = AIState.STRAFE

		AIState.STRAFE:
			if dist > disengage_range:
				state = AIState.IDLE
				return
			if absf(dist - desired_range) > range_tolerance * 1.6:
				state = AIState.ENGAGE
				return

			_maybe_flip_circle()

			if _attack_cd <= 0.0 and not moveset.is_busy():
				_try_attack(to_t, dist)

		AIState.ATTACK:
			if _state_timer <= 0.0 and not moveset.is_busy():
				state = AIState.RECOVER
				_state_timer = post_attack_reposition_time

		AIState.RECOVER:
			if _state_timer <= 0.0:
				state = AIState.STRAFE if dist <= desired_range + range_tolerance else AIState.ENGAGE

func _try_attack(to_t: Vector2, dist: float) -> void:
	if randf() > attack_chance:
		return

	var dir := to_t.normalized()

	# Close-range scratch
	if dist <= scratch_range:
		state = AIState.ATTACK
		_state_timer = 0.2
		_attack_cd = attack_cooldown
		_windup_close_timer = windup_close_time # NEW: allow brief close-in during windup
		moveset.scratch(dir)
		return

	# Pounce ONLY in STRAFE state (and avoid instant pounce right after spawn)
	if state == AIState.STRAFE and _alive_time > 0.9:
		if dist >= pounce_min_range and dist <= pounce_max_range:
			state = AIState.ATTACK
			_state_timer = 0.25
			_attack_cd = attack_cooldown + pounce_bonus_cd
			_windup_close_timer = 0.0
			moveset.pounce(dir)
			return

func _apply_movement() -> void:
	# During committed moveset actions, don't override velocity each frame.
	# (Moveset may set velocity for lunge etc.)
	if moveset.is_busy():
		return

	var to_t := target.global_position - enemy.global_position
	var dist := to_t.length()
	if dist <= 0.001:
		enemy.velocity = Vector2.ZERO
		return

	var dir := to_t / dist
	var tangent := Vector2(-dir.y, dir.x) * _circle_sign
	var desired_vel := Vector2.ZERO

	# NEW: Hard personal-space push-out (prevents sticking no matter what)
	if dist < min_personal_space:
		enemy.velocity = (-dir) * (move_speed * 1.6)
		return

	match state:
		AIState.IDLE:
			desired_vel = Vector2.ZERO

		AIState.ENGAGE:
			# Approach until we reach the strafe ring; never "hug" the player.
			var approach := dir * (move_speed * approach_speed_mult)
			var strafe := tangent * (move_speed * strafe_speed_mult) * circle_bias
			desired_vel = approach + strafe

		AIState.STRAFE:
			# Strafe around the player on a ring near attack range, not inside them.
			# Keep distance with radial correction; push out harder if too close.
			var orbit := tangent * (move_speed * strafe_speed_mult)

			var radial_error := dist - desired_range
			var radial_strength := 0.9

			# push out harder if we're inside the ring (prevents "running into player")
			if dist < desired_range - range_tolerance:
				radial_strength = 1.45

			var radial_correction := (-dir * clampf(radial_error / maxf(1.0, range_tolerance), -1.0, 1.0)) * (move_speed * radial_strength)
			desired_vel = orbit + radial_correction

		AIState.ATTACK:
			# NEW: only allow slight close-in during windup window, otherwise don't drive movement here.
			if _windup_close_timer > 0.0 and dist > scratch_range * 0.9:
				desired_vel = dir * (move_speed * windup_close_speed_mult)
			else:
				desired_vel = Vector2.ZERO

		AIState.RECOVER:
			# Create space + slight strafe
			desired_vel = (-dir) * (move_speed * 1.05) + tangent * (move_speed * 0.55)

	enemy.velocity = desired_vel

func _maybe_flip_circle() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_circle_flip_t:
		_circle_sign *= -1.0
		_schedule_circle_flip()

func _schedule_circle_flip() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_next_circle_flip_t = now + randf_range(circle_dir_change_min, circle_dir_change_max)

func _resolve_target() -> Node2D:
	if target_path != NodePath():
		return get_node_or_null(target_path) as Node2D
	var candidates := get_tree().get_nodes_in_group("player")
	return candidates[0] as Node2D if candidates.size() > 0 else null

extends CharacterBody2D
class_name PlayerController

enum State { IDLE, MOVE, DASH, ATTACK, PARRY }
enum AttackType { UNARMED, INNERORBIT, MIDORBIT, OUTERORBIT }

@export_group("Movement")
@export var speed: float = 120.0
@export var acceleration: float = 700.0
@export var friction: float = 950.0

@export_group("Dash")
@export var dash_speed: float = 350.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.8

@export var parry_duration: float = 0.3
@export var stats: Stats

const INPUT_SWAP_ATTACK_TYPE: StringName = &"swap_attack_type"

@onready var attack_system: AttackSystem = $AttackSystem
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_state: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")

signal parry_success

@export_group("Style/Power")
@export var power_max: float = 100.0
@export var power_decay_per_sec: float = 10.0
@export var power_gain_attacktype_swap: float = 10.0 # NOTE: no longer used (swap alone gives no power)
@export var power_gain_target_swap: float = 12.0
@export var power_gain_parry: float = 18.0
@export var target_swap_combo_window: float = 2.5
@export var parry_power_cooldown: float = 0.2
@export var stale_repeat_threshold: int = 4
@export var stale_penalty: float = 8.0

@export var power_loss_parry_fail: float = 12.0

@export_group("Style/Power - Swap Reward")
@export var power_gain_swap_combo: float = 14.0
@export var swap_reward_recent_block: int = 2

@export var mult_t0: float = 1.00
@export var mult_t1: float = 1.08
@export var mult_t2: float = 1.18
@export var mult_t3: float = 1.30
@export var mult_t4: float = 1.45

@export_group("Debug")
@export var debug_power_print: bool = true
@export var debug_power_print_decay: bool = false

var power_gauge: float = 0.0
var last_power_event_time: float = 0.0
var last_hit_time: float = -999.0
var last_target_id: int = -1
var last_attack_type_for_spam: int = -1
var repeat_counter: int = 0
var last_parry_award_time: float = -999.0

var pending_swap_active: bool = false
var pending_swap_type: int = -1
var combo_had_hit: bool = false
var recent_reward_types: Array[int] = []

var facing_dir: Vector2 = Vector2.DOWN
var state: State = State.IDLE
var state_timer: float = 0.0
var dash_cd: float = 0.0
var dash_dir: Vector2 = Vector2.ZERO

var current_attack_type: AttackType = AttackType.INNERORBIT

# avoid spamming travel() every frame
var _anim_node: StringName = &""

# NEW: cache multiplier so we only push changes
var _cached_power_mult: float = -1.0

func _ready() -> void:
	attack_system.attack_started.connect(_on_attack_started)
	attack_system.attack_finished.connect(_on_attack_finished)

	if attack_system.has_signal("attack_committed"):
		attack_system.attack_committed.connect(_on_attack_committed)

	if attack_system.has_signal("attack_hit"):
		attack_system.attack_hit.connect(_on_attack_hit)

	if attack_system.has_signal("combo_completed"):
		attack_system.combo_completed.connect(_on_combo_completed)

	if stats != null:
		attack_system.stats = stats

	_cached_power_mult = _get_power_multiplier()
	attack_system.set_power_multiplier(_cached_power_mult)

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_process_state(delta)

	_update_power_decay(delta)

	var mult: float = _get_power_multiplier()
	if mult != _cached_power_mult:
		_cached_power_mult = mult
		attack_system.set_power_multiplier(mult)

	move_and_slide()

func _update_timers(delta: float) -> void:
	if dash_cd > 0.0:
		dash_cd -= delta

	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0:
			state = State.IDLE

func _process_state(delta: float) -> void:
	match state:
		State.IDLE, State.MOVE:
			_handle_input()
			_handle_movement(delta)
		State.DASH:
			velocity = dash_dir * dash_speed
		State.ATTACK:
			_handle_input()
			_handle_movement(delta, 0.85)
		State.PARRY:
			velocity = Vector2.ZERO

	_update_animation()

func _handle_input() -> void:
	if Input.is_action_just_pressed("attack"):
		_start_attack()
	elif Input.is_action_just_pressed("dash"):
		_start_dash()
	elif Input.is_action_just_pressed("parry"):
		_start_parry()

	if Input.is_action_just_pressed(INPUT_SWAP_ATTACK_TYPE):
		_cycle_attack_type()

func _handle_movement(delta: float, speed_mult: float = 1.0) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if state == State.IDLE or state == State.MOVE:
		state = State.MOVE if input != Vector2.ZERO else State.IDLE

	if input != Vector2.ZERO:
		facing_dir = input.normalized()
		velocity = velocity.move_toward(input * speed * speed_mult, acceleration * delta)
		$Sprite2D.flip_h = input.x > 0.0
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	_update_animation_blend()

func _update_animation_blend() -> void:
	var dir: Vector2 = facing_dir
	anim_tree.set("parameters/walk/blend_position", dir)
	anim_tree.set("parameters/idle/blend_position", dir)
	anim_tree.set("parameters/dash/blend_position", dir)

func _start_attack() -> void:
	attack_system.request_attack(facing_dir)

func _on_attack_committed() -> void:
	state = State.ATTACK

func _start_dash() -> void:
	if dash_cd > 0.0:
		return

	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		input = facing_dir

	state = State.DASH
	state_timer = dash_duration
	dash_cd = dash_cooldown
	dash_dir = input.normalized()
	velocity = dash_dir * dash_speed

func _start_parry() -> void:
	state = State.PARRY
	state_timer = parry_duration

func _travel(node_name: StringName) -> void:
	if _anim_node == node_name:
		return
	anim_state.travel(node_name) # CHANGED: no String allocation
	_anim_node = node_name

func _update_animation() -> void:
	match state:
		State.IDLE:
			_travel(&"idle")
		State.MOVE:
			_travel(&"walk")
		State.DASH:
			_travel(&"dash")
		State.ATTACK:
			pass
		State.PARRY:
			pass

func _on_attack_started() -> void:
	var t: int = int(current_attack_type)
	if last_attack_type_for_spam == t:
		repeat_counter += 1
	else:
		repeat_counter = 0
		last_attack_type_for_spam = t

	if repeat_counter >= stale_repeat_threshold:
		_add_power(-stale_penalty, "STALE_PENALTY")
		repeat_counter = 0

	combo_had_hit = false

func _on_attack_finished() -> void:
	state = State.IDLE

func _cycle_attack_type() -> void:
	var next_i: int = (int(current_attack_type) + 1) % 4
	var next: AttackType = next_i as AttackType
	if next == current_attack_type:
		return

	current_attack_type = next
	attack_system.set_attack_type(next_i as AttackSystem.AttackType)

	pending_swap_active = true
	pending_swap_type = next_i

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _add_power(amount: float, source: String = "UNKNOWN") -> void:
	var before: float = power_gauge
	power_gauge = clampf(power_gauge + amount, 0.0, power_max)
	last_power_event_time = _now_sec()

	if debug_power_print:
		_debug_power_event(source, amount, before, power_gauge)

func _debug_power_event(source: String, delta: float, before: float, after: float) -> void:
	print(
		"[POWER] ",
		source,
		" | Δ=", snappedf(delta, 0.01),
		" | ", snappedf(before, 0.01), " -> ", snappedf(after, 0.01),
		" / ", snappedf(power_max, 0.01),
		" | type=", str(current_attack_type)
	)

func _get_power_multiplier() -> float:
	var p: float = power_gauge
	if p >= 90.0: return mult_t4
	if p >= 75.0: return mult_t3
	if p >= 50.0: return mult_t2
	if p >= 25.0: return mult_t1
	return mult_t0

func _update_power_decay(delta: float) -> void:
	var t: float = _now_sec()
	if (t - last_power_event_time) < 0.15:
		return

	var before: float = power_gauge
	power_gauge = maxf(0.0, power_gauge - power_decay_per_sec * delta)
	if debug_power_print and debug_power_print_decay and power_gauge != before:
		_debug_power_event("DECAY", power_gauge - before, before, power_gauge)

func _on_attack_hit(target_id: int, _attack_type: AttackSystem.AttackType, _final_damage: int) -> void:
	var t: float = _now_sec()

	combo_had_hit = true

	if (t - last_hit_time) <= target_swap_combo_window and target_id != last_target_id:
		_add_power(power_gain_target_swap, "TARGET_SWAP")

	last_target_id = target_id
	last_hit_time = t
	last_power_event_time = t

func _on_combo_completed(attack_type: AttackSystem.AttackType) -> void:
	if not pending_swap_active:
		return
	if int(attack_type) != pending_swap_type:
		return
	if not combo_had_hit:
		pending_swap_active = false
		return

	if recent_reward_types.has(pending_swap_type):
		pending_swap_active = false
		return

	_add_power(power_gain_swap_combo, "SWAP_COMBO_HIT")

	recent_reward_types.push_back(pending_swap_type)
	while recent_reward_types.size() > swap_reward_recent_block:
		recent_reward_types.pop_front()

	pending_swap_active = false

func notify_parry_success() -> void:
	var t: float = _now_sec()
	if (t - last_parry_award_time) < parry_power_cooldown:
		return
	last_parry_award_time = t
	_add_power(power_gain_parry, "PARRY_SUCCESS")
	parry_success.emit()

func notify_parry_fail() -> void:
	_add_power(-power_loss_parry_fail, "PARRY_FAIL")

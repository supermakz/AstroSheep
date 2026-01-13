extends CharacterBody2D
class_name PlayerController

enum State { IDLE, MOVE, DASH, ATTACK, PARRY }
enum AttackType { UNARMED, INNERORBIT, MIDORBIT, OUTERORBIT }

@export_group("Movement")
@export var speed: float = 120.0 # CHANGED:
@export var acceleration: float = 700.0 # CHANGED:
@export var friction: float = 950.0 # CHANGED:

@export_group("Dash")
@export var dash_speed: float = 350.0 # CHANGED:
@export var dash_duration: float = 0.2 # CHANGED:
@export var dash_cooldown: float = 0.8 # CHANGED:

@export var parry_duration: float = 0.3 # CHANGED:

@export var stats: Stats

# CHANGED: typed constant (StringName recommended for input actions)
const INPUT_SWAP_ATTACK_TYPE: StringName = &"swap_attack_type" # CHANGED:

@onready var attack_system: AttackSystem = $AttackSystem
@onready var anim_tree: AnimationTree = $AnimationTree
# CHANGED: Typed; AnimationNodeStateMachinePlayback ist der übliche Typ
@onready var anim_state: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback") # CHANGED:

# ---------------------------
# Style/Power
# ---------------------------
signal parry_success

@export_group("Style/Power")
@export var power_max: float = 100.0
@export var power_decay_per_sec: float = 10.0
@export var power_gain_attacktype_swap: float = 10.0
@export var power_gain_target_swap: float = 12.0
@export var power_gain_parry: float = 18.0
@export var target_swap_combo_window: float = 2.5
@export var parry_power_cooldown: float = 0.2
@export var stale_repeat_threshold: int = 3
@export var stale_penalty: float = 8.0

@export var mult_t0: float = 1.00
@export var mult_t1: float = 1.08
@export var mult_t2: float = 1.18
@export var mult_t3: float = 1.30
@export var mult_t4: float = 1.45

var power_gauge: float = 0.0
var last_power_event_time: float = 0.0
var last_hit_time: float = -999.0
var last_target_id: int = -1
var last_attack_type_for_spam: int = -1
var repeat_counter: int = 0
var last_parry_award_time: float = -999.0
# ---------------------------

var facing_dir: Vector2 = Vector2.DOWN
var state: State = State.IDLE
var state_timer: float = 0.0 # CHANGED:
var dash_cd: float = 0.0 # CHANGED:
var dash_dir: Vector2 = Vector2.ZERO # CHANGED:
var combo_requested: bool = false

var current_attack_type: AttackType = AttackType.INNERORBIT

func _ready() -> void:
	attack_system.attack_started.connect(_on_attack_started)
	attack_system.attack_finished.connect(_on_attack_finished)

	if attack_system.has_signal("attack_hit"):
		attack_system.attack_hit.connect(_on_attack_hit)

	if stats != null:
		attack_system.stats = stats

	attack_system.set_power_multiplier(_get_power_multiplier())

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_process_state(delta)

	_update_power_decay(delta)
	attack_system.set_power_multiplier(_get_power_multiplier())

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
		State.ATTACK, State.PARRY:
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

func _handle_movement(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down") # CHANGED:
	if input != Vector2.ZERO:
		facing_dir = input.normalized()
		state = State.MOVE
		velocity = velocity.move_toward(input * speed, acceleration * delta)

		$Sprite2D.flip_h = input.x > 0.0
	else:
		state = State.IDLE
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	_update_animation_blend()

func _update_animation_blend() -> void:
	if velocity.length() > 0.01:
		var dir: Vector2 = velocity.normalized() # CHANGED:
		anim_tree.set("parameters/walk/blend_position", dir)
		anim_tree.set("parameters/idle/blend_position", dir)

func _start_attack() -> void:
	state = State.ATTACK
	attack_system.request_attack(facing_dir)

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
	print("STATE:", state, " DASH_ACTION:", Input.is_action_just_pressed(&"dash"))
	
func _start_parry() -> void:
	state = State.PARRY
	state_timer = parry_duration

func _update_animation() -> void:
	match state:
		State.IDLE:
			anim_state.travel("idle")
		State.MOVE:
			anim_state.travel("walk")
		State.DASH:
			anim_state.travel("dash")

func _on_attack_started() -> void:
	var t: int = int(current_attack_type) # CHANGED:
	if last_attack_type_for_spam == t:
		repeat_counter += 1
	else:
		repeat_counter = 0
		last_attack_type_for_spam = t

	if repeat_counter >= stale_repeat_threshold:
		_add_power(-stale_penalty)
		repeat_counter = 0

func _on_attack_finished() -> void:
	state = State.IDLE

func _try_attack() -> void:
	attack_system.request_attack(facing_dir)

func _cycle_attack_type() -> void:
	var old: AttackType = current_attack_type # CHANGED:
	var next_i: int = (int(current_attack_type) + 1) % 4
	var next: AttackType = next_i as AttackType # CHANGED:

	if next == old:
		return

	current_attack_type = next
	attack_system.set_attack_type(next_i as AttackSystem.AttackType) # CHANGED:
	_add_power(power_gain_attacktype_swap)

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _add_power(amount: float) -> void:
	power_gauge = clampf(power_gauge + amount, 0.0, power_max)
	last_power_event_time = _now_sec()

func _get_power_multiplier() -> float:
	var p: float = power_gauge # CHANGED:
	if p >= 90.0:
		return mult_t4
	if p >= 75.0:
		return mult_t3
	if p >= 50.0:
		return mult_t2
	if p >= 25.0:
		return mult_t1
	return mult_t0

func _update_power_decay(delta: float) -> void:
	var t: float = _now_sec() # CHANGED:
	var idle_time: float = t - last_power_event_time # CHANGED:
	if idle_time < 0.15:
		return
	power_gauge = maxf(0.0, power_gauge - power_decay_per_sec * delta)

func _on_attack_hit(target_id: int, _attack_type: AttackSystem.AttackType, _final_damage: int) -> void: # CHANGED:
	var t: float = _now_sec() # CHANGED:
	var within_window: bool = (t - last_hit_time) <= target_swap_combo_window # CHANGED:
	if within_window and target_id != last_target_id:
		_add_power(power_gain_target_swap)

	last_target_id = target_id
	last_hit_time = t
	last_power_event_time = t

func notify_parry_success() -> void:
	var t: float = _now_sec() # CHANGED:
	if (t - last_parry_award_time) < parry_power_cooldown:
		return
	last_parry_award_time = t
	_add_power(power_gain_parry)
	emit_signal("parry_success")

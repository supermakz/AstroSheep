extends CharacterBody2D
class_name PlayerController

enum State { IDLE, MOVE, DASH, ATTACK, PARRY }
enum AttackType { UNARMED, INNERORBIT, MIDORBIT, OUTERORBIT }

@export_group("Movement")
@export var speed := 120.0
@export var acceleration := 700.0
@export var friction := 950.0

@export_group("Dash")
@export var dash_speed := 350.0
@export var dash_duration := 0.2
@export var dash_cooldown := 0.8

@export var parry_duration := 0.3

@onready var attack_system: AttackSystem = $AttackSystem
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_state = anim_tree.get("parameters/playback")

var facing_dir: Vector2 = Vector2.DOWN
var state: State = State.IDLE
var state_timer := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var combo_requested: bool = false

func _ready() -> void:
	attack_system.attack_started.connect(_on_attack_started)
	attack_system.attack_finished.connect(_on_attack_finished)

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_process_state(delta)
	move_and_slide()

func _update_timers(delta: float) -> void:
	if dash_cd > 0:
		dash_cd -= delta
	if state_timer > 0:
		state_timer -= delta
		if state_timer <= 0:
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

func _handle_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input != Vector2.ZERO:
		facing_dir = input.normalized()
		state = State.MOVE
		velocity = velocity.move_toward(input * speed, acceleration * delta)
	
		$Sprite2D.flip_h = input.x > 0
	else:
		state = State.IDLE
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
			
	_update_animation_blend()

func _update_animation_blend() -> void:
	if velocity.length() > 0.01:
		var dir := velocity.normalized()
		anim_tree.set("parameters/walk/blend_position", dir)
		anim_tree.set("parameters/idle/blend_position", dir)

func _start_attack() -> void:
	state = State.ATTACK
	attack_system.request_attack(facing_dir)

func _start_dash() -> void:
	if dash_cd > 0:
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return

	state = State.DASH
	state_timer = dash_duration
	dash_cd = dash_cooldown
	dash_dir = input.normalized()

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
	pass

func _on_attack_finished() -> void:
	state = State.IDLE

func _try_attack() -> void:
	attack_system.request_attack(facing_dir)

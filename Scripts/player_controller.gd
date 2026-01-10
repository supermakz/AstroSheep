extends CharacterBody2D
class_name PlayerController

# --- Enums ---
enum State { IDLE, MOVE, DASH, ATTACK, PARRY }
enum AttackType { INNERORBIT, MIDORBIT, OUTERORBIT }

# --- Configuration ---
@export_group("Movement")
@export var speed: float = 120
@export var acceleration: float = 700
@export var friction: float = 986

@export_group("Dash")
@export var dash_speed: float = 350.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.8

@export_group("Combat")
@export var parry_duration: float = 0.3
@export var duration_innerorbit: float = 0.15
@export var duration_midorbit: float = 0.3
@export var duration_outerorbit: float = 0.5

# --- Runtime State ---
var current_state: State = State.IDLE
var current_attack_type: AttackType = AttackType.INNERORBIT

# --- Reference for animation ---
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_state = anim_tree.get("parameters/playback")

var state_timer: float = 0.0
var dash_cd_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	_handle_timers(delta)
	
	# Input Handling nur wenn Action-fähig
	if current_state in [State.IDLE, State.MOVE]:
		_handle_input_actions()
		_handle_movement(delta)
	elif current_state == State.DASH:
		_process_dash()
	
	# --- NEU: Animations-Update jeden Frame ---
	_update_animations()
	
	move_and_slide()

func _handle_timers(delta: float) -> void:
	if dash_cd_timer > 0: dash_cd_timer -= delta
	
	if state_timer > 0:
		state_timer -= delta
		if state_timer <= 0:
			current_state = State.IDLE

func _handle_input_actions() -> void:
	# Weapon Cycling (Jederzeit möglich im Idle/Move)
	if Input.is_action_just_pressed("cycle_weapon"):
		_cycle_attack_type()

	# Action Triggers
	if Input.is_action_just_pressed("dash"):
		_try_dash()
	elif Input.is_action_just_pressed("attack"):
		_try_attack()
	elif Input.is_action_just_pressed("parry"):
		_try_parry()

# --- NEU: Funktion zur Steuerung des AnimationTrees ---
func _update_animations() -> void:
	match current_state:
		State.IDLE:
			anim_state.travel("idle")
		State.MOVE:
			anim_state.travel("walk_h")
		State.DASH:
			anim_state.travel("dash")
		State.PARRY:
			anim_state.travel("parry")
		State.ATTACK:
			# Spielt je nach Waffentyp eine andere Animation ab
			match current_attack_type:
				AttackType.INNERORBIT: anim_state.travel("attack_inner")
				AttackType.MIDORBIT: anim_state.travel("attack_mid")
				AttackType.OUTERORBIT: anim_state.travel("attack_outer")

func _cycle_attack_type() -> void:
	# Modulo-Arithmetik für endloses Cycling
	var type_count = AttackType.values().size()
	current_attack_type = (current_attack_type + 1) % type_count as AttackType
	print("Switched to: ", AttackType.keys()[current_attack_type])

func _handle_movement(delta: float) -> void:
	var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if input != Vector2.ZERO:
		current_state = State.MOVE
		velocity = velocity.move_toward(input * speed, acceleration * delta)
		
		# --- Sprite flippen basierend auf Laufrichtung ---
		if input.x != 0:
			$Sprite2D.flip_h = input.x > 0
		
	else:
		current_state = State.IDLE
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func _try_dash() -> void:
	if dash_cd_timer > 0: return
	
	var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO: return # Kein Dash im Stand
	
	current_state = State.DASH
	state_timer = dash_duration
	dash_cd_timer = dash_cooldown
	dash_direction = input
	velocity = dash_direction * dash_speed

func _process_dash() -> void:
	velocity = dash_direction * dash_speed

func _try_attack() -> void:
	current_state = State.ATTACK
	velocity = Vector2.ZERO # Stop movement on attack start
	
	# Waffenspezifische Logik
	match current_attack_type:
		AttackType.INNERORBIT:
			state_timer = duration_innerorbit
			# Todo: Hitbox aktivieren
		AttackType.MIDORBIT:
			state_timer = duration_midorbit
			# Todo: Projectile instanzieren
		AttackType.OUTERORBIT:
			state_timer = duration_outerorbit
			# Todo: Cast Area spawnen

func _try_parry() -> void:
	current_state = State.PARRY
	state_timer = parry_duration
	velocity = Vector2.ZERO

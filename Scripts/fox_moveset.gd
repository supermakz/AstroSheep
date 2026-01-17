extends Node
class_name Fox_Moveset

@export var melee_attack_path: NodePath = NodePath("../../../Attacks/MeleeAttack")
@export var anim_player_path: NodePath = NodePath("../../../AnimationPlayer")

@export_group("Damage")
@export var melee_damage: int = 8
@export var debug_damage_print: bool = true

@export_group("Scratch Timing")
@export var scratch_windup: float = 0.18
@export var scratch_active: float = 0.10
@export var scratch_recovery: float = 0.32

@export_group("Pounce Timing")
@export var pounce_windup: float = 0.30
@export var pounce_lunge_time: float = 0.22
@export var pounce_distance_px: float = 80.0 # NEW: controls how far the pounce goes (tune this)
@export var pounce_active_start: float = 0.06
@export var pounce_recovery: float = 0.45
@export var pounce_stop_distance: float = 34.0 # NEW: stop lunging if already very close (prevents "face sticking")

@onready var enemy: EnemyBase = get_parent().get_parent().get_parent() as EnemyBase
@onready var melee_attack: Area2D = get_node(melee_attack_path) as Area2D
@onready var anim_player: AnimationPlayer = get_node_or_null(anim_player_path) as AnimationPlayer

var _busy: bool = false
var _attack_dir: Vector2 = Vector2.RIGHT

func is_busy() -> bool:
	return _busy

func scratch(dir: Vector2) -> void:
	if _busy:
		return
	_busy = true
	_attack_dir = dir.normalized()

	if anim_player != null and anim_player.has_animation("fox_scratch"):
		anim_player.play("fox_scratch")

	await _wait(scratch_windup)
	_enable_hitbox()
	await _wait(scratch_active)
	_disable_hitbox()
	await _wait(scratch_recovery)

	_busy = false

func pounce(dir: Vector2) -> void:
	if _busy:
		return
	_busy = true
	_attack_dir = dir.normalized()

	if anim_player != null and anim_player.has_animation("fox_pounce"):
		anim_player.play("fox_pounce")

	await _wait(pounce_windup)

	# active starts slightly after takeoff
	await _wait(pounce_active_start)
	_enable_hitbox()

	# NEW: derive speed from desired distance and lunge time (distance = speed * time)
	var lunge_speed: float = pounce_distance_px / maxf(0.001, pounce_lunge_time)

	var t := 0.0
	while t < pounce_lunge_time and enemy != null and not enemy.dead:
		# NEW: stop if already close to target to avoid pushing/sticking
		var p := _get_player_target()
		if p != null and enemy.global_position.distance_to(p.global_position) <= pounce_stop_distance:
			break

		enemy.velocity = _attack_dir * lunge_speed
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

	_disable_hitbox()
	await _wait(pounce_recovery)

	_busy = false

func enable_attack_hitbox() -> void:
	_enable_hitbox()

func disable_attack_hitbox() -> void:
	_disable_hitbox()

func _enable_hitbox() -> void:
	if melee_attack == null:
		return
	melee_attack.monitoring = true
	melee_attack.monitorable = true
	var shape := melee_attack.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = false

func _disable_hitbox() -> void:
	if melee_attack == null:
		return
	melee_attack.monitoring = false
	var shape := melee_attack.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = true

func _get_player_target() -> Node2D:
	# Minimal dependency: player group. (FoxAI already uses this too.)
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node2D
	return null

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _on_melee_attack_area_entered(area: Area2D) -> void:
	# Only deal damage when hitbox is active
	if not melee_attack or not melee_attack.monitoring:
		return

	var target := area.get_parent()
	if target == null:
		return

	if not target.has_method("take_damage"):
		return

	# Avoid self-hits / hitting other enemy parts
	if target == enemy:
		return

	# Apply damage
	target.call("take_damage", melee_damage, enemy.global_position)

	if debug_damage_print:
		print("[FOX] hit ", target.name, " for ", melee_damage)

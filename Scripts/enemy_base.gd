extends CharacterBody2D
class_name EnemyBase

signal damaged(final_amount: int, from_position: Vector2) # OPTIONAL but recommended
signal died() # OPTIONAL but recommended

@export var stats: Stats
@export var duplicate_stats_per_instance: bool = true

@export_group("Hit / Movement Feel")
@export var knockback_strength: float = 120.0
@export var friction: float = 800.0

@export_group("Node Paths")
@export var body_sprite_path: NodePath = NodePath("Visuals/Body")
@export var hurtbox_path: NodePath = NodePath("Hurtbox")
@export var healthbar_path: NodePath = NodePath("HealthbarAnchor/Healthbar")

@onready var body_sprite: Node = get_node_or_null(body_sprite_path)
@onready var hurtbox: Area2D = get_node(hurtbox_path) as Area2D
@onready var health_bar: Node = get_node_or_null(healthbar_path)

@export_group("Debug")
@export var debug_damage_print: bool = true


var max_hp: int = 1
var hp: int = 1
var dead: bool = false
var _last_facing_x: float = 1.0

func _ready() -> void:
	if stats == null:
		push_error("EnemyBase has NO Stats assigned.")
		return

	if duplicate_stats_per_instance:
		stats = stats.duplicate(true) as Stats

	stats.recalculate_stats()

	max_hp = maxi(1, int(stats.current_max_health))
	hp = max_hp

	hurtbox.monitoring = false
	hurtbox.monitorable = true

	_apply_healthbar_initial()

func _physics_process(delta: float) -> void:
	if dead:
		return
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()
	
	_update_facing()
	
func take_damage(amount: int, from_position: Vector2) -> void:
	if dead:
		return
	
	
	var hp_before := hp
	var final_amount: int = maxi(1, _apply_defense(amount))
	hp = maxi(0, hp - final_amount)

	_update_health_bar()
	_debug_damage(amount, final_amount, hp_before)

	var dir: Vector2 = (global_position - from_position).normalized()
	velocity = dir * knockback_strength

	if hp <= 0:
		_die()

func _apply_defense(raw_damage: int) -> int:
	var d: float = maxf(0.0, float(stats.current_defense))
	var mult: float = 100.0 / (100.0 + d)
	return int(round(float(raw_damage) * mult))

func _apply_healthbar_initial() -> void:
	if health_bar == null:
		push_warning("EnemyBase has no Healthbar node at path: %s" % [str(healthbar_path)])
		return
	if not health_bar.has_method("set_health"):
		push_warning("Healthbar must implement set_health(current:int, max:int). Node: %s" % [health_bar.get_path()])
		return
	health_bar.visible = true
	health_bar.call("set_health", hp, max_hp)

func _update_health_bar() -> void:
	if health_bar == null:
		return
	if not health_bar.has_method("set_health"):
		return
	health_bar.call("set_health", hp, max_hp)
	
func _update_facing() -> void:
	if body_sprite == null:
		return
	if not body_sprite is Sprite2D:
		return

	# Only update facing if we are actually moving
	if absf(velocity.x) > 1.0:
		_last_facing_x = sign(velocity.x)

	var sprite := body_sprite as Sprite2D
	sprite.flip_h = _last_facing_x < 0.0
	

func _die() -> void:
	dead = true
	if health_bar != null:
		health_bar.visible = false
	died.emit() # OPTIONAL
	queue_free()

func _debug_damage(raw_amount: int, final_amount: int, hp_before: int) -> void:
	if not debug_damage_print:
		return
	print("[ENEMY] ", name, " took ", final_amount, " (raw ", raw_amount, ") | HP: ", hp_before, " -> ", hp, " / ", max_hp, " | DEF: ", stats.current_defense)

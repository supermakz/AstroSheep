extends CharacterBody2D
class_name EnemyBase

@export var stats: Stats
@export var duplicate_stats_per_instance: bool = true

@export_group("Hit / Movement Feel")
@export var knockback_strength: float = 120.0
@export var friction: float = 800.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var health_bar: ProgressBar = $HealthBar

var max_hp: int = 1
var hp: int = 1
var dead: bool = false
var hp_tween: Tween

func _ready() -> void:
	if stats == null:
		push_error("EnemyBase has NO Stats assigned.")
		return

	if duplicate_stats_per_instance:
		stats = stats.duplicate(true) as Stats

	stats.recalculate_stats()

	max_hp = maxi(1, int(stats.current_max_health))
	hp = max_hp

	health_bar.max_value = max_hp
	health_bar.value = hp
	health_bar.visible = true

	# Hurtbox should be passive receiver
	hurtbox.monitoring = false
	hurtbox.monitorable = true

func _physics_process(delta: float) -> void:
	if dead:
		return
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

func take_damage(amount: int, from_position: Vector2) -> void:
	if dead:
		return

	var final_amount: int = maxi(1, _apply_defense(amount))
	hp = maxi(0, hp - final_amount)

	_debug_damage(amount, final_amount)
	_update_health_bar()

	var dir: Vector2 = (global_position - from_position).normalized()
	velocity = dir * knockback_strength

	if hp <= 0:
		_die()

func _apply_defense(raw_damage: int) -> int:
	var d: float = maxf(0.0, float(stats.current_defense))
	var mult: float = 100.0 / (100.0 + d)
	return int(round(float(raw_damage) * mult))

func _update_health_bar() -> void:
	if hp_tween and hp_tween.is_running():
		hp_tween.kill()
	hp_tween = get_tree().create_tween()
	hp_tween.tween_property(health_bar, "value", hp, 0.12)

func _die() -> void:
	dead = true
	health_bar.visible = false
	queue_free()

func _debug_damage(raw_amount: int, final_amount: int) -> void:
	print("[EnemyBase] RAW:", raw_amount, " FINAL:", final_amount, " HP:", hp, "/", max_hp, " DEF:", stats.current_defense)

extends CharacterBody2D

# ASSUMPTIONS:
# - Jeder Enemy MUSS eine Stats-Resource haben.
# - Stats sind die einzige Quelle für HP & Defense.
# - knockback_strength & friction sind "Feel / Physics", keine RPG-Stats.

@export var stats: Stats
@export var duplicate_stats_per_instance: bool = true

@export_group("Hit / Movement Feel")
@export var knockback_strength: float = 120.0
@export var friction: float = 800.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hurtbox
@onready var health_bar: ProgressBar = $HealthBar

var max_hp: int
var defense: float
var hp: int
var dead: bool = false
var hp_tween: Tween

func _ready() -> void:
	if stats == null:
		push_error("Enemy has NO Stats assigned! This is required.")
		return
	
	if duplicate_stats_per_instance:
		stats = stats.duplicate(true) as Stats

	stats.recalculate_stats()

	max_hp = maxi(1, int(stats.current_max_health))
	defense = maxf(0.0, float(stats.current_defense))

	hp = max_hp
	health_bar.max_value = float(max_hp) # CHANGED
	health_bar.value = float(hp) # CHANGED


	sprite.play("idle")
	hitbox.monitorable = true
	hitbox.monitoring = false
	
func _physics_process(delta: float) -> void:
	if not dead:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func take_damage(amount: int, from_position: Vector2) -> void:
	if dead:
		return

	var used_def: float = stats.current_defense
	var final_amount: int = _apply_defense(amount)
	final_amount = maxi(1, final_amount)

	print(
		"[DMG]",
		"RAW:", amount,
		"| DEF:", used_def,
		"| FINAL:", final_amount,
		"| HP:", hp, "/", max_hp
	)

	hp -= final_amount
	hp = maxi(0, hp)

	_update_health_bar()
	_play_hit_effects(from_position)

	if hp <= 0:
		_die()

func _apply_defense(raw_damage: int) -> int:
	var d: float = maxf(0.0, float(stats.current_defense))
	var mult: float = 100.0 / (100.0 + d)
	return int(round(float(raw_damage) * mult))

func _update_health_bar() -> void:
	if health_bar == null:
		push_warning("[HB] HealthBar node is null. Check $HealthBar path.")
		return

	health_bar.visible = true

	# ADDED: set immediately (guaranteed)
	health_bar.max_value = float(max_hp)
	health_bar.value = float(hp)
	health_bar.queue_redraw() # ADDED: force repaint (helps if UI seems “stuck”)

	print("[HB UPDATE] max:", health_bar.max_value, "val:", health_bar.value, "hp:", hp, "/", max_hp) # ADDED

	if hp_tween and hp_tween.is_running():
		hp_tween.kill()

	hp_tween = get_tree().create_tween()
	hp_tween.tween_property(health_bar, "value", float(hp), 0.2)


func _play_hit_effects(from_position: Vector2) -> void:
	var tween: Tween = get_tree().create_tween()
	sprite.modulate = Color.RED
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)

	sprite.play("hit")
	if not sprite.animation_finished.is_connected(_on_hit_finished):
		sprite.animation_finished.connect(_on_hit_finished, CONNECT_ONE_SHOT)

	var dir: Vector2 = (global_position - from_position).normalized()
	velocity = dir * knockback_strength

func _on_hit_finished() -> void:
	if not dead:
		sprite.play("idle")

func _die() -> void:
	dead = true
	health_bar.visible = false
	sprite.play("death")

	hitbox.set_deferred("monitoring", false)
	hitbox.set_deferred("monitorable", false)
	$CollisionShape2D.set_deferred("disabled", true)

	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)

extends CharacterBody2D

@export var max_hp: int = 1000
@export var knockback_strength := 120.0
@export var friction := 800.0 # Um den Knockback sanft zu stoppen

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var health_bar: ProgressBar = $HealthBar

var hp: int = max_hp
var dead := false
var hp_tween: Tween

func _ready() -> void:
	hp = max_hp
	health_bar.max_value = max_hp
	health_bar.value = hp
	sprite.play("idle")

	hitbox.monitorable = true
	hitbox.monitoring = false
	
func _physics_process(delta: float) -> void:
	if not dead:
		# Sorgt dafür, dass der Knockback nicht unendlich gleitet
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func take_damage(amount: int, from_position: Vector2) -> void:
	print("DMG:", amount, "HP:", hp)
	if dead:
		return

	hp -= amount
	_update_health_bar()
	_play_hit_effects(from_position)

	if hp <= 0:
		_die()

func _update_health_bar() -> void:
	health_bar.visible = true
	
	if hp_tween and hp_tween.is_running():
		hp_tween.kill()
	
	hp_tween = get_tree().create_tween()
	hp_tween.tween_property(health_bar, "value", hp, 0.2)	

func _play_hit_effects(from_position: Vector2) -> void:
	# 1. Visuelles Feedback: Rot leuchten
	var tween = get_tree().create_tween()
	sprite.modulate = Color.RED # Sofort Rot
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2) # Zurück zu normal
	
	# 2. Animation abspielen
	sprite.play("hit")
	if not sprite.animation_finished.is_connected(_on_hit_finished):
		sprite.animation_finished.connect(_on_hit_finished, CONNECT_ONE_SHOT)

	# 3. Knockback
	var dir := (global_position - from_position).normalized()
	velocity = dir * knockback_strength

func _on_hit_finished() -> void:
	if not dead:
		sprite.play("idle")

func _die() -> void:
	dead = true
	health_bar.visible = false
	sprite.play("death")
	
	# Hitbox und Collision deaktivieren
	hitbox.set_deferred("monitoring", false)
	hitbox.set_deferred("monitorable", false)
	$CollisionShape2D.set_deferred("disabled", true)
	
	# Optional: Gegner nach Tod langsam ausblenden
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)

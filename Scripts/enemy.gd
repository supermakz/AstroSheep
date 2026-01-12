extends CharacterBody2D

@export var max_hp := 50
@export var knockback_strength := 15

var hp := max_hp
var dead := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox

func _ready():
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	sprite.play("idle")

func _physics_process(delta):
	if dead:
		return

# =========================
# DAMAGE HANDLING
# =========================
func take_damage(damage: int, from_position: Vector2):
	if dead:
		return

	hp -= damage
	sprite.play("hit")

	# Knockback
	var dir := (global_position - from_position).normalized()
	velocity = dir * knockback_strength

	if hp <= 0:
		die()

func die():
	dead = true
	sprite.play("death")
	hitbox.monitoring = false
	$CollisionShape2D.disabled = true

func _on_hitbox_area_entered(area: Area2D):
	# Erwartet, dass dein Player-Angriff:
	# - damage INT hat
	# - global_position benutzt
	if area.has_method("get_damage"):
		var dmg = area.get_damage()
		take_damage(dmg, area.global_position)

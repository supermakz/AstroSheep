class_name AttackSystem
extends Node2D

signal attack_started
signal attack_finished

enum AttackType { UNARMED, INNERORBIT, MIDORBIT, OUTERORBIT }

@onready var combo_timer: Timer = $ComboTimer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var effect_sprite: Node2D = $EffectSprite
@export var base_melee_damage: int = 10

var combo_requested: bool = false
var current_facing: Vector2 = Vector2.DOWN
var current_attack_type: AttackType = AttackType.INNERORBIT
var combo_step: int = 0
var can_attack: bool = true

func _ready() -> void:
	melee_hitbox.monitoring = false
	combo_timer.timeout.connect(_on_combo_timeout)
	
func request_attack(facing_dir: Vector2) -> void:
	if not can_attack:
		combo_requested = true
		return
		
	if facing_dir != Vector2.ZERO:
		rotation = facing_dir.angle() + (PI / 2.0)		
		
	current_facing = facing_dir
	can_attack = false
	emit_signal("attack_started")
	
	_play_combo_animation()

func _play_combo_animation() -> void:
	var anim_name := "attack_innerorbit%d" % (combo_step + 1)
	
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
	else:
		push_warning("Missing Combo Animation: %s" % anim_name)

	combo_timer.start()

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name.begins_with("attack_innerorbit"):
		combo_step += 1
		
		if combo_step >= 4:
			combo_step = 0
			
		can_attack = true
		
		set_melee_hitbox_active(false)
		
		emit_signal("attack_finished")
		if combo_requested:
			combo_requested = false
			request_attack(current_facing)

func _on_combo_timeout() -> void:
	combo_step = 0

# Wird per AnimationPlayer (Call Method Track) aufgerufen
func set_melee_hitbox_active(active: bool) -> void:
	melee_hitbox.monitoring = active
	$MeleeHitbox/CollisionShape2D.set_deferred("disabled", !active)

func _on_melee_hitbox_area_entered(area: Area2D) -> void:
	var target = area.get_parent() # Da Hitbox direkt unter Enemy liegt
	if target and target.has_method("take_damage"):
		target.take_damage(base_melee_damage, global_position)

func set_attack_type(type: AttackType) -> void:
	current_attack_type = type
	combo_step = 0

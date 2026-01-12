class_name AttackSystem
extends Node2D

@onready var combo_timer: Timer = $ComboTimer
@onready var ult_timer: Timer = $UltimateTimer
@onready var projectile_spawn: Marker2D = $OrbitSpawnPoint
@export var projectile_scene_orb: PackedScene
@export var projectile_scene_aoe: PackedScene

var current_orbit_index: int = 0 # 0 = Unarmed (Default)
var current_style_points: float = 0.0
var is_ultimate_active: bool = false
var current_combo_step: int = 0

enum AttackType { UNARMED = 0, INNERORBIT = 1, MIDORBIT = 2, OUTERORBIT = 3 }

const ATTACK_CONFIG = {
	AttackType.UNARMED: { "min_style": 0, "max_combo": 3, "damage_mult": 1.0, "style_gain": 10.0, "style_cost": 0.0 },
	AttackType.INNERORBIT:   { "min_style": 0, "max_combo": 4, "damage_mult": 1.4, "style_gain": 7.0, "style_cost":0.0 },
	AttackType.MIDORBIT:     { "min_style": 3, "max_combo": 1, "damage_mult": 1.2, "style_gain": 5.0,  "style_cost": 40.0 },
	AttackType.OUTERORBIT:     { "min_style": 5, "max_combo": 1, "damage_mult": 0.0, "style_gain": 0.0,  "style_cost": 80.0 } # Multi 0 = kein damage
			}

func trigger_attack(aim_position: Vector2) -> void:
	# Prüfen ob wir gerade überhaupt angreifen können
	if not _can_attack():
		return
		
	look_at(aim_position)

	_execute_attack_logic(aim_position)		

func _execute_attack_logic(aim_position: Vector2) -> void:
	# Combo Reset prüfen
	if combo_timer.is_stopped():
		current_combo_step = 0	
	
	var anim_to_play = "attack_innerorbit" + str(current_combo_step + 1)
	
	if $AnimationPlayer.has_animation(anim_to_play):
		$AnimationPlayer.play(anim_to_play)
		$EffectSprite.look_at(aim_position)
	
	var cost = ATTACK_CONFIG[current_orbit_index]["style_cost"]	
	current_style_points -= cost
	if current_style_points < 0: current_style_points = 0		
	
	
	var max_hits = ATTACK_CONFIG[current_orbit_index]["max_combo"]
	if current_combo_step >= max_hits:
		current_combo_step = 0 # Loop oder Reset je nach Design
	
	# Nächsten Schritt vorbereiten
	current_combo_step += 1
	combo_timer.start()
	

	# Rotation zum Ziel (Wichtig für Weapon 3 AOE & Weapon 2 Orb)
	look_at(aim_position)
	
func _spawn_projectile(scene: PackedScene) -> void:
	if not scene: return
	
	var proj = scene.instantiate()
	get_tree().root.add_child(proj)
	proj.global_position = projectile_spawn.global_position

func get_style_level() -> int:
	if current_style_points >= 700: return 7 # Ultimate Ready
	if current_style_points >= 500: return 5 # Weapon 3
	if current_style_points >= 300: return 3 # Weapon 2
	if current_style_points >= 100: return 1 # Weapon 1
	return 0 # Unarmed

func add_style(amount: float) -> void:
	current_style_points += amount
	# TODO: UI Update Signal hier emitten
	
	# Cap bei Max Level
	if current_style_points > 700: current_style_points = 700
	
var can_guard_counter: bool = false

func register_parry(is_perfect: bool) -> void:
	if is_perfect:
		can_guard_counter = true
		add_style(50.0) # Viel Style für Perfect Parry
		# Kleines Zeitfenster für den Counter öffnen
		get_tree().create_timer(1.0).timeout.connect(func(): can_guard_counter = false)
	else:
		add_style(0.0) # Wenig Style für normalen Block

func _check_guard_counter() -> bool:
	if can_guard_counter:
		print("EXECUTE GUARD COUNTER!")
		can_guard_counter = false
		add_style(20.0) # Bonus für den Counter selbst
		return true
	return false

func activate_ultimate() -> void:
	if get_style_level() < 7: return
	
	is_ultimate_active = true
	ult_timer.start()
	print("ULTIMATE ACTIVATED: ALL WEAPONS FIRE!")
	
	# Visuals hier triggern (Shader, Partikel)

func _on_ultimate_timer_timeout() -> void:
	is_ultimate_active = false
	current_style_points = 0 # Reset nach Ulti? (Design-Entscheidung)
	print("Ultimate beendet")
	
func _can_attack() -> bool:
	# Hier prüfen wir später States wie "Stunned", "Dead" oder "Global Cooldown"
	if is_ultimate_active: return true
	var config = ATTACK_CONFIG[current_orbit_index]
	
	if get_style_level() < config["min_style"]:
		print("Not enough Style!:Need more")
		return false
		
	if current_style_points < config["style_cost"]:
		print("zu Wenig style points")
		return false
	return true


func set_orbit_index(index: int) -> void:
	
	if get_style_level() < ATTACK_CONFIG[index]["min_style"]:
		print("Switch abgelehnt: Style Level zu niedrig. Fallback auf UNARMED.")
		current_orbit_index = AttackType.UNARMED
	else:
		current_orbit_index = index
		current_combo_step = 0 # Reset Combo bei Waffenwechsel
		print("AttackSystem: Weapon switched to index %s" % index)

# Wird vom AnimationPlayer via Method Call Track aufgerufen
func set_hitbox_active(is_active: bool) -> void:
	$MeleeHitbox/CollisionShape2D.disabled = !is_active
	if is_active:
		_check_guard_counter()

func _on_melee_hitbox_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage"):
		var config = ATTACK_CONFIG[current_orbit_index]
		
		var final_damage = 10 * config["damage_mult"]
		area.take_damage(final_damage)
		
		add_style(config["style_gain"])
		print("Hit! Damage: %s | Style gain: %s" % [final_damage, config["style_gain"]])

#Melee attack richtung ändern zu player direction nicht maus dir
#Innerorbit animation nur bei innerorbit und nicht bei allen anderen animationen
#animation placement fixen
#hitbox timing fixen, hitboxen generell fixen, hitboxen, hitboxen, leck eier, hitboxen

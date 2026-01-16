extends Node2D
class_name CameraRig

@export var target: CharacterBody2D
@onready var cam: Camera2D = $Camera2D

@export var look_ahead_px: float = 50.0
@export var look_ahead_lerp: float = 3.0
@export var look_ahead_lerp_turn: float = 3.0
@export var dir_lerp: float = 16.0
@export var min_speed_for_look: float = 10.0

var look_dir: Vector2 = Vector2.DOWN

func _ready() -> void:
	if target == null:
		push_error("CameraRig: target not assigned.")
		set_physics_process(false)
		return

	cam.position_smoothing_enabled = true
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS

func _physics_process(delta: float) -> void:
	global_position = target.global_position
	_update_lookahead(delta)

func _update_lookahead(delta: float) -> void:
	var v: Vector2 = target.velocity
	var k: float = look_ahead_lerp

	if v.length() >= min_speed_for_look:
		var new_dir: Vector2 = v.normalized()
		var dot: float = look_dir.dot(new_dir)

		look_dir = look_dir.lerp(new_dir, 1.0 - exp(-dir_lerp * delta)).normalized()

		if dot < 0.3:
			k = look_ahead_lerp_turn

	var target_offset: Vector2 = look_dir * look_ahead_px
	cam.offset = cam.offset.lerp(target_offset, 1.0 - exp(-k * delta))
	cam.offset = cam.offset.limit_length(look_ahead_px)

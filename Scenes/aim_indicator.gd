extends Node2D

@export_group("Shape")
@export var radius: float = 34.0
@export var arc_degrees: float = 280.0
@export var segments: int = 36

@export_group("Thickness")
@export var back_thickness: float = 2.0
@export var front_thickness: float = 10.0
@export var tip_length: float = 10.0
@export var tip_width: float = 10.0

@export_group("Look")
@export var color: Color = Color(1.0, 1.0, 1.0, 0.38)

@export_group("Behavior")
@export var mouse_deadzone: float = 6.0
@export var hide_when_mouse_too_close: bool = false

var _aim_dir: Vector2 = Vector2.RIGHT

func _process(_delta: float) -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - global_position

	if to_mouse.length_squared() > mouse_deadzone * mouse_deadzone:
		_aim_dir = to_mouse.normalized()

	queue_redraw()

func _draw() -> void:
	if hide_when_mouse_too_close:
		var dist_sq := (get_global_mouse_position() - global_position).length_squared()
		if dist_sq <= mouse_deadzone * mouse_deadzone:
			return

	_draw_open_arc()
	_draw_tip()

func _draw_open_arc() -> void:
	if segments < 2:
		return

	var aim_angle: float = _aim_dir.angle()

	# Offener Bogen um die Aim-Richtung herum.
	# Die Öffnung ist "hinten".
	var arc_rad: float = deg_to_rad(arc_degrees)
	var start_angle: float = aim_angle - arc_rad * 0.5
	var step: float = arc_rad / float(segments)

	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)

		var a0: float = start_angle + step * float(i)
		var a1: float = start_angle + step * float(i + 1)

		var dir0: Vector2 = Vector2.RIGHT.rotated(a0)
		var dir1: Vector2 = Vector2.RIGHT.rotated(a1)

		var th0: float = _get_arc_thickness(t0)
		var th1: float = _get_arc_thickness(t1)

		var outer0: Vector2 = dir0 * (radius + th0 * 0.5)
		var inner0: Vector2 = dir0 * (radius - th0 * 0.5)
		var outer1: Vector2 = dir1 * (radius + th1 * 0.5)
		var inner1: Vector2 = dir1 * (radius - th1 * 0.5)

		var quad := PackedVector2Array([
			outer0,
			outer1,
			inner1,
			inner0
		])

		draw_colored_polygon(quad, color)

func _draw_tip() -> void:
	var dir: Vector2 = _aim_dir
	var perp: Vector2 = Vector2(-dir.y, dir.x)

	var base_center: Vector2 = dir * radius
	var tip: Vector2 = dir * (radius + tip_length)

	var left: Vector2 = base_center + perp * (tip_width * 0.5)
	var right: Vector2 = base_center - perp * (tip_width * 0.5)

	var tri := PackedVector2Array([
		tip,
		left,
		right
	])

	draw_colored_polygon(tri, color)

func _get_arc_thickness(t: float) -> float:
	# t=0 und t=1 = offene Enden hinten -> dünn
	# t=0.5 = Frontbereich -> dick
	var front_factor: float = 1.0 - abs(t - 0.5) / 0.5
	front_factor = clampf(front_factor, 0.0, 1.0)

	# etwas weichere Kurve
	front_factor = pow(front_factor, 0.75)

	return lerpf(back_thickness, front_thickness, front_factor)

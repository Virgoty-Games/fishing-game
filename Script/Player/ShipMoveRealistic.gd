extends CharacterBody3D

@export_group("Motor")
@export var engine_force: float = 18.0
@export var max_speed_forward: float = 8.0
@export var max_speed_reverse: float = 3.0
@export var throttle_response: float = 2.5

@export_group("Agua / Drag")
@export var drag_longitudinal: float = 0.25
@export var drag_lateral: float = 2.2
@export var linear_damping: float = 0.15

@export_group("Timón / Giro")
@export var turn_power: float = 1.6
@export var angular_damping: float = 1.8
@export var angular_drag: float = 0.6
@export var align_hull: float = 1.5

var _throttle := 0.0
var _angular_vel_y := 0.0

func _physics_process(delta: float) -> void:
	var up := Vector3.UP
	var forward := -transform.basis.x
	var right := forward.cross(up).normalized()

	# Throttle: sube/baja suavemente para sentir inercia de motor
	var throttle_input := Input.get_axis("move_forward", "move_bottom")
	_throttle = lerpf(_throttle, throttle_input, clampf(throttle_response * delta, 0.0, 1.0))

	# Timón: giro depende de la velocidad hacia adelante (si vas parado, casi no giras)
	var rudder := Input.get_axis("move_left", "move_right")

	# === Descomponer velocidad en componentes barco ===
	var v_forward := velocity.dot(forward)
	var v_lateral := velocity.dot(right)

	# Limitar por disponibilidad de velocidad máxima
	var target_max := max_speed_forward if _throttle >= 0.0 else max_speed_reverse
	var speed_ratio := clampf(absf(v_forward) / max(target_max, 0.001), 0.0, 1.0)
	var engine_acc := forward * (engine_force * _throttle * (1.0 - speed_ratio))

	# === Resistencia del agua (cuadrática con la velocidad) ===
	var long_drag_acc := -forward * (v_forward * absf(v_forward) * drag_longitudinal)
	var lat_drag_acc  := -right   * (v_lateral * absf(v_lateral) * drag_lateral)

	# === Rozamiento lineal “general” (viscosidad) ===
	var linear_damp_acc := -velocity * linear_damping

	var acc := engine_acc + long_drag_acc + lat_drag_acc + linear_damp_acc
	velocity += acc * delta

	# El casco tiende a alinear el movimiento con la proa (reduce la deriva poco a poco)
	var aligned := forward * v_forward
	velocity = velocity.lerp(aligned, clampf(align_hull * delta, 0.0, 1.0))

	# Limitar velocidades máxima/min
	var max_f = max_speed_forward
	var max_b = max_speed_reverse
	var new_v_forward := clampf(velocity.dot(forward), -max_b, max_f)
	var new_v_lateral := velocity.dot(right)
	velocity = forward * new_v_forward + right * new_v_lateral

	var speed_sign := signf(v_forward)
	var turn_effect : float = (absf(v_forward) / (max_f + 0.001)) * (speed_sign if speed_sign != 0.0 else 0.0)
	var ang_acc := (rudder * turn_power * turn_effect)
	
	ang_acc += -(angular_damping * _angular_vel_y) - (angular_drag * _angular_vel_y * absf(_angular_vel_y))

	_angular_vel_y += ang_acc * delta
	rotation.y += _angular_vel_y * delta

	move_and_slide()

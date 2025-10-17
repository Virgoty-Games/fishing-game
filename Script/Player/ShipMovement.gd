extends CharacterBody3D

@export_group("Stats")
@export var move_speed: float = 5.5
@export var turn_speed: float = 1.25
@export var accel : float = 1.0

func _physics_process(delta: float) -> void:
	# Turn Ship
	var turn_input := Input.get_axis("move_right", "move_left")
	if turn_input != 0.0: rotation.y += turn_input * turn_speed * delta
	
	# Move Ship
	var move_input := Input.get_axis("move_forward", "move_bottom")
	var target_vel := Vector3.ZERO
	if move_input != 0.0: target_vel = -transform.basis.x * (move_input * move_speed)
	
	# Smoothed
	velocity = velocity.lerp(target_vel, clamp(accel * delta, 0.0, 1.0))

	move_and_slide()

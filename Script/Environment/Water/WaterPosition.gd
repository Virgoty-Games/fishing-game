extends Node3D
@export var target: Node3D
@export var sea_level: float = 0.0
@export var follow_smooth: float = 0.0

func _process(delta: float) -> void:
	if target == null: return
	var p := global_transform.origin
	var t := target.global_transform.origin
	var goal := Vector3(t.x, sea_level, t.z)
	global_transform.origin = p.lerp(goal, clamp(follow_smooth * delta, 0.0, 1.0))

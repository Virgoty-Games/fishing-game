extends Camera3D

@export var target: Node3D
@export var sensitivity: float = 0.010
@export var follow_smooth: float = 12.0
@export var lock_mouse_while_drag: bool = true
@export var snap_on_start: bool = true

var _radius: float
var _height: float
var _yaw: float
var _dragging := false
var _did_snap := false

func _ready() -> void:
	if target == null:
		set_process(false)
		return
	var off := global_position - target.global_position
	_height = off.y
	var xz := Vector2(off.x, off.z)
	_radius = xz.length()
	_yaw = atan2(xz.y, xz.x)
	_did_snap = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_action_pressed("move_camera"):
			_dragging = true
			if lock_mouse_while_drag:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif event.is_action_released("move_camera"):
			_dragging = false
			if lock_mouse_while_drag:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * sensitivity

func _process(delta: float) -> void:
	if target == null:
		return

	var tp := target.global_position
	var orbit := Vector3(cos(_yaw), 0.0, sin(_yaw)) * _radius
	var desired := tp + orbit + Vector3(0.0, _height, 0.0)

	# primer frame: colocación exacta, sin interpolación
	if snap_on_start and not _did_snap:
		global_position = desired
		look_at(tp, Vector3.UP)
		_did_snap = true
		return

	# frames siguientes: seguimiento suave
	var w : float = clamp(follow_smooth * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, w)
	look_at(tp, Vector3.UP)

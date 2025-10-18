extends Node3D
class_name Rock

@export_group("Setup")
@export var water_level: float = 0.0
@export var material_underwater: Material
@export var material_surface: Material

var _mesh_inst: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _notifier: VisibleOnScreenNotifier3D
var _base_mesh: Mesh
var _is_active: bool = true
var _was_ever_on_screen := false

func _ready() -> void:
	_mesh_inst = MeshInstance3D.new()
	add_child(_mesh_inst)
	_mesh_inst.owner = get_tree().edited_scene_root

	_body = StaticBody3D.new()
	add_child(_body)
	_body.owner = get_tree().edited_scene_root

	_shape = CollisionShape3D.new()
	_body.add_child(_shape)
	_shape.owner = get_tree().edited_scene_root

	_notifier = VisibleOnScreenNotifier3D.new()
	_mesh_inst.add_child(_notifier)
	_notifier.owner = get_tree().edited_scene_root
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)

func setup_from_mesh(mesh: Mesh, shape: Shape3D, mat_under: Material, mat_surface: Material, water_y: float) -> void:
	_base_mesh = mesh
	_mesh_inst.mesh = mesh
	_shape.shape = shape
	material_underwater = mat_under
	material_surface = mat_surface
	water_level = water_y
	_apply_material_by_height()

func _apply_material_by_height() -> void:
	if _mesh_inst == null or _base_mesh == null: return
		
	if global_position.y < water_level:
		_mesh_inst.set_surface_override_material(0, material_underwater)
		for i in range(1, _mesh_inst.mesh.get_surface_count()):
			_mesh_inst.set_surface_override_material(i, material_underwater)
	else:
		_mesh_inst.set_surface_override_material(0, material_surface)
		for i in range(1, _mesh_inst.mesh.get_surface_count()):
			_mesh_inst.set_surface_override_material(i, material_surface)

func set_active(a: bool) -> void:
	_is_active = a
	visible = a
	if _body:
		_body.set_collision_layer_value(1, a)
		_body.set_collision_mask_value(1, a)
	if _mesh_inst: _mesh_inst.visible = a

func _on_screen_entered() -> void:
	_was_ever_on_screen = true
	_mesh_inst.visible = true

func _on_screen_exited() -> void:
	if _was_ever_on_screen: _mesh_inst.visible = false

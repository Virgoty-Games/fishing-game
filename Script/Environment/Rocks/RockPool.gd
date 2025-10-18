extends Node
class_name RockPool

@export_group("Assets")
@export var rock_meshes: Array[Mesh] = []
@export var material_underwater: Material
@export var material_surface: Material
@export var water_level: float = 0.0

@export_group("Pool")
## Controla el pico máximo esperado
@export var initial_pool_size: int = 200
@export var growth_step: int = 50

var _shape_cache: Array[Shape3D] = []
var _free_list: Array[Rock] = []
var _all: Array[Rock] = []

func _ready() -> void:
	_shape_cache.resize(rock_meshes.size())
	for i in rock_meshes.size():
		var m := rock_meshes[i]
		if m: _shape_cache[i] = m.create_trimesh_shape()
		
		_expand_pool(initial_pool_size)

func _expand_pool(amount: int) -> void:
	for i in amount:
		var r := Rock.new()
		add_child(r)
		r.owner = get_tree().edited_scene_root
		r.set_active(false)
		_all.append(r)
		_free_list.append(r)

func acquire_random() -> Rock:
	if _free_list.is_empty():
		_expand_pool(growth_step)
	var r : Variant = _free_list.pop_back()
	# Elegir mesh aleatoria y shape cacheada
	var idx : float = randi() % max(rock_meshes.size(), 1)
	var mesh := rock_meshes[idx] if rock_meshes.size() > 0 else null
	var shape := _shape_cache[idx] if _shape_cache.size() > 0 else null
	r.setup_from_mesh(mesh, shape, material_underwater, material_surface, water_level)
	r.set_active(true)
	return r

func release(r: Rock) -> void:
	if r == null:
		return
	r.set_active(false)
	_free_list.append(r)

func for_each_active(callback: Callable) -> void:
	for r in _all:
		if r.visible:
			callback.call(r)

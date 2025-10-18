extends Node3D
class_name RockSpawner

@export_group("Referencias")
@export var pool: NodePath
@export var player: NodePath
@export var camera: NodePath

@export_group("Mundo / Agua")
@export var water_level: float = 0.0
@export var seabed_base_y: float = -12.0
@export var seabed_noise_amp: float = 3.0
## más chico = cambios suaves, asegura consistencia
@export var seabed_noise_scale: float = 0.03
## micro variación local dentro de la celda
@export var seabed_small_variation: float = 0.8

@export_group("Densidad / Distribución")
## tamaño de celda para underwater
@export var cell_size: float = 8.0
## 0..1 probabilidad de roca por celda underwater
@export var underwater_density: float = 0.65
## grilla paralela para superficie
@export var surface_cell_size: float = 22.0
## probabilidad por celda de intentar colocar una roca
@export var surface_spawn_chance: float = 0.15
## distancia mínima entre rocas de superficie
@export var surface_min_spacing: float = 16.0

@export_group("Streaming / Rendimiento")
## todo lo que queda dentro vive
@export var active_radius: float = 120.0
## precarga un anillo por delante del movimiento
@export var preload_ahead: float = 80.0
## fuera de esto se libera al pool
@export var unload_radius: float = 160.0
## limita trabajo por frame (celdas a evaluar)
@export var updates_per_frame: int = 24
## también limita instancias nuevas por frame
@export var max_new_rocks_per_frame: int = 12

@export_group("Tester: parámetros simples")
@export var enable_underwater_rocks: bool = true
@export var enable_surface_rocks: bool = true

var _pool: RockPool
var _player: Node3D
var _camera: Camera3D
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()

# Estado por celda -> referencia a Rock o null si no hay.
var _cells_underwater := {}
var _cells_surface := {}

var _surface_positions := {}

func _ready() -> void:
	_pool = get_node_or_null(pool) as RockPool
	_player = get_node_or_null(player) as Node3D
	_camera = get_node_or_null(camera) as Camera3D
	assert(_pool and _player and _camera)

	_rng.seed = 1337
	_noise.seed = 1337
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = seabed_noise_scale

	_pool.water_level = water_level

	set_process(true)

func _process(_dt: float) -> void:
	if _player == null:
		return

	var pos := _player.global_position
	var fwd := _get_player_forward()

	# 1) Generar/precargar hacia adelante de la dirección de movimiento
	_stream_cells(pos, fwd)

	# 2) Apagar / liberar lo demasiado lejano
	_cull_far_rocks(pos)
	
func _get_player_forward() -> Vector3:
	# Si tenés una orientación particular del Player, podés cambiar este cálculo.
	return -_player.global_transform.basis.z.normalized()

func _stream_cells(player_pos: Vector3, forward: Vector3) -> void:
	var processed := 0
	var created := 0

	# Calculamos un centro adelantado para precarga:
	var preload_center := player_pos + forward * preload_ahead

	# Evaluamos celdas en un círculo (para underwater) y en otro para superficie.
	var max_r := int(ceil(unload_radius / cell_size))
	var center_cell := _to_cell(player_pos.x, player_pos.z, cell_size)
	var preload_cell := _to_cell(preload_center.x, preload_center.z, cell_size)

	# Alternamos chequeo: primero anillo delantero (preload), luego alrededor del player.
	for pas in range(2):
		var base : Vector2i = preload_cell if(pas == 0) else center_cell
		for dx in range(-max_r, max_r + 1):
			for dz in range(-max_r, max_r + 1):
				if processed >= updates_per_frame:
					return
				var c := Vector2i(base.x + dx, base.y + dz)
				var world_center := _cell_center(c, cell_size)
				var dist := world_center.distance_to(Vector2(player_pos.x, player_pos.z))
				if dist > unload_radius: continue

				# Underwater
				if enable_underwater_rocks and dist <= active_radius * 1.2:
					if _maybe_spawn_underwater_cell(c, world_center, player_pos):
						created += 1
						if created >= max_new_rocks_per_frame: return

				processed += 1

	# Superficie (celda más grande, menos densidad)
	if enable_surface_rocks:
		var max_r_s := int(ceil(unload_radius / surface_cell_size))
		var center_cell_s := _to_cell(player_pos.x, player_pos.z, surface_cell_size)
		var preload_cell_s := _to_cell(preload_center.x, preload_center.z, surface_cell_size)

		for pas in range(2):
			var base_s := preload_cell_s if (pas == 0) else center_cell_s
			for dx in range(-max_r_s, max_r_s + 1):
				for dz in range(-max_r_s, max_r_s + 1):
					if processed >= updates_per_frame:
						return
					var c2 := Vector2i(base_s.x + dx, base_s.y + dz)
					var world_center2 := _cell_center(c2, surface_cell_size)
					var dist2 := world_center2.distance_to(Vector2(player_pos.x, player_pos.z))
					if dist2 > unload_radius: continue

					if dist2 <= active_radius * 1.2:
						if _maybe_spawn_surface_cell(c2, world_center2, player_pos):
							created += 1
							if created >= max_new_rocks_per_frame: return
					processed += 1

func _maybe_spawn_underwater_cell(c: Vector2i, world_center: Vector2, player_pos: Vector3) -> bool:
	if _cells_underwater.has(c):
		return false

	# Probabilidad controlada por densidad
	if _rng.randf() > underwater_density:
		_cells_underwater[c] = null
		return false

	# Altura del lecho marino "consistente" (ruido suave)
	var seabed_y := _seabed_height(world_center.x, world_center.y)
	# Pequeña variación local para evitar planicies
	var local_dy := (_rng.randf() * 2.0 - 1.0) * seabed_small_variation
	var rock_y := seabed_y + local_dy
	
	# Asegurar que sea underwater
	rock_y = min(rock_y, water_level - 0.1)

	var half := cell_size * 0.5
	var pos := Vector3(world_center.x + _rng.randf_range(-half * 0.8, half * 0.8), rock_y, world_center.y + _rng.randf_range(-half * 0.8, half * 0.8)
	)

	# Instanciar y activar
	var r := _pool.acquire_random()
	r.global_position = pos
	r.water_level = water_level
	r.set_active(true)

	_cells_underwater[c] = r
	return true

func _maybe_spawn_surface_cell(c: Vector2i, world_center: Vector2, player_pos: Vector3) -> bool:
	if _cells_surface.has(c):
		return false

	if _rng.randf() > surface_spawn_chance:
		_cells_surface[c] = null
		return false

	var half := surface_cell_size * 0.5
	var pos := Vector3(
		world_center.x + _rng.randf_range(-half * 0.9, half * 0.9),
		water_level + _rng.randf_range(0.4, 4.0),
		world_center.y + _rng.randf_range(-half * 0.9, half * 0.9)
	)

	# Enforce Poisson-like: chequear mínima distancia a otras rocas de superficie
	if not _surface_far_enough(pos, surface_min_spacing):
		_cells_surface[c] = null
		return false

	var r := _pool.acquire_random()
	r.global_position = pos
	r.water_level = water_level
	r.set_active(true)

	_cells_surface[c] = r
	_surface_register(pos)
	return true

func _surface_far_enough(p: Vector3, min_dist: float) -> bool:
	var b := _bucket2i(p, min_dist)
	for dx in range(-1,2):
		for dz in range(-1,2):
			var key := Vector2i(b.x + dx, b.y + dz)
			if _surface_positions.has(key):
				for q in _surface_positions[key]:
					if p.distance_to(q) < min_dist: return false
	return true

func _surface_register(p: Vector3) -> void:
	var bd := surface_min_spacing
	var key := _bucket2i(p, bd)
	if not _surface_positions.has(key):
		_surface_positions[key] = []
	_surface_positions[key].append(p)

func _cull_far_rocks(player_pos: Vector3) -> void:
	# Recorremos underwater
	for c in _cells_underwater.keys():
		var r: Rock = _cells_underwater[c]
		if r == null:
			continue
		var d := r.global_position.distance_to(player_pos)
		if d > unload_radius:
			_pool.release(r)
			_cells_underwater[c] = null

	# Y superficie
	for c in _cells_surface.keys():
		var r2: Rock = _cells_surface[c]
		if r2 == null:
			continue
		var d2 := r2.global_position.distance_to(player_pos)
		if d2 > unload_radius:
			_pool.release(r2)
			_cells_surface[c] = null

func _to_cell(x: float, z: float, size: float) -> Vector2i:
	return Vector2i(floor(x / size), floor(z / size))

func _cell_center(c: Vector2i, size: float) -> Vector2:
	return Vector2((c.x + 0.5) * size, (c.y + 0.5) * size)

func _seabed_height(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x, z) # -1..1
	return seabed_base_y + n * seabed_noise_amp

func _bucket2i(p: Vector3, bucket: float) -> Vector2i:
	return Vector2i(floor(p.x / bucket), floor(p.z / bucket))

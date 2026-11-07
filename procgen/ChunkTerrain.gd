class_name ChunkTerrain
extends Node3D
## Terreno sin fin: trozos de CHUNK m alrededor de quien se mueve (el jugador, su coche o su
## nave). Cada trozo es una malla con su color por vértice y, los cercanos, colisión (un
## HeightMapShape3D, barato); árboles y rocas por trozo, siempre los mismos (semilla). Los trozos
## se construyen en hilos (WorkerThreadPool) y se sueltan al alejarse. Lo hecho a mano (el
## pueblo, el centro de un planeta) queda dentro de `core` y aquí no se repite.

const CHUNK := 64.0
const VIEW := 4          # trozos visibles alrededor (radio)
const NEAR_STEP := 2.0   # resolución cerca (m)
const FAR_STEP := 8.0    # resolución lejos (m)

## Altura del terreno: Callable(x, z) -> float. Color: Callable(x, z, h) -> Color.
var height_fn: Callable
var color_fn: Callable
var material: Material
## Zona ya hecha a mano (no se generan quads dentro).
var core := Rect2()
## Zona ya decorada a mano (aquí no se ponen árboles ni rocas).
var props_exclude := Rect2()
## Qué crece: Callable(x, z, h, rng) -> String ("" nada, "tree", "rock", "bush"); y quién lo pone.
var prop_fn: Callable
## Cuántos intentos de poner algo por trozo.
var prop_tries := 26
## Hierba alta en los trozos cercanos (matas por m²; 0 = sin hierba) y dónde crece:
## Callable(x, z, h) -> bool. Se calcula en el hilo (las alturas salen del propio trozo).
var grass_density := 0.0
var grass_accept: Callable
var grass_tip := Color("#86a347")
var grass_base := Color("#3d5a24")
var prop_builder: Callable   # Callable(parent: Node3D, kind: String, pos: Vector3, rng) -> void
## A quién seguir (Node3D). Si es null, al primer jugador del grupo "player".
var follow: Node3D
## Agua sin fin a esta altura (-INF: no hay).
var water_level := -INF
var water_shallow := Color("#2a8c9c")
var water_deep := Color("#08324f")

var _chunks := {}         # Vector2i -> {node, lod, collider}
var _pending := {}        # Vector2i -> task id
var _results := {}        # Vector2i -> datos construidos en un hilo
var _mutex := Mutex.new()
var _center := Vector2i(999999, 999999)
var _ahead_c := Vector2i(999999, 999999)
var _water: MeshInstance3D
var _check_t := 0.0


func _ready() -> void:
	add_to_group("chunk_terrain")
	if water_level > -INF:
		_water = Decor.water(self, Vector3(0, water_level, 0), Vector2(CHUNK * (VIEW * 2 + 3), CHUNK * (VIEW * 2 + 3)), water_shallow, water_deep)
		_water.name = "Mar"


func _exit_tree() -> void:
	for id in _pending.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()


func _target() -> Vector3:
	if follow and is_instance_valid(follow):
		var r: Variant = follow.get("riding")
		if r is Node3D and is_instance_valid(r):
			return (r as Node3D).global_position
		return follow.global_position
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var r2: Variant = players[0].get("riding")
		if r2 is Node3D and is_instance_valid(r2):
			return (r2 as Node3D).global_position
	return (players[0] as Node3D).global_position if not players.is_empty() else Vector3.ZERO


## Hacia dónde va (en un vehículo rápido, el suelo con colisión se prepara por delante).
func _ahead() -> Vector3:
	var who: Node3D = follow if follow and is_instance_valid(follow) else null
	if who == null:
		var players := get_tree().get_nodes_in_group("player")
		who = players[0] if not players.is_empty() else null
	if who == null:
		return Vector3.ZERO
	var r: Variant = who.get("riding")
	var v := Vector3.ZERO
	if r is RigidBody3D and is_instance_valid(r):
		v = (r as RigidBody3D).linear_velocity
	elif r is CharacterBody3D and is_instance_valid(r):
		v = (r as CharacterBody3D).velocity
	v.y = 0.0
	return v.limit_length(40.0) * 1.5


func _process(delta: float) -> void:
	var p := _target()
	if not p.is_finite() or InteriorManager.is_interior_pos(p):
		return
	if _water:  # el mar va contigo (a saltos de un trozo: las olas se calculan en el mundo)
		_water.position = Vector3(snappedf(p.x, CHUNK), water_level, snappedf(p.z, CHUNK))
	_collect()
	_check_t -= delta
	var c := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	var pa := p + _ahead()
	var ca := Vector2i(floori(pa.x / CHUNK), floori(pa.z / CHUNK))
	if c == _center and ca == _ahead_c and _check_t > 0.0:
		return
	_check_t = 0.25
	_center = c
	_ahead_c = ca
	_update_around(c)


## Construye ya (sin hilos) los trozos alrededor de un punto: para que al aparecer haya suelo.
func build_now(at: Vector3) -> void:
	var c := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := c + Vector2i(dx, dz)
			if _chunks.has(k) or _skip(k):
				continue
			var data := _make(k, NEAR_STEP, true)
			_install(k, data)
	_center = Vector2i(999999, 999999)


func _skip(k: Vector2i) -> bool:
	if core.size == Vector2.ZERO:
		return false
	var r := Rect2(Vector2(k.x, k.y) * CHUNK, Vector2(CHUNK, CHUNK))
	return core.encloses(r)


func _update_around(c: Vector2i) -> void:
	var want := {}
	for dz in range(-VIEW, VIEW + 1):
		for dx in range(-VIEW, VIEW + 1):
			if Vector2(dx, dz).length() > VIEW + 0.5:
				continue
			var k := c + Vector2i(dx, dz)
			if _skip(k):
				continue
			var near := absi(dx) <= 1 and absi(dz) <= 1
			var near_ahead := absi(k.x - _ahead_c.x) <= 1 and absi(k.y - _ahead_c.y) <= 1
			want[k] = 0 if near or near_ahead else 1
	# Soltar lo que queda lejos
	for k in _chunks.keys():
		if not want.has(k):
			(_chunks[k].node as Node).queue_free()
			_chunks.erase(k)
	# Pedir lo que falta (o cambiar de detalle), lo más cercano primero, pocos a la vez
	var keys := want.keys()
	keys.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	var started := 0
	for k in keys:
		var lod: int = want[k]
		if _chunks.has(k) and int(_chunks[k].lod) == lod:
			continue
		if _pending.has(k) or started >= 4:
			continue
		var step := NEAR_STEP if lod == 0 else FAR_STEP
		var near := lod == 0
		var key: Vector2i = k
		_pending[k] = WorkerThreadPool.add_task(func():
			var data := _make(key, step, near)
			data["lod"] = lod
			_mutex.lock()
			_results[key] = data
			_mutex.unlock())
		started += 1


func _collect() -> void:
	_mutex.lock()
	var done := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for k in done:
		if _pending.has(k):
			WorkerThreadPool.wait_for_task_completion(_pending[k])
			_pending.erase(k)
		if absi(k.x - _center.x) > VIEW + 1 or absi(k.y - _center.y) > VIEW + 1:
			continue  # ya quedó lejos mientras se hacía
		if _chunks.has(k):
			(_chunks[k].node as Node).queue_free()
		_install(k, done[k])


## Datos de un trozo (en un hilo: nada de nodos en el árbol aquí).
func _make(k: Vector2i, step: float, near: bool) -> Dictionary:
	var x0 := k.x * CHUNK
	var z0 := k.y * CHUNK
	var n := int(CHUNK / step)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			heights[j * (n + 1) + i] = float(height_fn.call(x0 + i * step, z0 + j * step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var xa := x0 + i * step
			var za := z0 + j * step
			if core.size != Vector2.ZERO and core.has_point(Vector2(xa + step * 0.5, za + step * 0.5)) \
					and core.has_point(Vector2(xa, za)) and core.has_point(Vector2(xa + step, za + step)):
				continue  # esto ya lo pinta el terreno hecho a mano
			var idx := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]
			for q in [0, 1, 2, 2, 1, 3]:
				var g: Vector2i = idx[q]
				var x := x0 + g.x * step
				var z := z0 + g.y * step
				var h := heights[g.y * (n + 1) + g.x]
				st.set_color(color_fn.call(x, z, h))
				st.add_vertex(Vector3(x, h, z))
	# Faldón: un borde que baja, para que no se vean rendijas entre trozos de distinto detalle
	if not near:
		for e in 4:
			for i in n:
				var a := Vector2i(i, 0) if e == 0 else (Vector2i(n, i) if e == 1 else (Vector2i(n - i, n) if e == 2 else Vector2i(0, n - i)))
				var b := Vector2i(i + 1, 0) if e == 0 else (Vector2i(n, i + 1) if e == 1 else (Vector2i(n - i - 1, n) if e == 2 else Vector2i(0, n - i - 1)))
				var pa := Vector3(x0 + a.x * step, heights[a.y * (n + 1) + a.x], z0 + a.y * step)
				var pb := Vector3(x0 + b.x * step, heights[b.y * (n + 1) + b.x], z0 + b.y * step)
				var col: Color = color_fn.call(pa.x, pa.z, pa.y)
				for v in [pa, pb, pa - Vector3(0, 4, 0), pa - Vector3(0, 4, 0), pb, pb - Vector3(0, 4, 0)]:
					st.set_color(col)
					st.add_vertex(v)
	st.generate_normals()
	# Solo los datos: la malla (un recurso del servidor de render) se crea en el hilo principal
	var out := {"arrays": st.commit_to_arrays(), "near": near, "heights": heights, "n": n, "step": step, "x0": x0, "z0": z0, "props": []}
	if near and prop_fn.is_valid():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(k.x, k.y))
		for t in prop_tries:
			var x := x0 + rng.randf() * CHUNK
			var z := z0 + rng.randf() * CHUNK
			if core.size != Vector2.ZERO and core.grow(6.0).has_point(Vector2(x, z)):
				continue
			if props_exclude.size != Vector2.ZERO and props_exclude.has_point(Vector2(x, z)):
				continue
			var h := float(height_fn.call(x, z))
			if water_level > -INF and h < water_level + 0.4:
				continue
			var kind: String = prop_fn.call(x, z, h, rng)
			if not kind.is_empty():
				out.props.append({"kind": kind, "pos": Vector3(x, h, z), "seed": rng.randi()})
	if near and grass_density > 0.0:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash(Vector2i(k.y, k.x)) + 17
		var tufts := []
		var count := int(CHUNK * CHUNK * grass_density)
		for t in count:
			var gx := rng2.randf() * CHUNK
			var gz := rng2.randf() * CHUNK
			var x := x0 + gx
			var z := z0 + gz
			if core.size != Vector2.ZERO and core.has_point(Vector2(x, z)):
				continue
			# Altura: interpolada de la rejilla del trozo (rápido, sin volver a calcular ruido)
			var fx := gx / step
			var fz := gz / step
			var ix := mini(int(fx), n - 1)
			var iz := mini(int(fz), n - 1)
			var tx := fx - ix
			var tz := fz - iz
			var h00 := heights[iz * (n + 1) + ix]
			var h10 := heights[iz * (n + 1) + ix + 1]
			var h01 := heights[(iz + 1) * (n + 1) + ix]
			var h11 := heights[(iz + 1) * (n + 1) + ix + 1]
			var h := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
			if water_level > -INF and h < water_level + 0.3:
				continue
			if grass_accept.is_valid() and not grass_accept.call(x, z, h):
				continue
			var sc := rng2.randf_range(0.7, 1.35)
			tufts.append(Transform3D(Basis(Vector3.UP, rng2.randf() * TAU).scaled(Vector3(sc, sc * rng2.randf_range(0.7, 1.3), sc)), Vector3(x, h - 0.03, z)))
		out["grass"] = tufts
	return out


func _install(k: Vector2i, data: Dictionary) -> void:
	var root := StaticBody3D.new()
	root.name = "Trozo_%d_%d" % [k.x, k.y]
	root.collision_layer = Layers.WORLD
	root.collision_mask = 0
	root.add_to_group("terrain")
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	root.add_child(mi)
	if data.near:
		# Colisión: un mapa de alturas (en el centro del trozo, escalado al paso)
		var n: int = data.n
		var hm := HeightMapShape3D.new()
		hm.map_width = n + 1
		hm.map_depth = n + 1
		hm.map_data = data.heights
		var cs := CollisionShape3D.new()
		cs.shape = hm
		var step: float = data.step
		cs.scale = Vector3(step, 1.0, step)
		cs.position = Vector3(data.x0 + CHUNK / 2.0, 0, data.z0 + CHUNK / 2.0)
		root.add_child(cs)
		var tufts: Array = data.get("grass", [])
		if not tufts.is_empty():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = Decor._tuft()
			mm.instance_count = tufts.size()
			for i in tufts.size():
				mm.set_instance_transform(i, tufts[i])
				mm.set_instance_custom_data(i, Color(fposmod(float(i) * 0.618, 1.0), 0, 0, 0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var gm := ShaderMaterial.new()
			gm.shader = Decor.GRASS_SHADER
			gm.set_shader_parameter("tip_color", grass_tip)
			gm.set_shader_parameter("base_color", grass_base)
			mmi.material_override = gm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 75.0
			mmi.add_to_group("grass")
			root.add_child(mmi)
			Decor.apply_grass_quality(mmi)
		if prop_builder.is_valid():
			for p in data.props:
				var rng := RandomNumberGenerator.new()
				rng.seed = int(p.seed)
				prop_builder.call(root, str(p.kind), p.pos, rng)
	add_child(root)
	_chunks[k] = {"node": root, "lod": int(data.get("lod", 0 if data.near else 1))}


## ¿Hay suelo construido bajo este punto? (para no soltar a nadie al vacío)
func has_ground(x: float, z: float) -> bool:
	if core.has_point(Vector2(x, z)):
		return true
	var k := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
	return _chunks.has(k) and int(_chunks[k].lod) == 0


# --- Naturaleza por bioma (para los trozos) -----------------------------------------------------

## Cuánto crece de cada cosa por bioma: [árbol, planta, roca] (probabilidad por intento).
const DENSITY := {
	"temperate": [0.3, 0.2, 0.08], "jungle": [0.5, 0.3, 0.06], "ocean": [0.12, 0.1, 0.08], "desert": [0.06, 0.05, 0.12],
	"ice": [0.08, 0.03, 0.14], "barren": [0.02, 0.05, 0.2], "volcanic": [0.02, 0.0, 0.3], "urban": [0.05, 0.05, 0.02],
	"pine": [0.45, 0.15, 0.08], "crystal": [0.0, 0.0, 0.25], "void": [0.0, 0.0, 0.1],
}


## Qué crece en un punto (para prop_fn): "tree", "plant", "rock" o "".
static func nature_chooser(biome: String) -> Callable:
	var d: Array = DENSITY.get(biome, DENSITY.temperate)
	return func(_x: float, _z: float, _h: float, rng: RandomNumberGenerator) -> String:
		var r := rng.randf()
		if r < float(d[0]):
			return "tree"
		r -= float(d[0])
		if r < float(d[1]):
			return "plant"
		r -= float(d[1])
		return "rock" if r < float(d[2]) else ""


## Pone el árbol, la planta o la roca del bioma (para prop_builder).
static func nature_placer(biome: String) -> Callable:
	return func(parent: Node3D, kind: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
		var k: int = {"tree": 0, "plant": 1, "rock": 2}.get(kind, 2)
		var model := AssetLibrary.nature(biome, k, rng)
		if model == null:
			return
		var h: float = [rng.randf_range(4.0, 9.0), rng.randf_range(0.5, 1.4), rng.randf_range(0.6, 2.6)][k]
		AssetLibrary.place(parent, model, pos - Vector3(0, 0.15 if k == 2 else 0.0, 0), h, rng.randf() * TAU, ["trunk", "bush", true][k])

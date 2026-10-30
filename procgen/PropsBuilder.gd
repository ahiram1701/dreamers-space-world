class_name PropsBuilder
extends RefCounted
## Decora un lugar según su tipo (asentamiento, ruinas, naturaleza…), su época y su bioma.
## Todo sale del RNG con semilla: el mismo lugar se decora igual cada vez que vuelves.

const SPAWN_CLEAR := 12.0    # nada encima del jugador al llegar
const BEACON_CLEAR := 6.0    # ni encima de las balizas

## Estilo de edificios por época: paredes, tejado, altura, forma.
const ERA_STYLE := {
	"prehistory": {"walls": ["#7a5c3a", "#8a6a45"], "roof": "#5a4630", "h": [2.0, 2.8], "shape": "hut"},
	"ancient": {"walls": ["#d8c9a3", "#cbb88f"], "roof": "#a0663c", "h": [3.0, 5.0], "shape": "house"},
	"medieval": {"walls": ["#9a958a", "#b0a894"], "roof": "#6e3b2a", "h": [3.5, 6.0], "shape": "house"},
	"industrial": {"walls": ["#8c3f2e", "#7a3a2a"], "roof": "#3a3a3a", "h": [5.0, 9.0], "shape": "factory"},
	"present": {"walls": ["#f4f1de", "#dfe7e2", "#f7e6c4"], "roof": "#a64b3c", "h": [3.0, 6.0], "shape": "house"},
	"near_future": {"walls": ["#6f8fb0", "#8fb0c8"], "roof": "#2a3a4a", "h": [8.0, 18.0], "shape": "tower"},
	"far_future": {"walls": ["#e8eef2", "#d6e4ee"], "roof": "#73d9ff", "h": [4.0, 14.0], "shape": "dome"},
	"deep_future": {"walls": ["#2a2f45", "#3a3f5a"], "roof": "#c77dff", "h": [10.0, 26.0], "shape": "spire"},
}


## Lo que la escena necesita saber de la decoración (se rellena durante build()):
##   features: [{id, kind, node, pos}] árboles, rocas y arbustos que se pueden talar o romper
##   buildings: [Node3D] edificios con puerta; removed: ids que ya no existen (talados).
static var _extras: Dictionary = {}


static func build(parent: Node3D, def: Dictionary, height_at: Callable, rng: RandomNumberGenerator, avoid: Array, extras: Dictionary = {}) -> void:
	_extras = extras
	var kind: String = def.get("kind", "wilderness")
	var biome: String = def.get("biome", "barren")
	match kind:
		"town":
			_settlement(parent, def, height_at, rng, avoid, 10)
		"city":
			_settlement(parent, def, height_at, rng, avoid, 22)
		"ruins":
			_ruins(parent, height_at, rng, avoid)
		"anomaly_zone":
			_floating_rocks(parent, rng, biome)
	if biome == "urban" and kind != "town" and kind != "city":
		_settlement(parent, def, height_at, rng, avoid, 14)
	_nature(parent, biome, height_at, rng, avoid, 0.5 if kind in ["town", "city", "ruins"] else 1.0)


# --- Asentamientos --------------------------------------------------------------------

static func _settlement(parent: Node3D, def: Dictionary, height_at: Callable, rng: RandomNumberGenerator, avoid: Array, count: int) -> void:
	var style: Dictionary = ERA_STYLE.get(def.get("era", "present"), ERA_STYLE["present"])
	var hub := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
	for i in count:
		var p := _free_spot(rng, avoid, hub, 8.0, 34.0)
		if p == Vector3.INF:
			continue
		p.y = height_at.call(p.x, p.z) - 0.3
		var h := rng.randf_range(style.h[0], style.h[1])
		var w := rng.randf_range(4.0, 7.0)
		var wall := Color(style.walls[rng.randi() % style.walls.size()])
		var roof := Color(style.roof)
		if style.shape in ["house", "factory"] or (style.shape == "tower" and rng.randf() < 0.5):
			var size_class := "city" if count > 15 or style.shape != "house" else ("town" if rng.randf() < 0.4 else "small")
			var model := AssetLibrary.building(size_class, rng, wall)
			if model:
				var b := AssetLibrary.bounds(model)
				var building := AssetLibrary.place(parent, model, p + Vector3(0, 0.25, 0), b.size.y * rng.randf_range(2.4, 3.0),
					atan2(hub.x - p.x, hub.y - p.z), true)  # mirando a la plaza
				if _extras.has("buildings"):
					_extras.buildings.append(building)
				avoid.append(p)
				continue
		if _extras.has("buildings"):  # también se entra en las cabañas, cúpulas y torres procedurales
			var marker := Node3D.new()
			marker.position = p
			marker.rotation.y = atan2(hub.x - p.x, hub.y - p.z)
			marker.set_meta("size", Vector3(w, h, w * (1.4 if style.shape == "dome" else 0.95)))
			parent.add_child(marker)
			_extras.buildings.append(marker)
		match style.shape:
			"hut":
				_cylinder(parent, p + Vector3(0, h / 2, 0), w * 0.4, w * 0.45, h, wall, true)
				_cone(parent, p + Vector3(0, h + 1.0, 0), w * 0.55, 2.0, roof)
			"house":
				_box(parent, p + Vector3(0, h / 2, 0), Vector3(w, h, w * 0.9), wall, true)
				_prism(parent, p + Vector3(0, h + 0.9, 0), Vector3(w + 0.6, 1.8, w * 0.9 + 0.6), roof)
			"factory":
				_box(parent, p + Vector3(0, h / 2, 0), Vector3(w * 1.6, h, w), wall, true)
				_cylinder(parent, p + Vector3(w * 0.5, h + 2.5, 0), 0.5, 0.6, 5.0, roof, true)
			"tower":
				_box(parent, p + Vector3(0, h / 2, 0), Vector3(w * 0.8, h, w * 0.8), wall, true)
				_emissive_box(parent, p + Vector3(0, h * 0.75, 0), Vector3(w * 0.82, 0.3, w * 0.82), Color(style.roof).lightened(0.5))
			"dome":
				_sphere(parent, p, w * 0.7, wall, true)
				_emissive_box(parent, p + Vector3(0, w * 0.7, 0), Vector3(0.4, 0.4, 0.4), roof)
				if rng.randf() < 0.4:
					_cylinder(parent, p + Vector3(w, h / 2, 0), 0.3, 0.6, h, wall, true)
			"spire":
				_cylinder(parent, p + Vector3(0, h / 2, 0), 0.4, w * 0.35, h, wall, true)
				_emissive_box(parent, p + Vector3(0, h, 0), Vector3(0.6, 0.6, 0.6), roof)
		avoid.append(p)


static func _ruins(parent: Node3D, height_at: Callable, rng: RandomNumberGenerator, avoid: Array) -> void:
	var stone := Color("#a39e93")
	for i in 12:
		var rp := _free_spot(rng, avoid, Vector2.ZERO, 14.0, 70.0)
		var rock := AssetLibrary.nature("barren", 2, rng)
		if rp != Vector3.INF and rock:
			AssetLibrary.place(parent, rock, rp + Vector3(0, height_at.call(rp.x, rp.z) - 0.2, 0), rng.randf_range(0.8, 2.5), rng.randf() * TAU, true)
	for i in 26:
		var p := _free_spot(rng, avoid, Vector2.ZERO, 14.0, 65.0)
		if p == Vector3.INF:
			continue
		p.y = height_at.call(p.x, p.z)
		var h := rng.randf_range(1.0, 7.0)
		var col := _cylinder(parent, p + Vector3(0, h / 2, 0), 0.45, 0.55, h, stone.darkened(rng.randf() * 0.2), true)
		col.rotation_degrees = Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		if rng.randf() < 0.4:
			_box(parent, p + Vector3(rng.randf_range(-2, 2), 0.4, rng.randf_range(-2, 2)),
				Vector3(rng.randf_range(1, 3), 0.8, rng.randf_range(0.8, 1.6)), stone, true)


static func _floating_rocks(parent: Node3D, rng: RandomNumberGenerator, biome: String) -> void:
	var c := Color(TerrainBuilder.palette(biome).high)
	for i in 18:
		var p := Vector3(rng.randf_range(-60, 60), rng.randf_range(8, 30), rng.randf_range(-60, 60))
		var rock := _sphere(parent, p, rng.randf_range(1.0, 4.0), c.darkened(0.3), false)
		rock.scale = Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.5, 1.0), rng.randf_range(0.7, 1.4))
		var tw := rock.create_tween().set_loops()
		tw.tween_property(rock, "position:y", p.y + 1.5, rng.randf_range(2.5, 5.0)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(rock, "position:y", p.y, rng.randf_range(2.5, 5.0)).set_trans(Tween.TRANS_SINE)


# --- Naturaleza por bioma -------------------------------------------------------------

static func _nature(parent: Node3D, biome: String, height_at: Callable, rng: RandomNumberGenerator, avoid: Array, density: float) -> void:
	var pal := TerrainBuilder.palette(biome)
	var n := int(40 * density)
	match biome:
		"temperate", "jungle", "urban", "ocean":
			var trees := n * (2 if biome == "jungle" else 1) / (2 if biome == "urban" else 1)
			for i in trees:
				_model_at(parent, biome, 0, height_at, rng, avoid, rng.randf_range(5.0, 9.0) * (1.4 if biome == "jungle" else 1.0), true)
			for i in n:
				_model_at(parent, biome, 1, height_at, rng, avoid, rng.randf_range(0.5, 1.4), false)
			for i in n / 3:
				_model_at(parent, biome, 2, height_at, rng, avoid, rng.randf_range(0.6, 2.2), true)
			if biome == "ocean":
				Decor.water(parent, Vector3(0, -0.45, 0), Vector2(TerrainBuilder.SIZE * 2, TerrainBuilder.SIZE * 2))
		"desert", "barren", "volcanic":
			for i in n:
				var big := rng.randf() < 0.3
				_model_at(parent, biome, 2, height_at, rng, avoid, rng.randf_range(2.0, 5.0) if big else rng.randf_range(0.5, 1.8), true, Color(pal.low))
				if biome == "volcanic" and rng.randf() < 0.3:
					var p := _free_spot(rng, avoid, Vector2.ZERO, 14.0, 75.0)
					if p != Vector3.INF:
						_emissive_sphere(parent, p + Vector3(0, height_at.call(p.x, p.z) + 0.05, 0), 0.8, Color("#ff5a1f"))
			if biome == "desert":
				for i in n / 2:
					_model_at(parent, biome, 0, height_at, rng, avoid, rng.randf_range(1.5, 3.5), true)
			if biome == "barren":
				for i in n / 6:
					_model_at(parent, biome, 0, height_at, rng, avoid, rng.randf_range(3.0, 6.0), true)
		"ice", "crystal":
			var tint := Color("#bfe6f5") if biome == "ice" else Color("#a7e0f0").lerp(Color("#c77dff"), rng.randf())
			if biome == "ice":
				for i in n / 2:
					_model_at(parent, biome, 0, height_at, rng, avoid, rng.randf_range(4.0, 8.0), true)
				for i in n / 3:
					_model_at(parent, biome, 2, height_at, rng, avoid, rng.randf_range(0.8, 2.6), true)
			for i in (n if biome == "crystal" else n / 2):
				var p := _free_spot(rng, avoid, Vector2.ZERO, 14.0, 75.0)
				if p == Vector3.INF:
					continue
				p.y = height_at.call(p.x, p.z)
				var h := rng.randf_range(1.5, 6.0)
				var spike := _cone(parent, p + Vector3(0, h / 2, 0), rng.randf_range(0.3, 1.0), h, tint)
				spike.rotation_degrees = Vector3(rng.randf_range(-15, 15), rng.randf() * 360.0, rng.randf_range(-15, 15))
				var m: StandardMaterial3D = spike.material_override
				m.roughness = 0.15
				m.metallic = 0.3
				if biome == "crystal":
					m.emission_enabled = true
					m.emission = tint
					m.emission_energy_multiplier = 0.8
		"void":
			_floating_rocks(parent, rng, biome)


## Coloca un modelo de naturaleza del bioma (árbol 0, planta 1, roca 2) en un punto libre.
## `tint`: si tiene alfa, oscurece las rocas hacia el color del suelo del bioma.
static func _model_at(parent: Node3D, biome: String, kind: int, height_at: Callable, rng: RandomNumberGenerator,
		avoid: Array, height: float, collide: bool, tint: Color = Color(0, 0, 0, 0)) -> void:
	var p := _free_spot(rng, avoid, Vector2.ZERO, 14.0 if kind != 1 else 6.0, 76.0)
	if p == Vector3.INF:
		return
	var model := AssetLibrary.nature(biome, kind, rng)
	var fid := "%s_%d_%d" % [["tree", "bush", "rock"][kind], roundi(p.x), roundi(p.z)]
	if fid in _extras.get("removed", []):  # lo talaste o rompiste: ya no está
		if model:
			model.free()
		return
	if model == null:
		if kind == 0:
			_cylinder(parent, p + Vector3(0, height_at.call(p.x, p.z) + height / 2, 0), 0.2, 0.35, height, Color("#5a4030"), true)
		return
	var root := AssetLibrary.place(parent, model, p + Vector3(0, height_at.call(p.x, p.z) - 0.1, 0), height, rng.randf() * TAU,
		("trunk" if kind == 0 else collide) if kind != 1 else "bush")
	if _extras.has("features"):
		_extras.features.append({"id": fid, "kind": ["tree", "bush", "rock"][kind], "node": root, "pos": p})
	if tint.a > 0.0:
		for mi in AssetLibrary._meshes(root):
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if src:
					var m := src.duplicate() as StandardMaterial3D
					m.albedo_color = src.albedo_color.lerp(tint, 0.55)
					mi.set_surface_override_material(i, m)


## Un punto libre dentro del anillo [min_r, max_r] alrededor de `hub`, lejos de lo ya colocado.
static func _free_spot(rng: RandomNumberGenerator, avoid: Array, hub: Vector2, min_r: float, max_r: float) -> Vector3:
	for attempt in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(min_r, max_r)
		var p := Vector3(hub.x + cos(a) * r, 0, hub.y + sin(a) * r)
		var limit := TerrainBuilder.SIZE / 2.0 - 6.0
		if absf(p.x) > limit or absf(p.z) > limit or Vector2(p.x, p.z).length() < SPAWN_CLEAR:
			continue
		var ok := true
		for q in avoid:
			if Vector2(p.x - q.x, p.z - q.z).length() < BEACON_CLEAR:
				ok = false
				break
		if ok:
			return p
	return Vector3.INF


# --- Primitivas -----------------------------------------------------------------------

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, shape: Shape3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	if shape:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


static func _box(parent: Node3D, pos: Vector3, size: Vector3, c: Color, collide: bool) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var s: Shape3D = null
	if collide:
		s = BoxShape3D.new()
		s.size = size
	return _add(parent, m, pos, c, s)


static func _emissive_box(parent: Node3D, pos: Vector3, size: Vector3, c: Color) -> void:
	var mi := _box(parent, pos, size, c, false)
	mi.material_override.emission_enabled = true
	mi.material_override.emission = c
	mi.material_override.emission_energy_multiplier = 2.0


static func _cylinder(parent: Node3D, pos: Vector3, top: float, bottom: float, h: float, c: Color, collide: bool) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	var s: Shape3D = null
	if collide:
		s = CylinderShape3D.new()
		s.radius = maxf(top, bottom)
		s.height = h
	return _add(parent, m, pos, c, s)


static func _cone(parent: Node3D, pos: Vector3, radius: float, h: float, c: Color) -> MeshInstance3D:
	return _cylinder(parent, pos, 0.0, radius, h, c, false)


static func _prism(parent: Node3D, pos: Vector3, size: Vector3, c: Color) -> void:
	var m := PrismMesh.new()
	m.size = size
	_add(parent, m, pos, c, null)


static func _sphere(parent: Node3D, pos: Vector3, radius: float, c: Color, collide: bool) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	var s: Shape3D = null
	if collide:
		s = SphereShape3D.new()
		s.radius = radius
	return _add(parent, m, pos, c, s)


static func _emissive_sphere(parent: Node3D, pos: Vector3, radius: float, c: Color) -> void:
	var mi := _sphere(parent, pos, radius, c, false)
	mi.scale.y = 0.15
	mi.material_override.emission_enabled = true
	mi.material_override.emission = c
	mi.material_override.emission_energy_multiplier = 3.0

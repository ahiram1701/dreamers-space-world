class_name StationBuilder
extends RefCounted
## Estaciones espaciales e interiores de nave: una cubierta flotando entre estrellas, con
## módulos, luces y un planeta en el cielo. Misma interfaz que TerrainBuilder.

const DECK := 72.0


static func is_space(def: Dictionary) -> bool:
	return def.get("kind", "") in ["space_station", "ship_interior"] or def.get("biome", "") == "void"


## Devuelve { node, height_at, limit }.
static func build(def: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var metal := Color("#5c6370")
	var deck := PropsBuilder._box(root, Vector3(0, -0.5, 0), Vector3(DECK, 1.0, DECK), metal, true)
	deck.material_override.metallic = 0.6
	deck.material_override.roughness = 0.4
	# Franjas de luz en la cubierta
	for i in range(-3, 4):
		PropsBuilder._emissive_box(root, Vector3(i * 10.0, 0.02, 0), Vector3(0.25, 0.05, DECK - 4), Color("#4fc3f7"))
	# Módulos (sin tapar el centro ni las balizas)
	var interior: bool = def.get("kind", "") == "ship_interior"
	for i in (10 if interior else 14):
		var p := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))
		if Vector2(p.x, p.z).length() < 12.0 or Vector2(p.x, p.z).length() > 26.0 and rng.randf() < 0.5:
			continue
		var size := Vector3(rng.randf_range(3, 8), rng.randf_range(2.5, 6), rng.randf_range(3, 8))
		PropsBuilder._box(root, p + Vector3(0, size.y / 2, 0), size, metal.lightened(rng.randf() * 0.2), true)
		PropsBuilder._emissive_box(root, p + Vector3(0, size.y + 0.05, 0), Vector3(size.x * 0.6, 0.1, 0.2), Color("#f2a65a"))
	# Barandillas invisibles para no caer al vacío
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.shape.size = Vector3(DECK if side.x == 0 else 1.0, 6.0, DECK if side.z == 0 else 1.0)
		wall.add_child(cs)
		wall.position = side * (DECK / 2.0) + Vector3(0, 3, 0)
		root.add_child(wall)
		var rail := PropsBuilder._box(root, side * (DECK / 2.0 - 0.3) + Vector3(0, 0.6, 0),
			Vector3(DECK if side.x == 0 else 0.15, 0.1, DECK if side.z == 0 else 0.15), Color("#9aa3b0"), false)
		rail.material_override.metallic = 0.8
	if interior:
		var ceiling := PropsBuilder._box(root, Vector3(0, 12, 0), Vector3(DECK, 0.5, DECK), metal.darkened(0.3), false)
		ceiling.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	return {"node": root, "height_at": func(_x: float, _z: float) -> float: return 0.0, "limit": DECK / 2.0 - 2.0}


## Estrellas y un planeta en el cielo (para estaciones y el vacío).
static func add_starfield(parent: Node3D, rng: RandomNumberGenerator, planet_color: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var star := SphereMesh.new()
	star.radius = 0.7
	star.height = 1.4
	star.radial_segments = 6
	star.rings = 3
	mm.mesh = star
	mm.instance_count = 700
	for i in mm.instance_count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), dir * 420.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1, 1, 1)
	stars.material_override = sm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stars)
	var planet := PropsBuilder._sphere(parent, Vector3(rng.randf_range(-200, 200), rng.randf_range(40, 140), -300), 90.0, planet_color, false)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

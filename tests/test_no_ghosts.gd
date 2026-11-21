extends SceneTree
## v0.15.0: no se choca con nada que no se vea. La inversa de test_collision.gd: para cada cosa
## sólida (los modelos que coloca AssetLibrary.place y las piezas de PropsBuilder/PoiCatalog) se
## lanzan rayos horizontales hacia su centro a la altura de las piernas, la cintura y la cabeza, una
## vez contra su colisión y otra contra lo que se ve de ella. Si la colisión para el rayo bastante
## antes que lo visible (o donde no hay nada que ver), ahí hay una pared invisible.
##   godot --headless --path . -s tests/test_no_ghosts.gd

const VISUAL_LAYER := 1 << 20   # capa solo de esta prueba
const TOLERANCE := 0.35         # menos que esto no se nota (la cápsula del jugador mide 0.32 de radio)
const HEIGHTS := [0.4, 1.0, 1.7]
const BODY_SPAN := [0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0, 1.2, 1.4, 1.6, 1.8]  # el cuerpo del jugador
const DIRS := 16

var _failed := 0
var _ghost_bodies: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de fantasmas")

	# 1. El pueblo y el campo
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 6:
		await process_frame
	await _check(town, "el pueblo y el campo")
	town.queue_free()
	await process_frame

	# 2. Cada interior
	var builder = load("res://procgen/InteriorBuilder.gd")
	for kind in builder.ROOMS:
		var holder := Node3D.new()
		root.add_child(holder)
		builder.build(holder, kind, 4242, Vector3(0, -400, 0))
		await _check(holder, "interior «%s»" % kind)
		holder.queue_free()
		await process_frame

	# 3. Mundos generados: asentamientos de cada época, ruinas, naturaleza de cada bioma
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var defs := [
		{"kind": "town", "biome": "temperate", "era": "present"}, {"kind": "city", "biome": "urban", "era": "present"},
		{"kind": "town", "biome": "desert", "era": "ancient"}, {"kind": "town", "biome": "temperate", "era": "medieval"},
		{"kind": "city", "biome": "barren", "era": "industrial"}, {"kind": "planet_surface", "biome": "ice"},
		{"kind": "ruins", "biome": "jungle"}, {"kind": "wilderness", "biome": "ocean"}, {"kind": "wilderness", "biome": "crystal"},
		{"kind": "anomaly_zone", "biome": "volcanic"},
	]
	for def in defs:
		var holder := Node3D.new()
		root.add_child(holder)
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		load("res://procgen/PropsBuilder.gd").build(holder, def, flat, rng, [], {})
		await _check(holder, "mundo %s/%s" % [def.kind, def.biome])
		holder.queue_free()
		await process_frame

	# 4. Los puntos de interés (faro, mina, cueva, invernadero…)
	var Poi = load("res://procgen/PoiCatalog.gd")
	for kind in Poi.KINDS:
		var holder := Node3D.new()
		root.add_child(holder)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		Poi.build(holder, kind, rng, Color("#8a8478"))
		await _check(holder, "punto de interés «%s»" % kind)
		holder.queue_free()
		await process_frame

	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:
		await process_frame
	quit(_failed)


## Las cosas sólidas que se comprueban: el cuerpo de un modelo colocado o de una pieza primitiva.
func _solids(scene: Node) -> Array:
	var out := []
	for body in scene.find_children("*", "StaticBody3D", true, false):
		if body.has_meta("invisible_ok") or body.collision_layer & Layers.WORLD == 0:
			continue
		var holder: Node = body.get_parent()
		if holder == null or not (holder.has_meta("size") or holder is MeshInstance3D):
			continue
		if _exempt(holder):
			continue
		out.append(body)
	return out


func _exempt(n: Node) -> bool:
	while n != null:
		if n is CharacterBody3D or n is VehicleBody3D or n is RigidBody3D or n.has_meta("invisible_ok"):
			return true
		var s = n.get_script()
		if s != null and str(s.resource_path).ends_with("Boat.gd"):
			return true
		n = n.get_parent()
	return false


## Lo que se ve de un sólido, como colisión de prueba (en una capa aparte).
func _visual_body(body: StaticBody3D) -> StaticBody3D:
	var holder: Node3D = body.get_parent()
	var faces := PackedVector3Array()
	var meshes: Array = [holder] if holder is MeshInstance3D else []
	meshes.append_array(holder.find_children("*", "MeshInstance3D", true, false))
	for mi in meshes:
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var t: Transform3D = mi.global_transform
		for v in mi.mesh.get_faces():
			faces.append(t * v)
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var ghost := StaticBody3D.new()
	ghost.collision_layer = VISUAL_LAYER
	ghost.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ghost.add_child(cs)
	root.add_child(ghost)
	return ghost


## Cajas (en el mundo) de las formas de colisión de un cuerpo, una por forma.
func _shape_boxes(body: StaticBody3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for cs in body.find_children("*", "CollisionShape3D", true, false):
		if cs.disabled or cs.shape == null:
			continue
		var local: AABB
		if cs.shape is ConvexPolygonShape3D or cs.shape is ConcavePolygonShape3D:
			var pts: PackedVector3Array = cs.shape.points if cs.shape is ConvexPolygonShape3D else cs.shape.get_faces()
			if pts.is_empty():
				continue
			local = AABB(pts[0], Vector3.ZERO)
			for p in pts:
				local = local.expand(p)
		else:
			local = cs.shape.get_debug_mesh().get_aabb()
		out.append(cs.global_transform * local)
	return out


## Centro (a la altura `y`) de las formas que llegan a esa altura: un tronco por tramos se apunta
## en cada tramo, no en el centro de todo el árbol.
func _center_at(boxes: Array[AABB], y: float, fallback: Vector3) -> Vector3:
	var u := AABB()
	var first := true
	for b in boxes:
		if y >= b.position.y - 0.01 and y <= b.end.y + 0.01:
			u = b if first else u.merge(b)
			first = false
	return fallback if first else Vector3(u.get_center().x, y, u.get_center().z)


## Primer impacto del rayo contra `target` (ignorando todo lo demás de esa capa).
func _hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, target: CollisionObject3D) -> float:
	var exclude: Array[RID] = []
	for attempt in 12:
		var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return INF
		if hit.collider == target:
			return from.distance_to(hit.position)
		exclude.append(hit.rid)
	return INF


func _check(scene: Node3D, label: String) -> void:
	var solids := _solids(scene)
	var pairs := []
	for body in solids:
		var ghost := _visual_body(body)
		pairs.append([body, ghost])
	await physics_frame
	await physics_frame
	var space := scene.get_world_3d().direct_space_state
	var ghosts := []
	for pair in pairs:
		var body: StaticBody3D = pair[0]
		var visual: StaticBody3D = pair[1]
		var boxes := _shape_boxes(body)
		if boxes.is_empty():
			continue
		var box: AABB = boxes[0]
		for b in boxes:
			box = box.merge(b)
		var reach := Vector2(box.size.x, box.size.z).length() / 2.0 + 0.6
		var worst := 0.0
		var worst_h := 0.0
		for h in HEIGHTS:
			if h > box.size.y - 0.05:
				continue  # (rozando la cara de arriba no cuenta: ahí ni la vista ni la colisión son exactas)
			var y: float = box.position.y + h
			var c := _center_at(boxes, y, Vector3(box.get_center().x, y, box.get_center().z))
			for k in DIRS:
				var a := TAU * k / DIRS
				var out := Vector3(cos(a), 0, sin(a))
				var dc := _hit(space, c + out * reach, c, body.collision_layer, body)
				if dc == INF:
					continue
				# Lo que el cuerpo (de los tobillos a la cabeza) toca primero por este lado: el aire bajo
				# un tablero no se nota, porque el tablero ya te para.
				var dv := reach
				if visual != null:
					for hv in BODY_SPAN:
						var cv := Vector3(c.x, box.position.y + hv, c.z)
						dv = minf(dv, _hit(space, cv + out * reach, cv, VISUAL_LAYER, visual))
				if dv - dc > worst:
					worst = dv - dc
					worst_h = h
		if worst > TOLERANCE:
			ghosts.append("%s (%.1f m de aire a %.1f m)" % [_name(body), worst, worst_h])
	for pair in pairs:
		if pair[1] != null:
			pair[1].queue_free()
	_expect(ghosts.is_empty(), "%s: nada invisible estorba (%d sólidos) %s" % [label, solids.size(), ghosts.slice(0, 10)])
	if ghosts.size() > 10:
		print("      … y %d más" % (ghosts.size() - 10))


func _name(body: Node) -> String:
	var holder: Node = body.get_parent()
	if holder is MeshInstance3D:
		return "%s %s" % [holder.mesh.get_class().trim_suffix("Mesh"), str(holder.name)]
	for c in holder.get_children():
		if not (c is CollisionObject3D):
			var path := str(c.scene_file_path)
			return path.get_file().get_basename() if not path.is_empty() else str(c.name)
	return str(holder.name)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

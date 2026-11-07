class_name Creations
extends RefCounted
## Todo lo que el jugador (o la IA, con el agente creador) crea en el mundo: un banco, un carrito,
## una caseta, una máquina, una nave. Cada creación es un dato que se guarda en el mundo y se
## reconstruye igual al volver:
##   {id, name, pos [x,y,z], yaw, scale, model ("pack/Modelo") o parts [...], color, behaviors [...]}
## Las piezas: {shape, size [x,y,z] m, pos [x,y,z] m (desde el centro de la base), rot [x,y,z]
## grados, color "#rrggbb", material, role}. Formas: box, cylinder, sphere, capsule, cone, torus,
## ramp, wheel. Materiales: wood, metal, glass, fabric, stone, plastic, rubber, emissive.
## Los comportamientos los pone Behaviors (asiento, luz, puerta, ruedas y motor…).

const MAX_HERE := 150
const MAX_PARTS := 48
const SHAPES := ["box", "cylinder", "sphere", "capsule", "cone", "torus", "ramp", "wheel"]
const MATERIALS := ["wood", "metal", "glass", "fabric", "stone", "plastic", "rubber", "emissive", "paint"]

static var _catalog: Array = []


# --- Datos ----------------------------------------------------------------------------------

static func all_here(place: String = "") -> Array:
	if place.is_empty():
		place = GameState.current_location()
	return WorldDB.get_state("creations", {}).get(place, [])


static func get_entry(id: String) -> Dictionary:
	for e in all_here():
		if e.id == id:
			return e
	return {}


static func _save_here(list: Array) -> void:
	var all: Dictionary = WorldDB.get_state("creations", {})
	all[GameState.current_location()] = list
	WorldDB.set_state("creations", all)


## Guarda una creación nueva (le pone id). Devuelve la entrada guardada o {} si ya no cabe.
static func add(entry: Dictionary) -> Dictionary:
	var list := all_here()
	if list.size() >= MAX_HERE:
		return {}
	var e := entry.duplicate(true)
	e["id"] = "c%d_%d" % [Time.get_ticks_msec() % 100000, randi() % 10000]
	if not e.has("behaviors"):
		e["behaviors"] = []
	list.append(e)
	_save_here(list)
	return e


static func update(id: String, fields: Dictionary) -> Dictionary:
	var list := all_here()
	for i in list.size():
		if list[i].id == id:
			list[i].merge(fields, true)
			_save_here(list)
			return list[i]
	return {}


static func remove(id: String) -> bool:
	var list := all_here()
	var n := list.size()
	list = list.filter(func(e): return e.id != id)
	_save_here(list)
	return list.size() < n


# --- Catálogo de modelos (data/catalog.json, generado por tools/make_catalog.py) ------------

static func catalog() -> Array:
	if _catalog.is_empty():
		var f := FileAccess.open("res://data/catalog.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_catalog = parsed.get("models", [])
	return _catalog


## Modelos que pegan con lo que se busca (por nombre y etiquetas), los mejores primero.
static func search(query: String, limit: int = 12) -> Array:
	var words := query.to_lower().replace(",", " ").split(" ", false)
	var scored := []
	for m in catalog():
		var hay := (str(m.name) + " " + " ".join(PackedStringArray(m.tags)) + " " + str(m.model)).to_lower()
		var score := 0
		for w in words:
			if w.length() < 3:
				continue
			if str(m.name).to_lower().begins_with(w):
				score += 3
			elif hay.contains(w) or hay.contains(w.left(-1)):
				score += 1
		if score > 0:
			scored.append({"m": m, "s": score})
	scored.sort_custom(func(a, b): return a.s > b.s)
	return scored.slice(0, limit).map(func(x): return x.m)


static func model_info(model: String) -> Dictionary:
	for m in catalog():
		if m.model == model:
			return m
	return {}


# --- Construcción ---------------------------------------------------------------------------

## Hooks que ponen otros sistemas (Vehicle, en la fase de vehículos).
static var vehicle_builder: Callable


## Construye una creación dentro de `scene`. Devuelve su nodo raíz (con meta "creation_id").
static func build(scene: Node3D, e: Dictionary) -> Node3D:
	var behaviors: Array = e.get("behaviors", [])
	var types: Array = behaviors.map(func(b): return str(b.get("type", "")))
	var pos := Vector3(e.pos[0], e.pos[1], e.pos[2])
	var root: Node3D
	if vehicle_builder.is_valid() and (("wheels" in types and ("engine" in types or "pedals" in types)) or "thruster" in types or ("float" in types and "engine" in types)):
		root = vehicle_builder.call(scene, e)
		if root:
			root.set_meta("creation_id", e.id)  # (un vehículo no lleva su nombre flotando: lo dice el aviso al acercarte)
			for b in behaviors:
				Behaviors.attach(root, b, scene, e)
			return root
	var rigid := "rigid" in types
	if rigid:
		var rb := RigidBody3D.new()
		rb.mass = clampf(float(e.get("mass", 20.0)), 1.0, 2000.0)
		rb.collision_layer = Layers.WORLD
		rb.collision_mask = Layers.WORLD | Layers.CHARACTERS
		root = rb
	else:
		root = Node3D.new()
	root.name = "Creation_" + str(e.id)
	root.set_meta("creation_id", e.id)
	root.set_meta("placed_id", e.id)
	scene.add_child(root)
	root.global_position = pos
	root.rotation.y = float(e.get("yaw", 0.0))
	var s := clampf(float(e.get("scale", 1.0)), 0.1, 20.0)
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * s
	root.add_child(body)
	if not str(e.get("model", "")).is_empty():
		var parts_m: PackedStringArray = str(e.model).split("/")
		var model := AssetLibrary.instance(parts_m[0], parts_m[1]) if parts_m.size() == 2 else null
		if model:
			var h := float(e.get("height", model_info(str(e.model)).get("height", 1.0)))
			var placed := AssetLibrary.place(body, model, Vector3.ZERO, h, 0.0, not rigid)
			if e.has("color") and Color.html_is_valid(str(e.color)):
				_tint(placed, Color(str(e.color)))
	for i in mini(e.get("parts", []).size(), MAX_PARTS):
		_part(body, e.parts[i], i, not rigid)
	if rigid:
		_rigid_shapes(root as RigidBody3D, body)
	_label(root, str(e.get("name", "")), e)
	for b in behaviors:
		Behaviors.attach(root, b, scene, e)
	return root


static func _label(root: Node3D, text: String, e: Dictionary) -> void:
	if text.is_empty():
		return
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 32
	label.outline_size = 8
	label.visibility_range_end = 18.0
	label.position.y = top_of(root) + 0.4
	root.add_child(label)


## Altura de lo construido (para poner encima una luz o el nombre).
static func top_of(root: Node3D) -> float:
	var top := 0.5
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var aabb := mi.get_aabb()
		var t := root.global_transform.affine_inverse() * mi.global_transform
		for k in 8:
			top = maxf(top, (t * aabb.get_endpoint(k)).y)
	return top


static func material(kind: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	match kind:
		"metal":
			m.metallic = 0.85
			m.roughness = 0.35
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35
			m.roughness = 0.05
			m.metallic_specular = 0.9
		"fabric":
			m.roughness = 1.0
		"stone":
			m.roughness = 0.95
		"plastic":
			m.roughness = 0.45
		"rubber":
			m.roughness = 0.9
			m.albedo_color = color.darkened(0.2)
		"paint":
			m.roughness = 0.3
			m.metallic = 0.3
		"emissive":
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 1.6
	return m


## Una pieza. Las puertas (role "door") giran desde su borde izquierdo: van dentro de una bisagra.
static func _part(body: Node3D, p: Dictionary, index: int, collide: bool) -> Node3D:
	var shape := str(p.get("shape", "box"))
	if not shape in SHAPES:
		shape = "box"
	var size := _vec(p.get("size", [0.5, 0.5, 0.5]), Vector3.ONE * 0.5).clamp(Vector3.ONE * 0.01, Vector3.ONE * 30.0)
	var at := _vec(p.get("pos", [0, size.y / 2.0, 0]), Vector3(0, size.y / 2.0, 0))
	var rot := _vec(p.get("rot", [0, 0, 0]), Vector3.ZERO)
	var color := Color(str(p.color)) if Color.html_is_valid(str(p.get("color", ""))) else Color("#8b6b4a")
	var mesh: Mesh
	var col: Shape3D
	match shape:
		"box":
			mesh = BoxMesh.new()
			mesh.size = size
			col = BoxShape3D.new()
			col.size = size
		"ramp":
			mesh = PrismMesh.new()
			mesh.size = size
			mesh.left_to_right = 1.0
			col = ConvexPolygonShape3D.new()
			col.points = mesh.get_faces()
		"cylinder", "wheel":
			mesh = CylinderMesh.new()
			mesh.top_radius = size.x / 2.0
			mesh.bottom_radius = size.x / 2.0
			mesh.height = size.y
			col = CylinderShape3D.new()
			col.radius = size.x / 2.0
			col.height = size.y
			if shape == "wheel" and p.get("rot", []).is_empty():
				rot = Vector3(0, 0, 90)  # de canto, como una rueda
		"cone":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = size.x / 2.0
			mesh.height = size.y
			col = CylinderShape3D.new()
			col.radius = size.x / 2.0
			col.height = size.y
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = size.x / 2.0
			mesh.height = size.y
			col = SphereShape3D.new()
			col.radius = size.x / 2.0
		"capsule":
			mesh = CapsuleMesh.new()
			mesh.radius = size.x / 2.0
			mesh.height = maxf(size.y, size.x)
			col = CapsuleShape3D.new()
			col.radius = size.x / 2.0
			col.height = maxf(size.y, size.x)
		"torus":
			mesh = TorusMesh.new()
			mesh.outer_radius = size.x / 2.0
			mesh.inner_radius = maxf(size.x / 2.0 - maxf(size.y, 0.02), 0.005)
			col = CylinderShape3D.new()
			col.radius = size.x / 2.0
			col.height = size.y
	var mi := MeshInstance3D.new()
	mi.name = "Part_%d" % index
	mi.mesh = mesh
	mi.material_override = material(str(p.get("material", "wood")), color)
	mi.set_meta("part", p)
	var holder: Node3D = body
	if str(p.get("role", "")) == "door":
		var hinge := Node3D.new()
		hinge.name = "Hinge_%d" % index
		hinge.position = at + Vector3(-size.x / 2.0, 0, 0)
		hinge.rotation_degrees = rot
		body.add_child(hinge)
		mi.position = Vector3(size.x / 2.0, 0, 0)
		hinge.add_child(mi)
		holder = hinge
	else:
		mi.position = at
		mi.rotation_degrees = rot
		body.add_child(mi)
	var big := size.x * size.z > 0.04 or size.y > 0.4
	if collide and big and str(p.get("material", "")) != "emissive":
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = col
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


static func _rigid_shapes(rb: RigidBody3D, body: Node3D) -> void:
	for m in body.find_children("Part_*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mi.get_aabb().size * body.scale
		cs.shape = box
		var t := rb.global_transform.affine_inverse() * mi.global_transform
		cs.basis = t.basis.orthonormalized()
		cs.position = t * mi.get_aabb().get_center()
		rb.add_child(cs)
	if rb.get_child_count() <= 2:  # un modelo sin piezas: una caja de su tamaño
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var aabb := AssetLibrary.bounds(body)
		box.size = aabb.size.max(Vector3.ONE * 0.1)
		cs.shape = box
		cs.position = aabb.get_center()
		rb.add_child(cs)


static func _tint(node: Node, c: Color) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src:
				var d := src.duplicate() as StandardMaterial3D
				d.albedo_color = src.albedo_color.lerp(c, 0.65)
				mi.set_surface_override_material(i, d)


## Caja que ocupa una pieza (con su giro), en el espacio del objeto.
static func part_bounds(p: Dictionary, scale: float = 1.0) -> AABB:
	var size := _vec(p.get("size", [0.5, 0.5, 0.5]), Vector3.ONE * 0.5) * scale
	var at := _vec(p.get("pos", [0, 0, 0]), Vector3.ZERO) * scale
	var rot := _vec(p.get("rot", [0, 0, 0]), Vector3.ZERO)
	if str(p.get("shape", "")) == "wheel" and p.get("rot", []).is_empty():
		rot = Vector3(0, 0, 90)
	if str(p.get("shape", "")) == "capsule":
		size.y = maxf(size.y, size.x)
	var b := Basis.from_euler(rot * PI / 180.0)
	var ext := (b.x * size.x).abs() + (b.y * size.y).abs() + (b.z * size.z).abs()
	return AABB(at - ext / 2.0, ext)


static func _vec(v: Variant, fallback: Vector3) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Vector3:
		return v
	return fallback


## Busca el nodo construido de una creación en la escena (o null).
static func node_of(scene: Node, id: String) -> Node3D:
	for n in scene.get_children():
		if n is Node3D and str(n.get_meta("creation_id", "")) == id:
			return n
	return null


## Una frase por creación cercana (para la IA y para el jugador).
static func describe_near(pos: Vector3, radius: float = 30.0) -> PackedStringArray:
	var out := PackedStringArray()
	for e in all_here():
		var p := Vector3(e.pos[0], e.pos[1], e.pos[2])
		if p.distance_to(pos) <= radius:
			var b: Array = e.get("behaviors", []).map(func(x): return str(x.get("type", "")))
			out.append("%s «%s» a %d m%s" % [e.id, e.get("name", "algo"), int(p.distance_to(pos)), (" (" + ", ".join(PackedStringArray(b)) + ")") if not b.is_empty() else ""])
	return out

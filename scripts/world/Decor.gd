class_name Decor
extends RefCounted
## Detalles que dan vida a un escenario: hierba con viento, agua con olas, farolas que se
## encienden de noche. Los usan el pueblo del Acto 0 y los lugares generados.

const WATER_SHADER := preload("res://shaders/water.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

## Material de suelo con colores por vértice (bioma, arena, caminos) + variación procedural.
## Un letrero o texto flotante que se desvanece a lo lejos (de noche, un texto blanco diminuto a
## 100 m se veía como una luz). `far`: hasta dónde se lee.
static func fade_label(l: Label3D, far: float = 70.0) -> void:
	l.visibility_range_end = far
	l.visibility_range_end_margin = far * 0.15
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	l.modulate = l.modulate * Color(0.9, 0.9, 0.9, 1.0)


static func ground_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	return m


## Plano de agua animado de `size` metros, subdividido para que se vean las olas.
static func water(parent: Node3D, center: Vector3, size: Vector2, shallow: Color = Color("#2a8c9c"), deep: Color = Color("#08324f")) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	var q := Settings.graphics_quality
	plane.subdivide_width = int(size.x / (1.5 if q >= 1 else 3.0))
	plane.subdivide_depth = int(size.y / (1.5 if q >= 1 else 3.0))
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("shallow_color", shallow)
	m.set_shader_parameter("deep_color", deep)
	mi.material_override = m
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Hierba en una zona. `accept(x, z)` decide dónde puede crecer; `height_at(x, z)` la altura.
static func grass(parent: Node3D, center: Vector2, half_size: Vector2, density: float, rng: RandomNumberGenerator,
		height_at: Callable, accept: Callable, tip: Color = Color("#8fae4a"), base: Color = Color("#2e4a1c")) -> void:
	# Se crea entera y la calidad decide cuánta se ve (así cambiarla en Ajustes se nota al momento)
	var count := int(half_size.x * half_size.y * 4.0 * density)
	if count <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _tuft()
	var transforms := []
	for i in count * 2:
		if transforms.size() >= count:
			break
		var x := center.x + rng.randf_range(-half_size.x, half_size.x)
		var z := center.y + rng.randf_range(-half_size.y, half_size.y)
		if not accept.call(x, z):
			continue
		var s := rng.randf_range(0.7, 1.3)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.3), s))
		transforms.append(Transform3D(basis, Vector3(x, height_at.call(x, z) - 0.03, z)))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = GRASS_SHADER
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("base_color", base)
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 70.0
	mmi.add_to_group("grass")
	parent.add_child(mmi)
	apply_grass_quality(mmi)


const GRASS_DENSITY := [0.35, 0.7, 1.0]


## Cuánta hierba se ve según la calidad gráfica (sin reconstruirla).
static func apply_grass_quality(mmi: MultiMeshInstance3D) -> void:
	var mm := mmi.multimesh
	mm.visible_instance_count = int(mm.instance_count * GRASS_DENSITY[clampi(Settings.graphics_quality, 0, 2)])


## Mata de hierba: 7 briznas finas en abanico (UV.y = 0 en la punta, para el viento).
static func _tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.02, 0.16)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.18)
		var h := rng.randf_range(0.28, 0.5)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.025
		st.set_uv(Vector2(0, 1))
		st.add_vertex(off - side)
		st.set_uv(Vector2(1, 1))
		st.add_vertex(off + side)
		st.set_uv(Vector2(0.5, 0))
		st.add_vertex(off + lean + Vector3(0, h, 0))
	st.generate_normals()
	return st.commit()


## Farola (modelo CC0) con luz que se enciende de noche. Devuelve la luz.
static func streetlight(parent: Node3D, pos: Vector3, yaw: float, fx: EnvironmentFX) -> OmniLight3D:
	var model := AssetLibrary.instance("street_pack", "Streetlight_Single")
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc47a")
	light.omni_range = 11.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	# Desde lejos la luz ni se calcula (el halo de cien farolas en fila parecía una hilera de focos)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 55.0
	light.distance_fade_length = 15.0
	var glass: StandardMaterial3D = null
	if model:
		AssetLibrary.place(parent, model, pos, 4.4, yaw, true)
		# La luz va DEBAJO del farol: dentro, a centímetros del cristal, lo quemaba a blanco puro
		light.position = pos + Vector3(0, 3.55, 0)
		glass = _lantern_glass(model)
	else:
		PropsBuilder._cylinder(parent, pos + Vector3(0, 2.2, 0), 0.08, 0.1, 4.4, Color("#2a3a2e"), true)
		light.position = pos + Vector3(0, 4.3, 0)
	parent.add_child(light)
	if fx:
		var apply := func(n: float):
			light.light_energy = smoothstep(0.25, 0.6, n) * 2.2
			if glass:
				glass.emission_energy_multiplier = smoothstep(0.25, 0.6, n) * 0.9
		fx.night_changed.connect(apply)
		apply.call(fx.night_amount())
	return light


## El cristal del farol brilla por sí mismo (cálido y suave) en vez de recibir la luz a quemarropa.
static func _lantern_glass(model: Node) -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#d9c9a0")
	glass.emission_enabled = true
	glass.emission = Color("#ffc47a")
	glass.emission_energy_multiplier = 0.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var n := (str(m.resource_name) if m else "").to_lower()
			if n.contains("glass") or n == "light":
				(mi as MeshInstance3D).set_surface_override_material(s, glass)
	return glass


## Enciende las ventanas de todos los edificios de noche (comparten material).
static func bind_windows(fx: EnvironmentFX) -> void:
	fx.night_changed.connect(_light_windows)
	_light_windows.call_deferred(fx.night_amount())  # cuando ya existan los edificios


static var _own_windows := {}   # material de ventanas de un edificio -> ¿hay alguien despierto dentro?
static var _night := 0.0


static func _light_windows(n: float) -> void:
	_night = n
	var m := AssetLibrary._windows()
	m.emission_energy_multiplier = smoothstep(0.2, 0.7, n) * 2.5
	for w in _own_windows.keys():
		if not is_instance_valid(w):
			_own_windows.erase(w)
			continue
		(w as StandardMaterial3D).emission_energy_multiplier = smoothstep(0.2, 0.7, n) * (2.5 if _own_windows[w] else 0.0)


## Ventanas propias de un edificio (empiezan encendidas hasta que alguien diga lo contrario).
static func register_windows(m: StandardMaterial3D) -> void:
	_own_windows[m] = true


## Enciende o apaga las ventanas de un edificio (hay alguien despierto dentro, el negocio abierto).
static func set_windows_lit(m: StandardMaterial3D, lit: bool) -> void:
	if m == null:
		return
	_own_windows[m] = lit
	m.emission_energy_multiplier = smoothstep(0.2, 0.7, _night) * (2.5 if lit else 0.0)


## Detalles de una fachada: escalón ante la puerta, macetas con flores, buzón (casas), toldo de
## rayas y letrero colgante (negocios). Nada delante de la salida (se deja libre el paso).
static func facade(parent: Node3D, door: Vector3, yaw: float, business: String, rng: RandomNumberGenerator) -> void:
	var out := Vector3(sin(yaw), 0, cos(yaw))
	var side := out.cross(Vector3.UP).normalized()
	var step := PropsBuilder._box(parent, door - out * 0.25 + Vector3(0, 0.06, 0), Vector3(2.2, 0.12, 0.9), Color("#9a9288"), false)
	step.rotation.y = yaw
	for s in [-1, 1]:  # macetas a los lados de la puerta
		var pot_at: Vector3 = door - out * 0.35 + side * s * 1.5
		var pot := PropsBuilder._box(parent, pot_at + Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.4), Color("#8a4b2f"), true)
		pot.rotation.y = yaw
		var flowers := AssetLibrary.instance("nature_pack", ["Flowers", "Bush_1", "Plant_2"][rng.randi() % 3])
		if flowers:
			AssetLibrary.place(parent, flowers, pot_at + Vector3(0, 0.38, 0), 0.5, rng.randf() * TAU, false)
	if business.is_empty():  # buzón junto a la acera
		var post_at := door + out * 2.6 + side * 2.4
		PropsBuilder._box(parent, post_at + Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), Color("#3b3b3b"), true)
		var box := PropsBuilder._box(parent, post_at + Vector3(0, 1.2, 0), Vector3(0.28, 0.25, 0.45), Color(["#2e5e8c", "#8c2e2e", "#3b6e3b", "#444444"][rng.randi() % 4]), false)
		box.rotation.y = yaw
		return
	# Negocio: toldo de rayas sobre la puerta y letrero colgante
	var colors := [[Color("#c0392b"), Color("#f4efe6")], [Color("#2e7d5b"), Color("#f4efe6")], [Color("#2c5d8f"), Color("#f4efe6")], [Color("#d4a017"), Color("#5a3a1a")]]
	var pair: Array = colors[rng.randi() % colors.size()]
	for k in 6:
		var stripe := PropsBuilder._box(parent, door - out * 0.1 + side * (-1.25 + k * 0.5) + Vector3(0, 2.9, 0), Vector3(0.5, 0.06, 1.3), pair[k % 2], false)
		stripe.rotation = Vector3(-0.35, yaw, 0)
	var board_at := door + out * 0.25 + side * 1.9 + Vector3(0, 2.4, 0)
	PropsBuilder._box(parent, board_at + Vector3(0, 0.45, 0), Vector3(0.05, 0.05, 0.6), Color("#3b3b3b"), false).rotation.y = yaw
	var board := PropsBuilder._box(parent, board_at, Vector3(0.08, 0.6, 0.9), pair[0], false)
	board.rotation.y = yaw
	var l := Label3D.new()
	l.text = business
	l.font_size = 40
	l.pixel_size = 0.004
	l.outline_size = 6
	l.double_sided = false  # una cara del letrero por lado (si no, por detrás se lee al revés)
	l.rotation.y = yaw + PI / 2
	l.position = board_at + side * 0.05
	fade_label(l, 40.0)
	parent.add_child(l)
	var l2 := l.duplicate() as Label3D
	l2.rotation.y = yaw - PI / 2
	l2.position = board_at - side * 0.05
	parent.add_child(l2)


# --- Olas (las mismas que water.gdshader, para que las barcas floten con el agua) ---------

const WAVE_HEIGHT := 0.22
const WAVE_SPEED := 0.8


static func wave_y(x: float, z: float, t: float) -> float:
	var tt := t * WAVE_SPEED
	var y := _gerstner_y(x, z, Vector2(1.0, 0.3), 0.18, 14.0, tt) + _gerstner_y(x, z, Vector2(0.6, 1.0), 0.14, 8.0, tt) \
		+ _gerstner_y(x, z, Vector2(-0.4, 0.8), 0.10, 4.5, tt)
	return y * WAVE_HEIGHT / 0.35


static func _gerstner_y(x: float, z: float, dir: Vector2, steep: float, length: float, t: float) -> float:
	var k := TAU / length
	var c := sqrt(9.8 / k)
	var d := dir.normalized()
	return steep / k * sin(k * (d.dot(Vector2(x, z)) - c * t))


# --- Lo que construye o coloca el jugador (Actions.place_object) -------------------------

## Modelo de cada tipo: [pack, modelo, altura en m]. Las barcas se tratan aparte (Boat).
const PLACED_MODELS := {
	"campfire": ["survival_pack", "Bonfire_Fire", 0.8], "tent": ["survival_pack", "Tent", 2.2],
	"shelter": ["survival_pack", "Tent", 3.0], "table": ["house_interior_pack", "Table_RoundSmall", 0.75],
	"chair": ["house_interior_pack", "Chair_1", 0.9], "bed": ["house_interior_pack", "Bed_Single", 0.6],
	"torch": ["survival_pack", "WoodenTorch_Fire", 1.6], "box": ["survival_pack", "Backpack", 0.6],
}


## Construye un objeto colocado. `on_use(kind, node)` se llama al usarlo con E (sentarse, dormir…).
static func build_placed(parent: Node3D, entry: Dictionary, height_at: Callable, water_level: float, on_use: Callable) -> Node3D:
	var pos := Vector3(entry.pos[0], entry.pos[1], entry.pos[2])
	var kind: String = entry.kind
	var yaw: float = float(entry.get("yaw", 0.0))
	if kind in ["boat", "raft"]:
		var boat := Boat.new()
		boat.water_level = water_level
		boat.ground_at = height_at
		parent.add_child(boat)
		boat.position = Vector3(pos.x, water_level, pos.z)
		boat.rotation.y = yaw
		if kind == "boat":
			boat.setup("ships_pack", "Boat", 4.5, "Subir a %s" % entry.name)
		else:
			boat.setup("survival_pack", "Raft", 3.2, "Subir a %s" % entry.name)
		return boat
	pos.y = height_at.call(pos.x, pos.z)
	var root: Node3D
	if not entry.get("parts", []).is_empty():  # lo que se inventó el jugador, con su forma
		root = _composite(parent, entry.parts, pos, yaw)
	elif PLACED_MODELS.has(kind):
		var spec: Array = PLACED_MODELS[kind]
		var model := AssetLibrary.instance(spec[0], spec[1])
		if model:
			root = AssetLibrary.place(parent, model, pos, spec[2], yaw, "trunk" if kind == "torch" else kind != "campfire")  # todo es sólido menos el fuego
	if root == null:
		root = _primitive_placed(parent, kind, pos, yaw)
	var function: String = entry.get("function", "none")
	root.set_meta("placed_id", entry.get("id", ""))
	root.set_meta("function", function)
	if function == "light" and kind != "torch":
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#ffe6b0")
		lamp.omni_range = 9.0
		lamp.light_energy = 1.4
		lamp.position = Vector3(0, _top(root) + 0.2, 0)
		root.add_child(lamp)
	if kind in ["campfire", "torch"] or function == "heat":
		var light := OmniLight3D.new()
		light.light_color = Color("#ff9a4a")
		light.omni_range = 7.0 if kind == "campfire" else 5.0
		light.light_energy = 1.6
		light.position = Vector3(0, 0.8 if kind == "campfire" else 1.6, 0)
		root.add_child(light)
		var tw := light.create_tween().set_loops()  # el fuego parpadea
		tw.tween_property(light, "light_energy", 1.1, 0.13)
		tw.tween_property(light, "light_energy", 1.8, 0.17)
	var label := Label3D.new()
	label.text = entry.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 32
	label.outline_size = 8
	label.visibility_range_end = 20.0
	label.position.y = 2.0 if kind in ["tent", "shelter"] else 1.2
	root.add_child(label)
	var use_as: String = {"seat": "chair", "bed": "bed", "heat": "campfire", "storage": "storage", "signal": "signal"}.get(function, "")
	if use_as.is_empty() and kind in ["chair", "bed", "campfire"]:
		use_as = kind
	if not use_as.is_empty():
		var prompt: String = {"chair": "Sentarse", "bed": "Dormir", "campfire": "Sentarse junto al fuego", "storage": "Guardar o sacar: %s" % entry.name,
			"signal": "Usar: %s" % entry.name}[use_as]
		Interactable.create(root, Vector3(0, 0.6, 0), 1.6, prompt, func(player): on_use.call(use_as, root, player), root)
	return root


## Objeto hecho de piezas (cajas, cilindros, esferas) tal como lo describió la IA. Sólido.
static func _composite(parent: Node3D, parts: Array, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var lowest := INF
	for p in parts:
		lowest = minf(lowest, float(p.pos[1]) - float(p.size[1]) / 2.0)
	for p in parts:
		var size := Vector3(p.size[0], p.size[1], p.size[2]).clamp(Vector3.ONE * 0.02, Vector3.ONE * 6.0)
		var at := Vector3(p.pos[0], p.pos[1] - minf(lowest, 0.0), p.pos[2])  # que nada quede bajo el suelo
		var color := Color(p.color) if Color.html_is_valid(str(p.color)) else Color("#8b6b4a")
		match p.shape:
			"cylinder":
				PropsBuilder._cylinder(root, at, size.x / 2.0, size.x / 2.0, size.y, color, size.y > 0.3)
			"sphere":
				PropsBuilder._sphere(root, at, size.x / 2.0, color, size.x > 0.4)
			_:
				PropsBuilder._box(root, at, size, color, size.y > 0.3 or size.x * size.z > 0.5)
	return root


## Altura del objeto (para poner una luz encima).
static func _top(root: Node3D) -> float:
	var top := 1.0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (m as MeshInstance3D).position.y + (m as MeshInstance3D).get_aabb().size.y / 2.0)
	return top


static func _primitive_placed(parent: Node3D, kind: String, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var wood := Color("#8b6b4a")
	match kind:
		"fence":
			for i in 5:
				PropsBuilder._box(root, Vector3(i * 0.8 - 1.6, 0.5, 0), Vector3(0.1, 1.0, 0.1), wood, false)
			PropsBuilder._box(root, Vector3(0, 0.75, 0), Vector3(3.4, 0.12, 0.06), wood, true)
			PropsBuilder._box(root, Vector3(0, 0.5, 0), Vector3(3.4, 1.0, 0.12), wood, true).visible = false
			PropsBuilder._box(root, Vector3(0, 0.35, 0), Vector3(3.4, 0.12, 0.06), wood, false)
		"sign":
			PropsBuilder._box(root, Vector3(0, 0.6, 0), Vector3(0.1, 1.2, 0.1), wood, true)
			PropsBuilder._box(root, Vector3(0, 1.1, 0), Vector3(0.9, 0.5, 0.06), wood.lightened(0.2), false)
		"garden":
			PropsBuilder._box(root, Vector3(0, 0.08, 0), Vector3(2.4, 0.16, 1.6), Color("#4a3426"), true)
			for i in 6:
				PropsBuilder._sphere(root, Vector3((i % 3) * 0.7 - 0.7, 0.3, (i / 3) * 0.7 - 0.35), 0.22, Color("#4f8a3a"), false)
		_:
			PropsBuilder._box(root, Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 0.9), wood, true)
	return root

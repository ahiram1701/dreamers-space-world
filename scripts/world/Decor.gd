class_name Decor
extends RefCounted
## Detalles que dan vida a un escenario: hierba con viento, agua con olas, farolas que se
## encienden de noche. Los usan el pueblo del Acto 0 y los lugares generados.

const WATER_SHADER := preload("res://shaders/water.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

## Material de suelo con colores por vértice (bioma, arena, caminos) + variación procedural.
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
	var count := int(half_size.x * half_size.y * 4.0 * density * [0.35, 0.7, 1.0][Settings.graphics_quality])
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
	parent.add_child(mmi)


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
	if model:
		AssetLibrary.place(parent, model, pos, 4.4, yaw, true)
		light.position = pos + Vector3(0, 4.1, 0)
	else:
		PropsBuilder._cylinder(parent, pos + Vector3(0, 2.2, 0), 0.08, 0.1, 4.4, Color("#2a3a2e"), true)
		light.position = pos + Vector3(0, 4.3, 0)
	parent.add_child(light)
	if fx:
		var apply := func(n: float): light.light_energy = smoothstep(0.25, 0.6, n) * 2.2
		fx.night_changed.connect(apply)
		apply.call(fx.night_amount())
	return light


## Enciende las ventanas de todos los edificios de noche (comparten material).
static func bind_windows(fx: EnvironmentFX) -> void:
	fx.night_changed.connect(_light_windows)
	_light_windows.call_deferred(fx.night_amount())  # cuando ya existan los edificios


static func _light_windows(n: float) -> void:
	var m := AssetLibrary._windows()
	m.emission_energy_multiplier = smoothstep(0.2, 0.7, n) * 2.5

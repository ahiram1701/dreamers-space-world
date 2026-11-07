extends Node3D
## El espacio: vuelas en tu nave por el sistema solar de este mundo (StarSystem). El sol, los
## planetas con su atmósfera, el cinturón de asteroides y la estación; todo es sólido (chocar daña
## el casco). Al acercarte a un planeta o a la estación, E para aterrizar o acoplarte (Travel.land).
##   Ratón: apuntar · W/S: empujar · A/D: alabear · Espacio/Ctrl: subir/bajar · Shift: crucero
##   · X: frenar · Tab: destino · G: piloto automático · V: cabina · Z: asistencia de vuelo
##   · E: aterrizar · F: hacer algo · Esc: menú

const PLANET_SHADER := preload("res://shaders/planet.gdshader")
const SKY_SHADER := preload("res://shaders/space_sky.gdshader")

var system: Dictionary = {}
var ship: Ship
var _cam: Camera3D
var _sun_light: DirectionalLight3D
var _hud: Label
var _prompt: Label
var _near: Dictionary = {}
var _landing := false
var _bodies := []   # [{planet, node}]
var _rocks: Array = []        # transformaciones de los asteroides del cinturón
var _rock_bodies: Array = []  # los ~40 más cercanos tienen cuerpo (se reciclan al moverte)
var _rock_t := 0.0
var _target := 0              # índice del planeta de destino (Tab)
var _marker: Label
var _hit_flash := 0.0
var _actions: ActionPanel
var _toast: Label
var _toast_t := 0.0
var _land_after_auto := ""
var _heat_t := 0.0
var _moons: Array = []        # [{node, center, r, speed, angle}]
var _traffic: Array = []      # [{node, from, to, t, speed}]
var _dust: MultiMeshInstance3D
var _dust_pos := PackedVector3Array()
var DUST := 260
const DUST_BOX := 160.0
const MOUSE := 0.0022
const SUN_RADIUS := 2200.0


func _ready() -> void:
	system = StarSystem.get_or_create()
	_environment()
	_sun()
	for p in system.planets:
		_bodies.append({"planet": p, "node": _planet(p)})
	_belt()
	_add_moons()
	_spawn_ship()
	_add_traffic()
	_add_dust()
	ship.autopilot_stopped.connect(func(why): toast("Piloto automático desactivado: %s." % why))
	if not ("space_assist" in Settings.seen_hints):
		Settings.seen_hints.append("space_assist")
		toast.call_deferred("Z: asistencia de vuelo (frena sola la nave al soltar los mandos). G: piloto automático al destino. V: cabina.", 8.0)
	_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_target = maxi(system.planets.find(StarSystem.home_planet(system)), 0)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#20242e")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = Settings.graphics_quality >= 1
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _sun() -> void:
	var sun := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 2200.0
	m.height = 4400.0
	sun.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#fff2c8")
	mat.emission_enabled = true
	mat.emission = Color("#ffcf7a")
	mat.emission_energy_multiplier = 6.0
	sun.material_override = mat
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)
	_solid_sphere(sun, SUN_RADIUS)  # (antes se atravesaba)
	_label(Vector3(0, 2800, 0), str(system.get("star", "Sol")), Color("#ffe6a8"))
	_sun_light = DirectionalLight3D.new()
	_sun_light.light_energy = 1.4
	_sun_light.light_color = Color("#fff4dd")
	add_child(_sun_light)


func _planet(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = StarSystem.position_of(p)
	add_child(root)
	var r := float(p.radius)
	if p.kind == "station":
		_station(root, r)
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 96
		sm.rings = 48
		mi.mesh = sm
		var mat := ShaderMaterial.new()
		mat.shader = PLANET_SHADER
		var cols: Array = p.colors
		mat.set_shader_parameter("color_a", Color(cols[0]))
		mat.set_shader_parameter("color_b", Color(cols[1]))
		mat.set_shader_parameter("color_c", Color(cols[2]))
		mat.set_shader_parameter("banded", 1.0 if p.kind == "gas" else 0.0)
		mat.set_shader_parameter("seed", float(hash(str(p.name)) % 1000) / 1000.0)
		mat.set_shader_parameter("land", 0.55 if p.kind == "ocean" else 0.45)
		var atm: Color = {"terran": Color("#78b4ff"), "ocean": Color("#6fc0ff"), "jungle": Color("#9fe0a0"), "desert": Color("#ffc890"),
			"volcanic": Color("#ff7a50"), "ice": Color("#d0f0ff"), "crystal": Color("#d0a0ff"), "gas": Color("#ffd8a8")}.get(p.kind, Color(0, 0, 0))
		mat.set_shader_parameter("atmosphere", atm)
		mi.material_override = mat
		root.add_child(mi)
		root.set_meta("spin", 0.01)
		_solid_sphere(root, r)
		if p.get("rings", false):
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = r * 1.4
			tm.outer_radius = r * 2.1
			tm.rings = 96
			ring.mesh = tm
			ring.scale = Vector3(1, 0.02, 1)
			ring.rotation_degrees = Vector3(18, 0, 8)
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(cols[2]).darkened(0.1)
			rm.albedo_color.a = 0.6
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.material_override = rm
			root.add_child(ring)
	_label(Vector3(0, r * 1.25 + 40.0, 0), "%s%s" % [p.name, "  (tu planeta)" if p.get("home", false) else ""], Color.WHITE, root)
	return root


func _station(root: Node3D, r: float) -> void:
	var metal := Creations.material("metal", Color("#b8bcc2"))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.8
	tm.outer_radius = r
	ring.mesh = tm
	ring.material_override = metal
	root.add_child(ring)
	var hub := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.22
	cm.bottom_radius = r * 0.22
	cm.height = r * 0.9
	hub.mesh = cm
	hub.material_override = metal
	root.add_child(hub)
	for k in 4:
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 1.6, r * 0.06, r * 0.06)
		spoke.mesh = bm
		spoke.rotation.y = k * PI / 4.0
		spoke.material_override = metal
		root.add_child(spoke)
	for k in 8:  # luces de posición
		var l := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = r * 0.04
		s.height = r * 0.08
		l.mesh = s
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lm.emission = Color("#7fd0ff") if k % 2 == 0 else Color("#ff5a4a")
		lm.emission_energy_multiplier = 4.0
		l.material_override = lm
		l.position = Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * r * 0.9
		root.add_child(l)
	root.set_meta("spin", 0.0)  # (girar su cuerpo trimesh cada frame era frágil)
	# Sólida con su forma (el anillo, el eje y los radios): se puede pasar por los huecos
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	for mi in root.get_children():
		if mi is MeshInstance3D and not (mi.mesh is SphereMesh):
			var cs := CollisionShape3D.new()
			cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
			cs.transform = (mi as MeshInstance3D).transform
			body.add_child(cs)
	root.add_child(body)


func _solid_sphere(root: Node3D, r: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	body.add_child(cs)
	root.add_child(body)


func _belt() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.6
	rock.radial_segments = 6
	rock.rings = 4
	mm.mesh = rock
	mm.instance_count = 900
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(system.get("star", "")))
	var r0 := float(system.get("belt", 30000.0))
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var d := r0 + rng.randfn(0.0, 900.0)
		var s := rng.randf_range(4.0, 40.0)
		var t := Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s)),
			Vector3(cos(a) * d, rng.randfn(0.0, 120.0), sin(a) * d))
		mm.set_instance_transform(i, t)
		_rocks.append(t)
	for i in 40:  # cuerpos que se colocan en los asteroides más cercanos a la nave
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		var cs := CollisionShape3D.new()
		cs.shape = SphereShape3D.new()
		body.add_child(cs)
		body.position = Vector3(0, -1.0e7 - i * 100.0, 0)
		add_child(body)
		_rock_bodies.append(body)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#6b625a")
	mat.roughness = 1.0
	mmi.material_override = mat
	add_child(mmi)


func _label(pos: Vector3, text: String, color: Color, parent: Node3D = null) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 36
	l.outline_size = 8
	l.no_depth_test = true
	l.position = pos
	(parent if parent else self).add_child(l)


func _spawn_ship() -> void:
	var state: Dictionary = WorldDB.get_state("space", {})
	var e: Dictionary = state.get("ship", {})
	if e.is_empty():
		e = Ship.factory()
	var from := StarSystem.home_planet(system)
	for p in system.planets:
		if p.get("location_id", "") == str(state.get("from", "")) and not str(state.get("from", "")).is_empty():
			from = p
	ship = Ship.build(self, e, true)
	ship.piloted = true
	var center := StarSystem.position_of(from)
	var out := center.normalized() if center.length() > 1.0 else Vector3.FORWARD
	ship.global_position = center + out * (float(from.radius) * 1.35 + 60.0)
	ship.look_at(ship.global_position + out.cross(Vector3.UP).normalized(), Vector3.UP)
	ship.rotate_object_local(Vector3.UP, PI)  # la nave mira hacia su +Z
	_cam = Camera3D.new()
	_cam.far = 400000.0
	_cam.near = 0.3
	_cam.fov = 70.0
	add_child(_cam)
	_cam.current = true


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 20)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.72
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	layer.add_child(_prompt)
	_marker = Label.new()
	_marker.add_theme_font_size_override("font_size", 20)
	_marker.add_theme_color_override("font_color", Color("#9fe0ff"))
	_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	_marker.add_theme_constant_override("outline_size", 6)
	layer.add_child(_marker)
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.62
	_toast.offset_left = -360
	_toast.offset_right = 360
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Color("#ffe6a8"))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	layer.add_child(_toast)
	# F: hacer algo también aquí, a bordo (hablar con quien va contigo, aterrizar, ir a un sitio…)
	_actions = ActionPanel.new()
	_actions.context = space_context
	_actions.step_handler = _space_steps
	add_child(_actions)
	_actions.opened.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if ship: ship.piloted = false)
	_actions.closed.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if ship: ship.piloted = true)
	var help := Label.new()
	help.text = "Ratón apuntar · W/S empujar · A/D alabear · Shift crucero · X frenar · Tab destino · G piloto automático · V cabina · Z asistencia · E aterrizar · F hacer algo · Esc menú"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(24, -40)
	help.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(help)


## Algunos planetas tienen lunas (sólidas: también se chocan) que giran a su alrededor.
func _add_moons() -> void:
	for p in system.planets:
		if p.kind == "station":
			continue
		var h := hash(str(p.name))
		var count := 2 if p.kind == "gas" else (1 if h % 3 != 0 else 0)
		for i in count:
			var r := float(p.radius) * (0.18 + 0.08 * ((h >> (i + 2)) % 3))
			var node := Node3D.new()
			add_child(node)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = r * 2.0
			sm.radial_segments = 48
			sm.rings = 24
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color.from_hsv(fposmod(h * 0.0007 + i * 0.2, 1.0), 0.12, 0.62)
			m.roughness = 1.0
			mi.material_override = m
			node.add_child(mi)
			# (sin cuerpo físico: mover uno estático cada frame era frágil; se choca con la cuenta)
			_moons.append({"node": node, "r": r, "center": StarSystem.position_of(p), "dist": float(p.radius) * (2.4 + i * 1.3), "speed": 0.01 + 0.006 * i, "angle": float(h % 628) / 100.0 + i * 2.0})


## Otras naves que van y vienen entre la estación y los planetas (el sistema está vivo).
func _add_traffic() -> void:
	var models := ["Bob", "Dispatcher", "Striker"]
	var stops: Array = system.planets.map(func(p): return StarSystem.position_of(p) + Vector3(0, float(p.radius) * 1.3, 0))
	if stops.size() < 2:
		return
	for i in (4 if Settings.graphics_quality >= 1 else 2):
		var model := AssetLibrary.instance(Ship.MODEL_DIR, models[i % models.size()])
		if model == null:
			continue
		var holder := Node3D.new()
		add_child(holder)
		AssetLibrary.place(holder, model, Vector3.ZERO, 3.0, 0.0, false)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#7fd0ff")
		glow.omni_range = 12.0
		glow.light_energy = 2.0
		glow.position = Vector3(0, 1.5, -4)
		holder.add_child(glow)
		var a: int = i % stops.size()
		var b: int = (i * 3 + 1) % stops.size()
		if a == b:
			b = (b + 1) % stops.size()
		_traffic.append({"node": holder, "from": stops[a], "to": stops[b], "t": randf(), "speed": 1.0 / randf_range(120.0, 260.0)})


## Polvo y partículas a tu alrededor: al moverte pasan de largo (se nota la velocidad).
func _add_dust() -> void:
	DUST = 260 if Settings.graphics_quality >= 1 else 120
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := BoxMesh.new()
	q.size = Vector3(0.08, 0.08, 0.6)
	mm.mesh = q
	mm.instance_count = DUST
	_dust = MultiMeshInstance3D.new()
	_dust.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust.material_override = m
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.extra_cull_margin = DUST_BOX
	add_child(_dust)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	_dust_pos.resize(DUST)
	for i in DUST:
		_dust_pos[i] = Vector3(rng.randf(), rng.randf(), rng.randf()) * DUST_BOX


func _update_world(delta: float) -> void:
	for mo in _moons:
		mo.angle = float(mo.angle) + float(mo.speed) * delta
		(mo.node as Node3D).global_position = (mo.center as Vector3) + Vector3(cos(mo.angle), 0.15 * sin(mo.angle * 0.7), sin(mo.angle)) * float(mo.dist)
	for tr in _traffic:
		tr.t = float(tr.t) + float(tr.speed) * delta
		if float(tr.t) >= 1.0:  # llega y vuelve (otra ruta)
			tr.t = 0.0
			var f: Vector3 = tr.to
			tr.to = tr.from
			tr.from = f
		var from: Vector3 = tr.from
		var to: Vector3 = tr.to
		var p := from.lerp(to, smoothstep(0.0, 1.0, float(tr.t))) + Vector3(0, sin(float(tr.t) * PI) * 1500.0, 0)
		var n := tr.node as Node3D
		var dir := p - n.global_position
		if dir.length() > 0.5 and absf(dir.normalized().dot(Vector3.UP)) < 0.97:  # (si no, look_at falla)
			n.look_at(p + dir, Vector3.UP)
			n.rotate_object_local(Vector3.UP, PI)
		n.global_position = p
	# Polvo: cada mota vive en una caja que va con la nave (se recoloca al salirse)
	if _dust and ship:
		var c := ship.global_position
		var v := ship.velocity
		var stretch := clampf(v.length() / 30.0, 1.0, 40.0)
		var look := v.normalized() if v.length() > 1.0 else ship.global_basis.z
		var up := Vector3.UP if absf(look.y) < 0.95 else Vector3.RIGHT
		var basis := Basis.looking_at(look, up).scaled(Vector3(1, 1, stretch))
		for i in DUST:
			var p0: Vector3 = _dust_pos[i]
			var lp := Vector3(fposmod(p0.x - c.x, DUST_BOX), fposmod(p0.y - c.y, DUST_BOX), fposmod(p0.z - c.z, DUST_BOX)) - Vector3.ONE * DUST_BOX / 2.0
			_dust.multimesh.set_instance_transform(i, Transform3D(basis, c + lp))
		(_dust.material_override as StandardMaterial3D).albedo_color.a = clampf(v.length() / 200.0, 0.15, 0.6)


func toast(text: String, seconds: float = 4.0) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast_t = seconds


## Lo que la IA sabe al pulsar F en el espacio.
func space_context() -> String:
	var lines := PackedStringArray()
	lines.append("El jugador va EN EL ESPACIO, pilotando %s (combustible %d%%, casco %d%%, a %s)." % [ship.display_name, int(ship.fuel * 100.0), int(ship.hull), _speed_text(ship.speed())])
	var pax := PackedStringArray()
	for id in Travel.passengers():
		pax.append(str(WorldDB.get_entity("npc", str(id)).get("name", "alguien")))
	lines.append("A BORDO CON ÉL: " + (", ".join(pax) if not pax.is_empty() else "nadie") + ". No hay nadie más en la nave.")
	var bodies := PackedStringArray()
	for p in system.planets:
		var d := maxf(ship.global_position.distance_to(StarSystem.position_of(p)) - float(p.radius), 0.0)
		bodies.append("%s (%s, a %s%s)" % [p.name, StarSystem.describe(p), _dist_text(d), ", se puede aterrizar" if StarSystem.can_land(p) else ""])
	lines.append("CUERPOS DEL SISTEMA: " + "; ".join(bodies) + ".")
	lines.append("Aquí solo valen estos pasos: land (target: nombre del planeta o la estación), travel (target: nombre de un planeta: el piloto automático te lleva), npc_react con quien va a bordo, change_need, give_item, remove_item, journal y change_stat. No se camina ni se sale de la nave.")
	return "\n".join(lines)


## Los pasos de F en el espacio: aterrizar o ir a un planeta (piloto automático), y los efectos.
func _space_steps(steps: Array, what: String = "") -> Array:
	var notes := []
	if steps.is_empty() and not what.is_empty():  # sin IA: entender lo básico
		var low := what.to_lower()
		for p in system.planets:
			if low.contains(str(p.name).to_lower()) or (p.get("home", false) and ["casa", "pueblo", "mi planeta", "volver", "regres"].any(func(w): return low.contains(w))):
				steps = [{"type": "land" if ["aterriz", "baj", "volver", "regres", "casa", "pueblo"].any(func(w): return low.contains(w)) else "travel", "target": p.name}]
				break
	for s in steps:
		if not (s is Dictionary):
			continue
		var type := str(s.get("type", ""))
		if type in ["land", "travel"]:
			var p := _planet_named(str(s.get("target", "")))
			if p.is_empty():
				notes.append("No sabes adónde ir: «%s» no está en este sistema." % str(s.get("target", "")))
				continue
			_target = system.planets.find(p)
			_start_autopilot(p, type == "land")
			notes.append("Piloto automático rumbo a %s." % p.name)
		elif type in StoryDirector.WORLD_STEPS and not (type in ["go_to", "play", "use", "climb", "move_to", "force_door", "sleep", "wait", "ride", "spawn_npc", "create_place", "place_object", "affect_nearby"]):
			notes.append_array(Actions.execute("", [s]))
	return notes


func _planet_named(text: String) -> Dictionary:
	var t := text.to_lower().strip_edges().trim_prefix("location:")
	for p in system.planets:
		if str(p.name).to_lower() == t or t.contains(str(p.name).to_lower()) or (t.length() > 3 and str(p.name).to_lower().contains(t)):
			return p
		if p.get("home", false) and (t == GameState.HOME or ["casa", "pueblo", "bahía", "mi planeta", "tierra"].any(func(w): return t.contains(w))):
			return p
		if str(p.get("location_id", "")) == t and not t.is_empty():
			return p
	return {}


func _start_autopilot(p: Dictionary, land_on_arrival: bool) -> void:
	ship.auto_point = StarSystem.position_of(p)
	ship.auto_stop = float(p.radius) * 1.25 + 60.0
	ship.autopilot = true
	_land_after_auto = str(p.name) if land_on_arrival and StarSystem.can_land(p) else ""
	if not ship.autopilot_arrived.is_connected(_on_autopilot_arrived):
		ship.autopilot_arrived.connect(_on_autopilot_arrived)


func _on_autopilot_arrived() -> void:
	if not _land_after_auto.is_empty() and not _landing:
		var n := _land_after_auto
		_land_after_auto = ""
		_land(n)
	else:
		toast("Has llegado.")


func _physics_process(delta: float) -> void:
	if ship == null:
		return
	# No se atraviesan los planetas ni el sol: si la nave queda dentro (con su tamaño), sale
	for p in system.planets:
		if p.kind == "station":
			continue
		var c := StarSystem.position_of(p)
		var min_d := float(p.radius) + ship.length * 0.6 + 2.0
		var off := ship.global_position - c
		if off.length() < min_d:
			ship.global_position = c + (off.normalized() if off.length() > 0.01 else Vector3.UP) * min_d
			ship.velocity = ship.velocity.slide(off.normalized()) * 0.3
	for mo in _moons:  # las lunas también son sólidas
		var mc: Vector3 = (mo.node as Node3D).global_position
		var md := float(mo.r) + ship.length * 0.6 + 2.0
		var mo_off := ship.global_position - mc
		if mo_off.length() < md:
			var into := -ship.velocity.dot(mo_off.normalized())
			ship.global_position = mc + mo_off.normalized() * md
			ship.velocity = ship.velocity.slide(mo_off.normalized()) * 0.3
			if into > 20.0:
				ship.hull = maxf(ship.hull - minf(into * 0.3, Ship.MAX_HIT), 0.0)
				on_ship_hit(into)
	var sd := ship.global_position.length()
	if sd < SUN_RADIUS + ship.length + 2.0:
		ship.global_position = ship.global_position.normalized() * (SUN_RADIUS + ship.length + 2.0)
		ship.velocity = ship.velocity.slide(ship.global_position.normalized()) * 0.3
	# Cerca del sol, el calor daña el casco
	if sd < SUN_RADIUS * 3.0:
		_heat_t += delta
		if _heat_t > 1.0:
			_heat_t = 0.0
			ship.hull = maxf(ship.hull - lerpf(6.0, 1.0, (sd - SUN_RADIUS) / (SUN_RADIUS * 2.0)), 0.0)
			toast("¡Demasiado cerca del sol! El casco se calienta.", 1.5)


func _process(delta: float) -> void:
	_update_world(delta)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	for b in _bodies:  # giran los planetas a la vista (el cuerpo que choca es una esfera: no hace falta moverlo)
		for c in (b.node as Node3D).get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).rotate_y(float(b.node.get_meta("spin", 0.0)) * delta)
	if ship == null:
		return
	# Cámara detrás de la nave
	var want := ship.global_transform * Vector3(0, 5.0, -16.0)
	_cam.global_position = _cam.global_position.lerp(want, clampf(8.0 * delta, 0.0, 1.0)) if _cam.global_position.distance_to(want) < 200.0 else want
	_cam.look_at(ship.global_transform * Vector3(0, 1.5, 12.0), ship.global_basis.y)
	_cam.h_offset = lerpf(_cam.h_offset, 0.0, clampf(6.0 * delta, 0.0, 1.0))
	# El sol alumbra desde donde está
	var to_ship := ship.global_position.normalized()
	if to_ship.length() > 0.1:
		_sun_light.look_at_from_position(Vector3.ZERO, to_ship * 10.0, Vector3.UP if absf(to_ship.y) < 0.99 else Vector3.RIGHT)
	# Lo más cercano
	var best := {}
	var best_d := INF
	for p in system.planets:
		var d := ship.global_position.distance_to(StarSystem.position_of(p)) - float(p.radius)
		if d < best_d:
			best_d = d
			best = p
	_near = best if best_d < float(best.get("radius", 0.0)) * 0.6 + 80.0 else {}
	var tgt: Dictionary = system.planets[clampi(_target, 0, system.planets.size() - 1)]
	var tpos := StarSystem.position_of(tgt)
	var tdist := maxf(ship.global_position.distance_to(tpos) - float(tgt.radius), 0.0)
	var pax := PackedStringArray()
	for id in Travel.passengers():
		pax.append(str(WorldDB.get_entity("npc", str(id)).get("name", "?")).split(" ")[0])
	_hud.text = "%s · %s · combustible %d%% · casco %d%%%s%s\nCerca: %s a %s\nDestino: %s a %s%s%s" % [ship.display_name, _speed_text(ship.speed()), int(ship.fuel * 100.0),
		int(ship.hull), "" if ship.assist else " · asistencia APAGADA", " · ¡PROXIMIDAD!" if ship.proximity else "", best.get("name", "?"), _dist_text(maxf(best_d, 0.0)), tgt.name, _dist_text(tdist),
		"  · PILOTO AUTOMÁTICO (G o W/S para tomar el mando)" if ship.autopilot else ("  (G: piloto automático · Shift: crucero)" if tdist > 20000.0 and ship.speed() < 1000.0 else ""),
		("\nA bordo: " + ", ".join(pax)) if not pax.is_empty() else ""]
	_update_marker(tpos, str(tgt.name), tdist)
	_place_rock_bodies(delta)
	if _hit_flash > 0.0:
		_hit_flash -= delta
		_hud.modulate = Color(1, 0.5, 0.5) if int(_hit_flash * 10.0) % 2 == 0 else Color.WHITE
	else:
		_hud.modulate = Color.WHITE
	if _landing:
		_prompt.text = "Entrando en la atmósfera…" if best.get("kind", "") != "station" else "Acoplando…"
	elif _near.is_empty():
		_prompt.text = "" if ship.fuel > 0.0 else "Sin combustible: la nave va a la deriva."
		if ship.hull <= 0.0 and ship.fuel > 0.0:
			_prompt.text = "Casco crítico: la nave apenas responde. Aterriza para repararla."
	elif StarSystem.can_land(_near):
		_prompt.text = "[E] %s %s — %s" % ["Acoplarte a" if _near.kind == "station" else "Aterrizar en", _near.name, StarSystem.describe(_near)]
	else:
		_prompt.text = "%s: %s" % [_near.name, StarSystem.describe(_near)]


func _speed_text(v: float) -> String:
	return "%.0f m/s" % v if v < 1000.0 else "%.1f km/s" % (v / 1000.0)


func _dist_text(d: float) -> String:
	return "%.0f m" % d if d < 1000.0 else "%.1f km" % (d / 1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if _landing:  # aterrizando: ni menú ni mandos (antes Esc a mitad del aterrizaje cerraba el juego)
		return
	if event.is_action_pressed("act") and _actions and not _actions.is_busy():
		_actions.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("autopilot") and ship:
		if ship.autopilot:
			ship.autopilot = false
			toast("Piloto automático desactivado.")
		else:
			var tgt: Dictionary = system.planets[clampi(_target, 0, system.planets.size() - 1)]
			_start_autopilot(tgt, false)
			toast("Piloto automático rumbo a %s." % tgt.name)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and ship:
		ship.steer += Vector2(event.relative.x, event.relative.y * (-1.0 if Settings.invert_y else 1.0)) * MOUSE * Settings.mouse_sensitivity
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("next_target"):
		_target = (_target + 1) % system.planets.size()
	elif event.is_action_pressed("flight_assist") and ship:
		ship.assist = not ship.assist
		toast("Asistencia de vuelo %s: %s" % ["ENCENDIDA" if ship.assist else "APAGADA",
			"al soltar los mandos, la nave frena sola" if ship.assist else "la nave sigue a la deriva con su inercia (como en el espacio real)"])
	elif event.is_action_pressed("interact") and not _near.is_empty() and StarSystem.can_land(_near) and not _landing:
		_land(str(_near.name))
	elif event.is_action_pressed("pause"):
		WorldDB.flush()
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


## Una flecha en pantalla hacia el destino (o en el borde, si queda detrás o fuera).
func _update_marker(tpos: Vector3, name: String, dist: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var behind := _cam.is_position_behind(tpos)
	var sp := _cam.unproject_position(tpos)
	var inside := not behind and sp.x > 0 and sp.y > 0 and sp.x < vp.x and sp.y < vp.y
	if inside:
		_marker.text = "◇ %s · %s" % [name, _dist_text(dist)]
		_marker.position = sp + Vector2(-12, -12)
	else:
		var c := vp / 2.0
		var d := (sp - c) * (-1.0 if behind else 1.0)
		if d.length() < 1.0:
			d = Vector2(0, 1)
		var edge := c + d.normalized() * minf(c.x, c.y) * 0.85
		_marker.position = edge
		_marker.text = ("◀ " if d.x < -absf(d.y) else ("▶ " if d.x > absf(d.y) else ("▲ " if d.y < 0 else "▼ "))) + name


## Los asteroides cercanos tienen cuerpo: se pueden golpear (no se atraviesan).
func _place_rock_bodies(delta: float) -> void:
	_rock_t -= delta
	if _rock_t > 0.0 or ship == null:
		return
	# Más a menudo cuanto más rápido vas (a crucero se cruzan kilómetros en medio segundo)
	_rock_t = 0.5 if ship.speed() < 150.0 else 0.1
	var p := ship.global_position
	var reach := maxf(2500.0, ship.speed() * 1.5)
	if absf(p.length() - float(system.get("belt", 30000.0))) > 6000.0 + reach:
		return  # lejos del cinturón
	var near := []
	for t in _rocks:
		var d: float = (t.origin as Vector3).distance_squared_to(p)
		var r: float = t.basis.get_scale().x * 0.92
		if d < reach * reach and sqrt(d) > r + ship.length:  # nunca uno que ya esté encima de la nave
			near.append([d, t])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in _rock_bodies.size():
		var body: StaticBody3D = _rock_bodies[i]
		if i < near.size():
			var t: Transform3D = near[i][1]
			body.global_position = t.origin
			(body.get_child(0).shape as SphereShape3D).radius = t.basis.get_scale().x * 0.92
		else:
			body.global_position = Vector3(0, -1.0e7 - i * 100.0, 0)


func on_ship_hit(strength: float) -> void:
	_hit_flash = 1.0
	_cam.h_offset = randf_range(-0.4, 0.4) * clampf(strength / 20.0, 0.2, 1.0)
	if ship.hull <= 0.0:
		_prompt.text = "El casco está destrozado: la nave va a la deriva."


func _land(planet_name: String) -> void:
	_landing = true
	if _actions:
		_actions.close()
	var space: Dictionary = WorldDB.get_state("space", {})
	var e: Dictionary = space.get("ship", {})
	e["fuel"] = ship.fuel
	e["hull"] = ship.hull
	space["ship"] = e
	WorldDB.set_state("space", space)
	var r := await Travel.land(planet_name)
	if not is_inside_tree():
		return
	if not r.ok:
		_prompt.text = r.error
		_landing = false
		return
	WorldDB.flush()
	get_tree().change_scene_to_file(Travel.scene_for(r.location_id))

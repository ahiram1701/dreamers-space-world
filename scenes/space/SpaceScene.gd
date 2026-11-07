extends Node3D
## El espacio: vuelas en tu nave por el sistema solar de este mundo (StarSystem). El sol, los
## planetas con su atmósfera, el cinturón de asteroides y la estación; todo es sólido (chocar daña
## el casco). Al acercarte a un planeta o a la estación, E para aterrizar o acoplarte (Travel.land).
##   Ratón: apuntar · W/S: empujar · A/D: alabear · Espacio/Ctrl: subir/bajar · Shift: crucero
##   · Tab: destino · Z: asistencia de vuelo · E: aterrizar · Esc: menú

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
const MOUSE := 0.0022


func _ready() -> void:
	system = StarSystem.get_or_create()
	_environment()
	_sun()
	for p in system.planets:
		_bodies.append({"planet": p, "node": _planet(p)})
	_belt()
	_spawn_ship()
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
	env.glow_enabled = true
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
	root.set_meta("spin", 0.05)
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
	var help := Label.new()
	help.text = "Ratón apuntar · W/S empujar · A/D alabear · Espacio/Ctrl subir/bajar · Shift crucero · Tab destino · Z asistencia · E aterrizar · Esc menú"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(24, -40)
	help.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(help)


func _process(delta: float) -> void:
	for b in _bodies:
		(b.node as Node3D).rotate_y(float(b.node.get_meta("spin", 0.0)) * delta)
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
	if best_d < 0.0 and not best.is_empty():  # no se atraviesan los planetas
		var c := StarSystem.position_of(best)
		ship.global_position = c + (ship.global_position - c).normalized() * float(best.radius)
		ship.velocity = Vector3.ZERO
	var tgt: Dictionary = system.planets[clampi(_target, 0, system.planets.size() - 1)]
	var tpos := StarSystem.position_of(tgt)
	var tdist := maxf(ship.global_position.distance_to(tpos) - float(tgt.radius), 0.0)
	_hud.text = "%s · %s · combustible %d%% · casco %d%%%s\nCerca: %s a %s\nDestino: %s a %s%s" % [ship.display_name, _speed_text(ship.speed()), int(ship.fuel * 100.0),
		int(ship.hull), "" if ship.assist else " · asistencia APAGADA", best.get("name", "?"), _dist_text(maxf(best_d, 0.0)), tgt.name, _dist_text(tdist),
		"  (Shift para crucero)" if tdist > 20000.0 and ship.speed() < 2000.0 else ""]
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
	elif StarSystem.can_land(_near):
		_prompt.text = "[E] %s %s — %s" % ["Acoplarte a" if _near.kind == "station" else "Aterrizar en", _near.name, StarSystem.describe(_near)]
	else:
		_prompt.text = "%s: %s" % [_near.name, StarSystem.describe(_near)]


func _speed_text(v: float) -> String:
	return "%.0f m/s" % v if v < 1000.0 else "%.1f km/s" % (v / 1000.0)


func _dist_text(d: float) -> String:
	return "%.0f m" % d if d < 1000.0 else "%.1f km" % (d / 1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and ship:
		ship.steer += Vector2(event.relative.x, event.relative.y * (-1.0 if Settings.invert_y else 1.0)) * MOUSE * Settings.mouse_sensitivity
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("next_target"):
		_target = (_target + 1) % system.planets.size()
	elif event.is_action_pressed("flight_assist") and ship:
		ship.assist = not ship.assist
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
	_rock_t = 0.5
	var p := ship.global_position
	if absf(p.length() - float(system.get("belt", 30000.0))) > 6000.0:
		return  # lejos del cinturón
	var near := []
	for t in _rocks:
		var d: float = (t.origin as Vector3).distance_squared_to(p)
		if d < 2500.0 * 2500.0:
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
	var space: Dictionary = WorldDB.get_state("space", {})
	var e: Dictionary = space.get("ship", {})
	e["fuel"] = ship.fuel
	space["ship"] = e
	WorldDB.set_state("space", space)
	var r := await Travel.land(planet_name)
	if not r.ok:
		_prompt.text = r.error
		_landing = false
		return
	WorldDB.flush()
	get_tree().change_scene_to_file(Travel.scene_for(r.location_id))

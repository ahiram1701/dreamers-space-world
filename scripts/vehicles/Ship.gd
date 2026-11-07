class_name Ship
extends CharacterBody3D
## Una nave: cualquier creación con "thruster" (y "cockpit" para pilotarla), o una de fábrica con
## modelo (las naves de Quaternius). En un planeta despega y aterriza en vertical: apuntas con el
## ratón (la nave gira hacia donde miras), W/S avanza y frena, A/D se desplaza de lado, Espacio
## sube, Ctrl/Q baja y Shift da potencia; sin combustible cae. Si sube lo bastante, sale al
## espacio (SpaceScene). En el espacio: el ratón cabecea y gira, A/D alabea, W/S empuja, Shift
## crucero, Z asistencia de vuelo (frena la inercia sola). Choca de verdad: los golpes dañan el casco.

const SPACE_ALTITUDE := 160.0   # por encima de esto (sobre el suelo) estás saliendo de la atmósfera
const MODEL_DIR := "spaceships_pack"

var entry: Dictionary = {}
var entry_id := ""
var display_name := "la nave"
var power := 5.0
var fuel := 1.0
var hull := 100.0
var in_space := false
var scene: Node
var piloted := false            # en el espacio la pilota la escena (no hay Player)
var assist := true              # asistencia de vuelo (en el espacio)
## Giro pedido con el ratón en el espacio (lo suma SpaceScene; se consume cada frame).
var steer := Vector2.ZERO
var length := 8.0

var _rider: Player
var _use: Interactable
var _seat := Vector3(0, 1.2, 0)
var _body: Node3D
var _g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _save_t := 0.0
var _launching := false
var _audio: EngineAudio
var _bump_cool := 0.0


static func build(s: Node, e: Dictionary, space: bool = false) -> Node3D:
	var ship := Ship.new()
	ship.scene = s
	ship.entry = e.duplicate(true)
	ship.entry_id = str(e.get("id", ""))
	ship.display_name = str(e.get("name", "la nave"))
	ship.in_space = space
	ship.name = "Creation_" + ship.entry_id
	ship.collision_layer = Layers.WORLD
	ship.collision_mask = Layers.WORLD
	# En un planeta, con suelo (para saber cuándo está posada); en el espacio, libre
	ship.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING if space else CharacterBody3D.MOTION_MODE_GROUNDED
	ship.floor_max_angle = deg_to_rad(30.0)
	for b in e.get("behaviors", []):
		if str(b.get("type", "")) == "thruster":
			var p: Dictionary = b.get("params", {}) if b.get("params", {}) is Dictionary else {}
			ship.power = clampf(float(p.get("power", 5.0)), 1.0, 10.0)
	ship.fuel = clampf(float(e.get("fuel", 1.0)), 0.0, 1.0)
	ship.hull = clampf(float(e.get("hull", 100.0)), 0.0, 100.0)
	s.add_child(ship)
	if e.has("pos"):
		var start := Vector3(e.pos[0], e.pos[1], e.pos[2])
		if not space and s.has_method("ground_at") and not InteriorManager.is_interior_pos(start):
			start.y = maxf(start.y, float(s.call("ground_at", start.x, start.z)))
		ship.global_position = start
	ship.rotation.y = float(e.get("yaw", 0.0))
	ship._body = Node3D.new()
	ship._body.name = "Body"
	ship._body.scale = Vector3.ONE * clampf(float(e.get("scale", 1.0)), 0.2, 10.0)
	ship.add_child(ship._body)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var model_path := str(e.get("model", ""))
	if not model_path.is_empty():
		var mp: PackedStringArray = model_path.split("/")
		var model := AssetLibrary.instance(mp[0], mp[1]) if mp.size() == 2 else null
		if model:
			var placed := AssetLibrary.place(ship._body, model, Vector3.ZERO, float(e.get("height", 3.0)), 0.0, false)
			var b := AssetLibrary.bounds(placed)
			var sc: float = placed.get_meta("size", b.size).y / maxf(b.size.y, 0.01)
			lo = Vector3(-b.size.x, 0, -b.size.z) / 2.0 * sc
			hi = Vector3(b.size.x / 2.0, b.size.y, b.size.z / 2.0) * sc
			ship._model_shapes(placed, ship._body.scale.x)
	var parts: Array = e.get("parts", [])
	for i in parts.size():
		var p: Dictionary = parts[i]
		Creations._part(ship._body, p, i, false)
		var size := Creations._vec(p.get("size", [1, 1, 1]), Vector3.ONE) * ship._body.scale
		var at := Creations._vec(p.get("pos", [0, 0, 0]), Vector3.ZERO) * ship._body.scale
		var pb := Creations.part_bounds(p, ship._body.scale.x)
		lo = lo.min(pb.position)
		hi = hi.max(pb.end)
		if str(p.get("role", "")) in ["seat", "cockpit"]:
			ship._seat = at + Vector3(0, size.y * 0.1, 0)
		# Cada pieza choca con su forma (no una caja que lo envuelva todo: bajo las alas se pasa)
		if str(p.get("shape", "")) != "light":
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size.max(Vector3.ONE * 0.1)
			cs.shape = box
			cs.transform = Transform3D(Basis.from_euler(Creations._vec(p.get("rot", [0, 0, 0]), Vector3.ZERO) * PI / 180.0), at)
			ship.add_child(cs)
	if lo == Vector3.INF:
		lo = Vector3(-2, 0, -3)
		hi = Vector3(2, 2, 3)
	if ship.find_children("*", "CollisionShape3D", false, false).is_empty():
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (hi - lo).max(Vector3.ONE * 0.5)
		cs.shape = box
		cs.position = (hi + lo) / 2.0
		ship.add_child(cs)
	ship.length = hi.z - lo.z
	if ship._seat == Vector3(0, 1.2, 0):
		ship._seat = Vector3(0, hi.y * 0.55, (hi.z + lo.z) / 2.0 + (hi.z - lo.z) * 0.15)
	# Las toberas brillan al empujar (las piezas "thruster" o, en un modelo, la cola)
	var nozzles: Array = []
	for i in parts.size():
		if str(parts[i].get("role", "")) == "thruster":
			nozzles.append(Creations._vec(parts[i].get("pos", [0, 0, 0]), Vector3.ZERO) * ship._body.scale)
	if nozzles.is_empty():
		nozzles.append(Vector3(0, hi.y * 0.45, lo.z))
	for at in nozzles:
		var glow := OmniLight3D.new()
		glow.name = "Thrust"
		glow.light_color = Color("#7fd0ff")
		glow.omni_range = 5.0
		glow.light_energy = 0.0
		glow.position = at
		ship.add_child(glow)
	ship._audio = EngineAudio.new()
	ship._audio.kind = "ship"
	ship._audio.position = Vector3(0, hi.y * 0.5, lo.z)
	ship.add_child(ship._audio)
	if not space:
		ship._use = Interactable.create(ship, Vector3(0, 1.0, 0), maxf(ship.length * 0.45, 3.0), "Pilotar %s" % ship.display_name, ship._on_use, ship)
	return ship


## La forma de choque de un modelo: el fuselaje (la parte central, de arriba abajo) y las alas
## (una losa fina a su altura). Bajo las alas y junto a la nave se puede pasar.
func _model_shapes(placed: Node3D, user_scale: float) -> void:
	var pts := PackedVector3Array()
	for mi in AssetLibrary._meshes(placed):
		var t := Vehicle._to_root(mi, self)
		t = Transform3D(Basis.from_scale(Vector3.ONE / user_scale), Vector3.ZERO) * t if user_scale != 1.0 else t
		var faces := (mi as MeshInstance3D).mesh.get_faces()
		for i in range(0, faces.size(), 7):  # (una muestra basta)
			pts.append(t * faces[i])
	if pts.is_empty():
		return
	var all := AABB(pts[0], Vector3.ZERO)
	for v in pts:
		all = all.expand(v)
	var half := all.size.x / 2.0
	var cx := all.get_center().x
	var core := AABB()
	var wing := AABB()
	var core_set := false
	var wing_set := false
	for v in pts:
		if absf(v.x - cx) < half * 0.32:
			core = core.expand(v) if core_set else AABB(v, Vector3.ZERO)
			core_set = true
		else:
			wing = wing.expand(v) if wing_set else AABB(v, Vector3.ZERO)
			wing_set = true
	for a: AABB in [core, wing]:
		if a.size == Vector3.ZERO:
			continue
		var box: AABB = a
		if a == wing:  # las alas: una losa a media altura de lo que ocupan, no un bloque
			var mid := a.position.y + a.size.y * 0.5
			box = AABB(Vector3(a.position.x, mid - minf(a.size.y, 0.9) / 2.0, a.position.z), Vector3(a.size.x, minf(a.size.y, 0.9), a.size.z))
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = (box.size * user_scale).max(Vector3.ONE * 0.2)
		cs.shape = shape
		cs.position = box.get_center() * user_scale
		add_child(cs)


func seat_position() -> Vector3:
	return global_transform * _seat


func is_occupied() -> bool:
	return _rider != null


func camera_distance() -> float:
	return clampf(length * 1.4 + 4.0, 8.0, 26.0)


func the_name() -> String:
	return "la " + display_name.to_lower() if display_name.to_lower().begins_with("nave") or display_name.to_lower().begins_with("lanzadera") else display_name


func _on_use(player: Player) -> void:
	if _rider == null:
		_rider = player
		player.riding = self
		player.add_collision_exception_with(self)
		add_collision_exception_with(player)
		player.play_gesture("sit")
		_use.set_prompt("Bajar")
		Sfx.at(self, "door", global_position + Vector3(0, 1, 0))
	else:
		if not is_on_floor() and _ground_gap() > 2.5:
			if scene and scene.get("_ui") and scene.get("_ui").has_method("toast"):
				scene.get("_ui").toast("Aterriza primero (Ctrl/Q para bajar).")
			return
		_leave()


func _leave() -> void:
	var player := _rider
	_rider = null
	player.riding = null
	player.stop_gesture()
	_use.set_prompt("Pilotar %s" % display_name)
	var side := global_basis.x.normalized()
	var out := global_position - side * (length * 0.5 + 2.0)
	if scene and scene.has_method("ground_at"):
		out.y = float(scene.call("ground_at", out.x, out.z)) + 0.3
	if not InteriorManager.is_free(self, out, [self, player], 0.3):
		out = InteriorManager.free_spot_near(self, out, -side, [self, player]) + Vector3(0, 0.2, 0)
	player.global_position = out
	_save()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_instance_valid(player):
		player.remove_collision_exception_with(self)
		remove_collision_exception_with(player)


func _ground_gap() -> float:
	if scene and scene.has_method("ground_at"):
		return global_position.y - float(scene.call("ground_at", global_position.x, global_position.z))
	return 0.0


## Mandos: thrust (W/S), side (A/D), up (Espacio/Ctrl), boost (Shift).
func controls() -> Dictionary:
	var mv := Controls.move_vector()
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("descend") else 0.0)
	return {"side": mv.x, "up": up, "thrust": -mv.y, "boost": Input.is_action_pressed("run")}


func _physics_process(delta: float) -> void:
	_bump_cool -= delta
	var active := (_rider != null and _rider.controls_enabled) or piloted
	var c: Dictionary = controls() if active else {"side": 0.0, "up": 0.0, "thrust": 0.0, "boost": false}
	var has_fuel := fuel > 0.0 and hull > 0.0
	if in_space:
		_fly_space(c, delta, has_fuel)
	else:
		_fly_air(c, delta, has_fuel, active)
	var pushing := (absf(c.thrust) + absf(c.up) + absf(c.side) > 0.0 or (active and not in_space and not is_on_floor())) and has_fuel
	for n in get_children():
		if n.name.begins_with("Thrust"):
			(n as OmniLight3D).light_energy = lerpf((n as OmniLight3D).light_energy, (2.5 if pushing else 0.0) * (1.6 if c.boost else 1.0), 6.0 * delta)
	if _audio:
		_audio.running = active and has_fuel
		_audio.load = clampf(absf(c.thrust) + absf(c.up) * 0.7 + (0.6 if c.boost else 0.0), 0.0, 1.0)
		_audio.rpm = velocity.length() * 20.0
	if pushing:
		fuel = maxf(fuel - delta * (0.0009 if not c.boost else 0.003), 0.0)
	_save_t += delta
	if _save_t > 4.0 and not in_space:
		_save_t = 0.0
		_save()


## Hacia dónde miras (la cámara): la nave gira hacia ahí al volar.
func _aim_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return rotation.y
	var f := -cam.global_basis.z
	return atan2(f.x, f.z)


func _fly_air(c: Dictionary, delta: float, has_fuel: bool, active: bool) -> void:
	var gscale := float(scene.get("_player").gravity_scale) if scene and scene.get("_player") else 1.0
	var acc := 6.0 + power * 2.0
	var top := (12.0 + power * 6.0) * (1.8 if c.boost else 1.0)
	var grounded := is_on_floor()
	# Gira hacia donde apuntas con el ratón (en el aire, o en tierra si empujas)
	if active and has_fuel and (not grounded or absf(float(c.thrust)) > 0.0):
		rotation.y = lerp_angle(rotation.y, _aim_yaw(), clampf(1.6 * delta, 0.0, 1.0))
	var want := (global_basis.z * float(c.thrust) + global_basis.x * -float(c.side) * 0.6) * top
	if not has_fuel or not active:
		want = Vector3.ZERO
	var horiz := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3(want.x, 0, want.z), acc * delta * (0.25 if grounded and not active else 1.0))
	var vy := velocity.y
	if active and has_fuel:
		# Los motores compensan la gravedad (se queda flotando si no tocas nada)
		var climb := float(c.up) * (10.0 + power * 1.5) * (1.6 if c.boost else 1.0)
		vy = move_toward(vy, climb, acc * 1.4 * delta)
	elif not grounded:
		vy = maxf(vy - _g * gscale * delta, -55.0)  # sin motor (o sin combustible) cae
	else:
		vy = 0.0
	if grounded and vy < 0.0:
		vy = 0.0
	velocity = Vector3(horiz.x, vy, horiz.z)
	var hit_speed := velocity.length()
	move_and_slide()
	_check_bump(hit_speed)
	if _body:  # se inclina al acelerar y al desplazarse de lado
		_body.rotation.x = lerp_angle(_body.rotation.x, -float(c.thrust) * 0.12, 3.0 * delta)
		_body.rotation.z = lerp_angle(_body.rotation.z, float(c.side) * 0.22, 3.0 * delta)
	if active and _ground_gap() > SPACE_ALTITUDE and not _launching and scene and scene.has_method("launch_ship"):
		_launching = true
		scene.call("launch_ship", self)


func _fly_space(c: Dictionary, delta: float, has_fuel: bool) -> void:
	var acc := 14.0 + power * 6.0
	var top := (50.0 + power * 14.0) * (60.0 if c.boost else 1.0)
	# El ratón cabecea y gira; A/D alabean. Todo suavizado (una nave tiene inercia al girar)
	var s := steer
	steer = Vector2.ZERO
	rotate_object_local(Vector3.UP, -s.x)
	rotate_object_local(Vector3.RIGHT, s.y)
	rotate_object_local(Vector3.FORWARD, float(c.side) * 1.4 * delta)
	if has_fuel and (float(c.thrust) != 0.0 or float(c.up) != 0.0):
		var want := (global_basis.z * float(c.thrust) + global_basis.y * float(c.up) * 0.5) * top
		velocity = velocity.move_toward(want, acc * (40.0 if c.boost else 1.0) * delta)
	elif assist and not c.boost:
		velocity = velocity.move_toward(Vector3.ZERO, acc * 0.35 * delta)  # amortiguadores de inercia
	var hit := move_and_collide(velocity * delta)
	if hit:  # rebota y se daña el casco según lo fuerte del golpe
		var n := hit.get_normal()
		var into := -velocity.dot(n)
		if into > 0.0:
			velocity = velocity.bounce(n) * 0.35
			if into > 8.0 and _bump_cool <= 0.0:
				_bump_cool = 0.6
				hull = maxf(hull - (into - 8.0) * 0.6, 0.0)
				Sfx.at(self, "crash", global_position)
				if scene and scene.has_method("on_ship_hit"):
					scene.call("on_ship_hit", into)


## Un golpe en el aire (contra un edificio, el suelo a toda velocidad): daña el casco.
func _check_bump(before: float) -> void:
	if get_slide_collision_count() == 0 or _bump_cool > 0.0:
		return
	var lost := before - velocity.length()
	if lost > 9.0:
		_bump_cool = 0.8
		hull = maxf(hull - (lost - 9.0) * 1.2, 0.0)
		Sfx.at(self, "crash", global_position)
		if _rider:
			_rider.shake(0.4, 0.06)
			if GameState.is_awakened():
				GameState.change_stat("health", -int(lost * 0.6))


func speed() -> float:
	return velocity.length()


func _save() -> void:
	if entry_id.is_empty() or in_space:
		return
	var p := global_position
	Creations.update(entry_id, {"pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"yaw": snappedf(global_rotation.y, 0.001), "fuel": snappedf(fuel, 0.001), "hull": snappedf(hull, 0.1)})


## Nave de fábrica: la lanzadera vieja (el modelo «Insurgent» de Quaternius, de transporte).
## Sin el modelo, una lanzadera por piezas.
static func factory(model: String = "Insurgent") -> Dictionary:
	if ResourceLoader.exists(AssetLibrary.path(MODEL_DIR, model)):
		return {"name": "Lanzadera", "model": MODEL_DIR + "/" + model, "height": 3.4, "parts": [],
			"behaviors": [{"type": "thruster", "params": {"power": 6}}, {"type": "cockpit"}, {"type": "tank"}]}
	return {"name": "Lanzadera", "behaviors": [{"type": "thruster", "params": {"power": 6}}, {"type": "cockpit"}, {"type": "tank"}], "parts": [
		{"shape": "capsule", "size": [2.6, 7.0, 2.6], "pos": [0, 1.8, 0], "rot": [90, 0, 0], "material": "metal", "color": "#d8dde3"},
		{"shape": "sphere", "size": [2.0, 1.4, 2.0], "pos": [0, 2.7, 1.6], "material": "glass", "color": "#2a4a6a"},
		{"shape": "box", "size": [0.6, 0.5, 0.7], "pos": [0, 2.2, 1.4], "material": "fabric", "color": "#2b2f3a", "role": "cockpit"},
		{"shape": "box", "size": [7.0, 0.18, 2.4], "pos": [0, 1.4, -1.0], "material": "metal", "color": "#9aa3ad"},
		{"shape": "box", "size": [0.2, 1.8, 1.6], "pos": [0, 3.0, -2.6], "material": "metal", "color": "#b23a3a"},
		{"shape": "cylinder", "size": [1.0, 1.2, 1.0], "pos": [-0.8, 1.8, -3.6], "rot": [90, 0, 0], "material": "metal", "color": "#3a3f46", "role": "thruster"},
		{"shape": "cylinder", "size": [1.0, 1.2, 1.0], "pos": [0.8, 1.8, -3.6], "rot": [90, 0, 0], "material": "metal", "color": "#3a3f46", "role": "thruster"},
		{"shape": "cylinder", "size": [0.25, 1.4, 0.25], "pos": [-2.2, 0.7, 0.8], "material": "metal", "color": "#3a3f46"},
		{"shape": "cylinder", "size": [0.25, 1.4, 0.25], "pos": [2.2, 0.7, 0.8], "material": "metal", "color": "#3a3f46"},
		{"shape": "cylinder", "size": [0.25, 1.4, 0.25], "pos": [0, 0.7, -2.6], "material": "metal", "color": "#3a3f46"}]}

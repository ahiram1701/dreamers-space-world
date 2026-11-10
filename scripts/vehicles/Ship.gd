class_name Ship
extends CharacterBody3D
## Una nave: cualquier creación con "thruster" (y "cockpit" para pilotarla), o una de fábrica con
## modelo (las naves de Quaternius). En un planeta despega y aterriza en vertical: apuntas con el
## ratón (la nave gira hacia donde miras), W/S avanza y frena, A/D se desplaza de lado, Espacio
## sube, Ctrl/Q baja y Shift da potencia; sin combustible cae. Si sube lo bastante, sale al
## espacio (SpaceScene). En el espacio: el ratón cabecea y gira, A/D alabea, W/S empuja, Shift
## crucero, Z asistencia de vuelo (frena la inercia sola), X frena en seco. Choca de verdad: los
## golpes dañan el casco. Dentro vas sentado en la cabina (no encima): V cambia entre la vista de
## cabina, con el tablero, y la de fuera. Lleva pasajeros (quien te acompaña sube contigo).

const SPACE_ALTITUDE := 160.0   # por encima de esto (sobre el suelo) estás saliendo de la atmósfera
const MODEL_DIR := "spaceships_pack"
const CRUISE := 1500.0          # crucero (Shift) en el espacio, m/s: rápido pero controlable
const MAX_HIT := 35.0           # un golpe nunca quita más que esto del casco

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
## Quien va dentro no se ve (va en la cabina, no sentado encima del casco).
var hides_riders := true
## Vista desde la cabina (V): cámara en el asiento del piloto y tablero con los instrumentos.
var cockpit := false
var proximity := false          # el crucero se corta: hay algo delante
var _cruise_lock := false        # tras cortarse, no vuelve a engancharse hasta soltar Shift
## Piloto automático (en el espacio): vuela solo hasta auto_point y se para a auto_stop de él.
var autopilot := false
var auto_point := Vector3.ZERO
var auto_stop := 0.0
signal autopilot_arrived
signal autopilot_stopped(why: String)
var _detour := Vector3.INF
var _detour_t := 0.0

var _rider: Player
var _use: Interactable
var _seat := Vector3(0, 1.2, 0)
var _body: Node3D
var _g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _save_t := 0.0
var _launching := false
var _audio: EngineAudio
var _bump_cool := 0.0
var _seats: Array = []          # 0 = piloto; el resto, pasajeros
var _passengers := {}           # asiento -> TownNPC
var _eye := Vector3(0, 2.0, 1.0)
var _cockpit_root: Node3D
var _cockpit_cam: Camera3D
var _prev_cam: Camera3D
var _cam_pitch := 0.0
var _gauges: Label3D
var _stick: Node3D
var _throttle: Node3D
var _buttons := {}            # nombre -> material del piloto (asistencia, piloto automático, proximidad)
var _radar: Node3D
var _radar_dots: Array = []
var _radar_t := 0.0
var _cabin_light: OmniLight3D
var _shake := 0.0
var _prev_vel := Vector3.ZERO


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
	# Asientos: el piloto delante y, detrás, los pasajeros (todos dentro del casco)
	var back := clampf(ship.length * 0.12, 0.9, 1.6)
	ship._seats = [ship._seat, ship._seat + Vector3(0.75, 0, -back), ship._seat + Vector3(-0.75, 0, -back), ship._seat + Vector3(0, 0, -back * 2.0)]
	ship._eye = Vector3(0, maxf(ship._seat.y + 0.7, hi.y * 0.72), ship._seat.z + clampf(ship.length * 0.12, 0.4, 1.4))
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


func seat_position(i: int = 0) -> Vector3:
	var at: Vector3 = _seats[i] if i < _seats.size() else _seat
	return global_transform * at


func free_seats() -> int:
	return maxi(_seats.size() - 1 - _passengers.size(), 0)


## Un PNJ sube de pasajero (va dentro: no se ve). false si no cabe.
func board(npc: TownNPC) -> bool:
	if _passengers.values().has(npc):
		return true
	for i in range(1, _seats.size()):
		if not _passengers.has(i):
			_passengers[i] = npc
			npc.ride(self, i)
			add_collision_exception_with(npc)
			return true
	return false


func passengers() -> Array:
	return _passengers.values().filter(func(n): return is_instance_valid(n))


## Bajan todos, por el costado de la nave.
func alight_all() -> Array:
	var out := []
	var k := 0
	for i in _passengers.keys():
		var npc: TownNPC = _passengers[i]
		if not is_instance_valid(npc):
			continue
		k += 1
		var side := global_basis.x.normalized()
		var spot := global_position - side * (length * 0.5 + 2.0) - global_basis.z.normalized() * (1.2 * k)
		if scene and scene.has_method("ground_at"):
			spot.y = float(scene.call("ground_at", spot.x, spot.z)) + 0.2
		spot = InteriorManager.free_spot_near(self, spot, -side, [self, npc]) + Vector3(0, 0.15, 0)
		npc.get_off(spot)
		remove_collision_exception_with(npc)
		out.append(npc)
	_passengers.clear()
	return out


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
		if scene and scene.has_method("on_player_boarded"):
			scene.call("on_player_boarded", self)
	else:
		if not is_on_floor() and _ground_gap() > 2.5:
			if scene and scene.get("_ui") and scene.get("_ui").has_method("toast"):
				scene.get("_ui").toast("Aterriza primero (Ctrl/Q para bajar).")
			return
		_leave()


func _leave() -> void:
	var player := _rider
	set_cockpit(false)
	_rider = null
	player.riding = null
	player.stop_gesture()
	var left := alight_all()
	if scene and scene.has_method("on_player_alighted"):
		scene.call("on_player_alighted", self, left)
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
	var has_fuel := fuel > 0.0  # (con el casco destrozado aún responde, a poca potencia)
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
		# (limitado: a velocidad de crucero el silbido se salía del rango audible y sonaba raro)
		_audio.rpm = minf(velocity.length() * 20.0, 4200.0)
	if cockpit:
		_update_cockpit(delta, c)
	if pushing:
		fuel = maxf(fuel - delta * (0.0009 if not c.boost else 0.003), 0.0)
	_save_t += delta
	if _save_t > 4.0 and not in_space:
		_save_t = 0.0
		_save()


## Hacia dónde miras (la cámara): la nave gira hacia ahí al volar. En la cabina el ratón ya gira
## la nave directamente.
func _aim_yaw() -> float:
	if cockpit:
		return rotation.y
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
	var normal_top := (50.0 + power * 14.0) * (0.35 if hull <= 0.0 else 1.0)
	# Crucero con Shift, pero no a ciegas: si hay algo delante (un planeta, un asteroide, la
	# estación), se corta solo. Antes llegaba a 8 km/s y luego tardaba minutos en frenar.
	if not c.boost:
		_cruise_lock = false
	var boost: bool = c.boost and has_fuel and hull > 0.0 and not _cruise_lock
	proximity = false
	# Algo delante (planeta, luna, sol, asteroide, estación): se frena con tiempo hasta parar a
	# ~300 m, y el crucero no se vuelve a enganchar solo (antes daba tirones y chocabas a 130 m/s)
	var vspd := velocity.length()
	if vspd > 40.0 and not autopilot:
		var reach := clampf(vspd * 3.5, 400.0, 7000.0)
		var d := _obstacle_distance(global_position, global_position + velocity.normalized() * reach)
		if d < INF:
			proximity = true
			boost = false
			_cruise_lock = c.boost
			var safe := sqrt(maxf(d - 300.0, 0.0) * 2.0 * (CRUISE / 3.0)) * 0.8
			if vspd > safe:
				velocity = velocity.limit_length(maxf(vspd - CRUISE / 3.0 * 1.6 * delta, safe))
	var top := CRUISE if boost else normal_top
	# El ratón cabecea y gira; A/D alabean. Todo suavizado (una nave tiene inercia al girar)
	var s := steer
	steer = Vector2.ZERO
	# El piloto automático solo lo cortas a propósito: W/S, X o G (el ratón ya no lo corta: antes un
	# roce lo apagaba). Sin combustible se apaga y avisa.
	if autopilot and (float(c.thrust) != 0.0 or Input.is_action_pressed("ship_brake")):
		autopilot = false
		autopilot_stopped.emit("tomas el mando")
	if autopilot and not has_fuel:
		autopilot = false
		autopilot_stopped.emit("sin combustible")
	if not autopilot:
		rotate_object_local(Vector3.UP, -s.x)
		rotate_object_local(Vector3.RIGHT, s.y)
	rotate_object_local(Vector3.FORWARD, float(c.side) * 1.4 * delta)
	transform = transform.orthonormalized()
	var spd := velocity.length()
	if autopilot and has_fuel:
		# Esquiva: si hay algo entre la nave y el destino (una luna, el sol, otro planeta), pasa por
		# encima de ello antes de seguir
		_detour_t -= delta
		if _detour_t <= 0.0:
			_detour_t = 0.5
			var aim := auto_point - global_position
			var reach := minf(aim.length() - auto_stop * 0.8, 8000.0)
			if reach > 50.0:
				var q := PhysicsRayQueryParameters3D.create(global_position, global_position + aim.normalized() * reach, collision_mask, [get_rid()])
				var hit := get_world_3d().direct_space_state.intersect_ray(q)
				var d := _obstacle_distance(global_position, global_position + aim.normalized() * reach)
				if not hit.is_empty() or d < INF:
					# Se rodea por un lado, perpendicular al rumbo (nunca hacia la superficie)
					var at: Vector3 = hit.position if not hit.is_empty() else global_position + aim.normalized() * d
					var side := aim.normalized().cross(Vector3.UP)
					if side.length() < 0.1:
						side = aim.normalized().cross(Vector3.RIGHT)
					_detour = at + side.normalized() * 1400.0 + Vector3.UP * 300.0
				elif _detour != Vector3.INF and global_position.distance_to(_detour) < 300.0:
					_detour = Vector3.INF
		var goal := _detour if _detour != Vector3.INF else auto_point
		var to := goal - global_position
		var dist := to.length() - (0.0 if _detour != Vector3.INF else auto_stop)
		if dist < 25.0 and _detour != Vector3.INF:
			_detour = Vector3.INF
		elif dist < 25.0:
			autopilot = false
			velocity = velocity.limit_length(10.0)
			autopilot_arrived.emit()
		else:
			var dir := to.normalized()
			var up := global_basis.y if absf(global_basis.y.dot(dir)) < 0.95 else global_basis.x
			global_basis = global_basis.slerp(Basis.looking_at(-dir, up), clampf(1.5 * delta, 0.0, 1.0)).orthonormalized()
			# Acelera hasta crucero y frena con tiempo (llega a ~2 km de la superficie ya despacio)
			var want := clampf(sqrt(maxf(dist, 0.0) * 2.0 * (CRUISE / 3.0)) * 0.7, 20.0, CRUISE)
			if global_basis.z.dot(dir) < 0.9:
				want = minf(want, normal_top)  # primero se orienta
			velocity = velocity.move_toward(dir * want, CRUISE / 3.0 * delta)
	elif Input.is_action_pressed("ship_brake") and (_rider != null or piloted):
		velocity = velocity.move_toward(Vector3.ZERO, maxf(acc * 4.0, spd * 1.6) * delta)  # frenazo
	elif has_fuel and boost:
		velocity = velocity.move_toward(global_basis.z * top, CRUISE / 3.0 * delta)  # ~3 s hasta crucero
	elif has_fuel and (float(c.thrust) != 0.0 or float(c.up) != 0.0):
		var want := (global_basis.z * float(c.thrust) + global_basis.y * float(c.up) * 0.5) * top
		var rate := acc * (4.0 if float(c.thrust) < 0.0 and velocity.dot(global_basis.z) > 0.0 else 1.0)
		velocity = velocity.move_toward(want, rate * delta)
		if spd > top * 1.05:  # vienes de crucero: los amortiguadores bajan el exceso en ~2 s
			velocity = velocity.limit_length(maxf(spd - maxf(spd - top, 200.0) * 0.5 * delta * 2.0, top))
	elif assist:
		var bleed := acc * 0.35 if spd <= normal_top * 1.05 else maxf((spd - normal_top) * 1.2, acc)
		velocity = velocity.move_toward(Vector3.ZERO if spd <= normal_top * 1.05 else velocity.normalized() * normal_top, bleed * delta)
	elif spd > normal_top * 1.05:
		# Sin asistencia, al soltar Shift la nave vuelve a su velocidad normal (antes seguía a 1.5 km/s)
		velocity = velocity.move_toward(velocity.normalized() * normal_top, maxf((spd - normal_top) * 1.2, acc) * delta)
	if not velocity.is_finite():
		velocity = Vector3.ZERO  # nunca NaN
	# A crucero se recorren decenas de metros por paso: se mueve en tramos cortos para no atravesar
	# un asteroide pequeño
	var motion := velocity * delta
	var hit: KinematicCollision3D = null
	var steps := clampi(int(ceil(motion.length() / 10.0)), 1, 8)
	for i in steps:
		hit = move_and_collide(motion / steps)
		if hit:
			break
	if hit:  # rebota y se daña el casco según lo fuerte del golpe
		var n := hit.get_normal()
		var into := -velocity.dot(n)
		if into > 0.0:
			velocity = velocity.bounce(n) * 0.35
			velocity = velocity.limit_length(maxf(normal_top, 40.0))  # tras un golpe, a velocidad manejable
			if into > 8.0 and _bump_cool <= 0.0:
				_bump_cool = 0.6
				hull = maxf(hull - minf((into - 8.0) * 0.6, MAX_HIT), 0.0)
				Sfx.at(self, "crash", global_position)
				if scene and scene.has_method("on_ship_hit"):
					scene.call("on_ship_hit", into)


## Distancia al primer obstáculo en el tramo (planetas, lunas, sol, asteroides) o INF.
func _obstacle_distance(a: Vector3, b: Vector3) -> float:
	var d := INF
	if scene and scene.has_method("obstacle_distance"):
		d = float(scene.call("obstacle_distance", a, b, length + 30.0))
	if scene and scene.has_method("rock_on_segment") and scene.call("rock_on_segment", a, b, length):
		d = minf(d, a.distance_to(b) * 0.5)
	var q := PhysicsRayQueryParameters3D.create(a, b, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		d = minf(d, a.distance_to(hit.position))
	return d


## Un golpe en el aire (contra un edificio, el suelo a toda velocidad): daña el casco.
func _check_bump(before: float) -> void:
	if get_slide_collision_count() == 0 or _bump_cool > 0.0:
		return
	var lost := before - velocity.length()
	if lost > 9.0:
		_bump_cool = 0.8
		hull = maxf(hull - minf((lost - 9.0) * 1.2, MAX_HIT), 0.0)
		Sfx.at(self, "crash", global_position)
		if _rider:
			_rider.shake(0.4, 0.06)
			if GameState.is_awakened():
				GameState.change_stat("health", -int(lost * 0.6))


func speed() -> float:
	return velocity.length()


# --- Cabina ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _rider == null and not piloted:
		return
	if event.is_action_pressed("cockpit_view"):
		set_cockpit(not cockpit)
		get_viewport().set_input_as_handled()
	elif cockpit and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative * Settings.mouse_sensitivity
		if not in_space:  # en un planeta, el ratón gira la nave y mira arriba/abajo
			rotation.y -= rel.x * 0.0025
			_cam_pitch = clampf(_cam_pitch - rel.y * 0.002, -0.6, 0.45)


## Entrar o salir de la vista de cabina.
func set_cockpit(on: bool) -> void:
	if on == cockpit:
		return
	cockpit = on
	if on:
		if _cockpit_root == null:
			_build_cockpit()
		_prev_cam = get_viewport().get_camera_3d()
		_cockpit_root.visible = true
		if _body:
			_body.visible = false  # (el casco de fuera tapaba la vista desde dentro)
		_cockpit_cam.fov = Settings.fov
		_cockpit_cam.make_current()
	else:
		if _cockpit_root:
			_cockpit_root.visible = false
		if _body:
			_body.visible = true
		if _prev_cam and is_instance_valid(_prev_cam):
			_prev_cam.make_current()
		_prev_cam = null


## El tablero: consola, marco del cristal, palanca y una pantalla con los instrumentos.
func _build_cockpit() -> void:
	_cockpit_root = Node3D.new()
	_cockpit_root.name = "Cabina"
	add_child(_cockpit_root)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#23272e")
	dark.roughness = 0.6
	var frame_m := StandardMaterial3D.new()
	frame_m.albedo_color = Color("#3b414b")
	frame_m.metallic = 0.6
	frame_m.roughness = 0.4
	var screen_m := StandardMaterial3D.new()
	screen_m.albedo_color = Color("#06131c")
	screen_m.emission_enabled = true
	screen_m.emission = Color("#0d3a4f")
	screen_m.emission_energy_multiplier = 0.6
	var e := _eye
	# Consola bajo la vista, inclinada hacia el piloto
	_cockpit_box(Vector3(1.5, 0.08, 0.55), e + Vector3(0, -0.52, 0.62), Vector3(-0.5, 0, 0), dark)
	_cockpit_box(Vector3(1.5, 0.45, 0.08), e + Vector3(0, -0.78, 0.86), Vector3.ZERO, dark)
	_cockpit_box(Vector3(0.66, 0.24, 0.02), e + Vector3(0, -0.29, 0.95), Vector3.ZERO, screen_m)
	# Marco del cristal: dos montantes y el arco de arriba
	for sx in [-1.0, 1.0]:
		_cockpit_box(Vector3(0.06, 1.0, 0.06), e + Vector3(0.78 * sx, 0.0, 0.85), Vector3(0, 0, 0.25 * sx), frame_m)
	_cockpit_box(Vector3(1.7, 0.07, 0.07), e + Vector3(0, 0.48, 0.78), Vector3.ZERO, frame_m)
	# Palanca
	_stick = Node3D.new()
	_stick.position = e + Vector3(0, -0.85, 0.35)
	_cockpit_root.add_child(_stick)
	var stick_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.03
	cyl.height = 0.32
	stick_mesh.mesh = cyl
	stick_mesh.position.y = 0.16
	stick_mesh.material_override = frame_m
	_stick.add_child(stick_mesh)
	# Asiento: respaldo, cabecero y reposabrazos
	_cockpit_box(Vector3(0.62, 0.9, 0.12), e + Vector3(0, -0.25, -0.42), Vector3(0.2, 0, 0), dark)
	_cockpit_box(Vector3(0.36, 0.26, 0.1), e + Vector3(0, 0.33, -0.45), Vector3(0.2, 0, 0), dark)
	_cockpit_box(Vector3(0.62, 0.12, 0.6), e + Vector3(0, -0.74, -0.15), Vector3.ZERO, dark)
	for sx in [-1.0, 1.0]:
		_cockpit_box(Vector3(0.1, 0.1, 0.55), e + Vector3(sx * 0.36, -0.55, -0.1), Vector3.ZERO, frame_m)
	# Paneles laterales con botones que se iluminan
	for sx in [-1.0, 1.0]:
		_cockpit_box(Vector3(0.05, 0.4, 0.7), e + Vector3(sx * 0.72, -0.45, 0.35), Vector3(0, 0, -sx * 0.5), dark)
	var labels := [["asistencia", Color("#4fe08a"), -1.0, 0.0], ["piloto", Color("#4fc3f7"), -1.0, 0.12], ["proximidad", Color("#ff4a4a"), 1.0, 0.0], ["casco", Color("#ffb347"), 1.0, 0.12]]
	for lb in labels:
		var bm := StandardMaterial3D.new()
		bm.albedo_color = (lb[1] as Color).darkened(0.6)
		bm.emission_enabled = true
		bm.emission = lb[1]
		bm.emission_energy_multiplier = 0.0
		var btn := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(0.05, 0.05, 0.05)
		btn.mesh = bx
		btn.material_override = bm
		btn.position = e + Vector3(float(lb[2]) * 0.69, -0.36 - float(lb[3]), 0.3)
		_cockpit_root.add_child(btn)
		_buttons[lb[0]] = bm
	# Palanca de gases, a la izquierda
	_throttle = Node3D.new()
	_throttle.position = e + Vector3(-0.36, -0.55, 0.05)
	_cockpit_root.add_child(_throttle)
	var th := MeshInstance3D.new()
	var thm := BoxMesh.new()
	thm.size = Vector3(0.05, 0.22, 0.05)
	th.mesh = thm
	th.position.y = 0.11
	th.material_override = frame_m
	_throttle.add_child(th)
	# Radar: un disco con los cuerpos cercanos como puntos (planetas, rocas, naves)
	_radar = Node3D.new()
	_radar.position = e + Vector3(0.42, -0.46, 0.7)
	_radar.rotation = Vector3(-0.6, 0, 0)
	_cockpit_root.add_child(_radar)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.13
	dm.bottom_radius = 0.13
	dm.height = 0.01
	disc.mesh = dm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("#06131c")
	rmat.emission_enabled = true
	rmat.emission = Color("#0d3a2a")
	rmat.emission_energy_multiplier = 0.8
	disc.material_override = rmat
	_radar.add_child(disc)
	for k in 12:
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.008
		sm.height = 0.016
		dot.mesh = sm
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.albedo_color = Color("#7cffb0")
		dot.material_override = dmat
		dot.visible = false
		_radar.add_child(dot)
		_radar_dots.append(dot)
	# Luz de la cabina (roja si hay peligro)
	_cabin_light = OmniLight3D.new()
	_cabin_light.light_color = Color("#9fd0ff")
	_cabin_light.light_energy = 0.5
	_cabin_light.omni_range = 2.5
	_cabin_light.position = e + Vector3(0, 0.35, 0.2)
	_cockpit_root.add_child(_cabin_light)
	# Instrumentos (texto en la pantalla)
	_gauges = Label3D.new()
	_gauges.font_size = 28
	_gauges.pixel_size = 0.0008
	_gauges.modulate = Color("#8fe3ff")
	_gauges.outline_size = 0
	_gauges.shaded = false
	_gauges.double_sided = false
	_gauges.position = e + Vector3(0, -0.29, 0.92)
	_gauges.rotation = Vector3(0, PI, 0)
	_cockpit_root.add_child(_gauges)
	# La retícula en el centro
	var cross := Label3D.new()
	cross.text = "+"
	cross.font_size = 48
	cross.pixel_size = 0.0012
	cross.modulate = Color(0.6, 0.95, 1.0, 0.6)
	cross.no_depth_test = true
	cross.position = e + Vector3(0, 0, 2.0)
	cross.rotation.y = PI
	_cockpit_root.add_child(cross)
	_cockpit_cam = Camera3D.new()
	_cockpit_cam.position = e
	_cockpit_cam.rotation = Vector3(0, PI, 0)  # la cámara mira a -Z; la nave apunta a +Z
	_cockpit_cam.near = 0.05
	_cockpit_cam.far = 400000.0 if in_space else 4000.0
	_cockpit_root.add_child(_cockpit_cam)


func _cockpit_box(size: Vector3, at: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cockpit_root.add_child(mi)


## Un golpe sacude la cabina.
func shake_cockpit(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength / 40.0, 0.05, 0.25))


func _update_cockpit(delta: float, c: Dictionary) -> void:
	if _cockpit_cam == null:
		return
	_cockpit_cam.rotation.x = lerpf(_cockpit_cam.rotation.x, _cam_pitch, 1.0 - exp(-10.0 * delta))
	# Inercia: al acelerar la cabeza va hacia atrás; los golpes la sacuden
	var acc := (global_basis.inverse() * (velocity - _prev_vel)) / maxf(delta, 0.001)
	_prev_vel = velocity
	_shake = maxf(_shake - delta * 0.6, 0.0)
	_cockpit_cam.position = _cockpit_cam.position.lerp(_eye + Vector3(0, 0, -clampf(acc.z * 0.002, -0.06, 0.06)) + Vector3(randf_range(-_shake, _shake), randf_range(-_shake, _shake), 0) * 0.3, clampf(10.0 * delta, 0.0, 1.0))
	if _throttle:
		_throttle.rotation.x = lerpf(_throttle.rotation.x, float(c.thrust) * 0.5 + (0.3 if c.boost else 0.0), 8.0 * delta)
	if not _buttons.is_empty():
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		_buttons.asistencia.emission_energy_multiplier = 2.0 if assist else 0.0
		_buttons.piloto.emission_energy_multiplier = 2.0 if autopilot else 0.0
		_buttons.proximidad.emission_energy_multiplier = 3.0 * blink if proximity else 0.0
		_buttons.casco.emission_energy_multiplier = 3.0 * blink if hull < 30.0 else 0.0
	if _cabin_light:
		var alarm := proximity or hull < 30.0
		_cabin_light.light_color = Color("#ff3b30") if alarm else Color("#9fd0ff")
		_cabin_light.light_energy = (0.4 + 0.5 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0))) if alarm else 0.5
	_radar_t -= delta
	if _radar and _radar_t <= 0.0:
		_radar_t = 0.2
		var contacts: Array = scene.call("radar_contacts", global_position) if scene and scene.has_method("radar_contacts") else []
		var inv := global_basis.inverse()
		for k in _radar_dots.size():
			var dot: MeshInstance3D = _radar_dots[k]
			if k >= contacts.size():
				dot.visible = false
				continue
			var rel: Vector3 = inv * ((contacts[k][0] as Vector3) - global_position)
			var flat := Vector2(rel.x, rel.z)
			var dist := flat.length()
			var r := clampf(log(1.0 + dist / 200.0) / log(1.0 + 60000.0 / 200.0), 0.0, 1.0) * 0.12
			var p2 := flat.normalized() * r if dist > 0.01 else Vector2.ZERO
			dot.position = Vector3(-p2.x, 0.012 + clampf(rel.y / 20000.0, -0.02, 0.02), -p2.y)
			(dot.material_override as StandardMaterial3D).albedo_color = contacts[k][1]
			dot.visible = true
	if _stick:
		_stick.rotation.x = lerpf(_stick.rotation.x, float(c.thrust) * 0.35, 8.0 * delta)
		_stick.rotation.z = lerpf(_stick.rotation.z, -float(c.side) * 0.35, 8.0 * delta)
	if _gauges:
		var v := velocity.length()
		var lines := PackedStringArray()
		lines.append("VEL %s" % (("%.1f km/s" % (v / 1000.0)) if v >= 1000.0 else ("%d m/s" % roundi(v))))
		if not in_space:
			lines.append("ALT %d m" % roundi(_ground_gap()))
		lines.append("COMB %d%%   CASCO %d%%" % [roundi(fuel * 100.0), roundi(hull)])
		if proximity:
			lines.append("¡PROXIMIDAD!")
		elif in_space:
			lines.append("ASIST " + ("ON" if assist else "OFF"))
		var pax := passengers().size()
		if pax > 0:
			lines.append("A BORDO: %d" % pax)
		_gauges.text = "\n".join(lines)


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

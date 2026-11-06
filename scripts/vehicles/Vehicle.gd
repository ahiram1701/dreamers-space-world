class_name Vehicle
extends VehicleBody3D
## Un vehículo de verdad: física de ruedas y suspensión de Godot (VehicleBody3D). Lo mismo un
## sedán de fábrica que el carrito que inventó la IA: cualquier creación con piezas "wheel" y los
## comportamientos wheels + engine (o pedals) se conduce. E para subir y bajar, WASD para
## conducir. Gasta gasolina (comportamiento tank), y se guarda donde lo dejas.

const FACTORY_COLORS := ["#b23a3a", "#2c5d8f", "#e8e2d4", "#2b2f3a", "#6f7a82", "#2e7d5b", "#c9a227"]

var entry_id := ""
var display_name := "el vehículo"
var max_speed := 16.0       # m/s
var power := 5.0            # 1..10
var pedals := false
var fuel := 1.0             # 0..1
var uses_fuel := true
var owner_id := ""          # quién es el dueño ("" = el jugador o nadie)
var scene: Node

var _rider: Player
var _use: Interactable
var _seat := Vector3(0, 1.0, 0)
var _save_t := 0.0
var _hit_cool := 0.0
var _good := Transform3D()   # última posición sana (si la física se desboca, vuelve aquí)


## Construye un vehículo a partir de una creación (Creations). Lo usa Creations.build.
static func build(s: Node, e: Dictionary) -> Node3D:
	var types: Array = e.get("behaviors", []).map(func(b): return str(b.get("type", "")))
	if "float" in types and not "wheels" in types:
		return _build_boat(s, e)
	if "thruster" in types:
		return Ship.build(s, e)
	var wheels: Array = e.get("parts", []).filter(func(p): return str(p.get("shape", "")) == "wheel")
	if wheels.size() < 2:
		return null
	var v := Vehicle.new()
	v.scene = s
	v.entry_id = str(e.id)
	v.display_name = str(e.get("name", "el vehículo"))
	v.owner_id = str(e.get("owner", ""))
	v.name = "Creation_" + str(e.id)
	v.collision_layer = Layers.WORLD
	v.collision_mask = Layers.WORLD | Layers.CHARACTERS
	for b in e.get("behaviors", []):
		var p: Dictionary = b.get("params", {}) if b.get("params", {}) is Dictionary else {}
		match str(b.get("type", "")):
			"engine":
				v.power = clampf(float(p.get("power", 5.0)), 1.0, 10.0)
			"pedals":
				v.pedals = true
	if v.pedals and not "engine" in types:
		v.power = 1.2
		v.uses_fuel = false
	v.max_speed = 7.0 if v.pedals and not "engine" in types else 9.0 + v.power * 2.6
	v.fuel = clampf(float(e.get("fuel", 1.0)), 0.0, 1.0)
	s.add_child(v)
	var start := Vector3(e.pos[0], e.pos[1], e.pos[2])
	if s.has_method("ground_at") and not InteriorManager.is_interior_pos(start):
		start.y = maxf(start.y, float(s.call("ground_at", start.x, start.z)))  # nunca enterrado
	v.global_position = start + Vector3(0, 0.15, 0)
	v._good = Transform3D(v.global_basis, v.global_position)
	v.rotation.y = float(e.get("yaw", 0.0))
	var scale := clampf(float(e.get("scale", 1.0)), 0.2, 5.0)
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * scale
	v.add_child(body)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var parts: Array = e.get("parts", [])
	for i in parts.size():
		var p: Dictionary = parts[i]
		var size := Creations._vec(p.get("size", [0.5, 0.5, 0.5]), Vector3.ONE * 0.5) * scale
		var at := Creations._vec(p.get("pos", [0, 0, 0]), Vector3.ZERO) * scale
		if str(p.get("shape", "")) == "wheel":
			var w := VehicleWheel3D.new()
			w.name = "Wheel_%d" % i
			w.wheel_radius = size.x / 2.0
			w.wheel_rest_length = 0.12
			w.suspension_travel = 0.18
			w.suspension_stiffness = 45.0 if wheels.size() > 2 else 60.0
			w.suspension_max_force = 9000.0
			w.damping_compression = 2.2
			w.damping_relaxation = 2.8
			w.wheel_friction_slip = 2.8
			w.wheel_roll_influence = 0.25
			w.use_as_traction = at.z <= 0.0 or wheels.size() <= 2 or v.pedals
			w.use_as_steering = at.z > 0.0
			w.position = at + Vector3(0, 0.1, 0)
			v.add_child(w)
			var mesh := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x / 2.0
			cyl.bottom_radius = size.x / 2.0
			cyl.height = size.y
			mesh.mesh = cyl
			mesh.rotation_degrees = Vector3(0, 0, 90)
			mesh.material_override = Creations.material("rubber", Color(str(p.get("color", "#1c1c1c"))) if Color.html_is_valid(str(p.get("color", ""))) else Color("#1c1c1c"))
			w.add_child(mesh)
			var hub := MeshInstance3D.new()
			var hc := CylinderMesh.new()
			hc.top_radius = size.x * 0.22
			hc.bottom_radius = size.x * 0.22
			hc.height = size.y * 1.05
			hub.mesh = hc
			hub.rotation_degrees = Vector3(0, 0, 90)
			hub.material_override = Creations.material("metal", Color("#b8bcc2"))
			w.add_child(hub)
			continue
		Creations._part(body, p, i, false)
		var pb := Creations.part_bounds(p, scale)
		lo = lo.min(pb.position)
		hi = hi.max(pb.end)
		if str(p.get("role", "")) == "seat" or (str(p.get("material", "")) == "fabric" and v._seat == Vector3(0, 1.0, 0)):
			# Sentado: el personaje (sus pies) va a la altura del cojín menos lo que ocupa sentado
			v._seat = at + Vector3(0, size.y / 2.0 - (0.68 if wheels.size() > 2 else 0.5), 0)
	if lo == Vector3.INF:
		lo = Vector3(-0.5, 0.3, -0.8)
		hi = Vector3(0.5, 0.6, 0.8)
	# El chasis choca; las ruedas, no (las lleva la suspensión)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bottom := maxf(lo.y, 0.25 * scale)
	box.size = Vector3(hi.x - lo.x, maxf(hi.y - bottom, 0.2), hi.z - lo.z)
	cs.shape = box
	cs.position = Vector3((hi.x + lo.x) / 2.0, bottom + box.size.y / 2.0, (hi.z + lo.z) / 2.0)
	v.add_child(cs)
	var volume := box.size.x * box.size.y * box.size.z
	v.mass = clampf(volume * (90.0 if v.pedals else 160.0), 15.0, 2600.0)
	v.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	v.center_of_mass = Vector3(cs.position.x, bottom + 0.1, cs.position.z)
	if wheels.size() <= 2:  # bici o moto: no se cae de lado (no simulamos el equilibrio)
		v.axis_lock_angular_x = false
		v.axis_lock_angular_z = true
	if v._seat == Vector3(0, 1.0, 0):
		v._seat = Vector3(0, hi.y * 0.75, (lo.z + hi.z) / 2.0 - (hi.z - lo.z) * 0.1)
	v._use = Interactable.create(v, Vector3(0, 1.0, 0), maxf((hi.z - lo.z) * 0.6, 1.8), v._prompt(), v._on_use, v)
	v.contact_monitor = true
	v.max_contacts_reported = 4
	v.body_entered.connect(v._on_hit)
	return v


static func _build_boat(s: Node, e: Dictionary) -> Node3D:
	var water: float = float(s.get("_water_level")) if s.get("_water_level") != null else -0.45
	if not is_finite(water):  # aquí no hay agua: queda varada en el suelo
		water = float(s.call("ground_at", float(e.pos[0]), float(e.pos[2]))) if s.has_method("ground_at") else 0.0
	var boat := Boat.new()
	boat.water_level = water
	boat.ground_at = s.ground_at if s.has_method("ground_at") else boat.ground_at
	s.add_child(boat)
	boat.name = "Creation_" + str(e.id)
	boat.position = Vector3(e.pos[0], boat.water_level, e.pos[2])
	boat.rotation.y = float(e.get("yaw", 0.0))
	var types: Array = e.get("behaviors", []).map(func(b): return str(b.get("type", "")))
	if "engine" in types:
		boat.max_speed = 13.0
		boat.motor = true
	if not str(e.get("model", "")).is_empty():
		var mp: PackedStringArray = str(e.model).split("/")
		boat.setup(mp[0], mp[1], float(e.get("height", 4.5)) * 2.0, "Subir a %s" % e.get("name", "la lancha"))
	else:
		var holder := Node3D.new()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in e.get("parts", []).size():
			var p: Dictionary = e.parts[i]
			Creations._part(holder, p, i, false)
			var pb := Creations.part_bounds(p)
			lo = lo.min(pb.position)
			hi = hi.max(pb.end)
		boat.setup_custom(holder, hi - lo, "Subir a %s" % e.get("name", "la lancha"))
	return boat


func _prompt() -> String:
	if owner_id.is_empty() or owner_id == "player":
		return ("Subir a %s" if pedals else "Conducir %s") % display_name
	return "Tomar %s (no es tuyo)" % the_name()


## «el sedán», «la moto», «la camioneta».
func the_name() -> String:
	var low := display_name.to_lower()
	var fem := low.ends_with("a") or low.begins_with("moto") or low.begins_with("lancha")
	return ("la " if fem else "el ") + low


func seat_position() -> Vector3:
	return global_transform * _seat


func is_occupied() -> bool:
	return _rider != null


func _on_use(player: Player) -> void:
	if _rider == null:
		if not owner_id.is_empty() and owner_id != "player" and scene and scene.has_method("on_vehicle_taken"):
			scene.call("on_vehicle_taken", self)
		_rider = player
		player.riding = self
		player.add_collision_exception_with(self)
		add_collision_exception_with(player)
		player.play_gesture("sit")
		_use.set_prompt("Bajar")
		Sfx.at(self, "door", global_position + Vector3(0, 1, 0))
	else:
		_leave()


func _leave() -> void:
	var player := _rider
	_rider = null
	engine_force = 0.0
	brake = 30.0
	player.riding = null
	player.stop_gesture()
	_use.set_prompt(_prompt())
	var side := global_basis.x.normalized()
	var out := global_position - side * 1.6
	if scene and scene.has_method("ground_at"):
		out.y = float(scene.call("ground_at", out.x, out.z)) + 0.3
	player.global_position = out
	_save()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_instance_valid(player):
		player.remove_collision_exception_with(self)
		remove_collision_exception_with(player)


func speed() -> float:
	return linear_velocity.dot(global_basis.z)


func _physics_process(delta: float) -> void:
	_hit_cool -= delta
	if not global_position.is_finite() or global_position.y < -200.0:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		global_transform = _good
		return
	if linear_velocity.length() < 0.5 and absf(global_basis.y.dot(Vector3.UP)) > 0.8:
		_good = global_transform
	if _rider == null:
		engine_force = 0.0
		brake = 12.0
		return
	var input := Controls.move_vector() if _rider.controls_enabled else Vector2.ZERO
	var throttle := -input.y
	var v := speed()
	var has_fuel := fuel > 0.0 or not uses_fuel
	# ~3 m/s² un coche normal (0 a 100 km/h en unos 9 s); una bici, mucho menos
	var force := power * (110.0 if pedals and not uses_fuel else 260.0) * mass / 1000.0 * 1.4
	if throttle > 0.0 and v < -0.5 or throttle < 0.0 and v > 0.5:
		brake = 40.0 * absf(throttle)  # frenar antes de cambiar de sentido
		engine_force = 0.0
	else:
		brake = 0.0 if throttle != 0.0 else 3.0
		engine_force = throttle * force * (1.0 if throttle > 0.0 else 0.5) if has_fuel and absf(v) < max_speed else 0.0
	var steer_max := lerpf(0.55, 0.12, clampf(absf(v) / max_speed, 0.0, 1.0))
	steering = move_toward(steering, -input.x * steer_max, 2.5 * delta)
	if uses_fuel and engine_force != 0.0:
		fuel = maxf(fuel - absf(engine_force) / force * delta * 0.0012, 0.0)
		if fuel <= 0.0 and scene and scene.get("_ui") and scene.get("_ui").has_method("toast"):
			scene.get("_ui").toast("Se acabó la gasolina.")
	_rider.play_gesture("row" if pedals and not uses_fuel and absf(throttle) > 0.0 else "sit")
	_save_t += delta
	if _save_t > 3.0:
		_save_t = 0.0
		_save()


func _save() -> void:
	if entry_id.is_empty():
		return
	var p := global_position
	Creations.update(entry_id, {"pos": [snappedf(p.x, 0.01), snappedf(p.y - 0.15, 0.01), snappedf(p.z, 0.01)],
		"yaw": snappedf(global_rotation.y, 0.001), "fuel": snappedf(fuel, 0.001)})


## Un golpe fuerte: suena y, si vas dentro, te duele.
func _on_hit(_body: Node) -> void:
	if _hit_cool > 0.0 or linear_velocity.length() < 6.0:
		return
	_hit_cool = 1.0
	Sfx.at(self, "hit", global_position + Vector3(0, 0.8, 0))
	if _rider and GameState.is_awakened():
		GameState.change_stat("health", -int(linear_velocity.length() * 0.8))


func refuel(amount: float = 1.0) -> void:
	fuel = clampf(fuel + amount, 0.0, 1.0)
	_save()


# --- De fábrica ------------------------------------------------------------------------------

## Piezas de los vehículos de fábrica (a escala real; z hacia delante).
static func factory(kind: String, color: String = "") -> Dictionary:
	var c: String = color if Color.html_is_valid(color) else FACTORY_COLORS[randi() % FACTORY_COLORS.size()]
	var glass := "#1d2a35"
	var w := func(x: float, z: float, d: float = 0.66, t: float = 0.24) -> Dictionary:
		return {"shape": "wheel", "size": [d, t, d], "pos": [x, d / 2.0, z], "material": "rubber", "color": "#1a1a1a"}
	match kind:
		"sedan":
			return {"name": "Sedán", "behaviors": [{"type": "wheels"}, {"type": "engine", "params": {"power": 6}}, {"type": "cockpit"}, {"type": "tank"}], "parts": [
				{"shape": "box", "size": [1.8, 0.62, 4.4], "pos": [0, 0.66, 0], "material": "paint", "color": c},
				{"shape": "box", "size": [1.56, 0.56, 2.1], "pos": [0, 1.25, -0.25], "material": "glass", "color": glass},
				{"shape": "box", "size": [1.6, 0.07, 2.0], "pos": [0, 1.56, -0.25], "material": "paint", "color": c},
				{"shape": "box", "size": [0.5, 0.2, 0.6], "pos": [-0.38, 0.9, -0.1], "material": "fabric", "color": "#3a3a3a", "role": "seat"},
				{"shape": "box", "size": [0.3, 0.12, 0.05], "pos": [-0.62, 0.78, 2.21], "material": "emissive", "color": "#fff6d8"},
				{"shape": "box", "size": [0.3, 0.12, 0.05], "pos": [0.62, 0.78, 2.21], "material": "emissive", "color": "#fff6d8"},
				{"shape": "box", "size": [0.3, 0.1, 0.05], "pos": [-0.62, 0.8, -2.21], "material": "emissive", "color": "#c0201a"},
				{"shape": "box", "size": [0.3, 0.1, 0.05], "pos": [0.62, 0.8, -2.21], "material": "emissive", "color": "#c0201a"},
				w.call(-0.82, 1.42), w.call(0.82, 1.42), w.call(-0.82, -1.42), w.call(0.82, -1.42)]}
		"pickup":
			return {"name": "Camioneta", "behaviors": [{"type": "wheels"}, {"type": "engine", "params": {"power": 7}}, {"type": "cockpit"}, {"type": "tank"}], "parts": [
				{"shape": "box", "size": [1.95, 0.7, 5.2], "pos": [0, 0.8, 0], "material": "paint", "color": c},
				{"shape": "box", "size": [1.8, 0.62, 1.7], "pos": [0, 1.46, 0.75], "material": "glass", "color": glass},
				{"shape": "box", "size": [1.85, 0.08, 1.6], "pos": [0, 1.8, 0.75], "material": "paint", "color": c},
				{"shape": "box", "size": [0.08, 0.45, 2.2], "pos": [-0.94, 1.38, -1.4], "material": "paint", "color": c},
				{"shape": "box", "size": [0.08, 0.45, 2.2], "pos": [0.94, 1.38, -1.4], "material": "paint", "color": c},
				{"shape": "box", "size": [1.95, 0.45, 0.08], "pos": [0, 1.38, -2.56], "material": "paint", "color": c},
				{"shape": "box", "size": [0.5, 0.3, 0.6], "pos": [-0.42, 1.28, 0.7], "material": "fabric", "color": "#3a3a3a", "role": "seat"},
				{"shape": "box", "size": [0.3, 0.14, 0.05], "pos": [-0.68, 0.95, 2.61], "material": "emissive", "color": "#fff6d8"},
				{"shape": "box", "size": [0.3, 0.14, 0.05], "pos": [0.68, 0.95, 2.61], "material": "emissive", "color": "#fff6d8"},
				w.call(-0.9, 1.7, 0.78, 0.3), w.call(0.9, 1.7, 0.78, 0.3), w.call(-0.9, -1.7, 0.78, 0.3), w.call(0.9, -1.7, 0.78, 0.3)]}
		"van":
			return {"name": "Furgoneta", "behaviors": [{"type": "wheels"}, {"type": "engine", "params": {"power": 6}}, {"type": "cockpit"}, {"type": "tank"}], "parts": [
				{"shape": "box", "size": [1.95, 1.75, 4.9], "pos": [0, 1.35, -0.1], "material": "paint", "color": c},
				{"shape": "box", "size": [1.8, 0.6, 0.06], "pos": [0, 1.75, 2.36], "material": "glass", "color": glass},
				{"shape": "box", "size": [0.5, 0.3, 0.6], "pos": [-0.45, 1.0, 1.6], "material": "fabric", "color": "#3a3a3a", "role": "seat"},
				{"shape": "box", "size": [0.3, 0.14, 0.05], "pos": [-0.7, 0.85, 2.36], "material": "emissive", "color": "#fff6d8"},
				{"shape": "box", "size": [0.3, 0.14, 0.05], "pos": [0.7, 0.85, 2.36], "material": "emissive", "color": "#fff6d8"},
				w.call(-0.88, 1.6, 0.7, 0.26), w.call(0.88, 1.6, 0.7, 0.26), w.call(-0.88, -1.7, 0.7, 0.26), w.call(0.88, -1.7, 0.7, 0.26)]}
		"bike":
			return {"name": "Bicicleta", "behaviors": [{"type": "wheels"}, {"type": "pedals"}], "parts": [
				{"shape": "box", "size": [0.05, 0.05, 0.95], "pos": [0, 0.62, 0], "material": "metal", "color": c},
				{"shape": "box", "size": [0.05, 0.6, 0.05], "pos": [0, 0.55, -0.2], "material": "metal", "color": c, "rot": [-15, 0, 0]},
				{"shape": "box", "size": [0.05, 0.55, 0.05], "pos": [0, 0.6, 0.45], "material": "metal", "color": c, "rot": [20, 0, 0]},
				{"shape": "box", "size": [0.16, 0.05, 0.26], "pos": [0, 0.9, -0.25], "material": "fabric", "color": "#1c1c1c", "role": "seat"},
				{"shape": "box", "size": [0.55, 0.04, 0.04], "pos": [0, 0.98, 0.52], "material": "metal", "color": "#2b2f3a"},
				w.call(0, 0.55, 0.66, 0.05), w.call(0, -0.55, 0.66, 0.05)]}
		"moto":
			return {"name": "Moto", "behaviors": [{"type": "wheels"}, {"type": "engine", "params": {"power": 6}}, {"type": "tank"}], "parts": [
				{"shape": "box", "size": [0.32, 0.36, 1.1], "pos": [0, 0.62, 0], "material": "paint", "color": c},
				{"shape": "box", "size": [0.3, 0.12, 0.6], "pos": [0, 0.86, -0.25], "material": "fabric", "color": "#1c1c1c", "role": "seat"},
				{"shape": "box", "size": [0.3, 0.26, 0.4], "pos": [0, 0.86, 0.25], "material": "paint", "color": c},
				{"shape": "box", "size": [0.7, 0.04, 0.04], "pos": [0, 1.05, 0.55], "material": "metal", "color": "#2b2f3a"},
				{"shape": "box", "size": [0.12, 0.1, 0.05], "pos": [0, 0.92, 0.72], "material": "emissive", "color": "#fff6d8"},
				w.call(0, 0.72, 0.62, 0.12), w.call(0, -0.68, 0.62, 0.14)]}
		"speedboat":
			return {"name": "Lancha", "behaviors": [{"type": "float"}, {"type": "engine", "params": {"power": 6}}], "parts": [
				{"shape": "box", "size": [1.9, 0.7, 3.6], "pos": [0, 0.35, -0.4], "material": "paint", "color": "#e8e2d4"},
				{"shape": "ramp", "size": [1.9, 0.7, 1.2], "pos": [0, 0.35, 1.95], "material": "paint", "color": "#e8e2d4", "rot": [0, 90, 0]},
				{"shape": "box", "size": [1.92, 0.12, 4.0], "pos": [0, 0.62, -0.1], "material": "paint", "color": c},
				{"shape": "box", "size": [1.4, 0.4, 0.06], "pos": [0, 0.95, 0.5], "material": "glass", "color": glass, "rot": [-25, 0, 0]},
				{"shape": "box", "size": [0.3, 0.6, 0.4], "pos": [0, 0.5, -2.3], "material": "metal", "color": "#2b2f3a"}]}
	return {}


## Pone un vehículo de fábrica en el mundo (como creación guardada). Devuelve su entrada.
static func place_factory(s: Node, kind: String, pos: Vector3, yaw: float, owner: String = "", color: String = "") -> Dictionary:
	var f := factory(kind, color)
	if f.is_empty():
		return {}
	var e := Creations.add({"name": f.name, "parts": f.parts, "behaviors": f.behaviors, "pos": [pos.x, pos.y, pos.z], "yaw": yaw,
		"owner": owner, "factory": kind, "by": "world"})
	if not e.is_empty():
		Creations.build(s, e)
	return e

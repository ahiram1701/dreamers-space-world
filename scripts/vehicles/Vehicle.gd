class_name Vehicle
extends VehicleBody3D
## Un vehículo de verdad: física de ruedas y suspensión de Godot (VehicleBody3D). Los de fábrica
## usan los modelos del Car Kit de Kenney (sedán, camioneta, taxi, ambulancia…) con sus ruedas
## girando y frenando; lo que inventa la IA (piezas "wheel" + wheels/engine o pedals) también se
## conduce. Marchas automáticas, freno de mano (Espacio), claxon (H), motor que suena según las
## revoluciones, choques que abollan y averían, atropellos con consecuencias y asientos para
## llevar gente. E para subir y bajar.

const FACTORY_COLORS := ["#b23a3a", "#2c5d8f", "#e8e2d4", "#2b2f3a", "#6f7a82", "#2e7d5b", "#c9a227"]
const KIT_DIR := "kenney_cars"
## Vehículos de fábrica con modelo: tipo -> modelo, nombre, potencia (1..10) y masa (kg). El kit
## es achaparrado: el chasis se estira (BODY_SCALE) y las ruedas se escalan igual en todo.
const KIT := {
	"sedan": {"model": "sedan", "name": "Sedán", "power": 6, "mass": 1300.0},
	"sports": {"model": "sedan-sports", "name": "Deportivo", "power": 9, "mass": 1200.0},
	"hatchback": {"model": "hatchback-sports", "name": "Compacto", "power": 6, "mass": 1100.0},
	"suv": {"model": "suv", "name": "Camioneta SUV", "power": 7, "mass": 1800.0},
	"suv_luxury": {"model": "suv-luxury", "name": "Camioneta de lujo", "power": 8, "mass": 1900.0},
	"pickup": {"model": "truck", "name": "Camioneta", "power": 7, "mass": 1900.0},
	"flatbed": {"model": "truck-flat", "name": "Camioneta de plataforma", "power": 7, "mass": 2000.0},
	"van": {"model": "van", "name": "Furgoneta", "power": 6, "mass": 1900.0},
	"taxi": {"model": "taxi", "name": "Taxi", "power": 6, "mass": 1350.0},
	"police": {"model": "police", "name": "Patrulla", "power": 8, "mass": 1500.0},
	"delivery": {"model": "delivery", "name": "Camión de reparto", "power": 6, "mass": 3200.0, "big": true},
	"ambulance": {"model": "ambulance", "name": "Ambulancia", "power": 7, "mass": 3000.0, "big": true},
	"firetruck": {"model": "firetruck", "name": "Camión de bomberos", "power": 7, "mass": 6000.0, "big": true},
	"garbage": {"model": "garbage-truck", "name": "Camión de la basura", "power": 6, "mass": 7000.0, "big": true},
	"tractor": {"model": "tractor", "name": "Tractor", "power": 4, "mass": 2500.0, "uniform": true},
	"race": {"model": "race", "name": "Coche de carreras", "power": 10, "mass": 900.0},
}
const BODY_SCALE := Vector3(1.3, 1.35, 1.65)
const BIG_SCALE := Vector3(1.45, 1.55, 2.0)
const GEARS := [0.24, 0.43, 0.62, 0.81, 1.0]          # velocidad máxima de cada marcha (fracción)
const GEAR_TORQUE := [1.35, 1.2, 1.05, 0.9, 0.75]
## Tracción por tipo (las demás, delantera): 4x4 las camionetas, trasera los deportivos y camiones.
const DRIVE := {"suv": "awd", "suv_luxury": "awd", "pickup": "awd", "flatbed": "awd", "sports": "rwd", "race": "rwd",
	"police": "rwd", "delivery": "rwd", "ambulance": "rwd", "firetruck": "rwd", "garbage": "rwd", "tractor": "rwd"}
## Agarre de los neumáticos (VehicleWheel3D.friction_slip): antes 2.9, patinaba como en hielo.
const GRIP := {"sports": 8.0, "race": 9.0, "police": 7.5, "delivery": 5.5, "ambulance": 5.8, "firetruck": 5.5, "garbage": 5.5, "tractor": 6.0}

var entry_id := ""
var display_name := "el vehículo"
var factory_kind := ""
var max_speed := 16.0       # m/s
var power := 5.0            # 1..10
var pedals := false
var fuel := 1.0             # 0..1
var uses_fuel := true
var health := 100.0         # 0 = averiado (no arranca)
var owner_id := ""          # quién es el dueño ("" = el jugador o nadie)
var scene: Node
var gear := 1
var rpm := 900.0
var length := 4.0

var _rider: Player
var _use: Interactable
var _seat := Vector3(0, 1.0, 0)
var _seats: Array = []          # asientos (el 0 es el del conductor)
var _passengers := {}           # índice de asiento -> TownNPC
var _save_t := 0.0
var _hit_cool := 0.0
var _good := Transform3D()   # última posición sana (si la física se desboca, vuelve aquí)
var _prev_vel := Vector3.ZERO
var _audio: EngineAudio
var _smoke: CPUParticles3D
var _rear: Array = []           # ruedas traseras (freno de mano)
var _ground_t := 0.0
var _flip_t := 0.0
var _lamps: Array = []          # materiales de los faros y pilotos (piezas que brillan)
var _beams: Array = []          # luces de los faros (de noche, conduciendo)
var _lights_t := 0.0
var _lights_on := true


## Construye un vehículo a partir de una creación (Creations). Lo usa Creations.build.
static func build(s: Node, e: Dictionary) -> Node3D:
	var types: Array = e.get("behaviors", []).map(func(b): return str(b.get("type", "")))
	if "float" in types and not "wheels" in types:
		return _build_boat(s, e)
	if "thruster" in types:
		return Ship.build(s, e)
	var kit: Dictionary = KIT.get(str(e.get("factory", "")), {})
	var model_path := str(e.get("model", ""))
	if model_path.is_empty() and not kit.is_empty():
		model_path = KIT_DIR + "/" + str(kit.model)
	var is_kit := model_path.begins_with(KIT_DIR + "/")
	var wheels: Array = e.get("parts", []).filter(func(p): return str(p.get("shape", "")) == "wheel")
	if wheels.size() < 2 and not is_kit:
		return null
	var v := Vehicle.new()
	v.scene = s
	v.entry_id = str(e.id)
	v.factory_kind = str(e.get("factory", ""))
	v.display_name = str(e.get("name", kit.get("name", "el vehículo")))
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
	if not kit.is_empty():
		v.power = float(kit.power)
	if v.pedals and not "engine" in types:
		v.power = 1.2
		v.uses_fuel = false
	v.max_speed = 7.0 if v.pedals and not "engine" in types else 9.0 + v.power * 2.6
	v.fuel = clampf(float(e.get("fuel", 1.0)), 0.0, 1.0)
	v.health = clampf(float(e.get("health", 100.0)), 0.0, 100.0)
	s.add_child(v)
	var start := Vector3(e.pos[0], e.pos[1], e.pos[2])
	if s.has_method("ground_at") and not InteriorManager.is_interior_pos(start):
		start.y = maxf(start.y, float(s.call("ground_at", start.x, start.z)))  # nunca enterrado
	v.global_position = start + Vector3(0, 0.15, 0)
	v.rotation.y = float(e.get("yaw", 0.0))
	v._good = Transform3D(v.global_basis, v.global_position)
	var ok := v._build_kit(model_path, kit, clampf(float(e.get("scale", 1.0)), 0.3, 3.0)) if is_kit else false
	if not ok:
		if wheels.size() < 2:
			v.queue_free()
			return null
		v._build_parts(e, wheels)
	v._finish(wheels.size() if not ok else 4)
	return v


## El chasis y las ruedas de un modelo del kit: las ruedas del modelo pasan a ser VehicleWheel3D
## (giran, se mueven con la suspensión y se orientan al girar el volante).
func _build_kit(model_path: String, kit: Dictionary, user_scale: float) -> bool:
	var mp := model_path.split("/")
	var model := AssetLibrary.instance(mp[0], mp[1]) if mp.size() == 2 else null
	if model == null:
		return false
	var big := bool(kit.get("big", false))
	var bs: Vector3 = (Vector3.ONE * 1.6 if kit.get("uniform", false) else (BIG_SCALE if big else BODY_SCALE)) * user_scale
	var ws: float = bs.y
	var body := Node3D.new()
	body.name = "Body"
	body.scale = bs
	add_child(body)
	body.add_child(model)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var n := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var t := _to_root(mi, model)
		var local_aabb: AABB = mi.get_aabb()
		var center: Vector3 = t * local_aabb.get_center()
		var nm := str(mi.name)
		if nm.begins_with("wheel-") and (nm.contains("left") or nm.contains("right")):
			var w := VehicleWheel3D.new()
			w.name = "Wheel_%d" % n
			n += 1
			var size: Vector3 = (t.basis * local_aabb.size).abs()
			w.wheel_radius = size.y / 2.0 * ws
			w.wheel_rest_length = 0.15
			w.suspension_travel = 0.2
			w.suspension_stiffness = 38.0 if not big else 55.0
			w.suspension_max_force = 60000.0
			w.damping_compression = 2.4
			w.damping_relaxation = 3.2
			var drive: String = DRIVE.get(factory_kind, "fwd")
			w.wheel_friction_slip = float(GRIP.get(factory_kind, 6.8))
			w.wheel_roll_influence = 0.05
			w.use_as_traction = drive == "awd" or (nm.contains("back") if drive == "rwd" else nm.contains("front"))
			w.use_as_steering = nm.contains("front")
			w.set_meta("rear", nm.contains("back"))
			w.set_meta("grip", w.wheel_friction_slip)
			w.position = Vector3(center.x * bs.x, center.y * ws + 0.12, center.z * bs.z)
			add_child(w)
			mi.get_parent().remove_child(mi)
			mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * ws) * t.basis, (t.origin - center) * ws)
			w.add_child(mi)
			if nm.contains("back"):
				_rear.append(w)
			continue
		var a: AABB = t * local_aabb
		lo = lo.min(a.position * bs)
		hi = hi.max(a.end * bs)
	if n < 2 or lo == Vector3.INF:
		body.queue_free()
		for w in find_children("Wheel_*", "VehicleWheel3D", false, false):
			w.queue_free()
		_rear.clear()
		return false
	length = hi.z - lo.z
	# Chasis: una caja baja (de los bajos al cinturón) y la cabina, más estrecha y corta
	var belt := lo.y + (hi.y - lo.y) * 0.5
	var bottom := maxf(lo.y, 0.32)
	_box(Vector3((hi.x - lo.x) * 0.96, belt - bottom, (hi.z - lo.z) * 0.97), Vector3((hi.x + lo.x) / 2.0, (belt + bottom) / 2.0, (hi.z + lo.z) / 2.0))
	_box(Vector3((hi.x - lo.x) * 0.84, hi.y - belt, (hi.z - lo.z) * (0.85 if big else 0.6)), Vector3((hi.x + lo.x) / 2.0, (hi.y + belt) / 2.0, (hi.z + lo.z) / 2.0 - (hi.z - lo.z) * 0.05))
	mass = float(kit.get("mass", 1400.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, bottom + 0.02, (hi.z + lo.z) / 2.0)
	angular_damp = 0.9   # sin trompos ni bamboleos de más
	# Asientos: conductor a la izquierda (+x mirando hacia delante), copiloto y dos detrás
	var sx := (hi.x - lo.x) * 0.2
	var sy := bottom - 0.12
	var front_z := (hi.z + lo.z) / 2.0 + (0.6 if big else 0.1)
	_seats = [Vector3(sx, sy, front_z), Vector3(-sx, sy, front_z)]
	if not big:
		_seats.append_array([Vector3(sx, sy, front_z - 0.95), Vector3(-sx, sy, front_z - 0.95)])
	_seat = _seats[0]
	return true


func _box(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size.max(Vector3.ONE * 0.1)
	cs.shape = box
	cs.position = at
	add_child(cs)


static func _to_root(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Lo que inventa la IA: piezas sueltas (la caja de colisión envuelve el chasis).
func _build_parts(e: Dictionary, wheels: Array) -> void:
	var scale := clampf(float(e.get("scale", 1.0)), 0.2, 5.0)
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * scale
	add_child(body)
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
			w.use_as_traction = at.z <= 0.0 or wheels.size() <= 2 or pedals
			w.use_as_steering = at.z > 0.0
			w.position = at + Vector3(0, 0.1, 0)
			add_child(w)
			if w.use_as_traction and at.z <= 0.0:
				_rear.append(w)
			var tyre := MeshInstance3D.new()   # neumático con su hueco y la llanta dentro
			var tm := TorusMesh.new()
			tm.inner_radius = size.x * 0.3
			tm.outer_radius = size.x / 2.0
			tyre.mesh = tm
			tyre.scale = Vector3(1.0, size.y / maxf(size.x * 0.2, 0.01), 1.0)
			tyre.rotation_degrees = Vector3(0, 0, 90)
			tyre.material_override = Creations.material("rubber", Color(str(p.get("color", "#1c1c1c"))) if Color.html_is_valid(str(p.get("color", ""))) else Color("#1c1c1c"))
			w.add_child(tyre)
			var hub := MeshInstance3D.new()
			var hc := CylinderMesh.new()
			hc.top_radius = size.x * 0.31
			hc.bottom_radius = size.x * 0.31
			hc.height = size.y * 0.7
			hub.mesh = hc
			hub.rotation_degrees = Vector3(0, 0, 90)
			hub.material_override = Creations.material("metal", Color("#b8bcc2"))
			w.add_child(hub)
			continue
		Creations._part(body, p, i, false)
		var pb := Creations.part_bounds(p, scale)
		lo = lo.min(pb.position)
		hi = hi.max(pb.end)
		if str(p.get("role", "")) == "seat" or (str(p.get("material", "")) == "fabric" and _seat == Vector3(0, 1.0, 0)):
			# Sentado: el personaje (sus pies) va a la altura del cojín menos lo que ocupa sentado
			_seat = at + Vector3(0, size.y / 2.0 - (0.68 if wheels.size() > 2 else 0.5), 0)
		elif str(p.get("role", "")) == "passenger":
			_seats.append(at + Vector3(0, size.y / 2.0 - 0.68, 0))
	if lo == Vector3.INF:
		lo = Vector3(-0.5, 0.3, -0.8)
		hi = Vector3(0.5, 0.6, 0.8)
	# El chasis choca; las ruedas, no (las lleva la suspensión)
	var bottom := maxf(lo.y, 0.25 * scale)
	var size := Vector3(hi.x - lo.x, maxf(hi.y - bottom, 0.2), hi.z - lo.z)
	_box(size, Vector3((hi.x + lo.x) / 2.0, bottom + size.y / 2.0, (hi.z + lo.z) / 2.0))
	length = size.z
	var volume := size.x * size.y * size.z
	mass = clampf(volume * (90.0 if pedals else 160.0), 15.0, 2600.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3((hi.x + lo.x) / 2.0, bottom + 0.1, (hi.z + lo.z) / 2.0)
	if _seat == Vector3(0, 1.0, 0):
		_seat = Vector3(0, hi.y * 0.75, (lo.z + hi.z) / 2.0 - (hi.z - lo.z) * 0.1)
	_seats.push_front(_seat)
	if wheels.size() <= 2 and _seats.size() == 1 and not pedals:  # en la moto cabe uno detrás
		_seats.append(_seat + Vector3(0, 0.08, -0.45))


func _finish(wheel_count: int) -> void:
	# Los faros: solo brillan con el motor en marcha y de noche (de día eran manchas blancas)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m: Variant = (mi as MeshInstance3D).material_override
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
			var own := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			(mi as MeshInstance3D).material_override = own
			_lamps.append(own)
	if uses_fuel:
		for side in [-1.0, 1.0]:
			var beam := SpotLight3D.new()
			beam.spot_range = 28.0
			beam.spot_angle = 32.0
			beam.light_energy = 2.2
			beam.light_color = Color("#fff3d6")
			beam.position = Vector3(side * 0.5 if wheel_count > 2 else 0.0, 0.8, length * 0.5)
			beam.rotation.y = PI  # (una luz apunta hacia su -z; el coche mira hacia +z)
			beam.rotation.x = -0.08
			beam.visible = false
			add_child(beam)
			_beams.append(beam)
			if wheel_count <= 2:
				break
	_set_lights(false)
	if wheel_count <= 2:  # bici o moto: no se cae de lado (no simulamos el equilibrio)
		axis_lock_angular_z = true
	_use = Interactable.create(self, Vector3(0, 1.0, 0), maxf(length * 0.6, 1.8), _prompt(), _on_use, self)
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_hit)
	if uses_fuel:
		_audio = EngineAudio.new()
		_audio.kind = "moto" if wheel_count <= 2 else "car"
		_audio.position = Vector3(0, 0.6, length * 0.35)
		add_child(_audio)
	_update_smoke()


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
	if health <= 0.0:
		return "%s está averiado (no arranca)" % the_name().capitalize()
	if owner_id.is_empty() or owner_id == "player":
		return ("Subir a %s" if pedals else "Conducir %s") % display_name
	return "Tomar %s (no es tuyo)" % the_name()


## «el sedán», «la moto», «la camioneta».
func the_name() -> String:
	var low := display_name.to_lower()
	var fem := low.ends_with("a") or low.begins_with("moto") or low.begins_with("lancha") or low.begins_with("camioneta") or low.begins_with("furgoneta")
	return ("la " if fem else "el ") + low


func seat_position(i: int = 0) -> Vector3:
	var at: Vector3 = _seats[i] if i < _seats.size() else _seat
	return global_transform * at


func is_occupied() -> bool:
	return _rider != null


## Distancia a la que va la cámara detrás (según lo largo que es).
func camera_distance() -> float:
	return clampf(length * 1.15 + 2.6, 4.0, 14.0)


func free_seats() -> int:
	return maxi(_seats.size() - 1 - _passengers.size(), 0)


## Un PNJ se sube (de pasajero). Devuelve false si no cabe.
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


## Bajan todos los pasajeros (al lado del vehículo).
func alight_all() -> Array:
	var out := []
	for i in _passengers.keys():
		var npc: TownNPC = _passengers[i]
		if is_instance_valid(npc):
			var side := global_basis.x.normalized() * (1.0 if _seats[i].x >= 0.0 else -1.0)
			var spot := global_transform * Vector3(_seats[i].x, 0, _seats[i].z) + side * 1.6
			if scene and scene.has_method("ground_at"):
				spot.y = float(scene.call("ground_at", spot.x, spot.z)) + 0.2
			npc.get_off(spot)
			remove_collision_exception_with(npc)
			out.append(npc)
	_passengers.clear()
	return out


func passengers() -> Array:
	return _passengers.values()


func _on_use(player: Player) -> void:
	if _rider == null:
		if health <= 0.0:
			if scene and scene.get("_ui"):
				scene.get("_ui").toast("No arranca: está demasiado dañado. Hay que llevarlo al taller.")
			return
		if not owner_id.is_empty() and owner_id != "player" and scene and scene.has_method("on_vehicle_taken"):
			scene.call("on_vehicle_taken", self)
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
	var out := global_transform * Vector3(_seat.x, 0, _seat.z) + side * (1.6 if _seat.x >= 0.0 else -1.6)
	if scene and scene.has_method("ground_at"):
		out.y = float(scene.call("ground_at", out.x, out.z)) + 0.3
	if not InteriorManager.is_free(self, out, [self, player], 0.3):
		out = InteriorManager.free_spot_near(self, out, side, [self, player]) + Vector3(0, 0.2, 0)
	player.global_position = out
	Sfx.at(self, "door", global_position + Vector3(0, 1, 0))
	var left := alight_all()
	if scene and scene.has_method("on_player_alighted"):
		scene.call("on_player_alighted", self, left)
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
	var upright := global_basis.y.dot(Vector3.UP)
	if linear_velocity.length() < 0.5 and upright > 0.8:
		_good = global_transform
	var v := speed()
	_update_audio(v, 0.0)
	_lights_t -= delta
	if _lights_t <= 0.0:
		_lights_t = 1.0
		var h := WorldClock.hour()
		_set_lights(_rider != null and health > 0.0 and (h >= 19.5 or h < 7.0 or Weather.current() in ["rain", "storm", "fog"]))
	# Si el suelo de delante aún no tiene colisión (terreno por trozos), espera quieto en vez de caer
	_ground_t -= delta
	if _ground_t <= 0.0:
		_ground_t = 0.2
		var hold := false
		for t in get_tree().get_nodes_in_group("chunk_terrain"):
			if not t.call("has_ground", global_position.x, global_position.z):
				hold = true
		if hold != freeze:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = hold
	if _rider == null:
		engine_force = 0.0
		brake = 12.0
		_prev_vel = linear_velocity
		return
	# Volcado: tras unos segundos, se endereza (empujando entre todos, como haría cualquiera)
	if upright < 0.3 and linear_velocity.length() < 1.5:
		_flip_t += delta
		if _flip_t > 3.0:
			_flip_t = 0.0
			global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), global_position + Vector3(0, 1.0, 0))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0
	var input := Controls.drive_vector() if _rider.controls_enabled else Vector2.ZERO
	var throttle := input.y
	var has_fuel := (fuel > 0.0 or not uses_fuel) and health > 0.0
	var handbrake := _rider.controls_enabled and Input.is_action_pressed("jump")
	# Marchas automáticas: cada una empuja menos pero llega más lejos
	var av := absf(v)
	gear = 1
	for g in GEARS.size():
		if av < max_speed * float(GEARS[g]) * 0.97:
			gear = g + 1
			break
		gear = GEARS.size()
	var lo_speed: float = 0.0 if gear == 1 else max_speed * float(GEARS[gear - 2])
	var hi_speed: float = max_speed * float(GEARS[gear - 1])
	var force := power * (110.0 if pedals and not uses_fuel else 260.0) * mass / 1000.0 * 1.4 * (float(GEAR_TORQUE[gear - 1]) * 0.78 if not pedals else 1.0)
	var foot_brake := 0.0
	var engine_brake := 0.0
	if throttle > 0.0 and v < -0.5 or throttle < 0.0 and v > 0.5:
		foot_brake = 40.0 * absf(throttle) * mass / 1300.0  # frenar antes de cambiar de sentido
		engine_force = 0.0
	else:
		engine_brake = 0.0 if throttle != 0.0 else 2.2 * mass / 1300.0  # el motor retiene (solo las motrices)
		# El par cae suave al acercarse a la velocidad máxima (antes, un corte en seco)
		var taper := clampf((max_speed - av) / maxf(max_speed * 0.18, 0.5), 0.0, 1.0)
		engine_force = throttle * force * (1.0 if throttle > 0.0 else 0.5) * (taper if throttle > 0.0 else 1.0) if has_fuel else 0.0
	# Control de tracción: si las ruedas motrices patinan, menos fuerza
	if engine_force != 0.0 and not pedals:
		var grip := 1.0
		for w in find_children("Wheel_*", "VehicleWheel3D", false, false):
			if (w as VehicleWheel3D).use_as_traction and (w as VehicleWheel3D).is_in_contact():
				grip = minf(grip, (w as VehicleWheel3D).get_skidinfo())
		if grip < 0.6:
			engine_force *= lerpf(0.35, 1.0, grip / 0.6)
	# Dirección: menos ángulo cuanto más rápido, y vuelve sola al centro al soltar
	var steer_max := lerpf(0.55, 0.18, clampf(av / max_speed, 0.0, 1.0))
	var want := -input.x * steer_max
	steering = move_toward(steering, want, (2.4 if absf(want) > absf(steering) else 4.5) * delta)
	# Frenos por rueda: pie, motor (las motrices) y freno de mano (las de atrás, que patinan)
	for w in find_children("Wheel_*", "VehicleWheel3D", false, false):
		var wh := w as VehicleWheel3D
		var b := foot_brake + (engine_brake if wh.use_as_traction else 0.0)
		var rear := bool(wh.get_meta("rear", false)) or _rear.has(wh)
		if handbrake and rear:
			b += 30.0 * mass / 1300.0
		wh.brake = b
		if wh.has_meta("grip"):
			wh.wheel_friction_slip = 2.2 if handbrake and rear else float(wh.get_meta("grip"))
	if handbrake:
		engine_force = 0.0
	if uses_fuel and engine_force != 0.0:
		fuel = maxf(fuel - absf(engine_force) / maxf(force, 1.0) * delta * 0.0012, 0.0)
		if fuel <= 0.0 and scene and scene.get("_ui") and scene.get("_ui").has_method("toast"):
			scene.get("_ui").toast("Se acabó la gasolina.")
	if pedals and not uses_fuel:
		rpm = 0.0
	elif av < 0.5:
		rpm = 850.0 + 2600.0 * maxf(throttle, 0.0)
	else:
		rpm = 1100.0 + 5200.0 * clampf((av - lo_speed * 0.6) / maxf(hi_speed - lo_speed * 0.6, 0.1), 0.0, 1.0)
	_update_audio(v, absf(throttle) if has_fuel else 0.0)
	if _rider.controls_enabled and Input.is_action_just_pressed("horn") and uses_fuel:
		Sfx.horn(self)
		if scene and scene.has_method("on_horn"):
			scene.call("on_horn", self)
	_rider.play_gesture("row" if pedals and not uses_fuel and absf(throttle) > 0.0 else "sit")
	_prev_vel = linear_velocity
	_save_t += delta
	if _save_t > 3.0:
		_save_t = 0.0
		_save()


func _update_audio(v: float, load: float) -> void:
	if _audio == null:
		return
	_audio.running = _rider != null and health > 0.0 and (fuel > 0.0 or not uses_fuel)
	_audio.rpm = rpm if _rider != null else 0.0
	_audio.load = load
	_audio.roll = clampf(absf(v) / 30.0, 0.0, 1.0)
	var side := absf(linear_velocity.dot(global_basis.x))
	_audio.skid = clampf((side - 3.0) / 6.0, 0.0, 1.0) if absf(v) > 3.0 or side > 3.0 else 0.0


func _save() -> void:
	if entry_id.is_empty():
		return
	var p := global_position
	Creations.update(entry_id, {"pos": [snappedf(p.x, 0.01), snappedf(p.y - 0.15, 0.01), snappedf(p.z, 0.01)],
		"yaw": snappedf(global_rotation.y, 0.001), "fuel": snappedf(fuel, 0.001), "health": snappedf(health, 0.1)})


## Un golpe. Contra algo duro: chapa, daño y (si vas dentro) te duele. Contra una persona: la
## atropellas (cae, se hace daño, lo recuerda y quien lo vea también); el coche no se para en seco.
func _on_hit(body: Node) -> void:
	var impact := _prev_vel.length()
	if body is TownNPC:
		if impact < 2.5 or (body as TownNPC).is_knocked():
			return
		add_collision_exception_with(body)
		linear_velocity = _prev_vel * clampf(1.0 - 80.0 / mass, 0.6, 0.97)  # un cuerpo frena poco a un coche
		Sfx.at(self, "thump", (body as Node3D).global_position + Vector3(0, 1.0, 0))
		var push: Vector3 = _prev_vel * 0.7 + Vector3(0, 2.5 + impact * 0.15, 0)
		(body as TownNPC).knock_down(push, impact)
		if scene and scene.has_method("on_npc_hit"):
			scene.call("on_npc_hit", self, body, impact)
		var npc_ref: Node = body
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(self) and is_instance_valid(npc_ref):
				remove_collision_exception_with(npc_ref))
		return
	if _hit_cool > 0.0 or impact < 5.0:
		return
	# Cuánto se paró de golpe (no solo lo rápido que iba): rozar una pared casi no hace nada
	var lost := (_prev_vel - linear_velocity).length()
	if lost < 3.0:
		if impact > 6.0:
			Sfx.at(self, "scrape", global_position + Vector3(0, 0.6, 0))
		return
	_hit_cool = 0.8
	Sfx.at(self, "crash" if lost > 7.0 else "hit", global_position + global_basis.z * length * 0.4 + Vector3(0, 0.7, 0))
	var dmg := (lost - 2.5) * 4.5
	health = maxf(health - dmg, 0.0)
	_update_smoke()
	if lost > 9.0:
		_debris(global_position + _prev_vel.normalized() * length * 0.45 + Vector3(0, 0.6, 0))
	if _rider and GameState.is_awakened():
		GameState.change_stat("health", -int(lost * 0.9))
		_rider.shake(0.35, 0.05 + lost * 0.006)
	for npc in _passengers.values():
		if is_instance_valid(npc) and lost > 9.0:
			NPCMemory.add_event(npc.npc_id, "Ibas en el coche con el jugador y chocó contra algo.", -6)
	if health <= 0.0 and scene and scene.get("_ui"):
		scene.get("_ui").toast("El motor se para. %s está averiado." % the_name().capitalize())
	_use.set_prompt("Bajar" if _rider else _prompt())
	_save()


func _set_lights(on: bool) -> void:
	if on == _lights_on:
		return
	_lights_on = on
	for m in _lamps:
		(m as StandardMaterial3D).emission_energy_multiplier = 1.4 if on else 0.0
	for b in _beams:
		(b as SpotLight3D).visible = on


## Humo del capó cuando está muy dañado.
func _update_smoke() -> void:
	if health >= 30.0:
		if _smoke:
			_smoke.emitting = false
		return
	if _smoke == null:
		_smoke = CPUParticles3D.new()
		_smoke.amount = 24
		_smoke.lifetime = 2.2
		_smoke.direction = Vector3.UP
		_smoke.spread = 18.0
		_smoke.initial_velocity_min = 0.6
		_smoke.initial_velocity_max = 1.4
		_smoke.gravity = Vector3(0, 0.4, 0)
		_smoke.scale_amount_min = 0.4
		_smoke.scale_amount_max = 1.1
		var q := SphereMesh.new()
		q.radius = 0.25
		q.height = 0.5
		q.radial_segments = 6
		q.rings = 3
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.25, 0.25, 0.35) if health > 0.0 else Color(0.1, 0.1, 0.1, 0.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = m
		_smoke.mesh = q
		_smoke.position = Vector3(0, 1.0, length * 0.38)
		add_child(_smoke)
	_smoke.emitting = true


## Trozos que salen despedidos en un choque fuerte (piezas del kit, si están).
func _debris(at: Vector3) -> void:
	if scene == null:
		return
	for k in ["debris-bumper", "debris-plate-a", "debris-door"]:
		if randf() < 0.4:
			continue
		var m := AssetLibrary.instance(KIT_DIR, k)
		if m == null:
			return
		var rb := RigidBody3D.new()
		rb.collision_layer = Layers.WORLD
		rb.collision_mask = Layers.WORLD
		rb.mass = 12.0
		m.scale = BODY_SCALE
		rb.add_child(m)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.8, 0.2, 0.5)
		cs.shape = bx
		rb.add_child(cs)
		scene.add_child(rb)
		rb.global_position = at + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
		rb.linear_velocity = _prev_vel * 0.4 + Vector3(randf_range(-2, 2), 3.0, randf_range(-2, 2))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		get_tree().create_timer(90.0).timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())


## Reparar en el taller (o con herramientas).
func repair(amount: float = 100.0) -> void:
	health = clampf(health + amount, 0.0, 100.0)
	_update_smoke()
	_use.set_prompt("Bajar" if _rider else _prompt())
	_save()


func refuel(amount: float = 1.0) -> void:
	fuel = clampf(fuel + amount, 0.0, 1.0)
	_save()


# --- De fábrica ------------------------------------------------------------------------------

## Vehículo de fábrica: los del kit (con modelo) o, para bici, moto y lancha, por piezas.
static func factory(kind: String, color: String = "") -> Dictionary:
	if KIT.has(kind):
		var k: Dictionary = KIT[kind]
		return {"name": k.name, "model": KIT_DIR + "/" + str(k.model), "parts": [],
			"behaviors": [{"type": "wheels"}, {"type": "engine", "params": {"power": k.power}}, {"type": "cockpit"}, {"type": "tank"}]}
	var c: String = color if Color.html_is_valid(color) else FACTORY_COLORS[randi() % FACTORY_COLORS.size()]
	var glass := "#1d2a35"
	var w := func(x: float, z: float, d: float = 0.66, t: float = 0.24) -> Dictionary:
		return {"shape": "wheel", "size": [d, t, d], "pos": [x, d / 2.0, z], "material": "rubber", "color": "#1a1a1a"}
	match kind:
		"bike":
			return {"name": "Bicicleta", "behaviors": [{"type": "wheels"}, {"type": "pedals"}], "parts": [
				{"shape": "cylinder", "size": [0.045, 0.62, 0.045], "pos": [0, 0.62, 0.06], "material": "metal", "color": c, "rot": [72, 0, 0]},
				{"shape": "cylinder", "size": [0.04, 0.55, 0.04], "pos": [0, 0.6, -0.2], "material": "metal", "color": c, "rot": [-15, 0, 0]},
				{"shape": "cylinder", "size": [0.04, 0.6, 0.04], "pos": [0, 0.62, 0.46], "material": "metal", "color": c, "rot": [20, 0, 0]},
				{"shape": "cylinder", "size": [0.035, 0.5, 0.035], "pos": [0, 0.35, -0.38], "material": "metal", "color": c, "rot": [80, 0, 0]},
				{"shape": "cylinder", "size": [0.12, 0.03, 0.12], "pos": [0, 0.33, -0.05], "material": "metal", "color": "#3a3f46", "rot": [0, 0, 90]},
				{"shape": "box", "size": [0.16, 0.06, 0.26], "pos": [0, 0.92, -0.25], "material": "fabric", "color": "#1c1c1c", "role": "seat"},
				{"shape": "cylinder", "size": [0.03, 0.56, 0.03], "pos": [0, 1.0, 0.54], "material": "metal", "color": "#2b2f3a", "rot": [0, 0, 90]},
				w.call(0, 0.55, 0.68, 0.05), w.call(0, -0.55, 0.68, 0.05)]}
		"moto":
			return {"name": "Moto", "behaviors": [{"type": "wheels"}, {"type": "engine", "params": {"power": 6}}, {"type": "tank"}], "parts": [
				{"shape": "capsule", "size": [0.36, 0.7, 0.36], "pos": [0, 0.82, 0.2], "material": "paint", "color": c, "rot": [90, 0, 0]},
				{"shape": "box", "size": [0.28, 0.32, 0.5], "pos": [0, 0.5, -0.05], "material": "metal", "color": "#3a3f46"},
				{"shape": "box", "size": [0.3, 0.1, 0.62], "pos": [0, 0.9, -0.28], "material": "fabric", "color": "#1c1c1c", "role": "seat"},
				{"shape": "cylinder", "size": [0.07, 0.6, 0.07], "pos": [0.16, 0.4, -0.45], "material": "metal", "color": "#b8bcc2", "rot": [80, 0, 0]},
				{"shape": "cylinder", "size": [0.05, 0.62, 0.05], "pos": [0, 0.7, 0.62], "material": "metal", "color": "#b8bcc2", "rot": [25, 0, 0]},
				{"shape": "cylinder", "size": [0.03, 0.72, 0.03], "pos": [0, 1.08, 0.5], "material": "metal", "color": "#2b2f3a", "rot": [0, 0, 90]},
				{"shape": "sphere", "size": [0.18, 0.16, 0.12], "pos": [0, 0.95, 0.7], "material": "emissive", "color": "#fff6d8"},
				{"shape": "box", "size": [0.16, 0.06, 0.04], "pos": [0, 0.82, -0.62], "material": "emissive", "color": "#c0201a"},
				w.call(0, 0.72, 0.64, 0.12), w.call(0, -0.68, 0.64, 0.15)]}
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
	var e := Creations.add({"name": f.name, "parts": f.parts, "behaviors": f.behaviors, "model": f.get("model", ""),
		"pos": [pos.x, pos.y, pos.z], "yaw": yaw, "owner": owner, "factory": kind, "by": "world"})
	if not e.is_empty():
		Creations.build(s, e)
	return e

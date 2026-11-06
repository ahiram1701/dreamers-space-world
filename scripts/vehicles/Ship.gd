class_name Ship
extends CharacterBody3D
## Una nave: cualquier creación con "thruster" (y "cockpit" para pilotarla). En un planeta despega
## y aterriza en vertical (W/S avanza, A/D gira, Espacio sube, Ctrl/Q baja); si sube lo bastante,
## sale al espacio (SpaceScene). En el espacio vuela libre, con inercia, y con Shift entra en
## crucero para cruzar el sistema. Gasta combustible.

const SPACE_ALTITUDE := 160.0   # por encima de esto (sobre el suelo) estás saliendo de la atmósfera

var entry: Dictionary = {}
var entry_id := ""
var display_name := "la nave"
var power := 5.0
var fuel := 1.0
var in_space := false
var scene: Node
var piloted := false            # en el espacio la pilota la escena (no hay Player)

var _rider: Player
var _use: Interactable
var _seat := Vector3(0, 1.2, 0)
var _body: Node3D
var _g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _save_t := 0.0
var _launching := false


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
	for b in e.get("behaviors", []):
		if str(b.get("type", "")) == "thruster":
			var p: Dictionary = b.get("params", {}) if b.get("params", {}) is Dictionary else {}
			ship.power = clampf(float(p.get("power", 5.0)), 1.0, 10.0)
	ship.fuel = clampf(float(e.get("fuel", 1.0)), 0.0, 1.0)
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
	if not str(e.get("model", "")).is_empty():
		var mp: PackedStringArray = str(e.model).split("/")
		var model := AssetLibrary.instance(mp[0], mp[1]) if mp.size() == 2 else null
		if model:
			var placed := AssetLibrary.place(ship._body, model, Vector3.ZERO, float(e.get("height", 3.0)), 0.0, false)
			var b := AssetLibrary.bounds(placed)
			lo = b.position
			hi = b.end
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
	if lo == Vector3.INF:
		lo = Vector3(-2, 0, -3)
		hi = Vector3(2, 2, 3)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (hi - lo).max(Vector3.ONE * 0.5)
	cs.shape = box
	cs.position = (hi + lo) / 2.0
	ship.add_child(cs)
	if ship._seat == Vector3(0, 1.2, 0):
		ship._seat = Vector3(0, hi.y * 0.6, (hi.z + lo.z) / 2.0 + (hi.z - lo.z) * 0.15)
	# Las toberas brillan al empujar
	for i in parts.size():
		if str(parts[i].get("role", "")) == "thruster":
			var glow := OmniLight3D.new()
			glow.name = "Thrust"
			glow.light_color = Color("#7fd0ff")
			glow.omni_range = 4.0
			glow.light_energy = 0.0
			glow.position = Creations._vec(parts[i].get("pos", [0, 0, 0]), Vector3.ZERO) * ship._body.scale
			ship.add_child(glow)
	if not space:
		ship._use = Interactable.create(ship, Vector3(0, 1.0, 0), maxf((hi.z - lo.z) * 0.6, 2.5), "Pilotar %s" % ship.display_name, ship._on_use, ship)
	return ship


func seat_position() -> Vector3:
	return global_transform * _seat


func is_occupied() -> bool:
	return _rider != null


func _on_use(player: Player) -> void:
	if _rider == null:
		_rider = player
		player.riding = self
		player.add_collision_exception_with(self)
		add_collision_exception_with(player)
		player.play_gesture("sit")
		_use.set_prompt("Bajar")
	else:
		if not is_on_floor() and _ground_gap() > 1.5:
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
	var out := global_position - global_basis.x.normalized() * 3.0
	if scene and scene.has_method("ground_at"):
		out.y = float(scene.call("ground_at", out.x, out.z)) + 0.3
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


## Mandos: Vector3(x = girar, y = subir/bajar, z = empujar) y si va en crucero.
func controls() -> Dictionary:
	var mv := Controls.move_vector()
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("descend") else 0.0)
	return {"turn": -mv.x, "up": up, "thrust": -mv.y, "boost": Input.is_action_pressed("run")}


func _physics_process(delta: float) -> void:
	var active := (_rider != null and _rider.controls_enabled) or piloted
	var c: Dictionary = controls() if active else {"turn": 0.0, "up": 0.0, "thrust": 0.0, "boost": false}
	var has_fuel := fuel > 0.0
	if in_space:
		_fly_space(c, delta, has_fuel)
	else:
		_fly_air(c, delta, has_fuel, active)
	var pushing := absf(c.thrust) + absf(c.up) > 0.0 and has_fuel
	for n in get_children():
		if n.name.begins_with("Thrust"):
			(n as OmniLight3D).light_energy = lerpf((n as OmniLight3D).light_energy, 2.5 if pushing else 0.0, 6.0 * delta)
	if pushing:
		fuel = maxf(fuel - delta * (0.0009 if not c.boost else 0.003), 0.0)
	_save_t += delta
	if _save_t > 4.0 and not in_space:
		_save_t = 0.0
		_save()


func _fly_air(c: Dictionary, delta: float, has_fuel: bool, active: bool) -> void:
	var acc := 4.0 + power * 1.6
	var top := 8.0 + power * 4.0
	rotation.y += float(c.turn) * 1.3 * delta
	var want := global_basis.z * float(c.thrust) * top
	if not has_fuel:
		want = Vector3.ZERO
	var horiz := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3(want.x, 0, want.z), acc * delta)
	var vy := velocity.y
	if active and has_fuel:
		vy = move_toward(vy, float(c.up) * (6.0 + power), acc * 1.2 * delta)  # flota sola: la nave compensa la gravedad
	elif not is_on_floor():
		vy = maxf(vy - _g * delta, -55.0)
	else:
		vy = 0.0
	velocity = Vector3(horiz.x, vy, horiz.z)
	move_and_slide()
	if _body:  # se inclina un poco al acelerar y girar
		_body.rotation.x = lerp_angle(_body.rotation.x, -float(c.thrust) * 0.12, 3.0 * delta)
		_body.rotation.z = lerp_angle(_body.rotation.z, float(c.turn) * 0.18, 3.0 * delta)
	if active and _ground_gap() > SPACE_ALTITUDE and not _launching and scene and scene.has_method("launch_ship"):
		_launching = true
		scene.call("launch_ship", self)


func _fly_space(c: Dictionary, delta: float, has_fuel: bool) -> void:
	var acc := 12.0 + power * 6.0
	var top := (40.0 + power * 12.0) * (60.0 if c.boost else 1.0)
	rotate_object_local(Vector3.UP, float(c.turn) * 1.0 * delta)
	rotate_object_local(Vector3.RIGHT, -float(c.up) * 0.9 * delta)
	if has_fuel and float(c.thrust) != 0.0:
		velocity = velocity.move_toward(global_basis.z * float(c.thrust) * top, acc * (40.0 if c.boost else 1.0) * delta)
	elif not c.boost:
		velocity = velocity.move_toward(Vector3.ZERO, acc * 0.25 * delta)  # amortiguadores de inercia
	global_position += velocity * delta


func speed() -> float:
	return velocity.length()


func _save() -> void:
	if entry_id.is_empty() or in_space:
		return
	var p := global_position
	Creations.update(entry_id, {"pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"yaw": snappedf(global_rotation.y, 0.001), "fuel": snappedf(fuel, 0.001)})


## Nave de fábrica: una lanzadera pequeña para dos.
static func factory() -> Dictionary:
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
		{"shape": "cylinder", "size": [0.25, 1.4, 0.25], "pos": [0, 0.7, -2.6], "material": "metal", "color": "#3a3f46"},
		{"shape": "box", "size": [0.3, 0.12, 0.05], "pos": [-0.5, 1.6, 3.4], "material": "emissive", "color": "#fff6d8"},
		{"shape": "box", "size": [0.3, 0.12, 0.05], "pos": [0.5, 1.6, 3.4], "material": "emissive", "color": "#fff6d8"}]}

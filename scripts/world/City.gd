class_name City
extends Node3D
## Puerto Alto: la ciudad a unos 400 m al sur de Bahía de las Horas. Una cuadrícula de 4×4
## manzanas con aceras, pasos de cebra, semáforos que cambian y coches que paran en rojo. Edificios
## altos con portal y servicios que se usan de verdad: hospital, comisaría, escuela, banco, cine,
## gimnasio, supermercado, restaurante, inmobiliaria y oficinas o pisos.

const BLOCK := 26.0        # lado de una manzana
const ROAD := 10.0         # ancho de calle
const N := 4               # manzanas por lado
const LIGHT_CYCLE := 12.0  # segundos de verde para cada dirección
const CAR_SPEED := 9.0

## Qué hay en cada manzana (los servicios, primero; el resto, pisos y oficinas).
const SERVICES := [
	["hospital", "el hospital de Puerto Alto"], ["police", "la comisaría"], ["school", "la escuela"],
	["bank", "el banco"], ["cinema", "el cine"], ["gym", "el gimnasio"], ["grocery", "el supermercado"],
	["restaurant", "el restaurante de la avenida"], ["realty", "la inmobiliaria"], ["pharmacy", "la farmacia de la ciudad"],
]

var scene: Node3D
var ground: Callable
var center := Vector3.ZERO
var _lights: Array = []    # [{pos, ns: [MeshInstance3D×3], ew: [...]}]
var _t := 0.0
var _cars: Array = []      # [{node, path: [Vector3], i, speed}]
var _mat_cache := {}


func build(s: Node3D, at: Vector3, ground_at: Callable) -> void:
	scene = s
	ground = ground_at
	center = at
	name = "PuertoAlto"
	var span := N * BLOCK + (N + 1) * ROAD
	var origin := at - Vector3(span / 2.0, 0, span / 2.0)
	# Asfalto de toda la ciudad (las calles) y aceras en cada manzana
	_slab(at + Vector3(0, 0.02, 0), Vector3(span, 0.04, span), Color("#3a3d42"))
	var k := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for bx in N:
		for bz in N:
			var c := origin + Vector3(ROAD + bx * (BLOCK + ROAD) + BLOCK / 2.0, 0, ROAD + bz * (BLOCK + ROAD) + BLOCK / 2.0)
			_slab(c + Vector3(0, 0.1, 0), Vector3(BLOCK, 0.16, BLOCK), Color("#9a968e"))  # acera
			# Dos edificios por manzana, mirando a la calle (norte y sur)
			for side in [-1, 1]:
				var yaw := 0.0 if side > 0 else PI
				var pos := c + Vector3(0, 0.18, side * BLOCK * 0.22)
				var kind := "house"
				var label := "un portal de pisos"
				if k < SERVICES.size():
					kind = SERVICES[k][0]
					label = SERVICES[k][1]
				elif rng.randf() < 0.4:
					kind = "office"
					label = "unas oficinas"
				var floors := rng.randi_range(4, 8)
				_building("ciudad_%d" % k, pos, yaw, Vector3(BLOCK * 0.8, floors * 3.2, BLOCK * 0.36), kind, label, rng)
				k += 1
	# Semáforos en los cruces interiores y pasos de cebra
	for ix in range(1, N):
		for iz in range(1, N):
			var cross := origin + Vector3(ix * (BLOCK + ROAD) + ROAD / 2.0, 0, iz * (BLOCK + ROAD) + ROAD / 2.0)
			_traffic_light(cross)
	for ix in N + 1:
		for iz in N:
			var zc := origin + Vector3(ix * (BLOCK + ROAD) + ROAD / 2.0, 0.05, ROAD + iz * (BLOCK + ROAD) + 1.2)
			_zebra(zc, 0.0)
	# Coches que dan vueltas por la avenida del perímetro y paran en rojo
	var ring := [origin + Vector3(ROAD * 0.3, 0.1, ROAD * 0.3), origin + Vector3(span - ROAD * 0.3, 0.1, ROAD * 0.3),
		origin + Vector3(span - ROAD * 0.3, 0.1, span - ROAD * 0.3), origin + Vector3(ROAD * 0.3, 0.1, span - ROAD * 0.3)]
	for i in 4:
		_car(ring, i, rng)
	Decor.landmark(self, at, "Puerto Alto: una ciudad de calles en cuadrícula, edificios altos, semáforos, tráfico, hospital, comisaría, escuela, banco, cine y gimnasio", "city")


func _slab(pos: Vector3, size: Vector3, c: Color) -> void:
	var b := PropsBuilder._box(self, pos, size, c, true)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Un edificio alto con su portal: puerta de verdad (se entra) y ventanas por plantas.
func _building(id: String, pos: Vector3, yaw: float, size: Vector3, kind: String, label: String, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	add_child(holder)
	var wall := Color.from_hsv(rng.randf_range(0.0, 0.15), rng.randf_range(0.05, 0.25), rng.randf_range(0.55, 0.85))
	PropsBuilder._box(holder, Vector3(0, size.y / 2.0, 0), size, wall, true)
	# Ventanas: franjas por planta (de noche, unas encendidas)
	var floors := int(size.y / 3.2)
	for f in range(1, floors):
		var win := PropsBuilder._box(holder, Vector3(0, f * 3.2 + 1.2, size.z / 2.0 + 0.02), Vector3(size.x - 1.6, 1.1, 0.04), Color("#2a3a4a"), false)
		if rng.randf() < 0.45:
			win.material_override.emission_enabled = true
			win.material_override.emission = Color("#ffd27a")
			win.material_override.emission_energy_multiplier = 0.25
	# Portal y letrero
	PropsBuilder._box(holder, Vector3(0, 1.3, size.z / 2.0 + 0.04), Vector3(1.8, 2.6, 0.08), Color("#2b2b2b"), false)
	var sign := Label3D.new()
	sign.text = label.get_slice(" ", 1).capitalize() if label.begins_with("el ") or label.begins_with("la ") else label.capitalize()
	sign.font_size = 64
	sign.outline_size = 10
	sign.pixel_size = 0.01
	sign.position = Vector3(0, 3.3, size.z / 2.0 + 0.1)
	holder.add_child(sign)
	var door_pos := holder.to_global(Vector3(0, 0, size.z / 2.0 + 0.7))
	door_pos.y = pos.y
	var interiors = scene.get("_interiors")
	if interiors:
		interiors.add_door(id, door_pos, yaw, kind, hash(id), label)
		interiors.set_building(id, holder.global_position, size, yaw)
		if kind == "house":
			interiors.set_door_option(id, "floors", 2)
	if scene.get("_places") != null:
		scene.get("_places")[label] = door_pos


func _zebra(at: Vector3, yaw: float) -> void:
	for i in 6:
		var stripe := PropsBuilder._box(self, at + Vector3(-ROAD / 2.0 + 1.0 + i * 1.6, 0.03, 0).rotated(Vector3.UP, yaw), Vector3(0.8, 0.02, 2.0), Color("#e8e8e8"), false)
		stripe.rotation.y = yaw


func _traffic_light(at: Vector3) -> void:
	var entry := {"pos": at, "ns": [], "ew": []}
	for corner in [Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		var p: Vector3 = at + corner * (ROAD / 2.0 - 0.4)
		p.y = center.y
		PropsBuilder._box(self, p + Vector3(0, 1.6, 0), Vector3(0.12, 3.2, 0.12), Color("#2b2b2b"), true)
		for dir in ["ns", "ew"]:
			var head := Node3D.new()
			head.position = p + Vector3(0, 3.0, 0) + (Vector3(0, 0, 0.18) if dir == "ns" else Vector3(0.18, 0, 0))
			add_child(head)
			var lamps := []
			for j in 3:
				var lamp := PropsBuilder._box(head, Vector3(0, 0.3 - j * 0.3, 0), Vector3(0.2, 0.2, 0.2), Color("#222"), false)
				lamps.append(lamp)
			entry[dir].append(lamps)
	_lights.append(entry)


## ¿Está en verde para esa dirección? (los coches y el jugador lo ven igual)
func green_for(ns: bool) -> bool:
	var phase := fmod(_t, LIGHT_CYCLE * 2.0)
	var amber: bool = fmod(phase, LIGHT_CYCLE) > LIGHT_CYCLE - 2.0
	var ns_turn := phase < LIGHT_CYCLE
	return (ns_turn == ns) and not amber


func _car(ring: Array, i: int, rng: RandomNumberGenerator) -> void:
	var model := AssetLibrary.instance("kenney_cars", ["sedan", "taxi", "van", "hatchback-sports"][i % 4])
	var node := Node3D.new()
	add_child(node)
	if model:
		AssetLibrary.place(node, model, Vector3.ZERO, 1.5, 0.0, true)
	else:
		PropsBuilder._box(node, Vector3(0, 0.7, 0), Vector3(1.8, 1.3, 4.2), Color.from_hsv(rng.randf(), 0.6, 0.8), false)
	var body := AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.2)
	cs.shape = bs
	cs.position.y = 0.7
	body.add_child(cs)
	node.add_child(body)
	node.global_position = (ring[i] as Vector3)
	_cars.append({"node": node, "path": ring, "i": (i + 1) % ring.size(), "speed": CAR_SPEED})


func _process(delta: float) -> void:
	_t += delta
	# Semáforos: verde, ámbar y rojo de verdad
	var on := {"r": Color("#ff3a2a"), "a": Color("#ffb020"), "g": Color("#40e070")}
	for e in _lights:
		for dir in ["ns", "ew"]:
			var green := green_for(dir == "ns")
			var phase := fmod(_t, LIGHT_CYCLE * 2.0)
			var amber: bool = fmod(phase, LIGHT_CYCLE) > LIGHT_CYCLE - 2.0 and ((phase < LIGHT_CYCLE) == (dir == "ns"))
			for lamps in e[dir]:
				_lamp(lamps[0], on.r if not green and not amber else Color("#331010"))
				_lamp(lamps[1], on.a if amber else Color("#332810"))
				_lamp(lamps[2], on.g if green else Color("#103318"))
	# Coches: siguen la avenida; paran antes de un cruce en rojo o si hay alguien delante
	for c in _cars:
		var node: Node3D = c.node
		var target: Vector3 = c.path[c.i]
		var to := target - node.global_position
		to.y = 0.0
		if to.length() < 1.0:
			c.i = (c.i + 1) % c.path.size()
			continue
		var dir := to.normalized()
		var ns := absf(dir.z) > absf(dir.x)
		var stop := false
		for e in _lights:
			var d: Vector3 = (e.pos as Vector3) - node.global_position
			d.y = 0.0
			if d.length() < ROAD * 1.2 and d.length() > ROAD * 0.5 and d.normalized().dot(dir) > 0.7 and not green_for(ns):
				stop = true
		for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("townsfolk"):
			var dp: Vector3 = (p as Node3D).global_position - node.global_position
			dp.y = 0.0
			if dp.length() < 7.0 and dp.normalized().dot(dir) > 0.8:
				stop = true
		c.speed = move_toward(c.speed, 0.0 if stop else CAR_SPEED, (10.0 if stop else 3.0) * delta)
		node.global_position += dir * float(c.speed) * delta
		node.global_position.y = center.y + 0.12  # la ciudad está allanada
		node.rotation.y = lerp_angle(node.rotation.y, atan2(dir.x, dir.z), minf(1.0, 4.0 * delta))


func _lamp(lamp: MeshInstance3D, c: Color) -> void:
	var m := lamp.material_override as StandardMaterial3D
	if m == null:
		return
	m.albedo_color = c
	var bright := c.v > 0.5
	m.emission_enabled = bright
	if bright:
		m.emission = c
		m.emission_energy_multiplier = 1.5

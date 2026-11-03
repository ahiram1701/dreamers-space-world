class_name InteriorManager
extends Node3D
## Puertas de los edificios de una escena: al cruzar una (E) se construye su interior en una zona
## apartada (InteriorBuilder) y el jugador aparece dentro; con E en la puerta de dentro vuelve a
## la calle. Camas (dormir hasta la mañana) y sillas (sentarse) se usan con E.

signal entered(kind: String, door_id: String)
signal exited(kind: String, door_id: String)
signal message(text: String)
## Algo de dentro que abre un panel en la escena (armario, tienda de ropa, peluquería).
signal wants(what: String)
## Justo antes de construir el interior (para decidir cuánta gente vive ahí, etc.).
signal entering(kind: String, door_id: String)

const ORIGIN := Vector3(0, -400, 0)
const BED_TOP := 0.1   # a qué altura queda alguien tumbado sobre la cama   # bajo el mundo: nada de fuera se ve desde dentro

var player: Player
var _doors := {}          # id -> { pos, yaw, kind, seed, label, node }
## Puertas cerradas por dentro: id -> texto que se ve al intentar entrar ("Teo no abre").
var locked := {}
var _current := ""
var _interior: Dictionary = {}
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)


## Registra la puerta de un edificio. `pos`: delante de la fachada; `yaw`: hacia dónde mira.
func add_door(id: String, pos: Vector3, yaw: float, kind: String, seed: int, label: String) -> void:
	var door := Interactable.create(get_parent(), pos + Vector3(0, 1.0, 0), 1.6, "Entrar: %s" % label, func(p): enter(id))
	door.name = "Puerta_%s" % id.validate_node_name()
	_doors[id] = {"pos": pos, "yaw": yaw, "kind": kind, "seed": seed, "label": label, "node": door}


## Datos extra de una puerta para construir su interior (p. ej. cuánta gente duerme en la casa).
func set_door_option(id: String, key: String, value: Variant) -> void:
	if _doors.has(id):
		var o: Dictionary = _doors[id].get("opts", {})
		o[key] = value
		_doors[id]["opts"] = o


func doors() -> Dictionary:
	return _doors


func door_label(id: String) -> String:
	return _doors[id].label if _doors.has(id) else ""


## Cierra (o abre, con texto vacío) una puerta por dentro.
func set_locked(id: String, text: String) -> void:
	if not _doors.has(id):
		return
	if text.is_empty():
		locked.erase(id)
		_doors[id].node.set_prompt("Entrar: %s" % _doors[id].label)
	else:
		locked[id] = text
		_doors[id].node.set_prompt("Llamar a la puerta: %s" % _doors[id].label)


## Puerta del edificio de un tipo (para llevar a un PNJ dentro de "la cafetería").
func door_of_kind(kind: String) -> String:
	for id in _doors:
		if _doors[id].kind == kind:
			return id
	return ""


func door_position(id: String) -> Vector3:
	return _doors[id].pos if _doors.has(id) else Vector3.INF


func is_inside() -> bool:
	return not _current.is_empty()


func current_door() -> String:
	return _current


## Dentro del interior actual: la salida y la entrada (posiciones globales), o INF si no hay.
func exit_position() -> Vector3:
	return _interior.exit if is_inside() else Vector3.INF


func entry_position() -> Vector3:
	return _interior.spawn if is_inside() else Vector3.INF


## Hueco libre para un cuerpo de persona cerca de `pos` (los pies): el mismo punto si está libre;
## si no, el más cercano en anillos alrededor, mejor hacia `prefer`. Así nadie aparece dentro de
## un arbusto, un mueble u otra persona al salir de un edificio.
static func free_spot_near(at: Node3D, pos: Vector3, prefer: Vector3 = Vector3.ZERO, exclude: Array = [], radius: float = 0.36) -> Vector3:
	if at == null or not at.is_inside_tree():
		return pos
	if is_free(at, pos, exclude, radius):
		return pos
	var base_angle := atan2(prefer.x, prefer.z) if prefer.length() > 0.01 else 0.0
	for ring in range(1, 10):
		var r := ring * 0.45
		var steps := 8 + ring * 2
		for k in steps:
			# Primero hacia donde se prefiere, luego a un lado y a otro
			var turn := ceili(k / 2.0) * (1.0 if k % 2 == 1 else -1.0) * TAU / steps
			var a := base_angle + turn
			var p := pos + Vector3(sin(a), 0, cos(a)) * r
			if is_free(at, p, exclude, radius):
				return p
	return pos


## ¿Cabe una persona de pie en `pos` (pies) sin tocar nada sólido?
static func is_free(at: Node3D, pos: Vector3, exclude: Array = [], radius: float = 0.36) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
	q.collision_mask = Layers.WORLD | Layers.CHARACTERS
	var rids: Array[RID] = []
	for e in exclude:
		if e is CollisionObject3D:
			rids.append((e as CollisionObject3D).get_rid())
	q.exclude = rids
	return at.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## ¿Esta posición está en un interior? (los interiores se construyen muy por debajo del mundo)
static func is_interior_pos(p: Vector3) -> bool:
	return p.y < ORIGIN.y + 100.0


func current_kind() -> String:
	return _doors[_current].kind if is_inside() else ""


func current_label() -> String:
	return _doors[_current].label if is_inside() else ""


## Sitio dentro del interior actual para un PNJ (el primero libre según el índice).
func npc_spot(i: int) -> Vector3:
	var spots: Array = _interior.get("npc_spots", [])
	return spots[i % spots.size()] if not spots.is_empty() else Vector3.INF


## Dónde hace algo una persona dentro del interior actual: "bed" (dormir), "sofa", "table"
## (sentarse), "kitchen" (cocinar). El i-ésimo sitio de ese tipo. Devuelve {pos, face, node} o {}.
func activity_spot(what: String, i: int) -> Dictionary:
	if not is_inside():
		return {}
	match what:
		"bed":  # una plaza por cama individual, dos en la de matrimonio; si no hay más, {}
			var slots := []
			for b in _interior.beds:
				var bed: Node3D = b.node
				var side := bed.global_basis.x.normalized()
				if str(b.name).contains("King"):
					slots.append([bed, -side * 0.42])
					slots.append([bed, side * 0.42])
				else:
					slots.append([bed, Vector3.ZERO])
			if i >= slots.size():
				return {}
			var bed: Node3D = slots[i][0]
			var along := bed.global_basis.z.normalized()
			# Los pies hacia el borde de la cama: al tumbarse, la cabeza queda en la almohada
			var at: Vector3 = bed.global_position + slots[i][1] + along * 0.85 + Vector3(0, BED_TOP, 0)
			return {"pos": at, "face": at + along * 3.0, "node": bed}
		"sofa", "table":
			var seats: Array = _interior.get(what, [])
			if seats.is_empty():
				seats = _interior.seats
			if seats.is_empty():
				return {}
			var seat: Node3D = seats[i % seats.size()].node
			return {"pos": seat.global_position + Vector3(0, 0.05, 0), "face": seat.global_position + seat.global_basis.z * 2.0, "node": seat}
		"kitchen":
			var k: Array = _interior.get("kitchen", [])
			if not k.is_empty():
				var s: Dictionary = k[i % k.size()]
				return {"pos": s.pos, "face": s.face}
	var p := npc_spot(i)
	return {} if p == Vector3.INF else {"pos": p, "face": p + Vector3(0, 0, 1)}


func enter(id: String) -> void:
	if _busy or not _doors.has(id):
		return
	if locked.has(id):  # cerrado por dentro: llamas y no abren
		Sfx.knock(self)
		message.emit(locked[id])
		return
	_busy = true
	Sfx.door(self)
	await _fade_to(1.0)
	_clear_interior()
	entering.emit(_doors[id].kind, id)
	var door: Dictionary = _doors[id]
	_interior = InteriorBuilder.build(self, door.kind, door.seed, ORIGIN, door.get("opts", {}))
	_current = id
	var exit_it := Interactable.create(_interior.root, _interior.exit - ORIGIN + Vector3(0, 1.0, 0), 1.9, "Salir", func(p): leave())
	exit_it.name = "Salida"
	for seat in _interior.seats:
		var node: Node3D = seat.node
		Interactable.create(node, Vector3(0, 0.5, 0), 1.0, "Sentarse", func(p): sit(node), node)
	for bed in _interior.beds:
		var node: Node3D = bed.node
		Interactable.create(node, Vector3(0, 0.5, 0), 1.5, "Dormir", func(p): sleep(node), node)
	for u in _interior.get("uses", []):
		var node: Node3D = u.node
		var what: String = u.get("what", "")
		Interactable.create(node, Vector3(0, 1.0, 0), 1.4, u.get("prompt", "Usar"), func(p): use_fixture(what, node), node)
	player.velocity = Vector3.ZERO
	player.global_position = _interior.spawn
	player.look_direction(Vector3(0, 0, -1))  # mirando hacia dentro de la habitación
	player.clear_look()
	entered.emit(door.kind, id)
	await _fade_to(0.0)
	_busy = false


func leave() -> void:
	if _busy or not is_inside():
		return
	_busy = true
	Sfx.door(self)
	await _fade_to(1.0)
	var id := _current
	var door: Dictionary = _doors[id]
	_current = ""
	_clear_interior()
	player.velocity = Vector3.ZERO
	player.stop_gesture()
	var outward := Vector3(sin(door.yaw), 0, cos(door.yaw))
	player.global_position = free_spot_near(self, door.pos + outward * 1.2, outward, [player]) + Vector3(0, 0.3, 0)
	player.look_direction(outward)
	exited.emit(door.kind, id)
	await _fade_to(0.0)
	_busy = false


## Sentarse en un mueble (moverse lo interrumpe). El mueble deja de chocar con el jugador
## mientras está sentado (Player quita la excepción al levantarse).
func sit(seat: Node3D) -> void:
	_ignore_collision(seat)
	player.velocity = Vector3.ZERO
	player.global_position = seat.global_position + Vector3(0, 0.05, 0)
	player.face_towards(seat.global_position + seat.global_basis.z * 2.0)
	player.clear_look()
	player.hold_position = true
	player.play_gesture("sit")


## Comer de la nevera, beber del grifo, ducharse: el cuerpo lo nota y pasan unos minutos.
func use_fixture(what: String, node: Node3D) -> void:
	if _busy:
		return
	_busy = true
	player.face_towards(node.global_position)
	match what:
		"eat":
			player.play_gesture("eat", 3.0)
			await get_tree().create_timer(3.0).timeout
			Body.change("hunger", 45.0)
			WorldClock.advance(15)
			message.emit("Te preparas algo rápido con lo que hay en la nevera.")
		"drink":
			player.play_gesture("drink", 2.5)
			await get_tree().create_timer(2.5).timeout
			Body.change("thirst", 60.0)
			WorldClock.advance(2)
			message.emit("Bebes agua fresca del grifo.")
		"wardrobe", "clothes_shop", "haircut", "shop_buy", "order":
			_busy = false
			wants.emit(what)
			return
		"shower":
			await _fade_to(1.0)
			Body.shower()
			WorldClock.advance(15)
			await get_tree().create_timer(0.6).timeout
			await _fade_to(0.0)
			message.emit("Una ducha caliente. Te sientes otra persona.")
	_busy = false


## Dormir en una cama hasta la mañana (o una siesta de 3 h si ya es casi de día).
func sleep(bed: Node3D) -> void:
	await rest(maxf(fposmod(8.0 - WorldClock.hour(), 24.0) * 60.0, 180.0), bed, true)


## Dormir o esperar `minutes`: en una cama se descansa del todo (8 h = descanso lleno); en el
## suelo o en un banco, la mitad y te levantas entumecido; esperando no se descansa.
func rest(minutes: float, bed: Node3D = null, sleeping: bool = true) -> void:
	if _busy or minutes <= 0.0:
		return
	_busy = true
	if bed:
		_ignore_collision(bed)
		player.global_position = bed.global_position + Vector3(0, 0.45, 0)
	if sleeping:
		player.hold_position = true
		player.play_gesture("sleep")
	await get_tree().create_timer(1.2 if sleeping else 0.4).timeout
	await _fade_to(1.0)
	WorldClock.advance(minutes)
	var hours := minutes / 60.0
	if sleeping:
		Body.slept(minutes)
		Body.change("rest", hours * (12.5 if bed else 6.0))
		if bed and GameState.is_awakened():
			GameState.change_stat("health", 35)
			GameState.change_stat("instability", -10)
	await get_tree().create_timer(0.8).timeout
	if sleeping:
		player.stop_gesture()
		player.hold_position = false
	for e in player.get_collision_exceptions():
		player.remove_collision_exception_with(e)
	if bed:
		player.global_position = free_spot_near(self, bed.global_position + bed.global_basis.x * 1.4, Vector3.ZERO, [player]) + Vector3(0, 0.3, 0)
	await _fade_to(0.0)
	var h_text := ("%d horas" % roundi(hours)) if hours >= 1.5 else ("%d minutos" % roundi(minutes)) if hours < 1.0 else "una hora"
	if not sleeping:
		message.emit("Esperas %s. Son las %s." % [h_text, WorldClock.text()])
	elif bed:
		message.emit("Duermes %s. Son las %s." % [h_text, WorldClock.text()])
	else:
		message.emit("Duermes %s sin cama. Son las %s; te levantas entumecido/a." % [h_text, WorldClock.text()])
	_busy = false


func _ignore_collision(furniture: Node3D) -> void:
	for body in furniture.find_children("*", "PhysicsBody3D", true, false):
		player.add_collision_exception_with(body)


func _clear_interior() -> void:
	if _interior.has("root") and is_instance_valid(_interior.root):
		_interior.root.queue_free()
	_interior = {}


func _fade_to(a: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", a, 0.35)
	await tw.finished

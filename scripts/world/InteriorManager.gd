class_name InteriorManager
extends Node3D
## Puertas de los edificios de una escena: al cruzar una (E) se construye su interior en una zona
## apartada (InteriorBuilder) y el jugador aparece dentro; con E en la puerta de dentro vuelve a
## la calle. Camas (dormir hasta la mañana) y sillas (sentarse) se usan con E.

signal entered(kind: String, door_id: String)
signal exited(kind: String, door_id: String)
signal message(text: String)

const ORIGIN := Vector3(0, -400, 0)   # bajo el mundo: nada de fuera se ve desde dentro

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


func current_kind() -> String:
	return _doors[_current].kind if is_inside() else ""


func current_label() -> String:
	return _doors[_current].label if is_inside() else ""


## Sitio dentro del interior actual para un PNJ (el primero libre según el índice).
func npc_spot(i: int) -> Vector3:
	var spots: Array = _interior.get("npc_spots", [])
	return spots[i % spots.size()] if not spots.is_empty() else Vector3.INF


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
	var door: Dictionary = _doors[id]
	_interior = InteriorBuilder.build(self, door.kind, door.seed, ORIGIN)
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
	player.global_position = door.pos + outward * 1.2 + Vector3(0, 0.3, 0)
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
		"shower":
			await _fade_to(1.0)
			Body.set_need("hygiene", 100.0)
			WorldClock.advance(15)
			await get_tree().create_timer(0.6).timeout
			await _fade_to(0.0)
			message.emit("Una ducha caliente. Te sientes otra persona.")
	_busy = false


## Dormir hasta la mañana: pasa el tiempo y se recupera salud.
func sleep(bed: Node3D) -> void:
	if _busy:
		return
	_busy = true
	_ignore_collision(bed)
	player.global_position = bed.global_position + Vector3(0, 0.45, 0)
	player.hold_position = true
	player.play_gesture("sleep")
	await get_tree().create_timer(1.2).timeout
	await _fade_to(1.0)
	var h := WorldClock.hour()
	var minutes := fposmod(8.0 - h, 24.0) * 60.0
	if minutes < 180.0:  # una siesta si ya es casi de día
		minutes = 180.0
	WorldClock.advance(minutes)
	Body.set_need("rest", 100.0)
	if GameState.is_awakened():
		GameState.change_stat("health", 35)
		GameState.change_stat("instability", -10)
	await get_tree().create_timer(0.8).timeout
	player.stop_gesture()
	player.hold_position = false
	for e in player.get_collision_exceptions():
		player.remove_collision_exception_with(e)
	player.global_position = bed.global_position + bed.global_basis.x * 1.4 + Vector3(0, 0.3, 0)
	await _fade_to(0.0)
	message.emit("Duermes %d horas. Son las %s." % [roundi(minutes / 60.0), WorldClock.text()])
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

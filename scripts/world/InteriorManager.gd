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
var _doors := {}          # id -> { pos, yaw, kind, seed, label }
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
	_doors[id] = {"pos": pos, "yaw": yaw, "kind": kind, "seed": seed, "label": label}
	var door := Interactable.create(get_parent(), pos + Vector3(0, 0.4, 0), 1.4, "Entrar: %s" % label, func(p): enter(id))
	door.name = "Puerta_%s" % id.validate_node_name()


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
	_busy = true
	await _fade_to(1.0)
	_clear_interior()
	var door: Dictionary = _doors[id]
	_interior = InteriorBuilder.build(self, door.kind, door.seed, ORIGIN)
	_current = id
	var exit_it := Interactable.create(_interior.root, _interior.exit - ORIGIN + Vector3(0, 0.4, 0), 1.2, "Salir", func(p): leave())
	exit_it.name = "Salida"
	for seat in _interior.seats:
		var node: Node3D = seat.node
		Interactable.create(node, Vector3(0, 0.3, 0), 0.9, "Sentarse", func(p): sit(node))
	for bed in _interior.beds:
		var node: Node3D = bed.node
		Interactable.create(node, Vector3(0, 0.3, 0), 1.4, "Dormir", func(p): sleep(node))
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


## Sentarse en un mueble (moverse lo interrumpe).
func sit(seat: Node3D) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = seat.global_position + Vector3(0, 0.05, 0)
	player.face_towards(seat.global_position + seat.global_basis.z * 2.0)
	player.clear_look()
	player.hold_position = true
	player.play_gesture("sit")


## Dormir hasta la mañana: pasa el tiempo y se recupera salud.
func sleep(bed: Node3D) -> void:
	if _busy:
		return
	_busy = true
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
	if GameState.is_awakened():
		GameState.change_stat("health", 35)
		GameState.change_stat("instability", -10)
	await get_tree().create_timer(0.8).timeout
	player.stop_gesture()
	player.hold_position = false
	player.global_position = bed.global_position + bed.global_basis.x * 1.2 + Vector3(0, 0.2, 0)
	await _fade_to(0.0)
	message.emit("Duermes %d horas. Son las %s." % [roundi(minutes / 60.0), WorldClock.text()])
	_busy = false


func _clear_interior() -> void:
	if _interior.has("root") and is_instance_valid(_interior.root):
		_interior.root.queue_free()
	_interior = {}


func _fade_to(a: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", a, 0.35)
	await tw.finished

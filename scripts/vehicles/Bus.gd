class_name Bus
extends Node3D
## El autobús de línea entre Bahía de las Horas y Puerto Alto. Para en cada parada un rato, se
## sube con E pagando $2 y te lleva sentado (se ve el viaje); al llegar a la otra parada te bajas
## solo. No circula de 23:00 a 6:00.

const SPEED := 12.0
const WAIT := 25.0          # segundos parado en cada parada
const FARE := 2

var stops: Array = []       # [{name, pos}]
var route: Array = []       # puntos del camino, de la primera parada a la última
var ground: Callable
var _i := 0                 # punto al que va
var _dir := 1
var _wait := 5.0
var _passenger: Node3D = null
var _body: AnimatableBody3D
var _board: Interactable
var _ui: Node


func setup(route_points: Array, stop_names: Array, ground_at: Callable) -> void:
	route = route_points
	ground = ground_at
	stops = [{"name": stop_names[0], "pos": route[0]}, {"name": stop_names[1], "pos": route[-1]}]
	name = "Autobus"
	var mat := Color("#d9a520")
	PropsBuilder._box(self, Vector3(0, 1.6, 0), Vector3(2.5, 2.6, 9.0), mat, false)
	PropsBuilder._box(self, Vector3(0, 2.1, 0), Vector3(2.55, 0.9, 8.4), Color("#2a3a4a"), false)  # ventanas
	for z in [-3.2, 3.2]:
		for x in [-1.25, 1.25]:
			var w := PropsBuilder._cylinder(self, Vector3(x, 0.45, z), 0.45, 0.45, 0.3, Color("#1a1a1a"), false)
			w.rotation.z = PI / 2
	var sign := Label3D.new()
	sign.text = "Bahía ⇄ Puerto Alto"
	sign.font_size = 48
	sign.pixel_size = 0.008
	sign.position = Vector3(0, 3.1, 4.55)
	add_child(sign)
	_body = AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.5, 2.8, 9.0)
	cs.shape = bs
	cs.position.y = 1.5
	_body.add_child(cs)
	add_child(_body)
	_board = Interactable.create(self, Vector3(1.6, 1.2, 3.0), 2.0, "Subir al autobús ($%d)" % FARE, func(p): _get_on(p), self)
	global_position = route[0]
	Decor.landmark(self, Vector3.ZERO, "el autobús de línea Bahía ⇄ Puerto Alto", "bus")


func at_stop() -> bool:
	return _wait > 0.0 and (_i == 0 or _i == route.size() - 1) and global_position.distance_to(route[_i]) < 2.0


func _get_on(player: Node) -> void:
	_ui = get_tree().get_first_node_in_group("gameplay_ui")
	if _passenger:
		return
	if not at_stop():
		if _ui: _ui.toast("El autobús solo abre las puertas en las paradas.")
		return
	if not Wallet.pay(FARE):
		if _ui: _ui.toast("El billete cuesta $%d." % FARE, "warn")
		return
	_passenger = player
	if _ui: _ui.block(true, "bus")
	player.hold_position = true
	if player is CollisionObject3D:
		(player as CollisionObject3D).add_collision_exception_with(_body)
	player.play_gesture("sit", 1.0e6)
	var dest: String = stops[1 if _dir > 0 else 0].name
	if _ui: _ui.toast("Pagas $%d. Te sientas. Próxima parada: %s." % [FARE, dest])
	Journal.log_event("Tomaste el autobús hacia %s." % dest, "info")


func _get_off() -> void:
	var p := _passenger
	_passenger = null
	if p == null or not is_instance_valid(p):
		return
	p.global_position = global_position + global_basis.x * 2.6 + Vector3(0, 0.4, 0)
	p.hold_position = false
	p.stop_gesture()
	if p is CollisionObject3D:
		(p as CollisionObject3D).remove_collision_exception_with(_body)
	if _ui: _ui.block(false, "bus")
	if _ui: _ui.toast("Parada: %s. Te bajas." % stops[0 if _i == 0 else 1].name)


func _physics_process(delta: float) -> void:
	var h := WorldClock.hour()
	if h >= 23.0 or h < 6.0:  # de noche, en cochera (en la parada del pueblo)
		if _passenger:
			_get_off()
		return
	if _wait > 0.0:
		_wait -= delta
		_board.visible = _passenger == null
		return
	_board.visible = false
	var target: Vector3 = route[_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() < 1.0:
		var last := _i == route.size() - 1 if _dir > 0 else _i == 0
		if last:
			_wait = WAIT
			if _passenger:
				_get_off()
			_dir = -_dir
		_i = clampi(_i + _dir, 0, route.size() - 1)
		return
	var dir := to.normalized()
	# Para si hay alguien delante
	var blocked := false
	for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("townsfolk"):
		if p == _passenger:
			continue
		var dp: Vector3 = (p as Node3D).global_position - global_position
		dp.y = 0.0
		if dp.length() < 8.0 and dp.normalized().dot(dir) > 0.8:
			blocked = true
	if not blocked:
		global_position += dir * minf(SPEED * delta, to.length())
	if ground.is_valid():
		global_position.y = float(ground.call(global_position.x, global_position.z)) + 0.05
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, 3.0 * delta))
	if _passenger and is_instance_valid(_passenger):
		_passenger.global_position = to_global(Vector3(0.6, 0.6, 1.0))
		_passenger.look_direction(global_basis.z)

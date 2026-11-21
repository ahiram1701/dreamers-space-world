extends SceneTree
## v0.15.0: el cuerpo en el mundo.
##  - Escalones: el jugador sube bordillos y tarimas de hasta ~38 cm andando (de frente y en
##    diagonal), sin saltar; lo más alto, no.
##  - Las manos: una silla se coge, se lleva, se deja y se queda donde la dejaste; una nevera no se
##    coge, se empuja; un sofá se empuja andando; lo que se lanza vuela y se para.
##  - Los vecinos arrancan con inercia, suben un escalón y no se teletransportan a la vista.
##   godot --headless --path . -s tests/test_body015.gd

var _failed := 0
var _town: Node3D
var _player
var _spot := Vector3.ZERO
var _extra: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var body = root.get_node("/root/Body")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba del cuerpo")
	load("res://scripts/world/Weather.gd").forced = "clear"
	clock.set_hour(12.0)
	_town = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(_town)
	current_scene = _town
	for i in 12:
		await process_frame
	_player = _town.get("_player")
	for n in ["hunger", "thirst", "rest"]:
		body.set_need(n, 90.0)
	body.stamina = 100.0
	_spot = Vector3(-75, _town.ground_at(-75, -55) + 0.05, -55)  # campo abierto

	await _steps()
	await _hands()
	await _neighbours()

	for n in _extra:
		if is_instance_valid(n):
			n.queue_free()
	_town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:
		await process_frame
	quit(_failed)


# --- Escalones --------------------------------------------------------------------------------

## Un bloque de `h` m de alto delante del jugador (a `ahead` m), girado `angle` respecto a donde mira.
func _block(h: float, angle: float, ahead: float = 1.6) -> StaticBody3D:
	var fwd: Vector3 = _forward()
	var at: Vector3 = _spot + fwd * (ahead + 2.0)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(5.0, 4.0, 12.0)  # (largo: que no se acabe antes de que pare de andar)
	b.add_child(cs)
	root.add_child(b)
	at = _spot + fwd * (ahead + 6.0)
	b.global_position = Vector3(at.x, _spot.y - 0.05 + h - 2.0, at.z)
	b.global_rotation.y = atan2(fwd.x, fwd.z) + angle
	_extra.append(b)
	return b


func _forward() -> Vector3:
	var yaw: Node3D = _player.get("_yaw")
	var f := -yaw.global_basis.z
	f.y = 0.0
	return f.normalized()


func _reset_player() -> void:
	_player.global_position = _spot
	_player.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame


func _steps() -> void:
	for case in [[0.15, 0.0], [0.25, 0.0], [0.35, 0.0], [0.30, deg_to_rad(35.0)], [0.45, 0.0]]:
		await _reset_player()
		var block := _block(case[0], case[1])
		await physics_frame
		var top: float = _spot.y - 0.05 + case[0]
		Input.action_press("move_forward")
		var peak_vy := 0.0
		for i in 150:
			await physics_frame
			peak_vy = maxf(peak_vy, _player.velocity.y)
		Input.action_release("move_forward")
		var up: bool = _player.global_position.y > top - 0.06
		if case[0] <= 0.38:
			_expect(up and peak_vy < 3.0, "se sube andando un escalón de %d cm%s (sin saltar)" % [roundi(case[0] * 100), " en diagonal" if case[1] != 0.0 else ""])
		else:
			_expect(not up, "uno de %d cm ya no: hay que saltar" % roundi(case[0] * 100))
		block.queue_free()
		await physics_frame


# --- Las manos --------------------------------------------------------------------------------

func _furniture(model: String, at: Vector3, height: float) -> Node3D:
	var m: Node3D = load("res://procgen/AssetLibrary.gd").instance("house_interior_pack", model)
	var placed: Node3D = load("res://procgen/AssetLibrary.gd").place(_town, m, at, height, 0.0, true)
	load("res://scripts/world/Hands.gd").make_movable(placed)
	_extra.append(placed)
	return placed


func _hands() -> void:
	await _reset_player()
	var hands = _player.get("hands")
	var fwd := _forward()
	var chair := _furniture("Chair_1", _spot + fwd * 1.3, 0.9)
	await physics_frame
	await physics_frame
	_expect(hands.target() == chair, "tienes la silla delante: se puede coger")
	hands.grab(chair)
	_expect(hands.carried == chair, "con G la coges")
	var body: StaticBody3D = chair.get_children().filter(func(c): return c is StaticBody3D)[0]
	_expect(body.collision_layer == 0, "mientras la llevas no choca contigo")
	# Andar con ella 2 s
	Input.action_press("move_forward")
	await create_timer(2.0).timeout
	Input.action_release("move_forward")
	await create_timer(0.5).timeout
	_expect(chair.global_position.distance_to(_spot) > 2.5, "va contigo (a %.1f m de donde estaba)" % chair.global_position.distance_to(_spot + fwd * 1.3))
	hands.drop()
	for i in 240:
		await physics_frame
		if hands.get("_thrown").is_empty():
			break
	_expect(hands.get("_thrown").is_empty() and chair.get_parent() == _town, "al dejarla cae y se queda quieta")
	_expect(body.collision_layer != 0, "y vuelve a ser sólida")
	var saved: Dictionary = root.get_node("/root/WorldDB").get_state("moved", {})
	var key := str(chair.get_meta("move_key", ""))
	_expect(saved.has(key) and Vector3(saved[key][0], saved[key][1], saved[key][2]).distance_to(chair.global_position) < 0.05,
		"se recuerda dónde la dejaste")
	# Si se vuelve a construir el lugar, aparece donde la dejaste
	var again := _furniture("Chair_1", _spot + fwd * 1.3, 0.9)
	await process_frame
	await process_frame
	_expect(again.global_position.distance_to(chair.global_position) < 0.05, "al volver, sigue donde la dejaste")

	# Lo pesado no se coge
	await _reset_player()
	var fridge := _furniture("Kitchen_Fridge", _spot + _forward() * 1.4 + _forward().cross(Vector3.UP) * 2.5, 1.9)
	hands.grab(fridge)
	_expect(hands.carried == null, "una nevera no se lleva en brazos")

	# Lanzar: lo ligero vuela
	var stool := _furniture("Chair_2", _spot + _forward() * 1.3 - _forward().cross(Vector3.UP) * 0.2, 0.9)
	await physics_frame
	var from: Vector3 = _player.global_position
	hands.grab(stool)
	await physics_frame
	hands.throw()
	for i in 360:
		await physics_frame
		if hands.get("_thrown").is_empty():
			break
	var flown := Vector2(stool.global_position.x - from.x, stool.global_position.z - from.z).length()
	_expect(flown > 2.5 and hands.get("_thrown").is_empty(), "una silla lanzada vuela y se para (a %.1f m)" % flown)

	# Empujar: andando contra un sofá, se mueve
	await _reset_player()
	var sofa := _furniture("Couch_Medium1", _spot + _forward() * 1.6, 0.85)
	sofa.global_rotation.y = atan2(_forward().x, _forward().z)
	await physics_frame
	var s0 := sofa.global_position
	Input.action_press("move_forward")
	await create_timer(3.0).timeout
	Input.action_release("move_forward")
	var pushed := sofa.global_position.distance_to(s0)
	_expect(pushed > 0.4, "un sofá se empuja andando (%.1f m)" % pushed)
	_expect(pushed < 5.0, "pero despacio, no sale volando")
	for n in _extra:  # (los muebles de esta prueba no estorban en la siguiente)
		if is_instance_valid(n):
			n.queue_free()
	_extra.clear()
	await physics_frame


# --- Los vecinos ------------------------------------------------------------------------------

func _neighbours() -> void:
	# Una vecina de prueba (sin rutina: los del pueblo se van a sus cosas)
	var db = root.get_node("/root/WorldDB")
	var def: Dictionary = root.get_node("/root/ContentGenerator").load_fallback("npc")
	def["appearance"] = {"body": "average"}
	var npc_id: String = db.add_entity("npc", def, "test", "test_vecina_paso")
	var npc = load("res://scripts/npc/TownNPC.gd").new()  # (por ruta: el nombre de clase aún no existe al compilar la prueba)
	_town.add_child(npc)
	npc.setup(db.get_entity("npc", npc_id))
	_extra.append(npc)
	npc.set("talking", false)
	await _reset_player()
	var start: Vector3 = _spot + _forward().cross(Vector3.UP) * 3.0
	npc.global_position = start
	npc.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	var goal: Vector3 = start + _forward() * 8.0
	npc.walk_to(goal)
	await physics_frame
	await physics_frame
	var v_early: float = Vector2(npc.velocity.x, npc.velocity.z).length()
	for i in 60:
		await physics_frame
	var v_late: float = Vector2(npc.velocity.x, npc.velocity.z).length()
	_expect(v_early < v_late * 0.7 and v_late > npc.get("walk_speed") * 0.6, "arranca poco a poco (%.2f → %.2f m/s), no en seco" % [v_early, v_late])
	_expect(npc.get("walk_speed") >= 1.1 and npc.get("walk_speed") <= 1.7, "anda a paso de persona (%.2f m/s)" % npc.get("walk_speed"))

	# Un escalón de 30 cm en su camino: lo sube andando
	npc.global_position = start
	npc.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	var step := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(6.0, 2.0, 8.0)
	step.add_child(cs)
	root.add_child(step)
	var mid: Vector3 = start + _forward() * 6.0
	step.global_position = Vector3(mid.x, start.y - 0.05 + 0.30 - 1.0, mid.z)
	step.global_rotation.y = atan2(_forward().x, _forward().z)
	_extra.append(step)
	await physics_frame
	npc.walk_to(start + _forward() * 7.0)
	var top_y := start.y - 0.05 + 0.30
	var climbed := false
	var max_vy := 0.0
	for i in 400:
		await physics_frame
		max_vy = maxf(max_vy, npc.velocity.y)
		if npc.global_position.y > top_y - 0.06:
			climbed = true
			break
	_expect(climbed and max_vy < 2.0, "sube un escalón de 30 cm andando, sin saltito")

	# Si se queda atrás a la vista, no aparece de golpe a tu lado
	var cam: Camera3D = _player.get("_cam")
	var far_spot: Vector3 = _player.global_position + (-cam.global_basis.z * Vector3(1, 0, 1)).normalized() * 34.0
	far_spot.y = _town.ground_at(far_spot.x, far_spot.z) + 0.1
	npc.global_position = far_spot
	npc.velocity = Vector3.ZERO
	npc.follow(_player)
	var jump := 0.0
	var last: Vector3 = npc.global_position
	for i in 30:
		await physics_frame
		jump = maxf(jump, npc.global_position.distance_to(last))
		last = npc.global_position
	_expect(jump < 1.0, "si lo ves, viene andando (no aparece de golpe: el mayor salto fue de %.1f m)" % jump)
	npc.follow(null)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

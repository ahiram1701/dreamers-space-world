extends SceneTree
## v0.14.0: moverse a pie más ágil. Se anda a paso vivo (2.6 m/s), Alt alterna un paseo
## despacio, se salta ~1 m (menos si sueltas la tecla antes), mantener la tecla no rebota, vale
## saltar un instante después de dejar el borde y las piernas dan el paso entero desde que andas.
##   godot --headless --path . -s tests/test_movement014.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba movimiento 0.14")
	var W = load("res://scripts/world/Weather.gd")
	var Rig = load("res://scripts/npc/HumanoidRig.gd")
	var P = load("res://scripts/player/Player.gd")
	var body = root.get_node("/root/Body")

	# --- Zancada de persona: ni a saltitos ni a cámara lenta ----------------------------------
	var cad_stroll: float = 1.4 / Rig.stride_for(1.4)
	var cad_walk: float = P.WALK_SPEED / Rig.stride_for(P.WALK_SPEED)
	var cad_run: float = P.RUN_SPEED / Rig.stride_for(P.RUN_SPEED)
	_expect(cad_stroll > 1.7 and cad_stroll < 2.3, "paseando se dan unos 2 pasos por segundo (%.1f)" % cad_stroll)
	_expect(cad_walk > cad_stroll and cad_walk < 3.2, "a paso vivo, algo más (%.1f)" % cad_walk)
	_expect(cad_run > cad_walk and cad_run < 4.6, "y corriendo, más aún sin que los pies vayan a toda prisa (%.1f)" % cad_run)

	W.forced = "clear"
	clock.set_hour(12.0)
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 12:
		await process_frame
	var player = town.get("_player")
	for n in ["hunger", "thirst", "rest"]:
		body.set_need(n, 90.0)
	body.stamina = 100.0
	body.winded = false
	var spot := Vector3(-75, town.ground_at(-75, -55) + 0.2, -55)  # campo abierto (sin agua ni muros)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame

	# --- Andar: paso vivo, y con Alt, paseo ---------------------------------------------------
	Input.action_press("move_forward")
	await create_timer(1.2).timeout
	var v_walk: float = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(v_walk > 2.3 and v_walk < 2.8, "se anda a paso vivo (%.2f m/s)" % v_walk)
	await _tap("walk_toggle")
	await create_timer(1.2).timeout
	var v_stroll: float = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(player.stroll and v_stroll > 1.2 and v_stroll < 1.6, "con Alt se pasea despacio (%.2f m/s)" % v_stroll)
	await _tap("walk_toggle")
	await create_timer(1.0).timeout
	var v_back: float = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(not player.stroll and v_back > 2.3, "y otra vez Alt, al paso de antes (%.2f m/s)" % v_back)
	Input.action_release("move_forward")
	await create_timer(1.0).timeout

	# --- Saltar: ~1 m, una vez por pulsación, más bajo si sueltas pronto ----------------------
	player.global_position = spot
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var y0: float = player.global_position.y
	var peak := y0
	var takeoffs := 0
	var was_floor: bool = player.is_on_floor()
	Input.action_press("jump")
	for i in 150:  # 2.5 s con la tecla pulsada
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		if was_floor and not player.is_on_floor() and player.velocity.y > 1.0:
			takeoffs += 1
		was_floor = player.is_on_floor()
	Input.action_release("jump")
	_expect(peak - y0 > 0.85 and peak - y0 < 1.15, "un salto sube alrededor de un metro (%.2f m)" % (peak - y0))
	_expect(takeoffs == 1, "con la tecla pulsada se salta una vez, no se rebota (%d despegues)" % takeoffs)

	for i in 30:
		await physics_frame
	y0 = player.global_position.y
	peak = y0
	Input.action_press("jump")
	for i in 4:
		await physics_frame
	Input.action_release("jump")
	for i in 90:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
	_expect(peak - y0 < 0.6 and peak - y0 > 0.1, "soltar la tecla enseguida da un salto corto (%.2f m)" % (peak - y0))

	# --- Margen al dejar el borde (y no después) -----------------------------------------------
	for i in 30:
		await physics_frame
	player.global_position += Vector3(0, 0.6, 0)  # como si acabara de salir de un escalón
	player.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	Input.action_press("jump")  # (pulsada: soltarla enseguida cortaría el salto)
	await physics_frame
	await physics_frame
	var vy_edge: float = player.velocity.y
	Input.action_release("jump")
	_expect(vy_edge > 3.5, "justo al dejar el borde aún se puede saltar (%.1f m/s hacia arriba)" % vy_edge)
	for i in 120:
		await physics_frame
	player.global_position += Vector3(0, 1.5, 0)
	player.velocity = Vector3.ZERO
	for i in 20:  # ~0.33 s en el aire: ya no vale
		await physics_frame
	await _tap("jump")
	await physics_frame
	await physics_frame
	_expect(player.velocity.y < 0.0, "pero no en mitad de una caída (%.1f m/s)" % player.velocity.y)
	for i in 90:
		await physics_frame
	_expect(player.is_on_floor(), "(y vuelve al suelo)")

	town.queue_free()
	await process_frame
	W.forced = ""
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:
		await process_frame
	quit(_failed)


## Pulsa y suelta una acción como lo haría el jugador (llega como evento de entrada).
func _tap(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	await physics_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

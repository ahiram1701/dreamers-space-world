extends SceneTree
## v0.7.1: más realismo. Atropellar a alguien tiene consecuencias y chocar daña el coche; la gente
## se sube contigo al coche; el motor suena según las revoluciones; la nave no tiene una pared
## invisible; en una casa ajena se come (y si te ven, es robo); dormir en la cama de otro tiene
## consecuencias; forzar el faro sin Marina dentro no hace que «te pille»; en la cafetería te
## atienden en la mesa; el faro tiene escalera hasta la linterna; y la IA no puede ponerle a nadie
## una escoba que no lleva.
##   godot --headless --path . -s tests/test_realism.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var memory = root.get_node("/root/NPCMemory")
	var director = root.get_node("/root/StoryDirector")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba realismo")
	clock.set_hour(12.0)
	var Weather = load("res://scripts/world/Weather.gd")
	Weather.forced = "clear"
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 12:
		await process_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")
	var Creations = load("res://scripts/agent/Creations.gd")
	var V = load("res://scripts/vehicles/Vehicle.gd")

	# --- La IA no inventa lo que la gente lleva ni dónde está ----------------------------------
	var people := [{"name": "samir", "held": "", "place": "fuera, junto a: estación"}]
	var c: Dictionary = director.check_world_claims("Samir barre la entrada con su escoba. Te saluda con la cabeza.", people, ["faro", "estación"])
	_expect(c.dropped.size() == 1 and str(c.text).contains("Te saluda"), "«Samir barre con su escoba» se quita si no lleva escoba: «%s»" % c.text)
	people[0]["held"] = "una escoba"
	c = director.check_world_claims("Samir barre la entrada con su escoba.", people, ["faro", "estación"])
	_expect(c.dropped.is_empty(), "y se queda si de verdad la lleva")
	c = director.check_world_claims("Samir, que está en el faro, te llama.", [{"name": "samir", "held": "", "place": "fuera, junto a: estación"}], ["faro", "estación"])
	_expect(c.dropped.size() == 1, "«Samir está en el faro» se quita si está en la estación")
	var npcs: Dictionary = town.get("_npcs")
	var samir = npcs["npc_samir"]
	samir.set_activity("barriendo el andén", "wipe")
	_expect(samir.held == "una escoba", "si su rutina es barrer, lleva una escoba de verdad (%s)" % samir.held)
	samir.set_activity("mirando el horizonte", "")
	_expect(samir.held.is_empty(), "y la suelta al hacer otra cosa")
	player.global_position = samir.global_position + Vector3(2, 0.3, 0)
	await physics_frame
	var ctx: String = town.action_context()
	_expect(ctx.contains("no lleva nada en las manos") and ctx.contains("VEHÍCULOS CERCA"), "el contexto de F dice qué lleva cada uno y qué vehículos hay")

	# --- Choques y atropellos ------------------------------------------------------------------
	var e: Dictionary = V.place_factory(town, "sedan", Vector3(-30, 0.2, -70), 0.0, "player")
	var car = Creations.node_of(town, e.id)
	_expect(car.find_children("*", "MeshInstance3D", true, false).size() > 3 and car.find_children("Wheel_*", "VehicleWheel3D", false, false).size() == 4,
		"el sedán es el modelo de Kenney, con sus 4 ruedas")
	await create_timer(1.0).timeout
	player.global_position = car.global_position + Vector3(-2.5, 0.3, 0)
	await physics_frame
	car._on_use(player)
	var marina = npcs["npc_marina"]
	var rel0: int = int(memory.get_mem("npc_marina").relationship)
	marina.stop()
	marina.global_position = car.global_position + car.global_basis.z * 9.0 + Vector3(0, 0.1, 0)
	await physics_frame
	var rpm0: float = car.rpm
	Input.action_press("move_forward")
	await create_timer(1.2).timeout
	_expect(car.rpm > rpm0 + 500.0 and car.get("_audio") != null and car._audio.running, "el motor suena y sube de vueltas al acelerar (%d → %d rpm)" % [rpm0, car.rpm])
	var t := 0.0
	while t < 4.0 and not marina.is_knocked():
		await physics_frame
		t += 1.0 / 60.0
	Input.action_release("move_forward")
	_expect(marina.is_knocked(), "atropellas a Marina: cae al suelo")
	var mem: Dictionary = memory.get_mem("npc_marina")
	_expect(mem.recent.any(func(x): return str(x.text).contains("atropelló")) and int(mem.relationship) < rel0, "y lo recuerda (relación %d → %d)" % [rel0, int(mem.relationship)])
	await create_timer(9.0).timeout
	_expect(not marina.is_knocked(), "al rato se levanta")
	car._on_use(player)
	await create_timer(0.5).timeout
	# Contra un muro: el coche se daña
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	ws.shape = BoxShape3D.new()
	ws.shape.size = Vector3(8, 3, 1)
	wall.add_child(ws)
	town.add_child(wall)
	wall.global_position = car.global_position + car.global_basis.z * 14.0 + Vector3(0, 1.5, 0)
	wall.global_rotation.y = car.global_rotation.y
	player.global_position = car.global_position + Vector3(-2.5, 0.3, 0)
	car._on_use(player)
	car.linear_velocity = car.global_basis.z * 16.0
	Input.action_press("move_forward")
	await create_timer(2.0).timeout
	Input.action_release("move_forward")
	_expect(car.health < 100.0, "chocar contra un muro abolla el coche (salud %d)" % car.health)
	car._on_use(player)
	wall.queue_free()

	# --- Pasajeros -----------------------------------------------------------------------------
	var teo = npcs["npc_teo"]
	memory.set_fields("npc_teo", {"following": true})
	teo.stop()
	teo.global_position = car.global_position + Vector3(-3, 0.2, 2)
	teo.follow(player)
	await create_timer(0.5).timeout
	player.global_position = car.global_position + Vector3(-2.5, 0.3, 0)
	car._on_use(player)
	t = 0.0
	while t < 8.0 and not teo.is_riding():
		await create_timer(0.25).timeout
		t += 0.25
	_expect(teo.is_riding(), "Teo, que te acompaña, se sube contigo al coche")
	_expect(town.vehicles_described(player.global_position).contains("Teo"), "y la IA lo sabe: «%s»" % town.vehicles_described(player.global_position).left(80))
	car._on_use(player)
	await create_timer(0.3).timeout
	_expect(not teo.is_riding(), "al bajarte, baja él también")
	memory.set_fields("npc_teo", {"following": false})
	teo.stop()

	# --- La nave: sin pared invisible ---------------------------------------------------------
	var ship_e: Dictionary = Creations.all_here().filter(func(x): return x.name == "Lanzadera vieja")[0]
	var ship = Creations.node_of(town, ship_e.id)
	var shapes: Array = ship.find_children("*", "CollisionShape3D", false, false)
	var vol := 0.0
	var all := AABB()
	var first := true
	for s in shapes:
		var b: Vector3 = (s.shape as BoxShape3D).size if s.shape is BoxShape3D else Vector3.ONE
		vol += b.x * b.y * b.z
		var a := AABB(s.position - b / 2.0, b)
		all = a if first else all.merge(a)
		first = false
	_expect(shapes.size() >= 2 and vol < all.size.x * all.size.y * all.size.z * 0.7, "la nave choca con su forma (fuselaje y alas), no con una caja que la envuelve (%d formas, %.0f%% del volumen)" % [shapes.size(), vol / maxf(all.size.x * all.size.y * all.size.z, 0.01) * 100.0])

	# --- La cafetería: te atienden en la mesa -------------------------------------------------
	await interiors.enter(interiors.door_of_kind("cafe"), true)
	await create_timer(1.5).timeout
	var seats: Array = interiors.get("_interior").seats
	var seat: Node3D = seats[seats.size() - 1].node
	interiors.sit(seat)
	var waiter = town.get("_households").staff_here()
	_expect(waiter != null, "en la cafetería hay mesero/a")
	t = 0.0
	var panel_open := false
	while t < 14.0 and not panel_open:
		await create_timer(0.25).timeout
		t += 0.25
		panel_open = town.get_children().any(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("ShopPanel.gd"))
	_expect(panel_open and waiter and waiter.global_position.distance_to(player.global_position) < 2.6, "te sientas y viene a tu mesa a tomarte nota")
	for n in town.get_children():
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("ShopPanel.gd"):
			n.close()
	await create_timer(0.5).timeout
	player.hold_position = false
	interiors.leave()
	await create_timer(1.5).timeout

	# --- El faro: forzarlo sin Marina dentro no te «pilla» ------------------------------------
	clock.set_hour(10.5)  # Marina está en la playa
	town.call("_follow_schedules", true)
	await create_timer(0.5).timeout
	var before: int = memory.get_mem("npc_marina").recent.size()
	town.get("_door_rules").forced_door = "faro"
	await interiors.enter("faro", true)
	await create_timer(1.6).timeout
	var recent: Array = memory.get_mem("npc_marina").recent.slice(before)
	_expect(not recent.any(func(x): return str(x.text).contains("pillaste") or str(x.text).contains("Le pillaste")), "Marina no está: no «te pilla» dentro del faro")
	_expect(recent.any(func(x): return str(x.text).contains("puerta forzada")), "al volver encuentra la puerta forzada (sin saber quién fue)")
	# La escalera lleva a la linterna
	var hatch: Variant = interiors.get("_interior").get("hatch")
	_expect(hatch != null, "la escalera de caracol llega a una trampilla")
	var hatch_use: Node3D = interiors.get("_interior").uses.filter(func(u): return u.get("what", "") == "climb_up")[0].node
	interiors.use_fixture("climb_up", hatch_use)
	await create_timer(1.8).timeout
	_expect(not interiors.is_inside() and player.global_position.y > 18.0, "y por ella sales al balcón de la linterna (a %.0f m)" % player.global_position.y)
	await town.call("_climb_down")
	await create_timer(0.5).timeout
	_expect(interiors.is_inside() and interiors.current_door() == "faro", "y bajas por la misma escalera")
	interiors.leave()
	await create_timer(1.5).timeout

	# --- Casa ajena: comer y dormir -----------------------------------------------------------
	clock.set_hour(13.0)
	var doors: Dictionary = interiors.doors()
	var house := ""
	for id in doors:
		if doors[id].kind == "house" and not town.get("_door_rules").residents_home(id).filter(func(r): return r.awake).is_empty():
			house = id
			break
	await interiors.enter(house, true)
	await create_timer(1.6).timeout
	var inside: Array = town.people_inside()
	_expect(not inside.is_empty(), "en %s hay alguien en casa" % house)
	var fridge: Node3D = null
	for u in interiors.get("_interior").uses:
		if u.get("what", "") == "eat":
			fridge = u.node
	_expect(fridge != null, "la nevera de una casa ajena se puede usar")
	if fridge and not inside.is_empty():
		var w = inside[0]
		var n0: int = memory.get_mem(w.npc_id).recent.size()
		interiors.use_fixture("eat", fridge)
		await create_timer(3.6).timeout
		var ev: Array = memory.get_mem(w.npc_id).recent.slice(n0)
		_expect(ev.any(func(x): return str(x.text).contains("nevera")), "comes de su nevera delante de ellos: lo ven y no les gusta")
	var beds: Array = interiors.get("_interior").beds
	if not beds.is_empty():
		clock.set_hour(21.0)
		var r: Dictionary = town.call("_sleep_check", house, beds[0].node, 600.0)
		_expect(r.has("by") and float(r.minutes) < 600.0, "dormir en su cama a las 21:00: su dueño llegará a acostarse (%s)" % r)
		var owner: String = r.get("by", "")
		if not owner.is_empty():
			var n1: int = memory.get_mem(owner).recent.size()
			town.call("_on_slept", house, beds[0].node, float(r.minutes), owner)
			await create_timer(0.3).timeout
			_expect(memory.get_mem(owner).recent.slice(n1).any(func(x): return str(x.text).contains("cama")), "te despierta y lo recuerda")
	interiors.leave()
	await create_timer(1.5).timeout

	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

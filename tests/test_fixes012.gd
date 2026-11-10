extends SceneTree
## v0.12.0: escenas que muestran lo que dicen, interfaz sin bloqueos, PNJ sin empalmarse, todo
## edificio se usa, animales con cuerpo, examinar en singular, diálogo sin falsos positivos y el
## mundo nuevo (Puerto Alto, el autobús, el bosque, la cueva, el río, la economía y la sociedad).
##   godot --headless --path . -s tests/test_fixes012.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var story = root.get_node("/root/StoryDirector")
	var quests = root.get_node("/root/Quests")
	var memory = root.get_node("/root/NPCMemory")
	var economy = root.get_node("/root/Economy")
	var society = root.get_node("/root/Society")
	var wallet = root.get_node("/root/Wallet")
	root.get_node("/root/Settings").use_mock = true
	Engine.set_meta("cutscene_auto", true)
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba arreglos 012")

	# 1. Diálogo: sin falsos positivos
	for line in ["No me voy a ningún sitio, tranquilo.", "Me voy a tomar un café contigo, si quieres.", "Entro a trabajar a las 9.",
			"Vamos con calma.", "Me vuelvo a equivocar, qué tonto."]:
		var t := {"line": line, "actions": []}
		story.make_consistent(t)
		_expect(not t.actions.any(func(a): return a.type in ["leave", "go_inside", "guide_player"]), "«%s» no hace que se vaya" % line)
	var t2 := {"line": "Bueno, me voy a casa.", "actions": []}
	story.make_consistent(t2)
	_expect(t2.actions.any(func(a): return a.type == "leave"), "«me voy a casa» sí")
	_expect(story.check_places("Espera un cuarto de hora y vuelve.", "").dropped.is_empty(), "«un cuarto de hora» no es un cuarto inventado")
	clock.set_hour(20.0)
	_expect(story.parse_at_hour("ven mañana a las 9") >= 24.0, "«mañana a las 9» es mañana")
	_expect(absf(story.parse_at_hour("a las 12 de la noche") - 0.0) < 0.01, "«a las 12 de la noche» son las 0:00")
	_expect(absf(story.parse_at_hour("a las tres y media de la tarde") - 15.5) < 0.01, "«a las tres y media de la tarde» → 15:30")
	_expect(story.strip_name("Hola, José, pasa.", "José") == "Hola, pasa.", "quitar un nombre con tilde")
	_expect(story.strip_name("La luz del faro se ve.", "Luz") == "La luz del faro se ve.", "«Luz» no borra «la luz del faro»")
	_expect(not story._has_word("Hasta mañana", "Ana", false), "«mañana» no es decir «Ana»")

	# 2. Examinar: en singular y para alguien solo
	var Ex = load("res://scripts/world/Examine.gd")
	_expect(not Ex.bad_examine("Frente a ustedes hay una caja.", "una caja de carga").is_empty(), "«ustedes» se rechaza")
	_expect(not Ex.bad_examine("Ves dos cajas apiladas.", "una caja de carga").is_empty(), "«dos cajas» para una caja se rechaza")
	_expect(Ex.bad_examine("Ves una caja de madera hinchada por la humedad.", "una caja de carga").is_empty(), "una descripción correcta pasa")

	# 3. Economía: alquiler y factura semanal
	wallet.earn(400)
	var note: String = economy.rent("piso_test", "un piso de prueba", 90)
	_expect(not economy.rental().is_empty() and note.contains("contrato"), "alquilas un piso: %s" % note)
	var money: int = wallet.amount()
	clock.advance(7 * 24 * 60 + 10)
	economy.check_week()
	_expect(wallet.amount() == money - (90 + economy.UTILITIES), "a la semana se cobra el alquiler y la luz (%d → %d)" % [money, wallet.amount()])
	_expect(economy.deposit(50).contains("Ingresas") and economy.savings() == 50, "ingresas en el banco")

	# 4. Sociedad: el sábado hay mercado y el periódico cuenta cosas
	while clock.weekday() != "sábado":
		clock.advance(24 * 60)
	clock.set_hour(10.0)
	_expect(society.is_on("market"), "el sábado por la mañana hay mercado")
	society.add_news("Prueba: alguien perdió un gato.")
	_expect(society.newspaper().contains("perdió un gato") and society.newspaper().contains("Mercado"), "el periódico lista sucesos y la agenda")

	# 5. El pueblo: Puerto Alto, autobús, cueva, río, bosque, edificios con puerta, animales con cuerpo
	clock.set_hour(10.0)
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 40:
		await physics_frame
	var interiors = town.get("_interiors")
	var doors: Dictionary = interiors.doors()
	_expect(doors.has("granero") and doors.has("cueva") and doors.has("tienda_campamento"), "el granero, la cueva y la tienda de campaña tienen puerta")
	var city_kinds := []
	for id in doors:
		if str(id).begins_with("ciudad_"):
			city_kinds.append(doors[id].kind)
	_expect(["hospital", "police", "school", "bank", "cinema", "gym", "realty"].all(func(k): return k in city_kinds), "Puerto Alto tiene sus servicios con puerta (%d edificios)" % city_kinds.size())
	var ground: Callable = func(x, z): return town.call("ground_at", x, z)
	_expect(float(ground.call(-520.0, 115.0)) < -1.0, "el río tiene cauce (agua)")
	var bus: Node3D = town.find_child("Autobus", true, false)
	_expect(bus != null, "hay autobús")
	var city: Node = town.find_child("PuertoAlto", true, false)
	var g1: bool = city.call("green_for", true)
	city.set("_t", float(city.get("_t")) + 12.5)
	_expect(city.call("green_for", true) != g1, "los semáforos cambian")
	# Animales: chocan
	var animals := town.get_tree().get_nodes_in_group("animals")
	_expect(animals.size() >= 10 and animals.all(func(a): return a is CharacterBody3D), "animales con cuerpo (%d)" % animals.size())
	# Edificios: un interior nuevo se carga
	var player = town.get("_player")
	player.global_position = interiors.door_position("granero") + Vector3(0, 0.3, 0)
	await interiors.enter("granero", true)
	for i in 10:
		await physics_frame
	_expect(interiors.is_inside() and interiors.current_kind() == "barn", "se entra al granero")
	await interiors.leave()
	await interiors.wait_idle()

	# 6. Sitios: varias personas en un mismo interior no se empalman
	await interiors.enter("faro", true)
	for i in 10:
		await physics_frame
	var npcs: Dictionary = town.get("_npcs")
	var placed := []
	for id in npcs:
		var n = npcs[id]
		n.set_present(true)
		n.settle(interiors.npc_spot(0), interiors.npc_spot(0) + Vector3(0, 0, 1), "", "")
		placed.append(n)
	var min_d := INF
	for a in placed.size():
		for b in range(a + 1, placed.size()):
			min_d = minf(min_d, (placed[a] as Node3D).global_position.distance_to((placed[b] as Node3D).global_position))
	_expect(min_d > 0.5, "tres personas mandadas al mismo sitio no se empalman (%.2f m)" % min_d)
	await interiors.leave()
	await interiors.wait_idle()

	# 7. Interfaz: con un diálogo abierto no se abren Cuaderno ni celular, y la pausa para el reloj
	var ui = town.get("_ui")
	ui.block(true, "dialogue")
	ui.block(true, "dialogue")  # (abrir dos veces no suma dos)

	var ev := InputEventAction.new()
	ev.action = "inventory"
	ev.pressed = true
	ui._unhandled_input(ev)
	_expect(not ui.inventory.is_open(), "con un diálogo abierto no se abre el Cuaderno encima")
	ui.block(false, "dialogue")
	_expect(player.controls_enabled, "al cerrar el diálogo vuelve el control (sin quedar bloqueado)")
	ui.pause.toggle()
	_expect(clock.paused, "en pausa el reloj se para")
	ui.pause.toggle()
	_expect(not clock.paused and player.controls_enabled, "y al salir sigue")

	# 8. El Despertar: el vecino que corre hacia ti se ve y llega
	var p: Dictionary = db.get_state("act0", {"talked": [], "awakening_ready": false})
	p["awakening_ready"] = true
	db.set_state("act0", p)
	memory.set_fields("npc_marina", {"relationship": 50})
	clock.set_hour(3.5)
	player.global_position = interiors.door_position("faro") + Vector3(0, 0.3, 0)
	for i in 60:
		await physics_frame
	var seq = town.get("_awakening")
	_expect(seq != null, "a las 3:30 a. m. empieza El Despertar")
	var t0 := 0.0
	while seq and seq.get("log_checks").size() < 7 and t0 < 40.0:
		await create_timer(0.5).timeout
		t0 += 0.5
	var checks: Array = seq.get("log_checks") if seq else []
	_expect(checks.any(func(c): return c.shot == "companion" and c.ok), "la toma del vecino: visible, en cuadro y a su lado %s" % [checks])
	_expect(checks.any(func(c): return c.shot == "watch" and c.ok), "la brújula está en tu mano")
	_expect(not checks.any(func(c): return not c.ok), "todas las tomas muestran lo que dicen")

	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:
		await process_frame
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

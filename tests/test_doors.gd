extends SceneTree
## Puertas de verdad: en casa ajena se toca y abre alguien (y, si te invita, pasas); tu casa se
## abre con tu llave; un negocio cerrado no deja entrar; y una puerta que nadie abre se puede forzar.
##   godot --headless --path . -s tests/test_doors.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var settings = root.get_node("/root/Settings")
	var memory = root.get_node("/root/NPCMemory")
	var was_mock: bool = settings.use_mock
	settings.use_mock = true  # sin IA: de día y si no le caes mal, te invita a pasar
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de puertas")
	clock.set_hour(13.0)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var interiors = town.get("_interiors")
	var rules = town.get("_door_rules")
	var player = town.get("_player")
	var doors: Dictionary = interiors.doors()

	# Tu casa: con tu llave. Una casa ajena: «Tocar la puerta».
	var home: String = interiors.door_of_kind("home")
	_expect(rules.may_enter(home), "tu casa se abre con tu llave")
	var house := ""
	for id in doors:
		if doors[id].kind == "house" and id != "casa_4" and not rules.residents_home(id).filter(func(r): return r.awake).is_empty():
			house = id
			break
	_expect(not house.is_empty() and not rules.may_enter(house), "en una casa ajena con gente despierta (%s) no se entra sin llamar" % house)
	_expect(str(doors[house].node.prompt).begins_with("Tocar la puerta"), "y el aviso dice «%s»" % doors[house].node.prompt)

	# Tocas: sale alguien a la puerta (y sin IA, de día, te invita a pasar)
	player.global_position = interiors.door_position(house) + Vector3(0, 0.3, 1.5)
	await physics_frame
	interiors.try_enter(house)
	await create_timer(0.5).timeout
	_expect(not interiors.is_inside(), "tocar no te mete dentro")
	var answered := false
	var opener := ""
	var t := 0.0
	while t < 5.0 and not interiors.is_inside():
		if not rules.doorstep.is_empty():
			answered = true
			opener = rules.doorstep.id
		await create_timer(0.1).timeout
		t += 0.1
	_expect(answered, "alguien de la casa sale a abrir")
	await create_timer(1.6).timeout
	_expect(interiors.is_inside() and interiors.current_door() == house, "te invita a pasar y entras")
	var events: Array = memory.get_mem(opener).recent.map(func(e): return str(e.text)) if not opener.is_empty() else []
	_expect(events.any(func(e): return e.contains("nvitaste al jugador")) and not events.any(func(e): return e.contains("desconocido")),
		"y quien te abrió recuerda que te invitó (no «un desconocido»)")
	interiors.leave()
	await create_timer(1.5).timeout
	_expect(not interiors.invited.has(house) and not rules.may_enter(house), "al salir, la invitación se acaba")

	# Negocio cerrado: no deja entrar; nadie abre y entonces se puede forzar
	clock.set_hour(23.5)
	town.call("_shop_hours")
	var shop: String = interiors.door_of_kind("grocery")
	interiors.try_enter(shop)
	await create_timer(2.6).timeout
	_expect(not interiors.is_inside(), "los abarrotes cerrados no dejan entrar")
	_expect(str(doors[shop].node.prompt).begins_with("Forzar la puerta"), "y, como nadie abre, el aviso pasa a «%s»" % doors[shop].node.prompt)
	interiors.try_enter(shop)  # E otra vez: la fuerzas
	var tt := 0.0
	while tt < 8.0 and not interiors.is_inside():
		await create_timer(0.2).timeout
		tt += 0.2
	_expect(interiors.is_inside() and interiors.current_door() == shop, "forzando la puerta, entras")
	interiors.leave()
	await create_timer(1.5).timeout

	# Si alguien te ve forzar una casa, su dueño lo sabe y no te deja pasar
	rules.call("caught_inside", "npc_teo")
	_expect(rules.banned("npc_teo"), "a quien le forzaste la puerta no te deja pasar durante días")
	_expect(memory.get_mem("npc_teo").recent.any(func(e): return str(e.text).contains("forzó la puerta")), "y lo recuerda")

	town.queue_free()
	await process_frame
	settings.use_mock = was_mock
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:  # (que acabe lo pendiente: cerrar justo tras liberar la escena podía fallar)
		await process_frame
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

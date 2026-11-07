extends SceneTree
## v0.9.0: lo que ves funciona como parece.
##  - Los letreros se leen (E), y casi todo lo demás se puede examinar (la IA lo describe).
##  - Las cosas pequeñas (la radio del taller) se pueden tomar, y no vuelven a aparecer.
##  - La nevera se abre al comer de ella.
##  - Un edificio de 3 plantas tiene 3 por dentro, y desde el de balcón se sale al balcón.
##  - Las cúpulas de otros planetas son cúpulas por dentro (redondas, de una planta).
##  - «Te llevo con las vecinas»: te lleva con personas, no solo a sitios.
##   godot --headless --path . -s tests/test_interact.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _prompts(node: Node, prefix: String) -> Array:
	return node.find_children("*", "Area3D", true, false).filter(func(a): return a.get("prompt") != null and str(a.prompt).begins_with(prefix))


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba interactuar")
	clock.set_hour(11.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await physics_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")

	# 1. Leer y examinar
	_expect(_prompts(town, "Leer:").size() >= 6, "los letreros se leen (%d)" % _prompts(town, "Leer:").size())
	_expect(_prompts(town, "Examinar:").size() >= 20, "y muchas cosas del mundo se pueden examinar (%d)" % _prompts(town, "Examinar:").size())
	var Ex = load("res://scripts/world/Examine.gd")
	var text: String = await Ex.describe(town, "una farola de hierro", Vector3(-5, 0, 0))
	_expect(text.length() > 20, "examinar da una descripción («%s»)" % text.left(60))

	# 2. Tomar la radio del taller (y que no vuelva)
	player.global_position = Vector3(-36, 0.5, 34)
	await interiors.enter("station", true)
	for i in 10:
		await physics_frame
	var takes := _prompts(town, "Tomar:")
	_expect(not takes.is_empty(), "en el taller hay cosas que se pueden tomar (%d)" % takes.size())
	var before: int = root.get_node("/root/Inventory").items().size()
	if not takes.is_empty():
		takes[0].use(player)
		await process_frame
	_expect(root.get_node("/root/Inventory").items().size() == before + 1, "tomar una radio la pone en tu inventario")
	await interiors.leave()
	await interiors.wait_idle()
	await interiors.enter("station", true)
	for i in 10:
		await physics_frame
	_expect(_prompts(town, "Tomar:").size() == takes.size() - 1, "y no vuelve a aparecer")
	await interiors.leave()
	await interiors.wait_idle()

	# 3. La nevera se abre
	await interiors.enter(interiors.door_of_kind("home"), true)
	for i in 10:
		await physics_frame
	var fridge: Dictionary = (interiors.get("_interior").uses as Array).filter(func(u): return u.get("what", "") == "eat")[0]
	interiors.use_fixture("eat", fridge.node)
	await create_timer(0.7).timeout
	var leaves := town.find_children("*", "OmniLight3D", true, false).filter(func(l): return l.light_color == Color("#e8f6ff"))
	_expect(not leaves.is_empty(), "al comer de la nevera, primero la abres (se ve la puerta y su luz)")
	await create_timer(4.0).timeout
	await interiors.leave()
	await interiors.wait_idle()

	# 4. Plantas según el modelo, y el balcón
	var three := ""
	var balcony := ""
	for id in interiors.doors():
		var o: Dictionary = interiors.doors()[id].get("opts", {})
		if int(o.get("floors", 1)) == 3:
			three = id
		if bool(o.get("balcony", false)):
			balcony = id
	_expect(not three.is_empty(), "hay casas de 3 plantas (%s)" % three)
	if not balcony.is_empty():
		await interiors.enter(balcony, true)
		for i in 10:
			await physics_frame
		var bal := (interiors.get("_interior").uses as Array).filter(func(u): return u.get("what", "") == "balcony")
		_expect(not bal.is_empty(), "desde la planta de arriba se sale al balcón")
		if not bal.is_empty():
			interiors.use_fixture("balcony", bal[0].node)
			await create_timer(2.0).timeout
			_expect(not interiors.is_inside() and player.global_position.y > 2.5, "y estás fuera, en el balcón (a %.1f m)" % player.global_position.y)
			for i in 30:
				await physics_frame
			_expect(player.global_position.y > 2.5, "sin caerte")
	else:
		_expect(false, "hay algún edificio con balcón")

	# 5. Guiar hasta una persona
	var npcs: Dictionary = town.get("_npcs")
	var guide_ids := npcs.keys()
	var people: Array = town.call("_people_for_text", "con las vecinas", guide_ids[0])
	_expect(people.size() >= 1 and not (guide_ids[0] in people), "«con las vecinas» son personas de aquí (%s)" % [people])
	var turn := {"line": "¡Claro! Te llevo con Marina, sígueme.", "actions": []}
	root.get_node("/root/StoryDirector").make_consistent(turn)
	_expect(turn.actions.any(func(a): return a.type == "guide_player" and str(a.target).contains("marina")), "si dice «te llevo con…», lo hace (%s)" % [turn.actions])
	town.queue_free()
	await process_frame

	# 6. Una cúpula en otro planeta
	var holder := Node3D.new()
	root.add_child(holder)
	var Builder = load("res://procgen/InteriorBuilder.gd")
	var out: Dictionary = Builder.build(holder, "dome", 5, Vector3(0, -400, 0), {"floors": 2})
	_expect(not out.beds.is_empty() and out.uses.size() >= 2, "la cúpula por dentro: literas, cocina pequeña")
	var slabs := holder.find_children("*", "StaticBody3D", true, false).filter(func(b): return (b as Node3D).global_position.y > -400.0 + 2.5 and (b as Node3D).global_position.y < -400.0 + 3.6)
	_expect(slabs.is_empty(), "y de una sola planta, aunque se pidan dos")
	holder.queue_free()
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

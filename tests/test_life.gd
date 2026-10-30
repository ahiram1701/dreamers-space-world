extends SceneTree
## La vida real del jugador: el cuerpo (hambre, sed, descanso, higiene), el dinero y la gente y los
## sitios que la IA crea y se quedan. Sin red: las acciones llegan como las devolvería la IA.
##   godot --headless --path . -s tests/test_life.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var actions = root.get_node("/root/Actions")
	var body = root.get_node("/root/Body")
	var wallet = root.get_node("/root/Wallet")
	var clock = root.get_node("/root/WorldClock")
	var memory = root.get_node("/root/NPCMemory")
	var quests = root.get_node("/root/Quests")
	var validator = root.get_node("/root/ContentValidator")
	var game = root.get_node("/root/GameState")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de vida")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)
	await process_frame
	await process_frame

	# --- Cuerpo ---
	body.set_need("hunger", 80.0)
	body.set_need("thirst", 80.0)
	clock.advance(8 * 60)
	await process_frame
	_expect(body.get_need("hunger") < 60.0 and body.get_need("thirst") < 50.0, "en 8 horas entra hambre y sed (%.0f, %.0f)" % [body.get_need("hunger"), body.get_need("thirst")])
	var r: Dictionary = validator.validate("world_action", {"narration": "Te comes un bocadillo.", "steps": [{"type": "comer_beber", "target": "comida", "amount": 30}]})
	_expect(r.ok and r.data.steps[0].type == "change_need" and r.data.steps[0].target == "comida", "«comida» → change_need %s" % [r.data.get("steps")])
	var before: float = body.get_need("hunger")
	actions.execute("", r.data.steps)
	_expect(body.get_need("hunger") > before + 80.0 or body.get_need("hunger") == 100.0, "comer quita el hambre (%.0f → %.0f)" % [before, body.get_need("hunger")])
	body.set_need("rest", 5.0)
	body.set_need("hunger", 5.0)
	_expect(body.speed_factor() >= 0.7 and body.speed_factor() < 1.0, "con sueño y hambre vas más despacio, pero nunca menos del 70 %% (%.2f)" % body.speed_factor())
	_expect(body.describe().contains("sueño") and body.describe().contains("famélico"), "la IA sabe cómo estás: %s" % body.describe())
	_expect(game.get_stat("health") == 100 or not game.is_awakened(), "el cuerpo nunca quita salud")

	# --- Dinero ---
	_expect(wallet.amount() == 40, "empiezas con $40")
	var notes: Array = actions.execute("", [{"type": "pay", "target": "npc:npc_teo", "price": 2}])
	_expect(wallet.amount() == 38 and "Pagas $2" in str(notes), "pagas un café a Teo %s" % [notes])
	_expect(memory.describe_recent("npc_teo").contains("pagó"), "Teo recuerda que le pagaste")
	notes = actions.execute("", [{"type": "pay", "target": "npc:npc_teo", "price": 150}])
	_expect(wallet.amount() == 38 and "No te llega" in str(notes), "no puedes pagar lo que no tienes %s" % [notes])
	actions.execute("", [{"type": "earn", "price": 900}])
	_expect(wallet.amount() == 38 + 300, "como mucho $300 por acción (%d)" % wallet.amount())
	# Teo te pone un café y te lo cobra: queda pendiente hasta que pagas
	notes = actions.execute("npc_teo", [{"type": "give_item", "item_name": "Café solo", "item_description": "Un café recién hecho.", "price": 2}])
	_expect(actions.owed("npc_teo") == 2 and "cobra" in str(notes), "te cobra el café %s" % [notes])
	_expect(memory.describe("npc_teo").contains("te debe"), "Teo sabe que le debes")
	var money: int = wallet.amount()
	actions.settle("npc_teo")
	_expect(actions.owed("npc_teo") == 0 and wallet.amount() == money - 2, "pagas lo que debes")
	# Un trabajo pagado
	actions.execute("npc_samir", [{"type": "give_quest", "target": "Cables nuevos", "text": "Tráeme cable de la ferretería.", "price": 25}])
	money = wallet.amount()
	actions.execute("npc_samir", [{"type": "complete_quest"}])
	_expect(wallet.amount() == money + 25, "el encargo se paga al cumplirlo")

	# --- Gente nueva que se queda ---
	var arrived := []
	actions.resident_added.connect(func(e): arrived.append(e))
	actions.arrival_spot = func(): return {"from": Vector3(30, 0, 0), "to": Vector3(2, 0, 0), "home": Vector3(2, 0, 0)}
	r = validator.validate("world_action", {"narration": "Llamas a un fontanero.", "steps": [
		{"type": "crear_persona", "name": "Lucía Ferrer", "occupation": "Fontanera", "text": "Seria y eficaz, con mono azul.", "line": "¿Dónde está esa fuga?"},
		{"type": "spawn_npc", "name": "Otro Más", "occupation": "Curioso"}]})
	notes = actions.execute("", r.data.steps)
	var res: Array = actions.residents_here(game.current_location())
	_expect(res.size() == 1 and arrived.size() == 1, "llega una persona (y solo una por acción) %s" % [notes])
	var lucia: Dictionary = db.get_entity("npc", res[0].id)
	_expect(lucia.name == "Lucía Ferrer" and lucia.appearance.outfit == "work_uniform" and lucia.appearance.figure == "feminine",
		"la fontanera es válida, con uniforme %s" % [lucia.get("appearance")])
	_expect(lucia.greeting == "¿Dónde está esa fuga?" and "seri" in str(lucia.personality), "dice lo suyo y es como se describió %s" % [lucia.personality])

	# --- Un sitio nuevo ---
	var built := []
	actions.place_added.connect(func(e): built.append(e))
	actions.lot_finder = func(): return {"pos": Vector3(6, 0, 24), "yaw": PI / 2}
	notes = actions.execute("", [{"type": "abrir_negocio", "item_name": "Panadería La Espiga", "target": "panadería", "text": "Huele a pan."}])
	r = validator.validate("world_action", {"narration": "Abres una panadería.", "steps": [{"type": "abrir_negocio", "item_name": "Panadería La Espiga", "target": "panadería"}]})
	notes = actions.execute("", r.data.steps)
	var places: Array = actions.places_added_here(game.current_location())
	_expect(places.size() == 1 and places[0].kind == "bakery" and places[0].interior == "shop", "aparece la panadería %s" % [places])
	actions.lot_finder = func(): return {}
	notes = actions.execute("", [{"type": "create_place", "item_name": "Bar Sin Sitio", "target": "bar"}])
	_expect(actions.places_added_here(game.current_location()).size() == 1 and "No hay sitio" in str(notes), "sin solar libre no se construye")

	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

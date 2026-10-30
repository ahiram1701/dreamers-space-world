extends SceneTree
## Lo que los PNJs aceptan hacer pasa de verdad: prestar, recibir, acompañar, curar, encargos…
## Sin red (las acciones llegan ya validadas, como las devolvería la IA).
##   godot --headless --path . -s tests/test_actions.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var actions = root.get_node("/root/Actions")
	var inventory = root.get_node("/root/Inventory")
	var memory = root.get_node("/root/NPCMemory")
	var game = root.get_node("/root/GameState")
	var quests = root.get_node("/root/Quests")
	var journal = root.get_node("/root/Journal")
	var validator = root.get_node("/root/ContentValidator")

	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de acciones")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)

	# La IA devuelve las acciones a su manera: el validador las repara o las descarta
	var turn := {
		"line": "Claro, llévate mi radio, pero devuélvemela.", "emotion": "feliz",
		"choices": ["Gracias", "Adiós"],
		"actions": [
			{"type": "prestar", "item_name": "Radio de onda corta", "item_description": "Vieja, con el dial gastado.", "lent": "true"},
			{"type": "bailar_salsa"},
			"dame algo",
		],
	}
	var r: Dictionary = validator.validate("dialogue_turn", turn)
	_expect(r.ok and r.data.actions.size() == 1 and r.data.actions[0].type == "give_item", "repara 'prestar' y descarta acciones inventadas %s" % [r.data.get("actions")])
	_expect(r.data.actions[0].lent == true, "lent como texto → bool")

	# Samir presta la radio → está en el inventario, marcada como prestada
	var notes: Array = actions.execute("npc_samir", r.data.actions)
	var radio: String = inventory.find_by_name("la radio")
	_expect(not radio.is_empty() and inventory.has(radio), "la radio aparece en el inventario: %s" % [notes])
	_expect("Samir" in inventory.lent_label(radio), "queda como prestada por Samir")
	_expect(radio in memory.get_mem("npc_samir").lent, "Samir recuerda que te la prestó")

	# Como mucho dos regalos por turno ("te pongo el café y te presto el boli")
	var count: int = inventory.items().size()
	actions.execute("npc_marina", [
		{"type": "give_item", "item_name": "Llave del faro", "item_effect": "none", "lent": false, "amount": 0},
		{"type": "give_item", "item_name": "Prismáticos", "item_effect": "none", "lent": true, "amount": 0},
		{"type": "give_item", "item_name": "Otra cosa más", "item_effect": "none", "lent": false, "amount": 0}])
	_expect(inventory.items().size() == count + 2, "como máximo dos objetos por turno")

	# Devolverla: deja de estar prestada y vuelve a Samir
	notes = actions.execute("npc_samir", [{"type": "take_item", "target": "radio", "amount": 0}])
	_expect(not inventory.has(radio) and not (radio in memory.get_mem("npc_samir").lent), "devuelves la radio: %s" % [notes])
	# Pedir algo que no tienes no hace nada
	notes = actions.execute("npc_samir", [{"type": "take_item", "target": "dinosaurio", "amount": 0}])
	_expect(notes.is_empty(), "no puedes dar lo que no tienes")

	# Dar un objeto tuyo y que te lo devuelva (el mismo, no una copia)
	var key: String = inventory.find_by_name("llave")
	actions.player_gives("npc_teo", key)
	_expect(not inventory.has(key) and key in memory.get_mem("npc_teo").possessions, "Teo guarda la llave que le diste")
	actions.execute("npc_teo", [{"type": "give_item", "item_name": "Llave del faro", "item_effect": "none", "lent": false, "amount": 0}])
	_expect(inventory.has(key), "Teo te devuelve la misma llave")

	# Acompañar, enfadarse, encargos y diario
	actions.execute("npc_marina", [{"type": "follow_player", "item_effect": "none", "lent": false, "amount": 0}])
	_expect(memory.is_following("npc_marina"), "Marina te acompaña")
	actions.execute("npc_marina", [{"type": "stop_following", "item_effect": "none", "lent": false, "amount": 0}])
	_expect(not memory.is_following("npc_marina"), "Marina deja de seguirte")
	actions.execute("npc_teo", [{"type": "refuse_contact", "amount": 10, "item_effect": "none", "lent": false}])
	_expect(memory.refusal_left("npc_teo") > 500, "Teo no quiere hablarte durante 10 min")
	actions.execute("npc_marina", [{"type": "give_quest", "target": "Café para Marina", "text": "Tráele un café de la cafetería.", "amount": 0}])
	_expect(quests.active_custom().size() == 1, "Marina te hace un encargo")
	actions.execute("npc_marina", [{"type": "complete_quest", "amount": 0}])
	_expect(quests.active_custom().is_empty(), "Marina da el encargo por cumplido")
	actions.execute("npc_samir", [{"type": "journal", "text": "La señal llega siempre a las 3:33.", "amount": 0}])
	actions.execute("npc_samir", [{"type": "reveal_place", "target": "Estación Kepler", "text": "Una estación orbital abandonada.", "amount": 0}])
	_expect(journal.entries().size() == 2, "dos entradas en el diario")
	_expect(actions.take_revealed_place().get("name", "") == "Estación Kepler", "el lugar revelado será un próximo destino")

	# Stats: solo después del Despertar, y acotados por el validador
	r = validator.validate("dialogue_turn", {"line": "Toma, bebe.", "choices": ["Gracias", "Adiós"],
		"actions": [{"type": "curar", "target": "salud", "amount": 500}]})
	_expect(r.data.actions[0].amount == 30, "la curación se acota a 30")
	game.awaken("", false)
	game.set_stat("health", 50)
	actions.execute("npc_marina", r.data.actions)
	_expect(game.get_stat("health") == 80, "Marina te cura (+30): %d" % game.get_stat("health"))

	# Préstamo repetido: si ya te lo prestó y lo tienes, no aparece una copia
	actions.execute("npc_samir", [{"type": "give_item", "item_name": "Radio de válvulas averiada", "lent": true, "item_effect": "none", "amount": 0}])
	var before: int = inventory.items().size()
	actions.execute("npc_samir", [{"type": "give_item", "item_name": "Radio de válvulas", "lent": true, "item_effect": "none", "amount": 0}])
	_expect(inventory.items().size() == before, "no se duplica un préstamo")

	# Reparar: el mismo objeto cambia de nombre y descripción (sigue siendo prestado)
	var old_radio: String = inventory.find_by_name("radio")
	r = validator.validate("world_action", {"narration": "Recolocas la válvula floja y la radio vuelve a sonar.", "minutes": "45",
		"actions": [{"type": "reparar", "target": "la radio", "item_name": "Radio de válvulas (reparada)", "item_description": "Vuelve a captar la transmisión."}]})
	_expect(r.ok and r.data.minutes == 45 and r.data.actions[0].type == "update_item", "repara 'reparar' y los minutos %s" % [r.errors])
	actions.execute("", r.data.actions)
	var fixed: Dictionary = db.get_entity("item", old_radio)
	_expect(fixed.name == "Radio de válvulas (reparada)" and "transmisión" in fixed.lore, "la radio queda reparada: %s" % fixed.name)
	_expect(inventory.lent_label(old_radio).contains("Samir"), "sigue siendo de Samir")

	# Gastar materiales: si era prestado, el dueño lo sabe
	actions.execute("", [{"type": "remove_item", "target": "radio"}])
	_expect(not inventory.has(old_radio), "la radio se gasta")
	_expect(memory.get_mem("npc_samir").facts.any(func(f): return "rompió" in f), "Samir sabe que rompiste su radio")

	# Construir y talar: se guarda por lugar y se avisa a la escena
	var placed := []
	var removed := []
	actions.object_placed.connect(func(e): placed.append(e))
	actions.feature_removed.connect(func(id): removed.append(id))
	actions.player_pose = func(): return {"pos": Vector3(10, 0, 5), "yaw": 0.0, "water": Vector3(40, -0.4, 5)}
	actions.feature_finder = func(kind: String) -> String: return "tree_12_-30" if kind == "tree" else ""
	r = validator.validate("world_action", {"narration": "Talas un pino y con los troncos atas una balsa.",
		"actions": [{"type": "talar", "target": "árbol"}, {"type": "construir", "target": "balsa", "item_name": "Balsa de pino"},
			{"type": "affect_nearby", "target": "rock"}]})
	actions.execute("", r.data.actions)
	_expect(removed == ["tree_12_-30"], "talar quita el árbol más cercano %s" % [removed])
	_expect(actions.removed_here(game.current_location()) == ["tree_12_-30"], "el árbol talado se recuerda")
	_expect(placed.size() == 1 and placed[0].kind == "raft" and placed[0].pos[0] == 40.0, "la balsa se bota en el agua %s" % [placed])
	_expect(actions.placed_here(game.current_location()).size() == 1, "la balsa queda guardada en el lugar")

	# Si el modelo no da opciones, el turno sigue valiendo
	r = validator.validate("dialogue_turn", {"line": "Bueno, ya ves cómo está la cosa.", "emotion": "neutral"})
	_expect(r.ok and r.data.choices.size() == 3, "turno sin opciones → opciones por defecto %s" % [r.errors])

	# El Ancla no se regala
	var anchor: String = db.add_entity("item", {"name": "Ancla", "kind": "technology", "effect": "none", "power": 100, "lore": "El dispositivo.", "tags": []}, "awakening")
	db.set_state("awakening", {"anchor_id": anchor})
	inventory.add(anchor)
	actions.player_gives("npc_samir", anchor)
	_expect(inventory.has(anchor), "el Ancla no se puede regalar")

	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

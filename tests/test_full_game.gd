extends SceneTree
## Partida completa sin red (IA en modo mock): Despertar → mundos con misiones y objetos →
## 5 fragmentos → origen de la señal → final. Comprueba la lógica, no la parte visual.
##   godot --headless --path . -s tests/test_full_game.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var game = root.get_node("/root/GameState")
	var story = root.get_node("/root/StoryDirector")
	var travel = root.get_node("/root/Travel")
	var quests = root.get_node("/root/Quests")
	var inventory = root.get_node("/root/Inventory")

	var previous_last: String = db.last_world_id()
	root.get_node("/root/Settings").use_mock = true
	var world_id: String = db.create_world("Prueba de partida completa")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)
	story.apply_awakening(await story.generate_awakening(), 0)

	# Mundos: cada uno con habitantes, objetos y una misión que da un fragmento
	var first_location := ""
	for i in game.FRAGMENTS_NEEDED:
		var j: Dictionary = await travel.jump_new()
		_expect(j.ok, "salto %d %s" % [i + 1, j.error])
		var loc: Dictionary = db.get_entity("location", j.location_id)
		if i == 0:
			first_location = j.location_id
			_expect(loc.item_ids.size() == 2, "el lugar tiene 2 objetos")
			var q0: Dictionary = quests.for_location(j.location_id)
			_expect(not q0.is_empty() and q0.status == "active", "el lugar tiene una misión activa: %s" % quests.objective_text(q0))
			# Recoger y usar un objeto
			inventory.add(loc.item_ids[0])
			_expect(inventory.has(loc.item_ids[0]), "objeto recogido")
			game.set_stat("energy", 10)
			var msg: String = inventory.use(loc.item_ids[0], loc.npc_ids)
			_expect(not msg.is_empty() and not inventory.has(loc.item_ids[0]), "usar un objeto lo gasta: %s" % msg)
		_complete_quest(quests, inventory, j.location_id)
		_expect(game.fragments() == i + 1, "fragmentos: %d/%d" % [game.fragments(), game.FRAGMENTS_NEEDED])
		game.recharge()
		if i < game.FRAGMENTS_NEEDED - 1:
			await travel.pregenerate()
			_expect(not str(db.get_state("pending_jump", "")).is_empty(), "siguiente destino pregenerado")

	_expect(game.has_all_fragments(), "coordenadas completas")
	await travel.pregenerate()
	_expect(str(db.get_state("pending_jump", "")).is_empty(), "con las coordenadas completas no se pregenera")

	# Objeto de coordenadas: salto gratis
	game.grant_free_jump()
	_expect(game.travel_cost(first_location) == 0, "con coordenadas el salto es gratis")
	var back: Dictionary = await travel.go_to(first_location)
	_expect(back.ok and not game.has_free_jump(), "el salto gratis se consume")

	# Misión de "llevar objeto" (el modo mock solo genera "visitar"): sin el objeto no se completa
	var loc1: Dictionary = db.get_entity("location", first_location)
	var all: Dictionary = db.get_state("quests", {})
	all["q_bring"] = {"id": "q_bring", "location_id": first_location, "giver": loc1.npc_ids[0], "title": "Encargo",
		"description": "", "objective": "bring_item", "target": loc1.item_ids[1], "target_name": "x",
		"completion_text": "", "status": "active"}
	db.set_state("quests", all)
	db.update_entity("location", first_location, {"quest_id": "q_bring"})
	quests.notify("talk_npc", loc1.npc_ids[0])
	_expect(quests.get_quest("q_bring").status == "active", "sin el objeto, la misión sigue activa")
	inventory.add(loc1.item_ids[1])
	game.set_stat("energy", 0)
	quests.notify("talk_npc", loc1.npc_ids[0])
	_expect(quests.get_quest("q_bring").status == "done" and not inventory.has(loc1.item_ids[1]), "entregar el objeto completa la misión")
	_expect(game.get_stat("energy") == quests.BONUS_ENERGY, "con todos los fragmentos, la recompensa es energía")
	game.recharge()

	# El origen de la señal y el final
	var fin: Dictionary = await travel.jump_finale()
	_expect(fin.ok and db.get_entity("location", fin.location_id).get("finale", false), "salto al origen de la señal")
	var finale: Dictionary = await story.generate_finale()
	_expect(finale.choices.size() == 3, "tres finales")
	var ending: Dictionary = story.apply_ending(finale, 0)
	_expect(game.ending() == ending.ending and not ending.epilogue.is_empty(), "final aplicado: %s" % ending.ending)

	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


## Cumple la misión del lugar como lo haría un jugador.
func _complete_quest(quests, inventory, location_id: String) -> void:
	var q: Dictionary = quests.for_location(location_id)
	match q.objective:
		"visit_poi":
			quests.notify("visit_poi", q.target)
		"talk_npc":
			quests.notify("talk_npc", q.target)
		"bring_item":
			inventory.add(q.target)
			quests.notify("talk_npc", q.giver)
	_expect(quests.get_quest(q.id).status == "done", "misión completada (%s)" % q.objective)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

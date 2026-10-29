extends SceneTree
## Flujo completo sin red (IA en modo mock): Acto 0 → Despertar → salto → segundo salto → volver.
##   godot --headless --path . -s tests/test_awakening_flow.gd
## Usa un mundo temporal y restaura el "último mundo" del jugador al terminar.

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var settings = root.get_node("/root/Settings")
	var game = root.get_node("/root/GameState")
	var timeline = root.get_node("/root/TimelineManager")
	var story = root.get_node("/root/StoryDirector")
	var travel = root.get_node("/root/Travel")
	var memory = root.get_node("/root/NPCMemory")

	var previous_last: String = db.last_world_id()
	settings.use_mock = true  # solo en memoria: no se guarda en los ajustes del jugador
	var world_id: String = db.create_world("Prueba de flujo")

	# Acto 0: los vecinos base y algo de relación con Samir
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)
	memory.add_facts("npc_samir", ["Le ayudó a descifrar la señal."], 30)
	_expect(not game.is_awakened(), "antes del Despertar no hay stats")
	_expect(not game.can_travel("new"), "sin Despertar no se puede saltar")

	# El Despertar
	var awakening: Dictionary = await story.generate_awakening()
	_expect(awakening.has("origin") and awakening.choices.size() >= 2, "genera un Despertar válido (%s)" % awakening.get("source"))
	var idx := 0
	for i in awakening.choices.size():
		if awakening.choices[i].consequence == "jump_with_companion":
			idx = i
	var applied: Dictionary = story.apply_awakening(awakening, idx)
	_expect(applied.companion == "npc_samir", "el compañero es el vecino con más relación (%s)" % applied.companion)
	_expect(game.is_awakened() and game.get_stat("energy") == 100, "stats iniciales tras el Despertar")
	_expect(db.canon().size() >= 3, "canon registrado (%d hechos)" % db.canon().size())
	_expect(not db.get_entity("item", applied.anchor_id).is_empty(), "el Ancla es un item del mundo")
	_expect(timeline.has_root() and timeline.depth() == 0, "raíz del árbol temporal")

	# Primer salto: lugar nuevo + PNJs
	var j1: Dictionary = await travel.jump_new()
	_expect(j1.ok, "primer salto %s" % j1.error)
	var loc1: Dictionary = db.get_entity("location", j1.location_id)
	_expect(not loc1.is_empty() and loc1.npc_ids.size() == 2, "lugar generado con 2 PNJs")
	_expect(game.current_location() == j1.location_id, "el jugador está en el lugar nuevo")
	_expect(game.get_stat("energy") == 75 and game.get_stat("instability") == 12, "el salto cuesta energía y suma inestabilidad")
	_expect(timeline.depth() == 1, "rama nueva en el árbol")
	_expect(travel.scene_for(j1.location_id).ends_with("GeneratedLocation.tscn"), "escena de lugar generado")

	# Segundo salto y vuelta
	var j2: Dictionary = await travel.jump_new()
	_expect(j2.ok and j2.location_id != j1.location_id, "segundo salto crea otro lugar")
	_expect(timeline.depth() == 2, "profundidad 2")
	var back: Dictionary = await travel.go_to(j1.location_id)
	_expect(back.ok and game.current_location() == j1.location_id, "volver a un lugar visitado")
	_expect(timeline.depth() == 1, "volver no crea rama nueva")
	_expect(travel.known_destinations().size() == 2, "destinos conocidos: casa y el segundo lugar")

	# Sin energía no hay salto; la recarga lo arregla
	game.set_stat("energy", 5)
	var blocked: Dictionary = await travel.jump_new()
	_expect(not blocked.ok, "sin energía el salto se bloquea")
	game.recharge()
	_expect(game.get_stat("energy") == 100, "recarga completa")

	# Persistencia: recargar el mundo desde disco conserva todo
	db.load_world(world_id)
	_expect(game.current_location() == j1.location_id and timeline.nodes().size() == 3, "persistencia tras recargar")

	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

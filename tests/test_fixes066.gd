extends SceneTree
## Arreglos de la v0.6.6: lo que se compra llega completo, las acotaciones del PNJ van aparte y en
## tercera persona, la IA sabe qué ropa llevas y cómo son los sitios, el celular no te cuenta lo
## que ya hablasteis, F sube al techo, nadie se sienta en el aire y los PNJ caminan por una malla.
##   godot --headless --path . -s tests/test_fixes066.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var actions = root.get_node("/root/Actions")
	var inventory = root.get_node("/root/Inventory")
	var memory = root.get_node("/root/NPCMemory")
	var wallet = root.get_node("/root/Wallet")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba 0.6.6")
	clock.set_hour(13.0)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var SD = load("res://autoload/StoryDirector.gd")

	# Café y galletas: dos cosas distintas, las dos llegan
	_expect(not actions._same_thing("Taza de café", "Taza de galletas"), "«taza de café» y «taza de galletas» no son lo mismo")
	_expect(actions._same_thing("Radio de válvulas averiada", "Radio de válvulas"), "pero una radio averiada sí es la misma radio")
	wallet.earn(50)
	var before: int = inventory.items().size()
	actions.execute("npc_teo", [
		{"type": "give_item", "item_name": "Taza de café", "item_description": "Café de olla recién hecho.", "price": 2},
		{"type": "give_item", "item_name": "Galletas de nata", "item_description": "Tres galletas en una servilleta.", "price": 2}])
	_expect(inventory.items().size() == before + 2, "Teo te vende café y galletas: llevas las dos cosas (%d nuevas)" % (inventory.items().size() - before))

	# Acotaciones: fuera de la frase y en tercera persona
	var turn := {"line": "Ya veo. —Le doy un sorbo a mi café y miro hacia la escalera—. Si se le desvela, ya sabe dónde estoy."}
	SD.split_action(turn)
	_expect(not str(turn.line).contains("sorbo") and str(turn.line).begins_with("Ya veo. Si se"), "la frase queda solo con lo que dice: «%s»" % turn.line)
	_expect(str(turn.get("action", "")).contains("Le da un sorbo a su café") and str(turn.action).contains("mira"), "y la acción va aparte en tercera persona: «%s»" % turn.get("action", ""))
	_expect(SD.player_words("*le doy un abrazo* gracias").contains("(el jugador hace: le doy un abrazo)"), "lo que el jugador pone entre asteriscos es lo que HACE")

	# La IA sabe qué llevas puesto y cómo son los sitios
	var looks: String = town.call("_player_looks")
	_expect(looks.contains("camiseta") and looks.contains("sin abrigo"), "te ve con tu ropa real, sin abrigo: «%s»" % looks)
	var places: String = town.call("places_described")
	_expect(places.contains("UNA sola puerta") and places.contains("no hay puerta trasera"), "el faro tiene una sola puerta (no hay puerta de atrás)")

	# El celular: lo que pasó antes de hablar ya está hablado
	memory.add_event("npc_samir", "El jugador (aún no le conocías) entró en tu casa sin llamar.", -3)
	memory.add_event("npc_samir", "Acabas de hablar con el jugador en persona (en la estación).")
	var Phone_ = load("res://autoload/Phone.gd")
	_expect(Phone_.news_for("npc_samir", clock.absolute_minutes()).is_empty(), "Samir no te escribe «alguien entró en mi casa» después de haber hablado contigo")
	memory.add_event("npc_samir", "Se fue la luz en la estación.")
	_expect(Phone_.news_for("npc_samir", clock.absolute_minutes()).contains("luz"), "pero sí lo que pasó después")

	# F: subo al techo de mi casa (y bajo)
	var AP = load("res://scripts/world/ActionPerformer.gd")
	var plan: Array = AP.local_plan("subo al techo de mi casa", town, "")
	_expect(plan.size() == 1 and plan[0].type == "climb" and plan[0].target == "roof:home", "«subo al techo de mi casa» → subir al techo (no entrar)")
	var player = town.get("_player")
	var interiors = town.get("_interiors")
	var home: String = interiors.door_of_kind("home")
	var b: Dictionary = interiors.doors()[home].get("building", {})
	player.global_position = interiors.door_position(home) + Vector3(0, 0.3, 2.0)
	await physics_frame
	var performer = town.get("_performer")
	var notes: Array = await performer.perform(plan)
	for i in 30:
		await physics_frame
	var ground: float = interiors.door_position(home).y
	var height: float = b.size.y if not b.is_empty() else 0.0
	_expect(not b.is_empty() and (player.global_position.y > ground + 3.0 or height > 7.0), "en el techo de tu casa (%.1f m sobre el suelo; casa de %.1f m) %s" % [player.global_position.y - ground, height, str(notes)])
	if player.global_position.y > ground + 3.0:
		await performer.perform(AP.local_plan("me bajo del techo", town, ""))
		for i in 30:
			await physics_frame
		_expect(player.global_position.y < ground + 1.5, "y «me bajo del techo» te deja en el suelo")

	# Nadie se sienta en el aire
	var npc = town.get("_npcs")["npc_teo"]
	npc.global_position = Vector3(-5, 0.5, -30)
	for i in 20:
		await physics_frame
	npc.play_gesture("sit", 5.0)
	await create_timer(0.5).timeout
	_expect(not npc.is_settled() and npc.seat_near(6.0) == null, "sin silla cerca, no se sienta en el aire")

	# Malla de navegación: hay camino de una punta del pueblo a otra
	var NB = load("res://scripts/world/NavBaker.gd")
	var t := 0.0
	while t < 60.0 and not NB.ready_for(town):
		await create_timer(0.5).timeout
		t += 0.5
	await create_timer(1.0).timeout
	var path: PackedVector3Array = NB.path(town, Vector3(-5, 0, -40), Vector3(-5, 0, 30))
	_expect(path.size() >= 2, "los PNJ tienen camino por la malla (%d puntos, horneada en %.0f s)" % [path.size(), t])

	town.queue_free()
	await process_frame
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

extends SceneTree
## v0.11.0: textos que se leen, la hora de verdad, encargos realistas, desconocidos que no te
## conocen, un mundo que coincide con lo que se cuenta, la choza del pescador y las necesidades.
##   godot --headless --path . -s tests/test_fixes011.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var cv = root.get_node("/root/ContentValidator")
	var quests = root.get_node("/root/Quests")
	var story = root.get_node("/root/StoryDirector")
	var actions = root.get_node("/root/Actions")
	var inventory = root.get_node("/root/Inventory")
	var memory = root.get_node("/root/NPCMemory")
	var profile = root.get_node("/root/PlayerProfile")
	var game = root.get_node("/root/GameState")
	var body = root.get_node("/root/Body")
	root.get_node("/root/Settings").use_mock = true
	Engine.set_meta("cutscene_auto", true)
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba arreglos 011")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)

	# 1. Textos: nunca a mitad de palabra
	var long := "Una bobina de inducción que se desmonta del anillo de telemetría. Al vibrar, la ferrita canta una nota grave y constante que se oye a lo lejos sin cansarse nunca"
	var cut: String = cv.fit_text(long, 100)
	_expect(cut.length() <= 101 and (cut.ends_with(".") or cut.ends_with("…")), "un texto largo se corta al final de una frase o con «…»: «%s»" % cut)
	var cut2: String = cv.fit_text("palabra " .repeat(30), 50)
	_expect(cut2.ends_with("…") and not cut2.trim_suffix("…").ends_with("pal"), "si no hay frase, se corta en una palabra entera: «%s»" % cut2)

	# 2. La hora en formato de 12 horas
	_expect(clock.fmt(3.55) == "3:33 a. m." and clock.fmt(15.0) == "3:00 p. m." and clock.fmt(0.0) == "12:00 a. m." and clock.fmt(12.25) == "12:15 p. m.",
		"12 horas: %s, %s, %s, %s" % [clock.fmt(3.55), clock.fmt(15.0), clock.fmt(0.0), clock.fmt(12.25)])
	_expect(load("res://scripts/world/Shops.gd").hours_text("grocery").contains("a. m."), "los horarios de las tiendas también: %s" % load("res://scripts/world/Shops.gd").hours_text("grocery"))

	# 3. Lo que pide en voz alta queda apuntado, con su hora (sin am/pm: la próxima)
	clock.set_hour(10.0)
	var turn := {"line": "Escucha. ¿Me traes un café del muelle a las 3 de la tarde? Te lo pago.", "actions": []}
	story.make_consistent(turn)
	var gq: Array = turn.actions.filter(func(a): return a.type == "give_quest")
	_expect(gq.size() == 1 and absf(float(gq[0].get("at_hour", -1)) - 15.0) < 0.01 and gq[0].get("quest_kind", "") == "bring_item", "un pedido dicho en voz alta crea el encargo con hora y tipo: %s" % [gq])
	_expect(absf(story.parse_at_hour("nos vemos a las 3") - 15.0) < 0.01, "«a las 3» a las 10 de la mañana es a las 3 de la tarde")
	clock.set_hour(1.0)
	_expect(absf(story.parse_at_hour("nos vemos a las 3") - 3.0) < 0.01, "y a la 1 de la madrugada, a las 3 a. m.")

	# 4. Encargo con hora: si no estás, se pierde (y la persona lo recuerda)
	clock.set_hour(2.0)
	var q: Dictionary = quests.create_custom("npc_marina", "Verme en el faro", "Estar en el faro a las 3.", 0, {"kind": "be_there", "at_hour": 3.0})
	_expect(not q.is_empty() and quests.when_text(q) == "hoy a las 3:00 a. m.", "el encargo dice cuándo: %s" % quests.when_text(q))
	_expect(quests.describe_for_npc("npc_marina").contains("Verme en el faro"), "quien lo pidió lo recuerda")
	clock.set_hour(4.0)
	quests.check_now()
	_expect(quests.get_quest(q.id).status == "failed", "pasada la hora sin ir, el encargo se pierde")
	# varios encargos de la misma persona
	var a1: Dictionary = quests.create_custom("npc_teo", "Leña", "Traer leña.", 0, {})
	var a2: Dictionary = quests.create_custom("npc_teo", "Pan", "Traer pan.", 0, {})
	_expect(not a1.is_empty() and not a2.is_empty(), "una persona puede pedirte varias cosas")

	# 5. Entregar con «Dar objeto» cumple «tráeme X»
	var cafe: String = db.add_entity("item", {"name": "Café de olla", "kind": "consumable", "effect": "none", "power": 5, "lore": "Caliente.", "tags": []}, "test")
	inventory.add(cafe)
	var b: Dictionary = quests.create_custom("npc_samir", "Un café", "Tráeme un café.", 0, {"kind": "bring_item", "item": "café de olla"})
	var note: String = actions.player_gives("npc_samir", cafe)
	_expect(quests.get_quest(b.id).status == "done" and note.contains("Encargo cumplido"), "dárselo cumple el encargo: %s" % note)

	# 6. Desconocidos: no saben tu nombre ni te conocen por un rumor
	var stranger: String = db.add_entity("npc", {"name": "Dalia Márquez", "age": 40, "occupation": "Ingeniera", "personality": ["seca"], "goals": ["x"], "secret": "x", "greeting": "Hola."}, "location:x")
	memory.add_event(stranger, "Encontraste tu cama deshecha. No sabes quién fue.", 0, true)
	_expect(not memory.get_mem(stranger).met, "un rumor no hace que te conozca")
	_expect(not memory.knows_name(stranger) and not profile.describe(stranger).contains(profile.player_name()), "un desconocido no sabe tu nombre")
	_expect(memory.knows_name("npc_marina") or db.get_entity("npc", "npc_marina").is_empty(), "tus vecinos de siempre, sí")
	_expect(story.strip_name("Hola, %s, pasa." % profile.player_name(), profile.player_name()) == "Hola, pasa.", "si lo usa sin saberlo, se quita: «%s»" % story.strip_name("Hola, %s, pasa." % profile.player_name(), profile.player_name()))

	# 7. Sin sitios inventados
	var desc: String = load("res://procgen/InteriorBuilder.gd").DESCRIPTIONS.lighthouse
	var cp: Dictionary = story.check_places("Bajas al cuarto de aparejos y mueves un estante. El mar está quieto.", desc)
	_expect(cp.dropped.size() == 1 and cp.text == "El mar está quieto.", "«el cuarto de aparejos» del faro no existe: se quita (%s)" % [cp])

	# 8. El mundo manda: lo que se nombra se construye con su forma
	var Poi = load("res://procgen/PoiCatalog.gd")
	_expect(Poi.classify("El viejo faro de la bahía") == "lighthouse" and Poi.classify("Consola de recepción") == "console" and Poi.classify("Archivo de telemetría") == "archive",
		"faro → faro, consola → consola, archivo → archivo")
	var norm: Dictionary = Poi.normalize_location({"name": "Bahía de las Horas — Nodo 2190", "description": "Junto al faro hay una antena.", "points_of_interest": [{"name": "Antena de la bahía", "kind": "antenna"}]})
	_expect("lighthouse" in norm.poi_kinds, "si la descripción habla de un faro, el faro se construye: %s" % [norm.poi_kinds])

	var def: Dictionary = root.get_node("/root/ContentGenerator").load_fallback("location")
	def["biome"] = "barren"
	var npc_def: Dictionary = root.get_node("/root/ContentGenerator").load_fallback("npc")
	var npc_id: String = db.add_entity("npc", npc_def, "test", "test_ingeniera")
	def["npc_ids"] = [npc_id]
	var loc_id: String = db.add_entity("location", def, "test", "test_hesperia")
	game.set_location(loc_id)
	var gen: Node3D = load("res://scenes/generated_location/GeneratedLocation.tscn").instantiate()
	root.add_child(gen)
	current_scene = gen
	for i in 30:
		await process_frame
	var doors: Dictionary = gen.get("_interiors").doors()
	_expect(doors.keys().any(func(k): return str(k).begins_with("poi_")), "el faro del lugar tiene puerta (se entra): %s" % [doors.keys()])
	var stands: Dictionary = gen.get("_poi_stands")
	var npc: Node3D = gen.get("_npcs").get(npc_id)
	var console_name := ""
	for n in gen.get("_poi_kinds"):
		if gen.get("_poi_kinds")[n] == "console":
			console_name = n
	_expect(npc != null and not console_name.is_empty() and npc.global_position.distance_to(stands[console_name]) < 1.5, "la ingeniera está delante de su consola")
	var labels := []
	for m in gen.get_tree().get_nodes_in_group("landmark"):
		labels.append(str(m.get_meta("label", "")))
	_expect(labels.any(func(l): return l.begins_with("Consola de control — una consola")), "al examinar se lee el nombre real y qué es")
	_expect(not labels.any(func(l): return l.contains("mojón") and l.contains("Consola")), "y nunca «un mojón de piedras» para una consola")
	gen.queue_free()
	await process_frame

	# 9. La choza del pescador se puede abrir y la barca se usa
	game.set_location(game.HOME)
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await physics_frame
	_expect(town.get("_interiors").doors().has("choza"), "la cabaña del pescador tiene puerta")
	_expect((town.get("_boats") as Array).size() >= 5, "las barcas del lago y de la choza son barcas de verdad (%d)" % (town.get("_boats") as Array).size())

	# 10. Necesidades: con hambre a cero se pierde salud
	game.awaken("", false)
	var h0: int = game.get_stat("health")
	body.set_need("hunger", 0.0)
	body._decay(40.0)
	_expect(game.get_stat("health") < h0, "sin comer, la salud baja poco a poco (%d → %d)" % [h0, game.get_stat("health")])
	_expect(not body.can_run(), "y no puedes correr")
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

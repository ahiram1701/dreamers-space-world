extends SceneTree
## v0.7: el mundo es coherente. Los nombres casan con el género y el oficio con la edad, el pueblo
## se conoce entre sí, la ropa que se ve es la que la IA conoce (y el tiempo viste a la gente),
## la IA sabe qué hay alrededor (y qué no: un toldo) y lo que un PNJ narra que hace, lo hace.
##   godot --headless --path . -s tests/test_coherence.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var actions = root.get_node("/root/Actions")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba coherencia")
	clock.set_hour(13.0)
	var Weather = load("res://scripts/world/Weather.gd")
	Weather.forced = "clear"
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var SD = load("res://autoload/StoryDirector.gd")
	var Names = load("res://scripts/world/Names.gd")
	var Townsfolk = load("res://scripts/world/Townsfolk.gd")
	var Wardrobe = load("res://scripts/npc/Wardrobe.gd")
	var ActionMapper = load("res://scripts/npc/ActionMapper.gd")

	# --- Nombres, género, oficio y edad -----------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	var old_young := 0
	for i in 500:
		var fem := rng.randf() < 0.5
		var first: String = Names.first(fem, rng)
		var j: Dictionary = Names.job(fem, rng, ["street", "house", "home", "elder"][i % 4])
		if Names.is_female_name(first) != fem:
			wrong += 1
		if Names.fit_job(j.job, fem) != j.job:
			wrong += 1
		if str(j.job).contains("jubilad") and int(j.age) < 60:
			old_young += 1
	_expect(wrong == 0, "500 personas: ningún nombre ni oficio del género contrario (%d mal)" % wrong)
	_expect(old_young == 0, "nadie «jubilado» con menos de 60 años (%d)" % old_young)
	var jid: String = actions.build_npc("Joaquín Rojas", "maestra jubilada", "Vecino del barrio.", "Hola.")
	var joaquin: Dictionary = db.get_entity("npc", jid)
	_expect(joaquin.occupation == "maestro jubilado" and int(joaquin.age) >= 62, "Joaquín + «maestra jubilada» → %s, %d años" % [joaquin.occupation, joaquin.age])
	_expect(Names.fit_job("dependienta de Ferretería", false) == "dependiente de Ferretería", "el oficio cambia sin tocar el nombre del local")

	# --- El pueblo se conoce --------------------------------------------------------------
	var folk: String = Townsfolk.context_for(town, "npc_teo", "¿conoces a Samir?")
	_expect(folk.contains("Samir") and folk.contains("Marina"), "Teo conoce a Samir y a Marina")
	_expect(folk.contains("hombre") and folk.contains("mujer"), "y sabe si cada quien es hombre o mujer")
	memory.add_bond("npc_teo", "npc_samir", "hace poco charlaste con Samir («la tormenta»)")
	_expect(Townsfolk.bond("npc_teo", "npc_samir").contains("tormenta"), "lo que charlan entre ellos lo recuerdan")

	# --- La ropa: lo que se ve es lo que se dice --------------------------------------------
	Weather.forced = "rain"
	var rainy := 0
	for i in 60:
		var e := {"id": "x%d" % i, "appearance": {"outfit": "casual", "layers": []}}
		if Wardrobe.wears(Wardrobe.for_weather(e), "raincoat"):
			rainy += 1
	_expect(rainy >= 42, "con lluvia, al menos el 70%% lleva impermeable (%d/60)" % rainy)
	_expect(Wardrobe.for_weather({"id": "x1", "appearance": {"layers": []}}, false).is_empty(), "y dentro de casa nadie lo lleva puesto")
	Weather.forced = "clear"
	var desc: String = Wardrobe.describe({"outfit": "casual", "primary_color": "#2f6f9f"}, [{"id": "raincoat", "color": "#d9a521"}])
	_expect(desc.begins_with("impermeable amarillo") and desc.contains("sin abrigo"), "se describe lo que lleva: «%s»" % desc)
	var turn := {"line": "Pasa, deja tu abrigo en la silla. Te sirvo algo.", "action": "Se ajusta el cuello del impermeable. Sonríe."}
	SD.strip_clothes(turn, [], "casual", [], "casual")
	_expect(not str(turn.action).contains("impermeable") and str(turn.action).contains("Sonríe"), "una acotación con una prenda que no lleva se quita: «%s»" % turn.action)
	_expect(not str(turn.line).contains("abrigo") and str(turn.line).contains("Te sirvo"), "y no te pide el abrigo que no llevas: «%s»" % turn.line)
	var npc: Node = town.get("_npcs")["npc_teo"]
	npc.set_layers([{"id": "apron", "color": "#e8e2d4"}])
	var garments := 0
	for n in npc.find_children("Garment_*", "", true, false):
		garments += 1
	_expect(garments >= 1 and db.get_entity("npc", "npc_teo").appearance.layers.size() == 1, "Teo lleva el delantal puesto (en el modelo y en su ficha)")
	_expect(root.get_node("/root/StoryDirector")._system_prompt(db.get_entity("npc", "npc_teo"), "").contains("delantal"), "y la IA sabe que lo lleva")

	# --- Lo que hay alrededor (y lo que no) ---------------------------------------------------
	var cafe: Vector3 = town.place_position("cafetería")
	var around: String = town.surroundings_described(cafe, 20.0)
	_expect(around.contains("Sin toldo") and around.to_lower().contains("cafeter"), "junto a la cafetería: no hay toldo y se dice: «%s»" % around.left(260))
	var street: String = town.surroundings_described(Vector3(-5, 0, -30), 25.0)
	_expect(street.contains("farola") and street.contains("toldo de rayas"), "en la calle hay farolas y toldos de verdad")

	# --- Lo que narran, lo hacen ----------------------------------------------------------------
	var m: Dictionary = ActionMapper.map("Da un sorbo al café. Señala el faro con la barbilla. Piensa en la luna de otro planeta.", town.known_names())
	var kinds: Array = m.steps.map(func(s): return s.get("gesture", s.type))
	_expect("drink" in kinds and "point" in kinds, "«da un sorbo» bebe y «señala el faro» señala (%s)" % [kinds])
	_expect(not str(m.shown).contains("luna"), "lo que no se puede hacer no se muestra: «%s»" % m.shown)
	var t2 := {"line": "Mira.", "action": "Da un sorbo al café.", "emotion": "neutral", "actions": []}
	town.call("_on_turn", "npc_teo", t2)
	await create_timer(0.3).timeout
	_expect(npc.current_gesture() == "drink", "Teo da el sorbo de verdad (gesto: %s)" % npc.current_gesture())

	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


var memory:
	get:
		return root.get_node("/root/NPCMemory")


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

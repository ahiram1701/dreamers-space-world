extends SceneTree
## v0.7: el agente creador. La IA trabaja con herramientas (mirar, buscar en el catálogo, crear
## piezas, darles comportamientos, revisar) hasta terminar; lo creado se guarda y vuelve igual al
## regresar. Las herramientas validan todo: un argumento malo da un error que la IA puede corregir.
##   godot --headless --path . -s tests/test_agent.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var settings = root.get_node("/root/Settings")
	var inventory = root.get_node("/root/Inventory")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba agente")
	clock.set_hour(11.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var player = town.get("_player")
	player.global_position = Vector3(-5, 0.3, -30)
	await create_timer(0.3).timeout
	var Agent = load("res://scripts/agent/WorldAgent.gd")
	var Creations = load("res://scripts/agent/Creations.gd")

	_expect(Agent.wants_to_create("construyo un carrito con ruedas") and not Agent.wants_to_create("me siento en la banca"), "sabe cuándo es crear algo y cuándo no")
	_expect(not Creations.search("silla").is_empty() and not Creations.search("barco").is_empty(), "el catálogo encuentra sillas y barcos")

	# Una IA de mentira que trabaja como lo haría la de verdad, con un error que corrige
	var script := [
		{"tool": "look_around", "args": {"radius": 20}},
		{"tool": "spawn", "args": {"name": "Carrito", "parts": [{"shape": "triangle", "size": [1, 1, 1]}]}},  # forma que no existe
		{"tool": "spawn", "args": {"name": "Carrito de madera", "parts": [
			{"shape": "box", "size": [1.0, 0.1, 1.6], "pos": [0, 0.4, 0], "material": "wood"},
			{"shape": "box", "size": [0.9, 0.5, 0.08], "pos": [0, 0.7, -0.6]},
			{"shape": "wheel", "size": [0.5, 0.08, 0.5], "pos": [-0.55, 0.25, 0.55], "material": "rubber"},
			{"shape": "wheel", "size": [0.5, 0.08, 0.5], "pos": [0.55, 0.25, 0.55], "material": "rubber"}]}},
		{"tool": "attach", "args": {"id": "$last", "behavior": "seat"}},
		{"tool": "attach", "args": {"id": "$last", "behavior": "volar_a_la_luna"}},  # no existe
		{"tool": "inspect", "args": {"id": "$last"}},
		{"tool": "done", "args": {"narration": "Clavas las tablas y montas las ruedas: el carrito queda listo.", "minutes": 45}},
	]
	var seen_results := []
	var agent = Agent.new(town)
	var i := [0]
	agent.responder = func(messages: Array) -> Dictionary:
		if messages[-1].role == "user" and str(messages[-1].content).begins_with("RESULTADO"):
			seen_results.append(str(messages[-1].content))
		var step: Dictionary = script[mini(i[0], script.size() - 1)].duplicate(true)
		i[0] += 1
		if step.args.get("id", "") == "$last":
			step.args.id = agent.tools.created[-1] if not agent.tools.created.is_empty() else ""
		return step
	var res: Dictionary = await agent.run("construyo un carrito de madera para sentarme")
	_expect(res.ok and res.minutes == 45 and res.narration.begins_with("Clavas"), "el agente termina y narra (%s)" % res.get("error", "ok"))
	_expect(seen_results.any(func(r): return r.contains("ERROR") and r.contains("triangle")), "una forma que no existe da un error que la IA ve")
	_expect(seen_results.any(func(r): return r.contains("ERROR") and r.contains("volar_a_la_luna")), "un comportamiento que no existe, también")
	_expect(seen_results.any(func(r): return r.contains("Espacio libre delante")), "look_around le describe el entorno")
	var id: String = res.created[-1]
	var entry: Dictionary = Creations.get_entry(id)
	_expect(entry.get("parts", []).size() == 4 and entry.behaviors.map(func(b): return b.type) == ["seat"], "el carrito se guarda con sus piezas y su asiento")
	var node: Node3D = Creations.node_of(town, id)
	_expect(node != null and node.find_children("*", "Interactable", true, false).size() >= 1, "y existe en el mundo, con su «Sentarse»")
	_expect(node and node.global_position.distance_to(player.global_position) < 6.0, "delante del jugador")

	# Herramientas: validan, no rompen nada
	var tools = agent.tools
	_expect(tools.call_tool("spawn", {"name": "Torre", "parts": [{"shape": "box", "size": [1, 99, 1]}]}).begins_with("ERROR"), "no deja piezas de 99 m")
	_expect(tools.call_tool("spawn", {"name": "Algo", "model": "pack/NoExiste"}).begins_with("ERROR"), "ni modelos que no existen")
	_expect(tools.call_tool("remove", {"id": "door:casa_1"}).begins_with("ERROR"), "ni quitar lo que no se creó (un edificio)")
	_expect(tools.call_tool("borrar_disco", {}).begins_with("ERROR"), "ni herramientas inventadas")
	_expect(tools.call_tool("spawn", {"name": "Hoguera", "parts": [{"shape": "cone", "size": [0.8, 0.6, 0.8]}], "uses": ["leña mágica"]}).begins_with("ERROR"),
		"si faltan materiales, lo dice")
	var lamp_res: String = tools.call_tool("spawn", {"name": "Farol de jardín", "model": "street_pack/Streetlight_Single", "height": 2.5, "at": "front", "offset": [2, 0, 0]})
	var lamp_id: String = tools.created[-1]
	tools.call_tool("attach", {"id": lamp_id, "behavior": "light", "params": {"color": "#ffd9a0", "range": 9}})
	_expect(lamp_res.begins_with("Creado") and Creations.node_of(town, lamp_id).find_children("Lamp", "OmniLight3D", true, false).size() == 1, "un modelo del catálogo con luz")
	tools.call_tool("modify", {"id": lamp_id, "move": [1, 0, 0], "name": "Farol del porche"})
	_expect(Creations.get_entry(lamp_id).name == "Farol del porche", "se puede cambiar lo creado")

	# Sin IA: lo básico, a mano
	settings.use_mock = true
	var local = Agent.new(town)
	var lres: Dictionary = await local.run("construyo un banco junto a la calle")
	_expect(lres.ok and Creations.get_entry(local.tools.created[-1]).behaviors[0].type == "seat", "sin IA también se puede hacer un banco")

	# Se guarda y vuelve igual al regresar
	var count: int = Creations.all_here().size()
	town.queue_free()
	await process_frame
	await process_frame
	town = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for k in 10:
		await process_frame
	_expect(Creations.all_here().size() == count and Creations.node_of(town, id) != null, "al volver, lo creado sigue ahí (%d cosas)" % count)

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

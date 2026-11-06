extends SceneTree
## v0.7: vehículos, naves, espacio y reglas. Los coches se conducen con física de verdad (aceleran,
## giran, frenan, gastan gasolina y se quedan donde los dejas); lo que inventa la IA con ruedas y
## motor también; llevarse un coche ajeno es robo; pasa tráfico que frena ante ti; la nave
## despega al espacio y aterriza con ella; y las reglas («si llueve, enciende la luz») funcionan.
##   godot --headless --path . -s tests/test_vehicles.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var memory = root.get_node("/root/NPCMemory")
	var state = root.get_node("/root/GameState")
	var travel = root.get_node("/root/Travel")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba vehículos")
	clock.set_hour(12.0)
	var Weather = load("res://scripts/world/Weather.gd")
	Weather.forced = "clear"
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var Creations = load("res://scripts/agent/Creations.gd")
	var player = town.get("_player")

	# --- El pueblo tiene vehículos -------------------------------------------------------------
	var all: Array = Creations.all_here()
	var kinds: Array = all.map(func(e): return str(e.get("factory", e.name)))
	_expect(kinds.count("sedan") == 2 and "pickup" in kinds and "bike" in kinds and "speedboat" in kinds, "coches, camioneta, moto, bici y lancha en el pueblo (%s)" % [kinds])
	var bike: Dictionary = all.filter(func(e): return e.get("factory", "") == "bike")[0]
	_expect(bike.owner == "player", "la bici es tuya")
	_expect(all.any(func(e): return e.name == "Lanzadera vieja"), "y hay una lanzadera vieja en la plataforma de despegue")
	_expect(town.place_position("plataforma de despegue") != Vector3.INF, "la plataforma es un sitio con nombre")

	# --- Conducir un coche -------------------------------------------------------------------
	var teo_car: Dictionary = all.filter(func(e): return e.get("owner", "") == "npc_teo")[0]
	var car = Creations.node_of(town, teo_car.id)
	_expect(car is VehicleBody3D, "el coche es un VehicleBody3D con ruedas (%d)" % car.find_children("Wheel_*", "VehicleWheel3D", false, false).size())
	await create_timer(1.0).timeout
	var start: Vector3 = car.global_position
	var teo = town.get("_npcs")["npc_teo"]
	teo.global_position = start + Vector3(4, 0.3, 0)
	await physics_frame
	player.global_position = start + Vector3(-2, 0.3, 0)
	car._on_use(player)
	_expect(player.riding == car, "te subes al coche")
	_expect(memory.get_mem("npc_teo").recent.any(func(e): return str(e.text).contains("sin permiso")), "y como es de Teo y te ve, se entera de que te lo llevas")
	Input.action_press("move_forward")
	await create_timer(2.5).timeout
	var v: float = car.speed()
	_expect(v > 4.0 and v < 14.0, "acelera de forma realista (%.1f m/s en 2.5 s)" % v)
	Input.action_press("move_left")
	var yaw0: float = car.global_rotation.y
	await create_timer(1.2).timeout
	Input.action_release("move_left")
	_expect(absf(angle_difference(car.global_rotation.y, yaw0)) > 0.15, "gira")
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await create_timer(1.5).timeout
	Input.action_release("move_back")
	_expect(absf(car.speed()) < v * 0.6, "frena (%.1f m/s)" % car.speed())
	_expect(car.fuel < 1.0, "gasta gasolina (%.3f)" % car.fuel)
	car._on_use(player)
	_expect(player.riding == null and Creations.get_entry(teo_car.id).pos[2] != start.z, "te bajas y queda donde lo dejaste")

	# --- Lo que inventa la IA con ruedas y motor se conduce -------------------------------------
	var Agent = load("res://scripts/agent/WorldAgent.gd")
	var agent = Agent.new(town)
	player.global_position = Vector3(-5, 0.3, -50)
	await physics_frame
	agent.tools.call_tool("spawn", {"name": "Carrito", "parts": Agent.RECIPES.carrito.parts})
	var cart_id: String = agent.tools.created[-1]
	var r1: String = agent.tools.call_tool("attach", {"id": cart_id, "behavior": "wheels"})
	agent.tools.call_tool("attach", {"id": cart_id, "behavior": "engine", "params": {"power": 3}})
	_expect(Creations.node_of(town, cart_id) is VehicleBody3D, "un carrito de la IA con ruedas y motor es un vehículo de verdad")
	_expect(r1.contains("ruedas"), "y la herramienta lo confirma")

	# --- La bici no se cae de lado ------------------------------------------------------------
	var bike_node = Creations.node_of(town, bike.id)
	await create_timer(1.0).timeout
	_expect(absf(bike_node.global_rotation.z) < 0.2, "la bici se mantiene en pie")

	# --- Tráfico: pasa un coche y frena ante ti ------------------------------------------------
	var traffic: Node = town.find_children("*", "Traffic", false, false)[0] if not town.find_children("*", "Traffic", false, false).is_empty() else null
	if traffic == null:
		for c in town.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("Traffic.gd"):
				traffic = c
	traffic.set("_wait", 0.0)
	await create_timer(0.5).timeout
	var tcar: Node3D = traffic.car()
	_expect(tcar != null, "pasa un coche por la calle")
	if tcar:
		var dir: Vector3 = (traffic.LANES[traffic._lane][1] - traffic.LANES[traffic._lane][0]).normalized()
		player.global_position = tcar.global_position + dir * 6.0 + Vector3(0, 0.3, 0)
		await create_timer(1.5).timeout
		_expect(traffic._speed < 1.0, "y frena si estás delante (%.1f m/s)" % traffic._speed)

	# --- Reglas: «si llueve, enciende la luz» ----------------------------------------------------
	agent.tools.call_tool("spawn", {"name": "Farol", "parts": [{"shape": "cylinder", "size": [0.1, 2.0, 0.1], "pos": [0, 1, 0], "material": "metal"}]})
	var lamp_id: String = agent.tools.created[-1]
	agent.tools.call_tool("attach", {"id": lamp_id, "behavior": "light", "params": {"on": false}})
	var bad: String = agent.tools.call_tool("attach", {"id": lamp_id, "behavior": "rule", "params": {"when": "lluvia", "do": [{"act": "light_on"}]}})
	_expect(bad.begins_with("ERROR"), "una regla mal escrita da error: %s" % bad.left(80))
	agent.tools.call_tool("attach", {"id": lamp_id, "behavior": "rule", "params": {"when": "weather", "value": "rain", "do": [{"act": "light_on"}], "undo": [{"act": "light_off"}]}})
	var lamp: OmniLight3D = Creations.node_of(town, lamp_id).find_children("Lamp", "OmniLight3D", true, false)[0]
	_expect(not lamp.visible, "con buen tiempo, el farol está apagado")
	Weather.forced = "rain"
	await create_timer(2.5).timeout
	lamp = Creations.node_of(town, lamp_id).find_children("Lamp", "OmniLight3D", true, false)[0]
	_expect(lamp.visible, "empieza a llover y se enciende solo")
	Weather.forced = "clear"
	await create_timer(2.5).timeout
	_expect(not lamp.visible, "deja de llover y se apaga")

	# --- La nave: despegar al espacio y aterrizar con ella --------------------------------------
	var ship_e: Dictionary = Creations.all_here().filter(func(e): return e.name == "Lanzadera vieja")[0]
	var ship = Creations.node_of(town, ship_e.id)
	_expect(ship is CharacterBody3D and ship.get_script().resource_path.ends_with("Ship.gd"), "la lanzadera es una nave")
	player.global_position = ship.global_position + Vector3(-3, 0.3, 0)
	ship._on_use(player)
	Input.action_press("jump")
	await create_timer(2.0).timeout
	Input.action_release("jump")
	_expect(ship._ground_gap() > 4.0, "despega en vertical (%.1f m)" % ship._ground_gap())
	ship._rider = null
	player.riding = null
	travel.launch(Creations.get_entry(ship_e.id))
	_expect(state.current_location() == "space" and Creations.get_entry(ship_e.id).is_empty(), "al salir de la atmósfera estás en el espacio, con tu nave")
	town.queue_free()
	await process_frame
	var space: Node = load("res://scenes/space/SpaceScene.tscn").instantiate()
	root.add_child(space)
	for i in 5:
		await process_frame
	var sys: Dictionary = space.system
	_expect(sys.planets.size() >= 6 and sys.planets.any(func(p): return p.home), "un sistema solar con tu planeta (%d cuerpos)" % sys.planets.size())
	_expect(space.ship.display_name == "Lanzadera vieja", "vuelas en tu nave")
	Input.action_press("move_forward")
	await create_timer(1.0).timeout
	Input.action_release("move_forward")
	_expect(space.ship.speed() > 5.0, "en el espacio empuja con inercia (%.0f m/s)" % space.ship.speed())
	var home: Dictionary = load("res://scripts/space/StarSystem.gd").home_planet(sys)
	space.ship.global_position = load("res://scripts/space/StarSystem.gd").position_of(home) + Vector3(0, 0, float(home.radius) + 50.0)
	await process_frame
	await process_frame
	_expect(str(space._prompt.text).contains("Aterrizar en Tierra"), "junto a tu planeta: «%s»" % space._prompt.text)
	space.queue_free()
	await process_frame
	var landed: Dictionary = await travel.land("Tierra")
	_expect(landed.ok and state.current_location() == "home", "aterrizas en casa")
	town = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 12:
		await process_frame
	var parked: Array = Creations.all_here().filter(func(e): return e.name == "Lanzadera vieja")
	_expect(parked.size() == 1 and Creations.node_of(town, parked[0].id) != null, "y tu nave queda aparcada a tu lado")
	_expect(Vector3(parked[0].pos[0], 0, parked[0].pos[2]).distance_to(Vector3(town.get("_player").global_position.x, 0, town.get("_player").global_position.z)) < 15.0, "cerca de ti")

	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

extends SceneTree
## v0.8.0: la nave por dentro y el espacio estable.
##  - Vas DENTRO de la nave (no sentado encima) y quien te acompaña sube contigo, también oculto.
##  - Los pasajeros viajan contigo: despegan, cruzan el espacio y bajan a tu lado al aterrizar.
##  - Con Shift vas a crucero, pero al soltar frena en unos segundos (antes se quedaba a 8 km/s).
##  - Un golpe a toda velocidad no destroza el casco de una vez ni deja la nave sin mandos.
##  - Esc a mitad del aterrizaje no rompe nada.
##   godot --headless --path . -s tests/test_space_flight.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba nave")
	clock.set_hour(11.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	await _frames(20)
	var player = town.get("_player")
	var npcs: Dictionary = town.get("_npcs")
	var samir = npcs["npc_samir"]

	# 1. Dentro de la nave, no encima; y Samir sube contigo
	var ShipC = load("res://scripts/vehicles/Ship.gd")
	var Creations = load("res://scripts/agent/Creations.gd")
	var e: Dictionary = ShipC.factory()
	e["pos"] = [-60.0, town.ground_at(-60, 40), 40.0]
	var saved: Dictionary = Creations.add(e)
	var ship = Creations.build(town, saved)
	await _frames(5)
	samir.stop()
	samir.global_position = ship.global_position + Vector3(6, 0.3, 0)
	root.get_node("/root/NPCMemory").set_fields("npc_samir", {"following": true})
	player.global_position = ship.global_position + Vector3(-5, 0.3, 0)
	ship._on_use(player)
	await _frames(4)
	var body: Node3D = player.get("_body")
	_expect(player.riding == ship and not body.visible, "al subir a la nave vas dentro: tu cuerpo no se ve encima del casco")
	var t := 0.0
	while t < 12.0 and not samir.is_riding():
		await process_frame
		t += 1.0 / 60.0
	_expect(samir.is_riding() and samir.riding_vehicle() == ship, "quien te acompaña sube contigo a la nave")
	_expect(not (samir.get("_body") as Node3D).visible, "y también va dentro (no se le ve)")
	_expect(ship.passengers().size() == 1 and ship.free_seats() >= 2, "la nave tiene asientos para pasajeros")
	# Vista de cabina
	ship.set_cockpit(true)
	await process_frame
	_expect(root.get_viewport().get_camera_3d() == ship.get("_cockpit_cam"), "V: vista desde la cabina, con el tablero")
	ship.set_cockpit(false)
	await process_frame
	_expect(root.get_viewport().get_camera_3d() != ship.get("_cockpit_cam"), "V otra vez: vuelves a la vista de fuera")

	# 2. Los pasajeros viajan: despegar con Samir a bordo
	var travel = root.get_node("/root/Travel")
	var entry: Dictionary = Creations.get_entry(str(ship.entry_id)).duplicate(true)
	travel.launch(entry, ["npc_samir"])
	_expect(travel.passengers() == ["npc_samir"], "al despegar, Samir va a bordo")
	town.queue_free()
	await _frames(3)

	# 3. El espacio: crucero y frenado
	var space: Node3D = load("res://scenes/space/SpaceScene.tscn").instantiate()
	root.add_child(space)
	await _frames(10)
	var sship = space.get("ship")
	var sys: Dictionary = space.get("system")
	# Lejos de todo (para que no corte el crucero por proximidad)
	sship.global_position = Vector3(0, 30000, 0)
	sship.velocity = Vector3.ZERO
	Input.action_press("run")
	Input.action_press("move_forward")
	await _frames(300)
	var top_speed: float = sship.speed()
	Input.action_release("run")
	Input.action_release("move_forward")
	_expect(top_speed > 900.0 and top_speed < 1600.0, "Shift: crucero rápido pero con tope (%d m/s)" % int(top_speed))
	await _frames(240)
	_expect(sship.speed() < 220.0, "al soltar, la asistencia frena en unos segundos (%d m/s tras 4 s)" % int(sship.speed()))
	# X: frenar en seco
	sship.velocity = sship.global_basis.z * 800.0
	Input.action_press("ship_brake")
	await _frames(120)
	Input.action_release("ship_brake")
	_expect(sship.speed() < 40.0, "X frena en seco (%d m/s)" % int(sship.speed()))

	# 4. Un golpe a toda velocidad: daña, pero la nave sigue respondiendo
	var rock := StaticBody3D.new()
	rock.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 30.0
	cs.shape = sph
	rock.add_child(cs)
	space.add_child(rock)
	rock.global_position = sship.global_position + sship.global_basis.z * 120.0
	sship.hull = 100.0
	sship.velocity = sship.global_basis.z * 1500.0
	await _frames(10)
	_expect(sship.hull >= 60.0 and sship.hull < 100.0, "chocar a 1500 m/s daña el casco, pero no de golpe (%d%%)" % int(sship.hull))
	_expect(sship.speed() < 300.0, "y tras el golpe vas a una velocidad manejable (%d m/s)" % int(sship.speed()))
	sship.hull = 0.0
	sship.global_position = Vector3(0, -30000, 0)
	sship.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	_expect(sship.speed() > 5.0, "con el casco destrozado aún responde (a poca potencia) y puedes ir a aterrizar")
	rock.queue_free()

	# 5. Piloto automático al planeta marcado
	var home: Dictionary = {}
	for p in sys.planets:
		if p.get("home", false):
			home = p
	space.call("_start_autopilot", home, false)
	_expect(sship.autopilot, "G: el piloto automático lleva la nave al destino")
	await _frames(30)
	_expect(sship.speed() > 20.0, "y la nave arranca sola hacia allí")
	sship.autopilot = false

	# 6. Esc mientras aterriza: se ignora
	space.set("_landing", true)
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	space.call("_unhandled_input", esc)
	await process_frame
	_expect(is_instance_valid(space) and space.is_inside_tree(), "Esc a mitad del aterrizaje no saca del juego")
	space.set("_landing", false)

	# 7. Aterrizar en casa con Samir: baja contigo
	var r: Dictionary = await travel.land(str(home.name))
	_expect(r.ok, "aterrizas en tu planeta")
	space.queue_free()
	await _frames(3)
	var town2: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town2)
	await _frames(30)
	var p2 = town2.get("_player")
	var samir2 = town2.get("_npcs")["npc_samir"]
	_expect(samir2.global_position.distance_to(p2.global_position) < 8.0, "Samir baja de la nave contigo (a %.1f m)" % samir2.global_position.distance_to(p2.global_position))
	town2.queue_free()
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

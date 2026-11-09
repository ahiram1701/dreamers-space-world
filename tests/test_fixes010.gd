extends SceneTree
## v0.10.0: arreglos directos.
##  - A las 3:33, al llegar a la puerta del faro, empieza El Despertar (antes la zona no veía al jugador).
##  - Dormir: tumbado a lo largo de la cama, con la cabeza en la almohada y sobre el colchón.
##  - La escalera de caracol del faro se sube andando, de abajo a arriba.
##  - Al salir al balcón, estás sobre el balcón del edificio (no flotando delante).
##  - En el espacio, las rocas del cinturón no se atraviesan.
##   godot --headless --path . -s tests/test_fixes010.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba arreglos 010")
	clock.set_hour(22.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await physics_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")

	# 1. Dormir bien colocado
	await interiors.enter(interiors.door_of_kind("home"), true)
	for i in 10:
		await physics_frame
	var bed: Node3D = (interiors.get("_interior").beds as Array)[0].node
	interiors.rest(60.0, bed, true)
	await create_timer(0.6).timeout
	var along := bed.global_basis.z.normalized()
	var off: Vector3 = player.global_position - bed.global_position
	_expect(absf(off.dot(along) - 0.85) < 0.2 and absf(off.dot(bed.global_basis.x.normalized())) < 0.25, "te acuestas a lo largo de la cama, no de lado")
	var body_dir: Vector3 = player.call("facing_dir")
	_expect(body_dir.dot(along) > 0.8, "con la cabeza hacia la almohada")
	_expect(off.y > 0.15 and off.y < 0.45, "y sobre el colchón, sin flotar ni hundirte (%.2f)" % off.y)
	await create_timer(3.0).timeout
	await interiors.leave()
	await interiors.wait_idle()

	# 2. La escalera del faro: se sube andando
	await interiors.enter("faro", true)
	for i in 10:
		await physics_frame
	var hatch: Vector3 = interiors.get("_interior").hatch
	var start: Vector3 = player.global_position
	var t := 0.0
	var k := 0
	while t < 25.0 and player.global_position.y < hatch.y - 0.4:
		# sigue la hélice, peldaño a peldaño
		var a := 1.92 + TAU * (float(k) + 0.5) / 12.0
		var target := Vector3(cos(a) * 0.78, 0, sin(a) * 0.78) + Vector3(0, -400, 0)
		player.auto_walk_to(Vector3(target.x, player.global_position.y, target.z), 0.25)
		var tt := 0.0
		while tt < 2.0 and Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() > 0.35:
			await physics_frame
			tt += 1.0 / 60.0
		t += tt + 0.02
		k = mini(k + 1, 11) if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() <= 0.35 else k
	_expect(player.global_position.y > hatch.y - 0.6, "la escalera de caracol del faro se sube andando (llegas a %.1f m de %.1f)" % [player.global_position.y - start.y, hatch.y - start.y])
	player.cancel_auto_walk()
	await interiors.leave()
	await interiors.wait_idle()

	# 3. El balcón del modelo
	var balcony := ""
	for id in interiors.doors():
		if interiors.doors()[id].get("opts", {}).has("balcony_spot"):
			balcony = id
	_expect(not balcony.is_empty(), "el balcón se encuentra en el propio edificio")
	if not balcony.is_empty():
		var spot: Vector3 = interiors.doors()[balcony].opts.balcony_spot
		await interiors.enter(balcony, true)
		for i in 10:
			await physics_frame
		var bal := (interiors.get("_interior").uses as Array).filter(func(u): return u.get("what", "") == "balcony")
		interiors.use_fixture("balcony", bal[0].node)
		await create_timer(2.0).timeout
		for i in 60:
			await physics_frame
		_expect(player.global_position.distance_to(spot) < 0.7 and absf(player.global_position.y - spot.y) < 0.4, "sales al balcón del edificio y no te caes (a %.2f m)" % player.global_position.distance_to(spot))

	# 4. La puerta del faro a las 3:33
	if interiors.is_inside():
		await interiors.enter_at(balcony, "balcony_in")
		await interiors.leave()
		await interiors.wait_idle()
	var p: Dictionary = db.get_state("act0", {"talked": [], "awakening_ready": false})
	p["awakening_ready"] = true
	db.set_state("act0", p)
	town.call("_update_objective")
	var faro: Vector3 = interiors.door_position("faro")
	clock.set_hour(4.0)
	town.call("_update_objective")
	player.global_position = faro + Vector3(-3, 0.3, 3)
	for i in 10:
		await physics_frame
	player.global_position = faro + Vector3(0, 0.3, 0)
	for i in 40:
		await physics_frame
	_expect(town.get("_awakening") == null, "a las 4 a. m. la puerta del faro no hace nada")
	_expect(str(town.get("_ui").hud.get("_objective").text).contains("3:33 a. m."), "y el objetivo te dice que vuelvas a las 3:33 a. m.: %s" % town.get("_ui").hud.get("_objective").text)
	clock.set_hour(3.5)
	for i in 40:
		await physics_frame
	_expect(town.get("_awakening") != null, "a las 3:30 a. m., en la puerta del faro, empieza El Despertar")
	town.queue_free()
	await process_frame

	# 5. Las rocas del espacio son sólidas
	var space: Node3D = load("res://scenes/space/SpaceScene.tscn").instantiate()
	root.add_child(space)
	for i in 10:
		await physics_frame
	var ship = space.get("ship")
	var rocks: Array = space.get("_rocks")
	var big := 0
	for i in rocks.size():
		if (rocks[i] as Transform3D).basis.get_scale().x > (rocks[big] as Transform3D).basis.get_scale().x:
			big = i
	var rt: Transform3D = rocks[big]
	for speed in [30.0, 1500.0]:
		ship.global_position = rt.origin + Vector3(0, 0, -400)
		ship.set("_prev_ship_pos", Vector3.INF)
		space.set("_prev_ship_pos", Vector3.INF)
		ship.look_at(rt.origin, Vector3.UP)
		ship.rotate_object_local(Vector3.UP, PI)
		ship.velocity = (rt.origin - ship.global_position).normalized() * speed
		ship.assist = false
		var passed := false
		for i in (900 if speed < 100.0 else 60):
			await physics_frame
			if ship.global_position.z > rt.origin.z + 5.0:
				passed = true
		_expect(not passed, "volando hacia una roca a %d m/s, no la atraviesas" % int(speed))
	# 6. El viaje: mapa, cabina con radar y entrada en la atmósfera
	space.call("toggle_map")
	_expect(space.get("_map") != null, "M abre el mapa del sistema")
	(space.get("_map") as Node).call("emit_signal", "target_chosen", 2, false)
	_expect(int(space.get("_target")) == 2, "y un clic marca el destino")
	space.call("toggle_map")
	var contacts: Array = space.call("radar_contacts", ship.global_position)
	_expect(contacts.size() >= 5, "el radar ve planetas, lunas y naves (%d)" % contacts.size())
	ship.set_cockpit(true)
	await process_frame
	_expect(ship.get("_radar") != null and (ship.get("_buttons") as Dictionary).size() == 4, "la cabina tiene radar, asiento y pilotos que se iluminan")
	_expect(not (ship.get("_body") as Node3D).visible, "y desde dentro no tapa la vista el casco de fuera")
	ship.set_cockpit(false)
	var SS = load("res://scripts/space/StarSystem.gd")
	var home: Dictionary = {}
	for pl in (space.get("system") as Dictionary).planets:
		if pl.get("home", false):
			home = pl
	ship.global_position = SS.position_of(home) + Vector3(0, float(home.radius) + 300.0, 0)
	var d0: float = ship.global_position.distance_to(SS.position_of(home))
	await space.call("_atmosphere_entry", str(home.name))
	_expect(ship.global_position.distance_to(SS.position_of(home)) < d0, "al aterrizar, la nave entra en la atmósfera (desciende, con resplandor)")
	space.queue_free()
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

extends SceneTree
## Edificios realistas: casas con cuartos (recámara, baño, sala, cocina), escalera transitable
## y segundo piso en las altas, la puerta donde el modelo tiene la suya, fachadas con detalle y
## ventanas que se encienden solo si hay alguien despierto dentro.
##   godot --headless --path . -s tests/test_buildings.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de edificios")
	clock.set_hour(13.0)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var interiors = town.get("_interiors")
	var player = town.get("_player")
	var doors: Dictionary = interiors.doors()

	# Plantas: hay casas de una y de dos
	var one := ""
	var two := ""
	for id in doors:
		if doors[id].kind != "house":
			continue
		var f := int(doors[id].get("opts", {}).get("floors", 1))
		if f == 1 and one.is_empty():
			one = id
		elif f == 2 and two.is_empty():
			two = id
	_expect(not one.is_empty() and not two.is_empty(), "hay casas de una planta (%s) y de dos (%s)" % [one, two])

	# Una planta: la recámara y el baño son cuartos aparte (hay tabiques entre ellos y la sala)
	interiors.enter(one)
	await create_timer(1.6).timeout
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var bed: Dictionary = interiors.activity_spot("bed", 0)
	var sofa: Dictionary = interiors.activity_spot("sofa", 0)
	var q := PhysicsRayQueryParameters3D.create(bed.pos + Vector3(0, 1.2, 0), sofa.pos + Vector3(0, 1.2, 0), 1)
	_expect(not space.intersect_ray(q).is_empty(), "entre la cama y el sofá hay una pared: la recámara es un cuarto")
	var room: Node3D = interiors.get("_interior").root
	var names := room.find_children("*", "Node3D", true, false).map(func(n): return str(n.name))
	_expect(str(names).contains("Shower") or str(names).contains("Bathroom"), "y la casa tiene baño")

	# Dos plantas: se sube andando por la escalera y las camas están arriba
	interiors.enter(two)
	await create_timer(1.6).timeout
	var origin: Vector3 = Vector3(0, -400, 0)
	var bed2: Dictionary = interiors.activity_spot("bed", 0)
	_expect(not bed2.is_empty() and bed2.pos.y > origin.y + 2.5, "en la casa de dos plantas, las camas están arriba")
	var w := 10.0
	var d := 8.0
	player.global_position = origin + Vector3(-w / 2 + 0.75, 0.2, d / 2 - 0.4)
	await physics_frame
	player.auto_walk_to(origin + Vector3(-w / 2 + 0.75, 3.3, d / 2 - 0.7 - 4.6), 0.4)
	var t := 0.0
	while t < 12.0 and player.global_position.y < origin.y + 3.0:
		await physics_frame
		t += 1.0 / 60.0
	_expect(player.global_position.y > origin.y + 3.0, "el jugador sube la escalera andando (%.1f m en %.1f s)" % [player.global_position.y - origin.y, t])
	player.cancel_auto_walk()
	interiors.leave()
	await create_timer(1.2).timeout

	# La puerta donde la tiene el modelo (en las casas que la dejan ver)
	var found := 0
	for id in doors:
		if doors[id].kind in ["house", "home"] or load("res://scripts/world/Shops.gd").is_shop(doors[id].kind):
			found += 1
	_expect(found > 8, "las casas y negocios de la calle tienen su puerta registrada (%d)" % found)

	# Ventanas: de madrugada, todas las casas a oscuras; por la tarde, alguna con luz
	var windows: Dictionary = town.get("_windows")
	clock.set_hour(2.5)
	town.call("_update_windows")
	var lit_night := 0
	var Decor_ = load("res://scripts/world/Decor.gd")
	for id in windows:
		if doors[id].kind == "house" and Decor_._own_windows.get(windows[id], false):
			lit_night += 1
	clock.set_hour(19.5)
	town.call("_update_windows")
	var lit_evening := 0
	for id in windows:
		if doors[id].kind == "house" and Decor_._own_windows.get(windows[id], false):
			lit_evening += 1
	_expect(lit_night == 0 and lit_evening > 0, "de madrugada no hay luz en las casas; a las 19:30 sí en %d" % lit_evening)

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

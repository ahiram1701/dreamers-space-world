extends SceneTree
## v0.8.0: escaleras de verdad. En el faro se sube la escalera de caracol entera sin darte con el
## techo (tiene un hueco y un tubo hasta la trampilla), y los edificios de dos plantas tienen
## escalera hasta arriba, también las tiendas y la estación.
##   godot --headless --path . -s tests/test_stairs.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _clear(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.85
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), at + Vector3(0, 0.05 + cap.height / 2.0, 0))
	q.collision_mask = 0xFFFFFFFF
	return space.intersect_shape(q, 4).is_empty()


func _run() -> void:
	root.get_node("/root/Settings").use_mock = true
	var world := Node3D.new()
	root.add_child(world)
	var origin := Vector3(0, -400, 0)
	var Builder = load("res://procgen/InteriorBuilder.gd")
	var out: Dictionary = Builder.build(world, "lighthouse", 7, origin)
	for i in 4:
		await physics_frame
	var space := world.get_world_3d().direct_space_state
	# Cada peldaño de la escalera de caracol: cabe una persona de pie encima (sin techo)
	var blocked := []
	for i in 12:  # (v0.10: escalera centrada, sobre una rampa helicoidal)
		var a := 1.92 + TAU * (i + 0.5) / 12.0
		var top := origin + Vector3(cos(a) * 0.775, (i + 1) * 0.25 + 0.12, sin(a) * 0.775)
		if not _clear(space, top):
			blocked.append(i)
	_expect(blocked.is_empty(), "en el faro, de pie en cada peldaño no te das con el techo %s" % [blocked])
	var hatch := (out.uses as Array).filter(func(u): return u.get("what", "") == "climb_up")
	_expect(not hatch.is_empty() and (hatch[0].node as Node3D).global_position.y > origin.y + 2.5, "y arriba, al alcance, la trampilla de la linterna")
	world.queue_free()
	await process_frame

	# Una tienda y la estación de dos plantas: escalera transitable y planta de arriba
	for kind in ["shop", "station", "cafe", "house"]:
		var w2 := Node3D.new()
		root.add_child(w2)
		var o2: Dictionary = Builder.build(w2, kind, 3, origin, {"floors": 2})
		for i in 4:
			await physics_frame
		var sp := w2.get_world_3d().direct_space_state
		var room: Dictionary = Builder.ROOMS[kind]
		var w: float = room.size.x
		var d: float = room.size.y
		# Bajo los pies, a mitad de la escalera, hay algo que pisar (la rampa) a media altura
		var mid := origin + Vector3(-w / 2 + 0.75, 3.0, d / 2 - 0.7 - 2.1)
		var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid - Vector3(0, 4, 0)))
		var h: float = float(hit.position.y - origin.y) if not hit.is_empty() else -1.0
		_expect(h > 1.0 and h < 2.4, "%s de dos plantas: la escalera sube (a media escalera pisas a %.1f m)" % [kind, h])
		# Arriba hay suelo, y de pie en lo alto de la escalera cabes
		var up := origin + Vector3(1.5, Builder.HEIGHT + 1.0, 0.0)
		var floor_hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(up, up - Vector3(0, 2, 0)))
		_expect(not floor_hit.is_empty(), "%s: hay planta de arriba" % kind)
		var top2 := origin + Vector3(-w / 2 + 0.75, Builder.HEIGHT + 0.12, d / 2 - 0.7 - 4.2 - 0.3)
		_expect(_clear(sp, top2), "%s: en lo alto de la escalera cabes de pie" % kind)
		w2.queue_free()
		await process_frame
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:  # (que acabe lo pendiente: cerrar justo tras liberar la escena podía fallar)
		await process_frame
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

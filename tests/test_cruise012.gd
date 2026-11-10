extends SceneTree
## v0.12.0: el crucero (Shift) en el espacio frena solo ante un planeta o una luna y no vuelve a
## engancharse en diente de sierra; sin asistencia, al soltar Shift vuelve a su velocidad normal.
##   godot --headless --path . -s tests/test_cruise012.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba crucero")
	var ShipC = load("res://scripts/vehicles/Ship.gd")
	var Creations = load("res://scripts/agent/Creations.gd")
	var e: Dictionary = ShipC.factory()
	e["pos"] = [0.0, 0.0, 0.0]
	var saved: Dictionary = Creations.add(e)
	root.get_node("/root/Travel").launch(saved, [])
	var space: Node3D = load("res://scenes/space/SpaceScene.tscn").instantiate()
	root.add_child(space)
	current_scene = space
	await _frames(10)
	var ship = space.get("ship")
	var StarSystem = load("res://scripts/space/StarSystem.gd")
	var sys: Dictionary = space.get("system")
	var planet: Dictionary = {}
	for p in sys.planets:
		if p.kind != "station":
			planet = p
			break
	var c: Vector3 = StarSystem.position_of(planet)
	var r: float = float(planet.radius)

	# 1. En crucero hacia un planeta: frena antes de tocarlo
	var dir := Vector3(1, 0.2, 0.3).normalized()
	ship.global_position = c + dir * (r + 5000.0)
	ship.look_at(c, Vector3.UP)
	ship.rotate_object_local(Vector3.UP, PI)  # la nave mira hacia +z local
	ship.velocity = -dir * 1400.0
	var hull0: float = ship.hull
	Input.action_press("run")
	var min_alt := INF
	for i in 600:
		await physics_frame
		min_alt = minf(min_alt, ship.global_position.distance_to(c) - r)
	Input.action_release("run")
	_expect(min_alt > 60.0, "en crucero hacia un planeta, frena y no lo toca (lo más cerca: %.0f m)" % min_alt)
	_expect(ship.velocity.length() < 200.0, "y se queda casi parada (%.0f m/s)" % ship.velocity.length())
	_expect(ship.hull >= hull0 - 1.0, "sin dañar el casco (%.0f → %.0f)" % [hull0, ship.hull])

	# 2. Hacia una luna (no tiene cuerpo físico): también frena
	var moons: Array = space.get("_moons")
	if not moons.is_empty():
		var mc: Vector3 = (moons[0].node as Node3D).global_position
		var mr: float = float(moons[0].r)
		var md := (mc - c).normalized()
		ship.global_position = mc + md * (mr + 4000.0)
		ship.velocity = -md * 1400.0
		ship.hull = 100.0
		Input.action_press("run")
		var min_m := INF
		for i in 500:
			await physics_frame
			mc = (moons[0].node as Node3D).global_position
			min_m = minf(min_m, ship.global_position.distance_to(mc) - mr)
		Input.action_release("run")
		_expect(min_m > 40.0, "hacia una luna, también (lo más cerca: %.0f m)" % min_m)

	# 3. Sin asistencia, al soltar Shift vuelve a su velocidad normal
	ship.global_position = Vector3(0, 40000, 0)
	ship.assist = false
	ship.velocity = Vector3(0, 0, 1500)
	await _frames(240)
	_expect(ship.velocity.length() < 400.0, "sin asistencia, al soltar Shift baja de 1.5 km/s (%.0f m/s)" % ship.velocity.length())

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

extends SceneTree
## v0.9.0: el cuerpo y los vehículos de dos ruedas.
##  - Los escalones se suben andando (sin saltar).
##  - Caer de alto duele (y tumba); de poco, no.
##  - En la bici se pedalea (sin remo en la mano) y el gesto avanza; en la moto, postura de moto.
##  - Una moto o una bici que chocan no sueltan piezas de coche.
##   godot --headless --path . -s tests/test_physics_body.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba cuerpo")
	clock.set_hour(11.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await physics_frame
	var player = town.get("_player")

	# 1. Escalones: una plataforma de 0.25 m delante; se sube andando
	var base := Vector3(-60, town.ground_at(-60, -40), -40)
	var step := StaticBody3D.new()
	step.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.25, 4)
	cs.shape = box
	step.add_child(cs)
	town.add_child(step)
	step.global_position = base + Vector3(0, 0.125, -3.5)
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	player.auto_walk_to(base + Vector3(0, 0, -4.5), 0.3)
	var t := 0.0
	while t < 5.0 and player.global_position.y < base.y + 0.2:
		await physics_frame
		t += 1.0 / 60.0
	_expect(player.global_position.y > base.y + 0.2, "un escalón de 25 cm se sube andando, sin saltar (y = %.2f)" % (player.global_position.y - base.y))
	player.cancel_auto_walk()
	step.queue_free()

	# 2. Caídas: de 3 m no pasa nada; de 20 m duele y te tumba
	var hurt := []
	player.fell.connect(func(impact, dmg): hurt.append([impact, dmg]))
	var g := Vector3(-60, town.ground_at(-60, -60), -60)
	player.global_position = g + Vector3(0, 3.0, 0)
	player.velocity = Vector3.ZERO
	for i in 90:
		await physics_frame
	_expect(hurt.is_empty(), "saltar de 3 m no hace daño")
	var r0: float = root.get_node("/root/Body").get_need("rest")
	player.global_position = g + Vector3(0, 20.0, 0)
	player.velocity = Vector3.ZERO
	for i in 180:
		await physics_frame
	_expect(not hurt.is_empty() and int(hurt[-1][1]) > 0, "caer de 20 m duele (%s)" % [hurt])
	var r1: float = root.get_node("/root/Body").get_need("rest")
	_expect(r1 < r0, "y te deja molido (descanso %.0f → %.0f)" % [r0, r1])
	for i in 300:
		await physics_frame

	# 3. Bici: pedalear sin remo; moto: postura de moto
	var Creations = load("res://scripts/agent/Creations.gd")
	var all: Array = Creations.all_here()
	var bike_e: Dictionary = all.filter(func(e): return e.get("factory", "") == "bike")[0]
	var bike = Creations.node_of(town, bike_e.id)
	player.global_position = bike.global_position + Vector3(-1.2, 0.3, 0)
	bike._on_use(player)
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	var rig = player.get("_rig")
	_expect(rig.gesture() == "pedal", "en la bici se pedalea (%s)" % rig.gesture())
	_expect(rig.get("_tool") == null, "sin remo ni nada en la mano")
	_expect(float(rig.get("_gesture_t")) > 0.5, "y el pedaleo avanza (antes se reiniciaba cada frame)")
	Input.action_release("move_forward")
	_expect(absf(bike.global_rotation.z) < 0.35, "la bici sigue derecha (%.2f)" % bike.global_rotation.z)
	bike._on_use(player)
	for i in 10:
		await physics_frame
	var moto_e: Dictionary = all.filter(func(e): return e.get("factory", "") == "moto")[0]
	var moto = Creations.node_of(town, moto_e.id)
	player.global_position = moto.global_position + Vector3(-1.2, 0.3, 0)
	moto._on_use(player)
	for i in 20:
		await physics_frame
	_expect(rig.gesture() == "ride", "en la moto, postura de moto (%s)" % rig.gesture())
	moto._on_use(player)

	# 4. Restos de un choque según el vehículo
	var before := town.get_children().filter(func(c): return c.has_meta("debris")).size()
	moto.set("_prev_vel", Vector3(0, 0, 12))
	for i in 5:
		moto._debris(moto.global_position + Vector3(0, 1, 0))
	var pieces := town.get_children().filter(func(c): return c.has_meta("debris"))
	_expect(pieces.size() > before and pieces.all(func(c): return c.get_meta("debris") == "small"), "la moto suelta piezas de moto, no de coche (%d)" % (pieces.size() - before))
	var sedan_e: Dictionary = all.filter(func(e): return e.get("factory", "") == "sedan")[0]
	var sedan = Creations.node_of(town, sedan_e.id)
	sedan.set("_prev_vel", Vector3(0, 0, 12))
	for i in 5:
		sedan._debris(sedan.global_position + Vector3(0, 1, 0))
	_expect(town.get_children().any(func(c): return c.has_meta("debris") and c.get_meta("debris") == "kit"), "un coche, sus piezas de coche")

	# 5. Bici con brío; coches que no vuelcan; un coche volcado se endereza solo
	player.global_position = bike.global_position + Vector3(-1.2, 0.3, 0)
	bike._on_use(player)
	Input.action_press("move_forward")
	for i in 240:
		await physics_frame
	var bike_v: float = bike.speed()
	Input.action_release("move_forward")
	_expect(bike_v > 5.0, "la bici llega a %.1f m/s en 4 s (antes no pasaba de 1.9)" % bike_v)
	bike._on_use(player)
	for i in 10:
		await physics_frame
	var V = load("res://scripts/vehicles/Vehicle.gd")
	for kind in ["sedan", "suv"]:
		var ce: Dictionary = V.place_factory(town, kind, Vector3(-60, town.ground_at(-60, 20) + 0.3, 20), 0.0, "player")
		var c = Creations.node_of(town, ce.id)
		for i in 20:
			await physics_frame
		player.global_position = c.global_position + Vector3(-2.5, 0.3, 0)
		c._on_use(player)
		c.linear_velocity = c.global_basis.z * 15.0
		Input.action_press("move_forward")
		Input.action_press("move_left")
		var min_up := 1.0
		for i in 150:
			await physics_frame
			min_up = minf(min_up, c.global_basis.y.dot(Vector3.UP))
		Input.action_release("move_left")
		Input.action_release("move_forward")
		_expect(min_up > 0.6, "%s a 54 km/h con el volante a tope: no vuelca (inclinación mín. %.2f)" % [kind, min_up])
		c._on_use(player)
		for i in 10:
			await physics_frame
		if kind == "sedan":
			c.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), c.global_position + Vector3(0, 1.5, 0))
			c.linear_velocity = Vector3.ZERO
			for i in 300:
				await physics_frame
			_expect(c.global_basis.y.dot(Vector3.UP) > 0.8, "un coche volcado, sin nadie dentro, se endereza solo")

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

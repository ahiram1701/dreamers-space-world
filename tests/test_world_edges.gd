extends SceneTree
## v0.7.1: el mundo no tiene borde. Del pueblo se puede ir caminando (o en coche) tan lejos como
## quieras: el terreno se genera por trozos a tu alrededor (colinas, montañas, el mar con islas) y
## se suelta al alejarte. En un planeta, igual. Y nunca caes al vacío.
##   godot --headless --path . -s tests/test_world_edges.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _ground_under(scene: Node3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 200, 0), p - Vector3(0, 400, 0), Layers.WORLD)
	q.exclude = scene.get_tree().get_nodes_in_group("player").map(func(n): return (n as CollisionObject3D).get_rid())
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else -INF


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba bordes")
	clock.set_hour(12.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 12:
		await process_frame
	var player = town.get("_player")
	var terrain: Node = town.get_tree().get_nodes_in_group("chunk_terrain")[0]

	# Caminar hacia el oeste, mucho más allá de donde antes acababa el mapa (x = -110)
	var lowest := INF
	for x in [-130.0, -200.0, -300.0, -420.0]:
		var at := Vector3(x, 0, -10)
		at.y = town.ground_at(at.x, at.z) + 1.0
		player.global_position = at
		player.velocity = Vector3.ZERO
		var t := 0.0
		while t < 6.0 and not terrain.has_ground(at.x, at.z):
			await process_frame
			t += 1.0 / 60.0
		for i in 30:
			await physics_frame
		lowest = minf(lowest, player.global_position.y - town.ground_at(player.global_position.x, player.global_position.z))
		_expect(_ground_under(town, player.global_position) > -50.0, "a x = %d hay suelo bajo tus pies" % x)
	_expect(lowest > -1.0, "y nunca te hundes ni caes (%.2f m)" % lowest)
	var far: float = town.ground_at(-700.0, -10.0)
	_expect(far > 6.0, "tierra adentro el relieve sube hasta montañas (%.0f m a 700 m)" % far)
	var wet := 0
	for k in 20:
		if town.ground_at(250.0 + k * 40.0, -60.0 + k * 7.0) < -0.45:
			wet += 1
	_expect(wet >= 14, "al este sigue el mar abierto, con alguna isla (%d de 20 puntos bajo el agua)" % wet)
	var chunks := terrain.get_children().filter(func(c): return str(c.name).begins_with("Trozo_")).size()
	_expect(chunks > 0 and chunks < 90, "los trozos lejanos se sueltan (hay %d)" % chunks)
	# El mar va contigo
	player.global_position = Vector3(330, -0.2, 10)
	for i in 20:
		await process_frame
	var sea: Node3D = terrain.get_node_or_null("Mar")
	_expect(sea != null and sea.global_position.distance_to(Vector3(player.global_position.x, sea.global_position.y, player.global_position.z)) < 64.0, "el mar no se acaba: va contigo")
	town.queue_free()
	await process_frame

	# Un planeta: también sin borde
	var def: Dictionary = root.get_node("/root/ContentGenerator").load_fallback("location")
	def["biome"] = "temperate"
	var loc_id: String = db.add_entity("location", def, "test", "test_planeta")
	root.get_node("/root/GameState").set_location(loc_id)
	var gen: Node3D = load("res://scenes/generated_location/GeneratedLocation.tscn").instantiate()
	root.add_child(gen)
	for i in 12:
		await process_frame
	var p2 = gen.get("_player")
	_expect(_ground_under(gen, p2.global_position) > -50.0, "en un planeta apareces sobre suelo")
	var go := Vector3(320, 0, 260)
	go.y = gen.ground_at(go.x, go.z) + 1.0
	p2.global_position = go
	var t2 := 0.0
	var gt: Node = gen.get_tree().get_nodes_in_group("chunk_terrain")[0]
	while t2 < 6.0 and not gt.has_ground(go.x, go.z):
		await process_frame
		t2 += 1.0 / 60.0
	for i in 30:
		await physics_frame
	_expect(_ground_under(gen, p2.global_position) > -50.0 and absf(p2.global_position.x - go.x) < 5.0, "lejos del centro (%d m) sigues teniendo suelo y nadie te frena" % int(Vector2(go.x, go.z).length()))
	gen.queue_free()
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

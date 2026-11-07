extends SceneTree
## Nunca atrapado: al salir de cualquier edificio apareces en un hueco libre, ningún arbusto tapa
## una puerta y, si te quedas metido dentro de algo, te despegas al intentar moverte.
##   godot --headless --path . -s tests/test_unstuck.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de atascos")
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 5:
		await physics_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")
	var IM = load("res://scripts/world/InteriorManager.gd")

	# Ningún arbusto delante de una puerta
	var doors: Dictionary = interiors.doors()
	var blocked := []
	for f in town.get("_features"):
		if f.kind != "bush":
			continue
		for id in doors:
			var d: Dictionary = doors[id]
			var out := Vector3(sin(d.yaw), 0, cos(d.yaw))
			var exit_at: Vector3 = d.pos + out * 1.2
			if Vector2(f.pos.x - exit_at.x, f.pos.z - exit_at.z).length() < 2.0:
				blocked.append(id)
	_expect(blocked.is_empty(), "ningún arbusto tapa la salida de una puerta %s" % str(blocked))

	# Salir de cada edificio deja al jugador en un hueco libre
	var stuck := []
	for id in doors:
		interiors.enter(id)
		for i in 30:
			await physics_frame
		interiors.leave()
		for i in 30:
			await physics_frame
		if not IM.is_free(player, player.global_position + Vector3(0, 0.05, 0), [player], 0.26):
			stuck.append(id)
	_expect(stuck.is_empty() and doors.size() > 3, "al salir de los %d edificios no quedas dentro de nada %s" % [doors.size(), str(stuck)])

	# Metido dentro de un arbusto: al empujar, te despegas
	var bush_pos := Vector3.INF
	for f in town.get("_features"):
		if f.kind == "bush" and is_instance_valid(f.node):
			bush_pos = f.node.global_position
			break
	_expect(bush_pos != Vector3.INF, "hay arbustos en el pueblo")
	if bush_pos != Vector3.INF:
		player.set_physics_process(false)  # sin la física normal: solo lo saca el despegue
		player.global_position = bush_pos + Vector3(0, 0.1, 0)
		await physics_frame
		_expect(not IM.is_free(player, player.global_position + Vector3(0, 0.05, 0), [player], 0.26), "el jugador empieza metido en el arbusto")
		var t := 0.0
		while t < 2.0 and not IM.is_free(player, player.global_position + Vector3(0, 0.05, 0), [player], 0.26):
			player.call("_check_stuck", Vector3(1, 0, 0), 4.0, player.global_position, 1.0 / 60.0)
			await physics_frame
			t += 1.0 / 60.0
		_expect(IM.is_free(player, player.global_position + Vector3(0, 0.05, 0), [player], 0.26), "empujando, se despega en %.1f s" % t)
		player.set_physics_process(true)

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

extends SceneTree
## Con qué interactúa E cuando hay varias cosas cerca: la persona a la que miras gana a la silla
## de al lado, salir de una zona no deja al jugador sin objetivo, y una pared tapa lo de detrás.
##   godot --headless --path . -s tests/test_interaction.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de interacción")
	var npc_entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json"))[0]
	db.add_entity("npc", npc_entry.entity, "act0:base", npc_entry.id)

	var scene := Node3D.new()
	root.add_child(scene)
	_floor(scene)
	var player = load("res://scripts/player/Player.gd").new()
	scene.add_child(player)
	player.position = Vector3(0, 0.1, 0)
	player.look_direction(Vector3(0, 0, -1))  # mira hacia -Z

	# Una persona delante y una silla un poco a la derecha, las dos a mano
	var npc = load("res://scripts/npc/TownNPC.gd").new()
	scene.add_child(npc)
	npc.position = Vector3(0, 0.1, -1.6)
	npc.setup(db.get_entity("npc", npc_entry.id))
	var seat := Node3D.new()
	scene.add_child(seat)
	seat.position = Vector3(0.9, 0, -0.6)
	var used := []
	var interactable = load("res://scripts/world/Interactable.gd")
	var chair = interactable.create(seat, Vector3(0, 0.5, 0), 1.0, "Sentarse", func(_p): used.append("silla"), seat)
	await _frames(6)
	_expect(player.interaction.candidates().size() == 2, "las dos zonas se apuntan (%d)" % player.interaction.candidates().size())
	_expect(player.interact_target == npc, "mirando a la persona, gana la persona y no la silla")

	# Mirando a la silla, gana la silla
	player.look_direction(Vector3(0.9, 0, -0.6).normalized())
	await _frames(3)
	_expect(player.interact_target == chair, "mirando a la silla, gana la silla")

	# Al salir de la zona de la silla, la persona sigue siendo el objetivo (antes se perdía)
	player.look_direction(Vector3(0, 0, -1))
	seat.position = Vector3(8, 0, 0)
	await _frames(6)
	_expect(player.interact_target == npc, "salir de una zona no deja sin objetivo")

	# Una pared entre el jugador y una puerta: no se elige lo que no se ve
	npc.position = Vector3(20, 0.1, 0)
	var door = interactable.create(scene, Vector3(0, 1.0, -2.2), 2.5, "Salir", func(_p): used.append("puerta"))
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(4, 3, 0.2)
	wall.add_child(cs)
	scene.add_child(wall)
	wall.position = Vector3(0, 1.5, -1.0)
	await _frames(6)
	_expect(player.interact_target == null, "con una pared en medio no se elige nada")
	wall.queue_free()
	await _frames(4)
	_expect(player.interact_target == door, "sin la pared, la puerta")

	# De espaldas, lo de detrás no cuenta (salvo que esté pegado)
	player.look_direction(Vector3(0, 0, 1))
	await _frames(3)
	_expect(player.interact_target == null, "de espaldas no se elige lo de detrás")

	scene.queue_free()
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(60, 0.2, 60)
	body.add_child(cs)
	body.position.y = -0.1
	parent.add_child(body)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

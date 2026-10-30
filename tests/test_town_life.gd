extends SceneTree
## La gente del pueblo ve lo que haces y se lo cuenta: un testigo con visión se entera, uno detrás
## de una pared no; al pasar una hora, quien coincide con el testigo lo sabe por él (una vez).
##   godot --headless --path . -s tests/test_town_life.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var memory = root.get_node("/root/NPCMemory")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de vida del pueblo")
	root.get_node("/root/WorldClock").set_hour(15)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 5:
		await process_frame
	var npcs: Dictionary = town.get("_npcs")
	var life = town.get("_life")
	# Marina mira desde campo abierto; Samir, al otro lado de una casa
	var spot := Vector3(-5, 0.3, 30)
	npcs["npc_teo"].global_position = spot
	npcs["npc_marina"].global_position = spot + Vector3(0, 0, 8)
	npcs["npc_samir"].global_position = Vector3(300, 0.3, 300)
	for id in npcs:
		npcs[id].call("stop")
	for i in 4:
		await physics_frame
	var saw: Array = life.witness("el jugador le dio un puñetazo a Teo", spot, ["npc_teo"])
	_expect(saw == ["npc_marina"], "Marina lo ve; Samir, lejos, no %s" % [saw])
	_expect(memory.describe_recent("npc_marina").contains("puñetazo"), "Marina lo recuerda")
	_expect(not memory.describe_recent("npc_samir").contains("puñetazo"), "Samir no sabe nada aún")

	# Samir se encuentra con Marina: al pasar la hora, se entera por ella
	npcs["npc_samir"].global_position = spot + Vector3(2, 0, 8)
	for i in 2:
		await physics_frame
	var passed: int = life.gossip()
	_expect(passed >= 1 and memory.describe_recent("npc_samir").contains("Marina te contó"), "Samir lo sabe por Marina (%d rumores)" % passed)
	var again: int = life.gossip()
	var count := 0
	for e in memory.get_mem("npc_samir").recent:
		if "puñetazo" in e.text:
			count += 1
	_expect(count == 1, "el rumor no se repite (%d, %d)" % [count, again])

	# Actividades: cada uno hace lo suyo en su sitio
	_expect(not str(npcs["npc_teo"].activity).is_empty() or not str(npcs["npc_samir"].activity).is_empty(), "los vecinos tienen actividad")

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

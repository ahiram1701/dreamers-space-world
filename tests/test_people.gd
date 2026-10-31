extends SceneTree
## Cómo se mueve y se comunica la gente: no te escribe quien está contigo, te lleva a un sitio
## saliendo por la puerta (y te espera si te quedas atrás), y despedirse deja constancia.
##   godot --headless --path . -s tests/test_people.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var settings = root.get_node("/root/Settings")
	var phone = root.get_node("/root/Phone")
	var memory = root.get_node("/root/NPCMemory")
	settings.use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de gente")
	root.get_node("/root/WorldClock").set_hour(14)  # Samir está en la estación
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")
	var samir = town.get("_npcs")["npc_samir"]
	interiors.enter("station")
	await create_timer(1.5).timeout
	_expect(interiors.is_inside() and samir.is_present() and samir.global_position.y < -300, "Samir está dentro de la estación contigo")
	_expect(phone.is_near.call("npc_samir"), "el celular sabe que está contigo")
	phone.send("npc_samir", "¿Me llevas al muelle?")
	await create_timer(0.3).timeout
	_expect(phone.messages("npc_samir").filter(func(m): return m.from == "npc").is_empty(), "no te contesta por chat estando delante")
	_expect(phone.call_refusal("npc_samir").contains("contigo"), "llamarle: «está aquí contigo»")

	# Despedirse deja constancia
	town.call("_start_dialogue", samir)
	await create_timer(0.5).timeout
	town.get("_dialogue").close()
	await process_frame
	_expect(float(memory.get_mem("npc_samir").get("last_talk", -1)) >= 0.0 and memory.describe_recent("npc_samir").contains("Acabas de hablar"), "despedirse deja el recuerdo de la charla")

	# Llevarte al muelle: sale por la puerta, aparece fuera y espera si te quedas atrás
	Engine.time_scale = 4.0
	town.call("guide", "npc_samir", "el muelle")
	var t := 0.0
	while samir.global_position.y < -300 and t < 30.0:
		await process_frame
		t += 1.0 / 60.0
	_expect(samir.global_position.y > -50, "Samir sale de la estación por la puerta (%.1f s)" % t)
	interiors.leave()
	await create_timer(1.2).timeout
	# El jugador se queda quieto lejos: Samir espera
	player.global_position = samir.global_position + Vector3(-15, 0.5, 0)
	await create_timer(1.0).timeout
	_expect(samir.is_paused(), "si te quedas atrás, te espera")
	# El jugador le sigue de cerca hasta que llega
	t = 0.0
	while town.get("_guiding").has("npc_samir") and t < 120.0:
		var d: Vector3 = samir.global_position - player.global_position
		player.global_position = samir.global_position - d.normalized() * 2.0 + Vector3(0, 0.5, 0)
		await create_timer(0.25).timeout
		t += 0.25
	var muelle: Vector3 = town.get("_places")["muelle"]
	_expect(not town.get("_guiding").has("npc_samir") and Vector2(samir.global_position.x - muelle.x, samir.global_position.z - muelle.z).length() < 6.0,
		"llegáis juntos al muelle (%s)" % samir.global_position)
	_expect(memory.describe_recent("npc_samir").contains("Llevaste al jugador"), "Samir recuerda que te llevó")
	# Un sitio que no existe: lo dice
	town.call("guide", "npc_samir", "el aeropuerto")
	_expect(not town.get("_guiding").has("npc_samir") and memory.describe_recent("npc_samir").contains("no sabes dónde"), "a un sitio que no existe no te lleva")
	Engine.time_scale = 1.0

	town.queue_free()
	await process_frame
	settings.use_mock = false
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

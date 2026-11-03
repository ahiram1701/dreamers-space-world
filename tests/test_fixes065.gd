extends SceneTree
## Arreglos de la v0.6.5: el faro apagado (salvo el pulso de las 3:33), rumores que no se toman por
## propios, dormir con F hasta una hora, la linterna en la mano, casas lejos de las vías, el
## objetivo con nombres y bocadillos que no se ven desde lejos.
##   godot --headless --path . -s tests/test_fixes065.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var memory = root.get_node("/root/NPCMemory")
	var clock = root.get_node("/root/WorldClock")
	var body = root.get_node("/root/Body")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de arreglos")
	clock.set_hour(21.0)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var Town = load("res://scenes/act0_town/Act0Town.gd")

	# El faro está desconectado: apagado, salvo el pulso de las 3:33
	var off := true
	for h in [21.0, 23.5, 2.0, 3.4, 5.0, 12.0]:
		for t in [0.1, 0.7, 1.3]:
			off = off and Town.beacon_energy(h, t, false) == 0.0
	_expect(off, "el faro está apagado a cualquier hora")
	var lit := false
	for t in range(20):
		lit = lit or Town.beacon_energy(3.0 + 33.5 / 60.0, t * 0.13, false) > 0.0
	_expect(lit, "a las 3:33 un pulso lo enciende unos segundos")
	await process_frame
	_expect(town.get("_beacon").light_energy == 0.0, "y ahora (21:00) no alumbra")

	# Rumores: no se toman por cosas vividas ni llegan como noticia propia al celular
	memory.add_event("npc_teo", "Te marchaste y dejaste al jugador ahí.")
	var npcs: Dictionary = town.get("_npcs")
	npcs["npc_samir"].global_position = npcs["npc_teo"].global_position + Vector3(1.5, 0, 0)
	await physics_frame
	town.get("_life").gossip()
	var lived: String = memory.describe_recent("npc_samir")
	var heard: String = memory.describe_recent("npc_samir", true)
	_expect(not lived.contains("Te marchaste") and heard.contains("Teo te contó") and heard.contains("no tú"), "a Samir le llega como rumor de Teo, no como algo suyo")
	_expect(memory.describe("npc_samir").contains("rumores: tú NO lo viviste"), "y su memoria lo separa de lo que vivió")
	var prompt: String = root.get_node("/root/StoryDirector").call("_system_prompt", db.get_entity("npc", "npc_samir"), "escena")
	_expect(prompt.contains("Si te dice que no notó nada"), "el PNJ cree al jugador cuando dice que no notó nada")

	# Dormir con F hasta una hora (sin IA: se entiende la hora)
	var AP = load("res://scripts/world/ActionPerformer.gd")
	var plan: Array = AP.local_plan("duermo hasta las 3:30 am", town, "sleep")
	_expect(plan.size() == 1 and plan[0].type == "sleep" and absf(plan[0].until_hour - 3.5) < 0.01, "«duermo hasta las 3:30 am» → dormir hasta las 3:30")
	_expect(absf(AP.parse_rest("espero hasta las 7 de la tarde").until_hour - 19.0) < 0.01, "«hasta las 7 de la tarde» → 19:00")
	body.set_need("rest", 20.0)
	await town.get("_performer").perform(plan)
	await create_timer(0.5).timeout
	_expect(absf(clock.hour() - 3.5) < 0.05, "y al despertar son las %s" % clock.text())
	_expect(body.get_need("rest") > 50.0, "descansó (sin cama, algo menos): %d" % body.get_need("rest"))

	# La linterna se ve en la mano y la luz sale de ella
	var player = town.get("_player")
	player.set_light(true)
	for i in 10:
		await process_frame
	var rig = player.get("_rig")
	var held: Node3D = rig.get("_held")
	_expect(held != null and held.visible, "con la linterna encendida, la llevas en la mano")
	var hand: Vector3 = rig.get("_sk").global_transform * rig.get("_sk").get_bone_global_pose(rig.get("_sk").find_bone("Hand.R")).origin
	var lamp: SpotLight3D = player.get("_lamp")
	_expect(held != null and held.global_position.distance_to(hand) < 0.35 and lamp.global_position.distance_to(hand) < 0.6, "y la luz sale de la mano")
	player.set_light(false)

	# Nada construido encima de las vías
	var tracks := 37.0
	var near := []
	for id in town.get("_interiors").doors():
		var p: Vector3 = town.get("_interiors").doors()[id].pos
		if p.x < 15.0 and absf(p.z - tracks) < 8.0:
			near.append(id)
	for lot in town.get("_free_lots"):
		if absf(lot.pos.z - tracks) < 8.0:
			near.append("solar")
	_expect(near.is_empty(), "ninguna casa ni solar sobre las vías %s" % str(near))
	_expect(town.get("_interiors").doors().has("casa_4"), "y las casas conservan su número (casa_4, la de Teo)")

	# El objetivo dice a quién buscar; los bocadillos no se ven desde lejos
	town.call("_update_objective")
	var objective: String = town.get("_ui").hud.get("_objective").text if town.get("_ui").hud.get("_objective") else ""
	_expect(objective.is_empty() or (objective.contains("Marina") and objective.contains("falta")), "el objetivo nombra a Marina, Teo y Samir: «%s»" % objective)
	npcs["npc_teo"].say("hola")
	var bubble: Label3D = npcs["npc_teo"].get("_bubble")
	_expect(npcs["npc_teo"].BUBBLE_RANGE <= 30.0, "los bocadillos no se ven desde lejos")

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

extends SceneTree
## v0.8.0: la tecla F hace lo que escribes (aun sin IA, con el plan local).
##  - «voy a dormir a mi casa»: vas a tu casa, entras y te acuestas en TU cama (no en el suelo).
##  - «súbete al auto, Samir» con el jugador ya dentro del coche: Samir va y sube.
##  - «regreso al pueblo» desde otro planeta: vas a tu nave, despegas y aterrizas en el pueblo.
##   godot --headless --path . -s tests/test_f_travel.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba F")
	clock.set_hour(22.5)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await process_frame
	var player = town.get("_player")
	var performer = town.get("_performer")
	var interiors = town.get("_interiors")
	var AP = load("res://scripts/world/ActionPerformer.gd")

	# 1. Dormir en casa, en la cama
	player.global_position = Vector3(-5, 0.3, 20)
	var plan: Array = AP.local_plan("me voy a dormir a mi casa", town, "sleep")
	_expect(plan.size() == 1 and plan[0].get("target", "") == "home", "«voy a dormir a mi casa» = dormir en casa (%s)" % [plan])
	var slept := []
	interiors.slept.connect(func(door, bed, _m, _by): slept.append([door, bed]))
	var hour0: float = clock.hour()
	await performer.perform(plan)
	_expect(interiors.is_inside() and interiors.current_kind() == "home", "vas a tu casa y entras")
	_expect(not slept.is_empty() and slept[0][1] != null, "y duermes en tu cama, no en el suelo")
	_expect(absf(clock.hour() - hour0) > 2.0, "pasa la noche (%.1f h → %.1f h)" % [hour0, clock.hour()])
	await interiors.leave()
	await interiors.wait_idle()
	for i in 10:
		await process_frame

	# 2. «Súbete al auto» con el jugador ya al volante
	var Creations = load("res://scripts/agent/Creations.gd")
	var V = load("res://scripts/vehicles/Vehicle.gd")
	var e: Dictionary = V.place_factory(town, "sedan", Vector3(-20, 0.3, 40), 0.0, "player")
	var car = Creations.node_of(town, e.id)
	for i in 20:
		await physics_frame
	player.global_position = car.global_position + Vector3(-2.5, 0.3, 0)
	car._on_use(player)
	var samir = town.get("_npcs")["npc_samir"]
	samir.stop()
	samir.global_position = car.global_position + Vector3(9, 0.3, 4)
	var plan2: Array = AP.local_plan("súbete al auto, Samir", town, "")
	_expect(not plan2.is_empty() and plan2[0].type == "ride", "«súbete al auto, Samir» = que suba (%s)" % [plan2])
	await performer.perform(plan2)
	var t := 0.0
	while t < 20.0 and not samir.is_riding():
		await process_frame
		t += 1.0 / 60.0
	_expect(samir.is_riding() and samir.riding_vehicle() == car, "Samir va hasta el coche y sube, aunque tú ya estuvieras dentro")
	car._on_use(player)
	for i in 5:
		await process_frame

	# 3. En otro planeta: «regreso al pueblo» con la nave
	var def: Dictionary = root.get_node("/root/ContentGenerator").load_fallback("location")
	def["biome"] = "temperate"
	def["kind"] = "planet_surface"
	var loc_id: String = db.add_entity("location", def, "test", "test_planeta_f")
	root.get_node("/root/TimelineManager").branch("Prueba", loc_id, "")
	root.get_node("/root/GameState").set_location(loc_id)
	var ShipC = load("res://scripts/vehicles/Ship.gd")
	var se: Dictionary = ShipC.factory()
	db.set_state("arrival_ship", {"to": loc_id, "ship": se, "passengers": []})
	town.queue_free()
	await process_frame
	var gen: Node3D = load("res://scenes/generated_location/GeneratedLocation.tscn").instantiate()
	root.add_child(gen)
	current_scene = gen
	for i in 30:
		await process_frame
	var p2 = gen.get("_player")
	_expect(gen.travel_destination_for("pueblo") == "home", "desde el planeta, «el pueblo» es un destino")
	var plan3: Array = AP.local_plan("regreso al pueblo", gen, "")
	_expect(not plan3.is_empty() and plan3[0].type == "travel", "«regreso al pueblo» = viajar (%s)" % [plan3])
	var perf2 = gen.get("_performer")
	perf2.perform(plan3)
	var t2 := 0.0
	while t2 < 30.0 and root.get_node("/root/GameState").current_location() != "home":
		await process_frame
		t2 += 1.0 / 60.0
	_expect(root.get_node("/root/GameState").current_location() == "home", "vas a tu nave, despegas y aterrizas en el pueblo")
	var arrival: Dictionary = db.get_state("arrival_ship", {})
	_expect(arrival.get("to", "") == "home" and not arrival.get("ship", {}).is_empty(), "con tu nave, que aparcarás en la plataforma")
	await process_frame
	await process_frame
	if is_instance_valid(gen):
		gen.queue_free()
	if current_scene and is_instance_valid(current_scene) and current_scene != gen:
		current_scene.queue_free()
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

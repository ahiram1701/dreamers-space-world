extends SceneTree
## v0.10.0: la tecla F hace más cosas de verdad.
##  - «enciendo la tele»: la tele queda encendida (y se ve).
##  - «manejo hasta la granja»: llegas en tu coche, con menos gasolina.
##  - «compro pan»: vas a la tienda y lo compras (dinero y objeto).
##  - «llamo a Marina»: la llamas por teléfono.
##  - aprender: queda en tu perfil.
##  - Los pasos nuevos los acepta el validador de la IA (antes, «viajar» o «subir» se perdían).
##   godot --headless --path . -s tests/test_f_more.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba F 010")
	clock.set_hour(10.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	root.get_node("/root/Wallet").earn(50)
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await physics_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")
	var performer = town.get("_performer")
	var AP = load("res://scripts/world/ActionPerformer.gd")
	var CV = root.get_node("/root/ContentValidator")

	# 0. El validador acepta los pasos nuevos
	var arch: Dictionary = CV.archetypes()
	_expect(["travel", "ride", "land", "interact", "drive_to", "buy", "call", "swim_to", "learn"].all(func(t): return t in arch.npc_action), "la IA puede usar viajar, subir, aterrizar, usar cosas, conducir, comprar, llamar, nadar y aprender")

	# 1. Encender la tele
	await interiors.enter(interiors.door_of_kind("home"), true)
	for i in 10:
		await physics_frame
	var plan: Array = AP.local_plan("enciendo la tele", town, "")
	_expect(not plan.is_empty() and plan[0].type == "interact", "«enciendo la tele» = usar la tele (%s)" % [plan])
	await performer.perform(plan)
	var tv: Node3D = null
	for t in town.get_tree().get_nodes_in_group("things"):
		if str(t.get_meta("thing", "")) == "la tele":
			tv = t
	_expect(tv != null and bool(tv.get_meta("toggle_on", false)), "y la tele queda encendida")
	await interiors.leave()
	await interiors.wait_idle()

	# 2. Comprar pan
	var money0: int = root.get_node("/root/Wallet").amount()
	var items0: int = root.get_node("/root/Inventory").items().size()
	plan = AP.local_plan("compro pan", town, "")
	var notes: Array = await performer.perform(plan)
	_expect(root.get_node("/root/Inventory").items().size() == items0 + 1 and root.get_node("/root/Wallet").amount() < money0, "«compro pan»: vas a la tienda y lo compras (%s)" % [notes])
	if interiors.is_inside():
		await interiors.leave()
		await interiors.wait_idle()

	# 3. Ir en coche a la granja
	var Creations = load("res://scripts/agent/Creations.gd")
	var V = load("res://scripts/vehicles/Vehicle.gd")
	var ce: Dictionary = V.place_factory(town, "sedan", player.global_position + Vector3(4, 0.3, 0), 0.0, "player")
	var car = Creations.node_of(town, ce.id)
	for i in 20:
		await physics_frame
	var fuel0: float = car.fuel
	plan = AP.local_plan("manejo hasta la granja", town, "")
	_expect(not plan.is_empty() and plan[0].type == "drive_to", "«manejo hasta la granja» = conducir (%s)" % [plan])
	await performer.perform(plan)
	var farm: Vector3 = town.place_position("la granja")
	_expect(player.riding == car and car.global_position.distance_to(farm) < 15.0, "llegas a la granja en tu coche (a %.0f m)" % car.global_position.distance_to(farm))
	_expect(car.fuel < fuel0, "y gastas gasolina")
	car._on_use(player)

	# 4. Llamar a Marina
	root.get_node("/root/NPCMemory").set_fields("npc_marina", {"met": true})
	plan = AP.local_plan("llamo a Marina", town, "")
	_expect(not plan.is_empty() and plan[0].type == "call", "«llamo a Marina» = llamarla (%s)" % [plan])

	# 5. Aprender
	var r: Array = await performer.perform([{"type": "learn", "item_name": "hacer café de olla", "target": "npc:npc_teo"}])
	_expect(root.get_node("/root/PlayerProfile").skills().any(func(x): return str(x.skill).contains("café")), "lo que aprendes queda (%s)" % [r])
	_expect(root.get_node("/root/PlayerProfile").describe().contains("Sabe hacer"), "y la IA lo sabe")
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

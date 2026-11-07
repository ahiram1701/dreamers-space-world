extends SceneTree
## v0.9.0: la cafetería atiende bien.
##  - Pides varias cosas de la carta (no se cierra al pedir una) y te las traen juntas.
##  - Lo que se bebe llega en vaso o taza; lo que se come, en plato.
##  - La mesera no se sube a la barra ni a las mesas.
##  - Desde la mesa puedes llamar a la mesera para pedir más.
##   godot --headless --path . -s tests/test_service.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba servicio")
	clock.set_hour(10.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	root.get_node("/root/Wallet").earn(200)
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await physics_frame
	var player = town.get("_player")
	var interiors = town.get("_interiors")
	var LS = load("res://scenes/common/LocationScene.gd")
	_expect(LS.is_drink({"name": "Agua", "effect": "hydrate"}) and LS.is_drink({"name": "Café de olla", "effect": "nourish"}) and not LS.is_drink({"name": "Molletes", "effect": "nourish"}), "sabe qué se bebe y qué se come")

	player.global_position = Vector3(20, 0.5, 18)
	await create_timer(0.5).timeout
	await interiors.enter(interiors.door_of_kind("cafe"), true)
	for i in 60:
		await physics_frame
	var floor_y: float = player.global_position.y
	var seats: Array = interiors.get("_interior").seats
	interiors.sit(seats[seats.size() - 1].node)
	var max_staff_y := -INF
	var panel: Node = null
	var t := 0.0
	while t < 20.0 and panel == null:
		await physics_frame
		t += 1.0 / 60.0
		for c in town.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("ShopPanel.gd"):
				panel = c
		for n in town.get("_npcs").values():
			if n.global_position.y < -200.0:
				max_staff_y = maxf(max_staff_y, n.global_position.y - floor_y)
	_expect(panel != null, "al sentarte viene la mesera con la carta")
	if panel:
		var items: Array = panel.get("items")
		var water: Dictionary = {}
		var food: Dictionary = {}
		for it in items:
			if LS.is_drink(it) and water.is_empty():
				water = it
			elif not LS.is_drink(it) and food.is_empty():
				food = it
		panel.call("_buy", water)
		await process_frame
		_expect(is_instance_valid(panel) and panel.is_inside_tree(), "pedir una cosa no cierra la carta")
		panel.call("_buy", food)
		await process_frame
		panel.call("close")
	var served := []
	t = 0.0
	while t < 40.0 and served.size() < 2:
		await physics_frame
		t += 1.0 / 60.0
		served = town.get_children().filter(func(c): return c.has_meta("served"))
		for n in town.get("_npcs").values():
			if n.global_position.y < -200.0:
				max_staff_y = maxf(max_staff_y, n.global_position.y - floor_y)
	var kinds := served.map(func(c): return str(c.get_meta("served")))
	_expect(served.size() >= 2, "te traen las dos cosas juntas (%s)" % [kinds])
	_expect(kinds.any(func(k): return k in ["vaso", "taza"]) and kinds.has("plato"), "la bebida en vaso o taza y la comida en plato (%s)" % [kinds])
	_expect(max_staff_y < 0.5, "la mesera no se sube a la barra ni a las mesas (altura máx. %.2f m)" % max_staff_y)
	for i in 600:
		await physics_frame
	# Llamarla desde la mesa
	var call_it = town.get("_call_it")
	_expect(call_it != null and is_instance_valid(call_it) and str(call_it.prompt).begins_with("Llamar a"), "sentado, puedes llamar a la mesera (%s)" % (str(call_it.prompt) if call_it and is_instance_valid(call_it) else "—"))
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

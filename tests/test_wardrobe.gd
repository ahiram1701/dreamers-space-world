extends SceneTree
## Tu aspecto en el mundo: la ropa es tuya (armario, tienda), el pelo se corta en la peluquería,
## la lluvia te moja y se seca, el trabajo te ensucia y la ducha te limpia, y el cuerpo cambia
## despacio con cómo vives.
##   godot --headless --path . -s tests/test_wardrobe.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var body = root.get_node("/root/Body")
	var wallet = root.get_node("/root/Wallet")
	var inventory = root.get_node("/root/Inventory")
	var actions = root.get_node("/root/Actions")
	var clock = root.get_node("/root/WorldClock")
	var Look = load("res://scripts/player/PlayerLook.gd")
	var Weather = load("res://scripts/world/Weather.gd")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de ropa")
	var chosen := {"figure": "masculine", "body": "average", "outfit": "formal", "primary_color": "#2b2f3a", "secondary_color": "#e8e2d4",
		"skin": "#b07a50", "hair": "Suit", "hair_color": "#3e2a1c", "height": 1.84}
	Look.save(chosen)
	Look.start_clothes(chosen)
	Weather.forced = "clear"
	clock.set_hour(12.0)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var player = town.get("_player")

	# Empiezas con la ropa que elegiste puesta y una muda en el armario
	var worn: String = Look.wearing()
	_expect(not worn.is_empty() and db.get_entity("item", worn).clothing.outfit == "formal", "llevas puesta la ropa que elegiste")
	var spare: Array = actions.stash(Look.WARDROBE)
	_expect(spare.size() == 1, "y tienes otra muda en el armario de casa")

	# Cambiarte en el armario: te pones la otra, la de antes queda guardada, y se ve al momento
	var model_before: Node = player.get("_body").get_child(0)
	town.call("_apply_look_panel", "wardrobe", {"_item": spare[0]})
	await process_frame
	_expect(Look.wearing() == spare[0] and worn in actions.stash(Look.WARDROBE), "te cambias: la de antes queda en el armario")
	_expect(Look.current().outfit == db.get_entity("item", spare[0]).clothing.outfit, "y ahora vistes lo que te pusiste")
	_expect(Look.current().hair == "Suit" and Look.current().skin == "#b07a50", "sin cambiar tu pelo ni tu piel")

	# La tienda: compras, te lo pones, y lo de antes va a la mochila
	wallet.earn(300)
	var money: int = wallet.amount()
	var offers: Array = Look.shop_offers("casa_x")
	_expect(offers.size() == 6 and offers == Look.shop_offers("casa_x"), "la tienda tiene 6 conjuntos hoy (los mismos todo el día)")
	var previous: String = Look.wearing()
	town.call("_apply_look_panel", "clothes_shop", {"_offer": offers[0]})
	_expect(wallet.amount() == money - int(offers[0].price), "comprar cobra lo que cuesta (%s)" % wallet.text(int(offers[0].price)))
	_expect(inventory.has(previous) and Look.current().primary_color == offers[0].clothing.primary_color, "te lo pones y lo de antes va en la mochila")

	# La peluquería: pagas y cambia tu peinado
	money = wallet.amount()
	var cut: Dictionary = Look.current().duplicate()
	cut["hair"] = "Adventurer"
	cut["_price"] = 18
	town.call("_apply_look_panel", "haircut", cut)
	_expect(Look.current().hair == "Adventurer" and wallet.amount() == money - 18, "en la peluquería te cortan el pelo ($18)")

	# La lluvia moja (sin techo) y luego se seca; se nota en la ropa
	Weather.forced = "rain"
	body.wet = 0.0
	body.call("_weather", 30.0)
	_expect(body.wet > 0.6, "bajo la lluvia te mojas (%.2f)" % body.wet)
	player.call("_apply_condition")
	var mats: Array = player.get("_look_mats").filter(func(e): return e[3] == "cloth")
	_expect(not mats.is_empty() and mats[0][0].albedo_color.v < mats[0][1].v, "la ropa mojada se ve más oscura")
	_expect(body.describe().contains("empapado") or body.describe().contains("mojado"), "y se nota en cómo estás: «%s»" % body.describe())
	Weather.forced = "clear"
	body.call("_weather", 200.0)
	_expect(body.wet < 0.4, "al dejar de llover, te secas (%.2f)" % body.wet)

	# Talar o cavar ensucia; la ducha limpia
	body.dirt = 0.0
	player.play_gesture("dig", 1.0)
	player.play_gesture("dig", 1.0)
	_expect(body.dirt >= 0.35, "cavar te ensucia (%.2f)" % body.dirt)
	body.shower()
	_expect(body.dirt == 0.0 and body.get_need("hygiene") == 100.0, "la ducha te deja limpio")

	# El cuerpo cambia despacio con cómo vives
	body.shape = 0.0
	body.exertion = 1.0
	for h in 24 * 7:  # una semana comiendo bien y sin moverte
		body.set_need("hunger", 95.0)
		body.call("_decay", 60.0)
	var wider: float = body.shape
	body.exertion = 1.8
	for h in 24 * 7:  # otra semana con mucho ejercicio
		body.set_need("hunger", 60.0)
		body.call("_decay", 60.0)
	_expect(wider > 0.0 and body.shape < wider, "bien comido y quieto te ensanchas; moviéndote te afinas (%.2f → %.2f)" % [wider, body.shape])

	# En el pueblo hay tienda de ropa y peluquería, con alguien que atiende
	var kinds: Array = town.get("_interiors").doors().values().map(func(d): return d.kind)
	_expect("clothes" in kinds and "salon" in kinds, "el pueblo tiene tienda de ropa y peluquería")
	var shop := ""
	for id in town.get("_interiors").doors():
		if town.get("_interiors").doors()[id].kind == "clothes":
			shop = id
	town.get("_interiors").enter(shop)
	await create_timer(1.6).timeout
	_expect(town.get("_households").staff_here() != null, "en la tienda te atiende alguien")

	town.queue_free()
	await process_frame
	Weather.forced = ""
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

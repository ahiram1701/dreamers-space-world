extends SceneTree
## Locales de verdad: abarrotes, fonda, farmacia y ferretería con quien atiende en su horario;
## lo que compras es un objeto que se come, cura o sirve; en la fonda te sirven en la mesa.
##   godot --headless --path . -s tests/test_shops.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var wallet = root.get_node("/root/Wallet")
	var inventory = root.get_node("/root/Inventory")
	var body = root.get_node("/root/Body")
	var Shops = load("res://scripts/world/Shops.gd")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de locales")
	clock.set_hour(13.0)
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 10:
		await process_frame
	var interiors = town.get("_interiors")
	var player = town.get("_player")
	wallet.earn(200)

	var by_kind := {}
	for id in interiors.doors():
		by_kind[interiors.doors()[id].kind] = id
	_expect(["grocery", "restaurant", "pharmacy", "hardware"].all(func(k): return by_kind.has(k)), "el pueblo tiene abarrotes, fonda, farmacia y ferretería")
	_expect(by_kind.has("clothes") and by_kind.has("salon"), "y siguen la tienda de ropa y la peluquería")

	# Abarrotes: hay quien atiende, compras pan y te lo comes
	interiors.enter(by_kind.grocery)
	await create_timer(1.6).timeout
	_expect(town.get("_households").staff_here() != null, "en los abarrotes te atiende alguien")
	var money: int = wallet.amount()
	var bread: Dictionary = Shops.info("grocery").items[0]
	var id: String = Shops.buy(bread)
	_expect(not id.is_empty() and inventory.has(id) and wallet.amount() == money - int(bread.price), "comprar %s cobra %s y te lo da" % [bread.name, wallet.text(int(bread.price))])
	body.set_need("hunger", 30.0)
	inventory.use(id)
	_expect(body.get_need("hunger") > 45.0 and not inventory.has(id), "al comértelo se te quita el hambre")

	# Ferretería: con un hacha comprada, al talar se ve el hacha
	_expect(not player.has_tool_for("chop"), "sin hacha no la llevas en la mano")
	Shops.buy(Shops.info("hardware").items[0])
	_expect(player.has_tool_for("chop"), "con el hacha de la ferretería, sí")

	# Fonda: pides, te sientas, te sirven y comes
	interiors.leave()
	await create_timer(1.0).timeout
	interiors.enter(by_kind.restaurant)
	await create_timer(1.6).timeout
	var staff = town.get("_households").staff_here()
	_expect(staff != null, "en la fonda hay quien atiende")
	var seat: Dictionary = interiors.activity_spot("table", 0)
	interiors.sit(seat.node)
	body.set_need("hunger", 20.0)
	money = wallet.amount()
	var meal: Dictionary = Shops.info("restaurant").items[0]
	wallet.pay(int(meal.price))
	var minutes_before: float = clock.absolute_minutes()
	await town.call("_serve", meal, staff)
	_expect(body.get_need("hunger") > 60.0, "te sirven %s y comes (hambre %d)" % [meal.name, body.get_need("hunger")])
	_expect(wallet.amount() == money - int(meal.price) and clock.absolute_minutes() > minutes_before, "lo pagaste y pasó el rato de comer")

	# Fuera de horario, cerrado
	interiors.leave()
	await create_timer(1.0).timeout
	clock.set_hour(23.0)
	await process_frame
	town.call("_shop_hours")
	_expect(interiors.locked.has(by_kind.pharmacy), "de noche la farmacia está cerrada")

	# Cada época tiene sus negocios
	_expect(Shops.for_era("ancient").has("restaurant") and Shops.label("restaurant", "ancient") == "la taberna", "en la Antigüedad hay taberna y mercado")

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

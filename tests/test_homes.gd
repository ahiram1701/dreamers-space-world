extends SceneTree
## La gente vive en sus casas: cada casa tiene su hogar (que se queda), y al entrar los ves
## haciendo lo que toca por la hora; quien entra por una puerta está dentro; los vecinos se van a
## dormir a su casa; y quien se va mientras estás dentro sale caminando.
##   godot --headless --path . -s tests/test_homes.gd

var _failed := 0
var town: Node
var interiors


func _initialize() -> void:
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _enter(door: String) -> void:
	if interiors.is_inside():
		interiors.leave()
		await _wait(1.0)
	interiors.enter(door)
	await _wait(1.6)


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	var memory = root.get_node("/root/NPCMemory")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de casas")
	clock.set_hour(13.8)
	town = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	await _wait(0.5)
	interiors = town.get("_interiors")
	var H = load("res://scripts/world/Households.gd")
	var hh = town.get("_households")

	# Una casa cualquiera tiene su hogar, y es siempre el mismo
	await _enter("casa_1")
	var people: Array = H.members("casa_1")
	_expect(not people.is_empty(), "casa_1 tiene quien viva en ella (%d)" % people.size())
	var again: Array = hh.ensure("casa_1")
	_expect(again == people, "y es siempre la misma gente")
	var inside: Dictionary = hh.spawned()
	var settled := inside.values().filter(func(n): return n.is_settled() and (n.global_position.y < -300.0))
	_expect(settled.size() == inside.size(), "los que están en casa están en su sitio (%d de %d)" % [settled.size(), inside.size()])
	for n in inside.values():
		print("     · %s: %s" % [db.get_entity("npc", n.npc_id).get("name", "?"), n.doing()])

	# De madrugada, todos duermen en sus camas
	clock.set_hour(2.5)
	await _enter("casa_2")
	var sleepers: Array = hh.spawned().values()
	_expect(not sleepers.is_empty() and sleepers.all(func(n): return n.is_asleep() or n.activity_gesture == "sit"),
		"de madrugada, en casa_2 están durmiendo (%d)" % sleepers.size())
	_expect(sleepers.size() == H.members("casa_2").size(), "de noche están todos en casa")

	# Teo de noche está en su casa (casa_4), dormido
	await _enter("casa_4")
	var teo = town.get("_npcs")["npc_teo"]
	_expect(teo.is_present() and (teo.global_position.y < -300.0) and teo.is_asleep(), "Teo duerme en su casa de madrugada")
	_expect(town.call("_door_for", "npc_teo", "me voy a mi casa") == "casa_4", "«me voy a mi casa»: Teo va a casa_4, no a la primera casa")

	# Alguien de paso que entra en una casa está dentro al entrar tú
	clock.set_hour(16.0)
	H.add_guest("casa_3", {"figure": "feminine", "outfit": "casual", "body": "average", "primary_color": "#aa3355", "secondary_color": "#222222"}, true, 60.0)
	await _enter("casa_3")
	var guests: Array = hh.spawned().values().filter(func(n): return n.has_meta("passerby"))
	_expect(guests.size() == 1 and guests[0].is_present(), "la persona que entró en casa_3 está dentro")

	# Se le acaba el rato dentro estando tú: sale andando por la puerta (no se teletransporta)
	clock.set_hour(12.0)
	memory.go_inside("npc_marina", "casa_5", "una casa", 5.0, false)
	await _enter("casa_5")
	var marina = town.get("_npcs")["npc_marina"]
	_expect(marina.is_present() and (marina.global_position.y < -300.0), "Marina, que entró en casa_5, está dentro")
	clock.advance(10)
	town.call("_refresh_presence")
	await _wait(0.2)
	_expect((marina.global_position.y < -300.0) and marina.is_walking(), "al acabar su rato, sale caminando hacia la puerta")

	# El objetivo sigue contando solo a tus vecinos de siempre
	var obj: String = town.get("_objective_text") if town.get("_objective_text") != null else ""
	town.call("_update_objective")
	_expect(town.call("_base_talked", town.call("_progress")) <= 3, "el objetivo cuenta a tus 3 vecinos, no a las familias")

	interiors.leave()
	await _wait(1.0)
	_expect(hh.spawned().is_empty(), "al salir, la gente de dentro se queda dentro (sin nodos en la calle)")
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

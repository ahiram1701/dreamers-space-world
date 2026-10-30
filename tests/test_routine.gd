extends SceneTree
## La rutina del jugador: el celular (contactos, quién contesta), el trabajo (contratar, trabajar,
## llegar tarde, faltar y que te despidan) y lo que construye (piezas, baúl, objetos con uso).
## Sin red: las acciones llegan como las devolvería la IA.
##   godot --headless --path . -s tests/test_routine.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var actions = root.get_node("/root/Actions")
	var phone = root.get_node("/root/Phone")
	var jobs = root.get_node("/root/Jobs")
	var wallet = root.get_node("/root/Wallet")
	var clock = root.get_node("/root/WorldClock")
	var memory = root.get_node("/root/NPCMemory")
	var inventory = root.get_node("/root/Inventory")
	var body = root.get_node("/root/Body")
	var validator = root.get_node("/root/ContentValidator")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de rutina")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)
	await process_frame

	# --- Celular ---
	phone.ensure_phone()
	phone.ensure_phone()
	_expect(phone.has_phone() and inventory.items().size() == 1, "empiezas con un celular (y solo uno)")
	_expect(phone.contacts().is_empty(), "sin el número de nadie, no hay contactos")
	actions.execute("npc_teo", [{"type": "dar_numero"}].map(func(a): return validator.validate("dialogue_turn", {"line": "Apunta.", "actions": [a]}).data.actions[0]))
	_expect(phone.contacts() == ["npc_teo"], "Teo te da su número %s" % [phone.contacts()])
	clock.set_hour(3.0)
	_expect(phone.call_refusal("npc_teo").contains("durmiendo"), "a las 3:00 no contesta: %s" % phone.call_refusal("npc_teo"))
	clock.set_hour(12.0)
	_expect(phone.call_refusal("npc_teo").is_empty(), "a mediodía contesta")
	memory.set_fields("npc_teo", {"relationship": -60})
	_expect(phone.call_refusal("npc_teo").contains("rechaza"), "si te odia, te cuelga")
	memory.set_fields("npc_teo", {"relationship": 10})
	settings_mock(true)
	phone.send("npc_teo", "¿Abres hoy?")
	_expect(phone.messages("npc_teo").size() == 1 and phone.messages("npc_teo")[0].from == "player", "tu mensaje queda guardado")
	var phone_id: String = inventory.items()[0]
	actions.player_gives("npc_samir", phone_id)
	_expect(not phone.has_phone() and phone.call_refusal("npc_teo").contains("celular"), "sin celular no hay llamadas")
	actions.execute("npc_samir", [{"type": "give_item", "item_name": "Celular", "lent": false}])

	# --- Trabajo ---
	actions.workplace_finder = func(_id): return {"place": "cafe", "label": "la cafetería"}
	var r: Dictionary = validator.validate("dialogue_turn", {"line": "Te contrato.", "actions": [
		{"type": "contratar", "target": "Camarero/a", "price": 90, "start_hour": 8, "end_hour": 14, "text": "Atender la barra."}]})
	var notes: Array = actions.execute("npc_teo", r.data.actions)
	var job: Dictionary = jobs.job()
	_expect(job.employer == "npc_teo" and job.wage == 90 and job.start_hour == 8 and job.place == "cafe", "Teo te contrata %s" % [notes])
	# Jueves (el mundo empieza en jueves), 7:45: se puede empezar
	clock.set_hour(7.75)
	_expect(jobs.can_work_now(), "a las 7:45 ya puedes empezar tu turno")
	var money: int = wallet.amount()
	var res: Dictionary = jobs.work_shift()
	_expect(res.paid == 90 and wallet.amount() == money + 90 and is_equal_approx(clock.hour(), 14.0), "un turno entero: cobras $90 y son las 14:00 (%s)" % [res])
	_expect(not jobs.can_work_now(), "hoy ya trabajaste")
	_expect(wallet.log_entries()[-1].what.contains("Sueldo"), "el banco lo apunta como sueldo")
	# Al día siguiente llegas tarde: cobras menos
	clock.advance(24 * 60 - 6 * 60 + 2.5 * 60)  # viernes 10:30
	res = jobs.work_shift()
	_expect(res.late_minutes == 150 and res.paid < 90, "llegas 2,5 h tarde y cobras menos (%s)" % [res])
	_expect(memory.describe_recent("npc_teo").contains("tarde"), "Teo se acuerda de que llegaste tarde")
	# Faltar tres días seguidos: despido (sábado y domingo no se trabaja)
	for i in 4:
		clock.advance(24 * 60)
		clock.set_hour(15.0)
		jobs.check_missed()
	_expect(jobs.has_job() and jobs.job().missed == 2, "faltas el lunes y el martes (%s)" % [jobs.job().get("missed")])
	clock.advance(24 * 60)
	jobs.check_missed()
	_expect(not jobs.has_job(), "a la tercera falta seguida, te despiden")

	# --- Construir e inventar ---
	actions.player_pose = func(): return {"pos": Vector3(0, 0, 0), "yaw": 0.0, "water": Vector3.INF}
	var placed := []
	actions.object_placed.connect(func(e): placed.append(e))
	r = validator.validate("world_action", {"narration": "Montas una antena.", "steps": [{"type": "place_object", "target": "other",
		"item_name": "Antena casera", "function": "antena", "parts": [
			{"shape": "cilindro", "size": [0.1, 4.0, 0.1], "pos": [0, 2, 0], "color": "#999999"},
			{"shape": "sphere", "size": [1.2, 1.2, 1.2], "pos": [0, 4.2, 0], "color": "#dddddd"},
			{"shape": "box", "size": [99, 1, 1], "pos": [0, 0, 0]}, "basura"]}]})
	actions.execute("", r.data.steps)
	_expect(placed.size() == 1 and placed[0].function == "signal" and placed[0].parts.size() == 3, "la antena: función señal y sus piezas %s" % [placed[0].get("parts")])
	_expect(placed[0].parts[2].size[0] <= 6.0, "las piezas se acotan (%s)" % [placed[0].parts[2].size])
	actions.execute("", [{"type": "place_object", "target": "box", "item_name": "Baúl de madera"}])
	var key: String = placed[1].id
	_expect(placed[1].function == "storage", "un baúl sirve para guardar")
	actions.execute("", [{"type": "give_item", "item_name": "Hacha vieja", "item_effect": "tool"}])
	var axe: String = inventory.find_by_name("hacha")
	actions.stash_put(key, axe)
	_expect(not inventory.has(axe) and axe in actions.stash(key), "guardas el hacha en el baúl")
	actions.stash_take(key, axe)
	_expect(inventory.has(axe) and actions.stash(key).is_empty(), "y la vuelves a sacar")
	# Objetos con uso real
	actions.execute("", [{"type": "give_item", "item_name": "Bocadillo", "item_effect": "nourish"}, {"type": "give_item", "item_name": "Linterna casera", "item_effect": "luz"}])
	body.set_need("hunger", 20.0)
	inventory.use(inventory.find_by_name("bocadillo"))
	_expect(body.get_need("hunger") > 40.0 and inventory.find_by_name("bocadillo").is_empty(), "el bocadillo se come y quita el hambre")
	var torch: String = inventory.find_by_name("linterna")
	inventory.use(torch)
	_expect(db.get_state("light_on", false) and inventory.has(torch), "la linterna se enciende y no se gasta")

	settings_mock(false)
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


## Sin red: que el envío de un mensaje no llame a la IA de verdad.
func settings_mock(on: bool) -> void:
	root.get_node("/root/Settings").use_mock = on


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

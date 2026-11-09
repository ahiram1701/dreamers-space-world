extends Node
## Misiones: una por lugar generado, escrita por la IA y anclada a cosas reales del lugar.
## Completarlas da fragmentos de coordenadas de la transmisión (el hilo principal):
## con FRAGMENTS_NEEDED, el Ancla puede seguir la señal hasta su origen.
##
## Misión: { id, location_id, giver, title, description, objective, target, target_name,
##           completion_text, status: "active" | "done" }

signal quest_added(quest: Dictionary)
signal quest_completed(quest: Dictionary, reward_text: String)
signal quest_failed(quest: Dictionary, text: String)
signal quest_accepted(quest: Dictionary)

const MAX_PER_GIVER := 3  # encargos pendientes que una misma persona te puede tener hechos
const WINDOW := 30.0       # minutos de margen para «estar allí a las 3»
const CHECK_EVERY := 1.0   # segundos reales entre comprobaciones de hora y sitio

var _check_t := 0.0

const BONUS_ENERGY := 40  # recompensa cuando ya tienes todos los fragmentos


## Crea la misión de un lugar recién generado. Siempre crea una (IA o respaldo).
func create_for_location(location_id: String) -> Dictionary:
	var loc := WorldDB.get_entity("location", location_id)
	var npc_ids: Array = loc.get("npc_ids", [])
	if npc_ids.is_empty():
		return {}
	var pois: Array = loc.get("points_of_interest", [])
	var items: Array = loc.get("item_ids", [])
	var npc_names := npc_ids.map(func(id): return WorldDB.get_entity("npc", id).get("name", "?"))
	var item_names := items.map(func(id): return WorldDB.get_entity("item", id).get("name", "?"))
	var giver := WorldDB.get_entity("npc", npc_ids[0])

	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nDiseñas misiones cortas y concretas que encajan en el lugar y en la historia del jugador."},
		{"role": "user", "content": """Lugar: %s — %s
Quien pide ayuda: %s (%s). Sus objetivos: %s

Objetivos posibles (elige uno y usa "target_index" para el elemento de su lista):
- visit_poi: ir a uno de estos puntos de interés: %s
- talk_npc: hablar con una de estas personas: %s
- bring_item: llevarle a %s uno de estos objetos que hay en el lugar: %s

La misión debe ayudar al jugador a seguir la transmisión que le trajo hasta aquí: al completarla obtendrá un fragmento de sus coordenadas.
"completion_text": lo que ocurre o se descubre al terminarla.""" % [
			loc.get("name", ""), loc.get("description", ""), giver.get("name", "?"), giver.get("occupation", ""),
			"; ".join(PackedStringArray(giver.get("goals", []))),
			_numbered(pois), _numbered(npc_names), giver.get("name", "?"), _numbered(item_names)]},
	]
	var res := await ContentGenerator.request_valid("quest", messages)
	var q: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("quest")

	# Resolver el objetivo contra lo que existe de verdad; si la lista está vacía, visitar un punto
	var lists := {"visit_poi": pois, "talk_npc": npc_ids, "bring_item": items}
	var objective: String = q.objective
	if (lists[objective] as Array).is_empty():
		objective = "visit_poi"
	# «Habla con…» nunca es hablar con quien te lo pide (eso ya lo haces para recibirla)
	if objective == "talk_npc" and npc_ids.size() < 2:
		objective = "visit_poi" if not pois.is_empty() else "bring_item"
	if (lists[objective] as Array).is_empty():
		objective = "visit_poi"
	var list: Array = lists[objective]
	var index := clampi(int(q.target_index), 0, list.size() - 1)
	if objective == "talk_npc" and index == 0:
		index = 1
	var target: String = str(list[index]) if objective != "visit_poi" else str(index)
	var target_name: String = pois[index] if objective == "visit_poi" \
		else (npc_names[index] if objective == "talk_npc" else item_names[index])

	var all: Dictionary = WorldDB.get_state("quests", {})
	var quest := {
		"id": "q%d" % (all.size() + 1), "location_id": location_id, "giver": npc_ids[0],
		"title": q.title, "description": q.description, "objective": objective,
		"target": target, "target_name": target_name, "completion_text": q.completion_text,
		"status": "offered",  # nadie te la ha pedido aún: aparece al hablar con quien la da
	}
	all[quest.id] = quest
	WorldDB.set_state("quests", all)
	WorldDB.update_entity("location", location_id, {"quest_id": quest.id})
	quest_added.emit(quest)
	return quest


## La misión del lugar pasa de ofrecida a aceptada: ya te la han pedido en persona.
func accept(q: Dictionary) -> void:
	var all: Dictionary = WorldDB.get_state("quests", {})
	q.status = "active"
	all[q.id] = q
	WorldDB.set_state("quests", all)
	NPCMemory.add_event(q.giver, "Le pediste ayuda al jugador: «%s» — %s." % [q.title, q.description], 2)
	quest_accepted.emit(q)


## Encargo personal que un PNJ hace en una conversación ("tráeme café", "ve al muelle a las 3").
## opts: kind (custom | bring_item | go_to | be_there), item (nombre del objeto), place (sitio),
## at_hour (hora del día, 3.0 = 3 a. m.; -1 sin hora). Lo que el motor puede comprobar se
## completa solo (entregar el objeto, llegar al sitio, estar allí a la hora); el resto lo da por
## cumplido el propio PNJ (complete_quest). La persona lo recuerda.
func create_custom(giver: String, title: String, description: String, reward: int = 0, opts: Dictionary = {}) -> Dictionary:
	var all: Dictionary = WorldDB.get_state("quests", {})
	var pending := 0
	for q in all.values():
		if q.giver == giver and q.status == "active" and q.objective == "custom":
			pending += 1
			if _same_title(str(q.title), title):
				return {}  # ya te lo había pedido
	if pending >= MAX_PER_GIVER:
		return {}
	var kind := str(opts.get("kind", "custom"))
	if not kind in ["custom", "bring_item", "go_to", "be_there"]:
		kind = "custom"
	var at_hour := float(opts.get("at_hour", -1.0))
	var quest := {
		"id": "q%d" % (all.size() + 1), "location_id": GameState.current_location(), "giver": giver,
		"title": title, "description": description, "objective": "custom", "kind": kind,
		"item": str(opts.get("item", "")), "place": str(opts.get("place", "")),
		"target": "", "target_name": "", "completion_text": "", "status": "active",
		"reward": clampi(reward, 0, Wallet.MAX_PER_ACTION),
		"due": due_from_hour(at_hour) if at_hour >= 0.0 else -1.0,
	}
	if kind == "be_there" and float(quest.due) < 0.0:
		quest.kind = "go_to"
	all[quest.id] = quest
	WorldDB.set_state("quests", all)
	var when := (" (" + when_text(quest) + ")") if float(quest.due) >= 0.0 else ""
	NPCMemory.add_event(giver, "Le pediste al jugador: «%s» — %s%s." % [title, description, when], 0)
	quest_added.emit(quest)
	return quest


## El PNJ da por cumplido un encargo suyo: el que se parece a `title` o, si no, el más antiguo.
func complete_custom(giver: String, title: String = "") -> Dictionary:
	var mine := active_custom().filter(func(q): return q.giver == giver)
	if mine.is_empty():
		return {}
	var pick: Dictionary = mine[0]
	for q in mine:
		if not title.is_empty() and _same_title(str(q.title), title):
			pick = q
	return _finish_custom(pick)


func _finish_custom(q: Dictionary) -> Dictionary:
	var all: Dictionary = WorldDB.get_state("quests", {})
	q.status = "done"
	all[q.id] = q
	WorldDB.set_state("quests", all)
	NPCMemory.add_facts(q.giver, ["El jugador cumplió tu encargo «%s»." % q.title], 15)
	var paid := Wallet.earn(int(q.get("reward", 0)))
	quest_completed.emit(q, "%s confía más en ti%s" % [WorldDB.get_entity("npc", q.giver).get("name", "?"),
		(" y te paga %s" % Wallet.text(paid)) if paid > 0 else ""])
	return q


func _fail(q: Dictionary, why: String) -> void:
	var all: Dictionary = WorldDB.get_state("quests", {})
	q.status = "failed"
	all[q.id] = q
	WorldDB.set_state("quests", all)
	NPCMemory.add_event(q.giver, "El jugador no cumplió tu encargo «%s»: %s." % [q.title, why], -6)
	quest_failed.emit(q, "Encargo perdido: %s (%s)" % [q.title, why])


func active_custom() -> Array:
	return all_quests().filter(func(q): return q.objective == "custom" and q.status == "active")


## Le diste un objeto a alguien: si era lo que te había encargado, queda cumplido.
func on_item_given(npc_id: String, item_name: String) -> Dictionary:
	for q in active_custom():
		if q.giver == npc_id and q.get("kind", "custom") == "bring_item" and _same_title(str(q.get("item", "")), item_name):
			return _finish_custom(q)
	# La misión del lugar «llévale X a Y» también se cumple al dárselo
	var lq := for_location(GameState.current_location())
	if not lq.is_empty() and lq.status == "active" and lq.objective == "bring_item" and lq.giver == npc_id \
			and _same_title(str(lq.target_name), item_name):
		return _complete(lq)
	return {}


## Minutos absolutos de la próxima vez que el reloj marque `at_hour` (hoy si aún no ha pasado).
static func due_from_hour(at_hour: float) -> float:
	var now := WorldClock.absolute_minutes()
	var due := now - fmod(now, 1440.0) + fposmod(at_hour, 24.0) * 60.0
	if due < now - WINDOW:
		due += 1440.0
	return due


## «hoy a las 3:00 a. m.», «mañana a las 5:00 p. m.».
static func when_text(q: Dictionary) -> String:
	var due := float(q.get("due", -1.0))
	if due < 0.0:
		return ""
	var today := floorf(WorldClock.absolute_minutes() / 1440.0)
	var day := floorf(due / 1440.0)
	var word := "hoy" if day == today else ("mañana" if day == today + 1.0 else "el %s" % WorldClock.WEEKDAYS[(int(day) + 3) % 7])
	return "%s a las %s" % [word, WorldClock.fmt(fmod(due, 1440.0) / 60.0)]


## Lo que una persona recuerda que te encargó (para su prompt).
func describe_for_npc(npc_id: String) -> String:
	var lines := PackedStringArray()
	var states := {"active": "pendiente", "done": "cumplido", "failed": "no lo cumplió"}
	for q in all_quests():
		if q.giver != npc_id or q.status == "offered":
			continue
		var extra := ""
		if q.status == "active" and q.get("kind", "") == "bring_item" and not str(q.get("item", "")).is_empty():
			extra = " · lleva encima «%s»: %s" % [q.item, "sí" if _carries(str(q.item)) else "no"]
		if q.status == "active" and q.objective == "bring_item" and Inventory.has(str(q.target)):
			extra = " · ya lleva encima %s" % q.target_name
		var when := when_text(q) if q.status == "active" else ""
		lines.append("- «%s» (%s%s): %s%s" % [q.title, states.get(q.status, q.status), (", " + when) if not when.is_empty() else "", q.description, extra])
	return "\n".join(lines) if not lines.is_empty() else "(ninguno)"


func _carries(name: String) -> bool:
	for id in Inventory.items():
		if _same_title(str(WorldDB.get_entity("item", id).get("name", "")), name):
			return true
	return false


## Dos títulos o nombres se refieren a lo mismo (sin mayúsculas, artículos ni acentos).
static func _same_title(a: String, b: String) -> bool:
	var x := _norm(a)
	var y := _norm(b)
	if x.is_empty() or y.is_empty():
		return false
	return x == y or (x.length() >= 4 and y.contains(x)) or (y.length() >= 4 and x.contains(y))


static func _norm(s: String) -> String:
	var t := s.to_lower().strip_edges()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"]]:
		t = t.replace(pair[0], pair[1])
	for art in ["el ", "la ", "los ", "las ", "un ", "una ", "unos ", "unas "]:
		if t.begins_with(art):
			t = t.substr(art.length())
	return t.strip_edges()


## Comprueba encargos con sitio u hora: llegar, estar allí a tiempo o que se pase la hora.
func _process(delta: float) -> void:
	_check_t += delta
	if _check_t < CHECK_EVERY or not WorldDB.is_loaded():
		return
	_check_t = 0.0
	check_now()


func check_now() -> void:
	var now := WorldClock.absolute_minutes()
	var scene := get_tree().current_scene
	var players := get_tree().get_nodes_in_group("player")
	var player: Node3D = players[0] if not players.is_empty() else null
	for q in active_custom():
		var kind: String = q.get("kind", "custom")
		var due := float(q.get("due", -1.0))
		var here: bool = q.get("location_id", "") == GameState.current_location() and player != null
		var at_place := here and _player_at(scene, player, q)
		if kind == "be_there":
			if at_place and absf(now - due) <= WINDOW:
				_finish_custom(q)
			elif now > due + WINDOW:
				_fail(q, "no estabas allí a la hora")
		elif kind == "go_to" and at_place and (due < 0.0 or now <= due + WINDOW):
			_finish_custom(q)
		elif due >= 0.0 and now > due + 60.0:
			_fail(q, "se pasó la hora")


## ¿Está el jugador en el sitio del encargo? (o junto a quien se lo pidió, si no dijo sitio)
func _player_at(scene: Node, player: Node3D, q: Dictionary) -> bool:
	var place := str(q.get("place", ""))
	if not place.is_empty() and scene and scene.has_method("place_position"):
		var p: Vector3 = scene.place_position(place)
		if p != Vector3.INF:
			return Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length() < 12.0
	for n in get_tree().get_nodes_in_group("townsfolk"):
		if n.get("npc_id") == q.giver and n.is_inside_tree():
			return player.global_position.distance_to(n.global_position) < 6.0
	return false


## El encargo pendiente con hora que antes vence (o {}).
func next_timed() -> Dictionary:
	var best := {}
	for q in active_custom():
		if float(q.get("due", -1.0)) >= 0.0 and (best.is_empty() or float(q.due) < float(best.due)):
			best = q
	return best


func get_quest(quest_id: String) -> Dictionary:
	return WorldDB.get_state("quests", {}).get(quest_id, {})


func for_location(location_id: String) -> Dictionary:
	return get_quest(WorldDB.get_entity("location", location_id).get("quest_id", ""))


func all_quests() -> Array:
	return WorldDB.get_state("quests", {}).values()


## Texto corto para el HUD.
func objective_text(q: Dictionary) -> String:
	if q.is_empty():
		return ""
	if q.status == "done":
		return "Completada: %s" % q.title
	var giver: String = WorldDB.get_entity("npc", q.giver).get("name", "?")
	match q.objective:
		"custom":
			return "%s — Encargo de %s" % [q.title, giver]
		"visit_poi":
			return "%s — Ve a: %s" % [q.title, q.target_name]
		"talk_npc":
			return "%s — Habla con %s" % [q.title, q.target_name]
		"bring_item":
			if Inventory.has(q.target):
				return "%s — Lleva %s a %s" % [q.title, q.target_name, giver]
			return "%s — Encuentra %s y llévaselo a %s" % [q.title, q.target_name, giver]
	return q.title


## Se llama desde la escena: llegaste a un punto (`visit_poi`, índice) o cerraste una
## conversación (`talk_npc`, id del PNJ). Devuelve la misión si se completó.
func notify(event: String, value: String) -> Dictionary:
	var q := for_location(GameState.current_location())
	if q.is_empty():
		return {}
	# Hablar por primera vez con quien la pide: te la cuenta y la aceptas
	if q.status == "offered":
		if event == "talk_npc" and value == q.giver:
			accept(q)
		return {}
	if q.status != "active":
		return {}
	var done := false
	match q.objective:
		"visit_poi":
			done = event == "visit_poi" and value == q.target
		"talk_npc":
			done = event == "talk_npc" and value == q.target
		"bring_item":
			done = event == "talk_npc" and value == q.giver and Inventory.has(q.target)
			if done:
				Inventory.remove(q.target)
	if done:
		return _complete(q)
	return {}


func _complete(q: Dictionary) -> Dictionary:
	var all: Dictionary = WorldDB.get_state("quests", {})
	q.status = "done"
	all[q.id] = q
	WorldDB.set_state("quests", all)
	NPCMemory.add_facts(q.giver, ["El jugador completó la misión «%s»." % q.title], 20)

	var reward: String
	if not GameState.has_all_fragments():
		var n := GameState.add_fragment()
		var left := GameState.FRAGMENTS_NEEDED - n
		reward = "La brújula gana rumbo: faltan %d %s para casa." % [left, "salto" if left == 1 else "saltos"]
		if GameState.has_all_fragments():
			reward = "La brújula apunta firme a casa: ya puedes dar el último salto (T)."
	else:
		GameState.change_stat("energy", BONUS_ENERGY)
		reward = "El Ancla recupera energía (+%d)" % BONUS_ENERGY
	quest_completed.emit(q, reward)
	return q


func _numbered(list: Array) -> String:
	if list.is_empty():
		return "(ninguno)"
	var parts := PackedStringArray()
	for i in list.size():
		parts.append("[%d] %s" % [i, list[i]])
	return ", ".join(parts)

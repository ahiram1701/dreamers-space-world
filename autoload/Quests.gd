extends Node
## Misiones: una por lugar generado, escrita por la IA y anclada a cosas reales del lugar.
## Completarlas da fragmentos de coordenadas de la transmisión (el hilo principal):
## con FRAGMENTS_NEEDED, el Ancla puede seguir la señal hasta su origen.
##
## Misión: { id, location_id, giver, title, description, objective, target, target_name,
##           completion_text, status: "active" | "done" }

signal quest_added(quest: Dictionary)
signal quest_completed(quest: Dictionary, reward_text: String)

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
	var list: Array = lists[objective]
	var index := clampi(int(q.target_index), 0, list.size() - 1)
	var target: String = str(list[index]) if objective != "visit_poi" else str(index)
	var target_name: String = pois[index] if objective == "visit_poi" \
		else (npc_names[index] if objective == "talk_npc" else item_names[index])

	var all: Dictionary = WorldDB.get_state("quests", {})
	var quest := {
		"id": "q%d" % (all.size() + 1), "location_id": location_id, "giver": npc_ids[0],
		"title": q.title, "description": q.description, "objective": objective,
		"target": target, "target_name": target_name, "completion_text": q.completion_text,
		"status": "active",
	}
	all[quest.id] = quest
	WorldDB.set_state("quests", all)
	WorldDB.update_entity("location", location_id, {"quest_id": quest.id})
	quest_added.emit(quest)
	return quest


## Encargo personal que un PNJ hace en una conversación ("tráeme café", "busca a mi hermano").
## No tiene objetivo comprobable por el motor: lo da por cumplido el propio PNJ (complete_quest).
func create_custom(giver: String, title: String, description: String) -> Dictionary:
	var all: Dictionary = WorldDB.get_state("quests", {})
	for q in all.values():
		if q.giver == giver and q.status == "active" and q.objective == "custom":
			return {}  # un encargo pendiente por persona
	var quest := {
		"id": "q%d" % (all.size() + 1), "location_id": GameState.current_location(), "giver": giver,
		"title": title, "description": description, "objective": "custom", "target": "",
		"target_name": "", "completion_text": "", "status": "active",
	}
	all[quest.id] = quest
	WorldDB.set_state("quests", all)
	quest_added.emit(quest)
	return quest


## El PNJ que hizo el encargo lo da por cumplido. Devuelve la misión o {}.
func complete_custom(giver: String) -> Dictionary:
	for q in all_quests():
		if q.giver == giver and q.status == "active" and q.objective == "custom":
			var all: Dictionary = WorldDB.get_state("quests", {})
			q.status = "done"
			all[q.id] = q
			WorldDB.set_state("quests", all)
			NPCMemory.add_facts(giver, ["El jugador cumplió tu encargo «%s»." % q.title], 15)
			quest_completed.emit(q, "%s confía más en ti" % WorldDB.get_entity("npc", giver).get("name", "?"))
			return q
	return {}


func active_custom() -> Array:
	return all_quests().filter(func(q): return q.objective == "custom" and q.status == "active")


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
	if q.is_empty() or q.status != "active":
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
		reward = "Fragmento de coordenadas %d/%d" % [n, GameState.FRAGMENTS_NEEDED]
		if GameState.has_all_fragments():
			reward += " — ¡coordenadas completas! El Ancla puede seguir la señal hasta su origen (T)."
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

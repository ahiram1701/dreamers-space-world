extends Node
## Lo que cada PNJ recuerda del jugador. Vive en WorldDB, así que es distinto en cada mundo.
## Los hechos son permanentes (hasta MAX_FACTS); el historial literal es solo una ventana corta.

const MAX_FACTS := 20
const MAX_HISTORY := 12  # líneas sueltas; lo importante debería haber quedado como hecho


func get_mem(npc_id: String) -> Dictionary:
	var all: Dictionary = WorldDB.get_state("memories", {})
	var m: Dictionary = all.get(npc_id, {})
	m.merge(_empty())  # las partidas antiguas no tienen los campos nuevos
	return m


## Cambia campos sueltos (posesiones, si te sigue, si está enfadado…).
func set_fields(npc_id: String, fields: Dictionary) -> void:
	var all: Dictionary = WorldDB.get_state("memories", {})
	var m := get_mem(npc_id)
	m.merge(fields, true)
	all[npc_id] = m
	WorldDB.set_state("memories", all)


func is_following(npc_id: String) -> bool:
	return bool(get_mem(npc_id).following)


## Segundos que le quedan al PNJ sin querer hablarte (0 si habla).
func refusal_left(npc_id: String) -> int:
	return maxi(0, int(get_mem(npc_id).refuse_until) - int(Time.get_unix_time_from_system()))


## Lo que el PNJ tiene de ti y lo que te ha dejado, para el prompt.
func describe_possessions(npc_id: String) -> String:
	var m := get_mem(npc_id)
	var names := func(ids: Array) -> String:
		var out := PackedStringArray()
		for id in ids:
			out.append(WorldDB.get_entity("item", id).get("name", "?"))
		return "nada" if out.is_empty() else ", ".join(out)
	return "Objetos que el jugador te ha dado (los tienes tú): %s.\nObjetos que le has prestado (son tuyos, puedes pedírselos): %s." % [
		names.call(m.possessions), names.call(m.lent)]


## Aplica un turno de conversación ya validado por StoryDirector.
func record_turn(npc_id: String, player_said: String, npc_said: String, new_facts: Array, relationship_delta: int) -> void:
	var all: Dictionary = WorldDB.get_state("memories", {})
	var m: Dictionary = all.get(npc_id, _empty())
	m.met = true
	m.conversations += 1 if m.history.is_empty() else 0
	if not player_said.is_empty():
		m.history.append({"who": "player", "text": player_said})
	m.history.append({"who": "npc", "text": npc_said})
	while m.history.size() > MAX_HISTORY:
		m.history.pop_front()
	for fact in new_facts:
		if not (fact in m.facts):
			m.facts.append(fact)
	while m.facts.size() > MAX_FACTS:
		m.facts.pop_front()
	# int(): tras cargar de JSON todos los números llegan como float
	m.relationship = clampi(int(m.relationship) + relationship_delta, -100, 100)
	all[npc_id] = m
	WorldDB.set_state("memories", all)


## Hechos que el PNJ vive fuera de una conversación (p. ej. acompañarte a través de la brecha).
func add_facts(npc_id: String, facts: Array, relationship_delta: int = 0) -> void:
	var all: Dictionary = WorldDB.get_state("memories", {})
	var m: Dictionary = all.get(npc_id, _empty())
	for fact in facts:
		if not (fact in m.facts):
			m.facts.append(fact)
	while m.facts.size() > MAX_FACTS:
		m.facts.pop_front()
	m.relationship = clampi(int(m.relationship) + relationship_delta, -100, 100)
	all[npc_id] = m
	WorldDB.set_state("memories", all)


## Marca el fin de una conversación (la próxima empezará con historial limpio).
func end_conversation(npc_id: String) -> void:
	var all: Dictionary = WorldDB.get_state("memories", {})
	if not all.has(npc_id):
		return
	all[npc_id].history = []
	WorldDB.set_state("memories", all)


## Texto compacto para meter en el prompt.
func describe(npc_id: String) -> String:
	var m := get_mem(npc_id)
	if not m.met:
		return "Nunca has hablado con esta persona."
	var facts := "ninguno" if m.facts.is_empty() else "- " + "\n- ".join(PackedStringArray(m.facts))
	return "Relación con el jugador: %d (de -100 a 100). Conversaciones anteriores: %d.\nLo que recuerdas:\n%s" % [
		int(m.relationship), int(m.conversations), facts]


func _empty() -> Dictionary:
	return {"met": false, "relationship": 0, "conversations": 0, "facts": [], "history": [],
		"possessions": [], "lent": [], "following": false, "refuse_until": 0}

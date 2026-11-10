extends Node
## Lo que cada PNJ recuerda del jugador. Vive en WorldDB, así que es distinto en cada mundo.
## Los hechos son permanentes (hasta MAX_FACTS); el historial literal es solo una ventana corta.

const MAX_FACTS := 20
const MAX_HISTORY := 12  # líneas sueltas; lo importante debería haber quedado como hecho
const MAX_RECENT := 6    # lo que acaba de pasar físicamente (un golpe, un regalo, irse enfadado)


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
	var until := float(get_mem(npc_id).refuse_until)
	if until > 1.0e8:  # partidas de antes: hora real
		return 0
	return maxi(0, int((until - WorldClock.absolute_minutes()) * 60.0))  # (en «segundos» de minuto de juego)


## Dónde está metido el PNJ ahora (id de puerta) si se fue a un edificio y aún no ha salido.
## Vacío si está donde diga su rutina.
func inside(npc_id: String) -> String:
	var w: Dictionary = get_mem(npc_id).whereabouts
	if w.is_empty() or WorldClock.absolute_minutes() >= float(w.get("until", 0.0)):
		return ""
	return str(w.get("door", ""))


func is_locked_in(npc_id: String) -> bool:
	return not inside(npc_id).is_empty() and bool(get_mem(npc_id).whereabouts.get("locked", false))


## El PNJ entra en un edificio y se queda `minutes` minutos de juego (con pestillo si no quiere ver a nadie).
func go_inside(npc_id: String, door: String, label: String, minutes: float, locked: bool) -> void:
	set_fields(npc_id, {"whereabouts": {"door": door, "label": label, "locked": locked,
		"until": WorldClock.absolute_minutes() + minutes}})


func come_out(npc_id: String) -> void:
	set_fields(npc_id, {"whereabouts": {}})


## Algo que acaba de pasar de verdad entre el PNJ y el jugador. Lo escribe el motor cuando
## ocurre (no la IA), así que el PNJ nunca "recuerda" algo que no pasó.
## rumor: te lo contó otro (no lo viviste); se separa en el prompt.
## meet: false si solo te vio o te sufrió (te vio pasar, le despertaste, le golpeó un coche):
## eso no es conocerte, así que no sabrá tu nombre ni te tratará de conocido.
## private: lo que se dijo en una conversación, que no se cuenta a otros como rumor.
func add_event(npc_id: String, text: String, relationship_delta: int = 0, rumor: bool = false, meet: bool = true, private: bool = false) -> void:
	var m := get_mem(npc_id)
	var recent: Array = m.recent
	var e := {"at": WorldClock.absolute_minutes(), "text": text}
	if rumor:
		e["rumor"] = true
	if private:
		e["private"] = true
	recent.append(e)
	while recent.size() > MAX_RECENT:
		recent.pop_front()
	# Un rumor (te lo contaron, o encontraste rastros sin ver a nadie) no es conocer al jugador
	var fields := {"recent": recent, "relationship": clampi(int(m.relationship) + relationship_delta, -100, 100)}
	if not rumor and meet:
		fields["met"] = true
	set_fields(npc_id, fields)


## Lo importante (cómo te llamas, lo que vivisteis en El Despertar, un encargo) no se olvida
## primero: al llenarse, se va el hecho corriente más antiguo.
const KEEP_FACTS := ["se llama", "despertar", "brecha", "encargo", "contigo"]
static func _trim_facts(facts: Array) -> void:
	while facts.size() > MAX_FACTS:
		var drop := 0
		for i in facts.size():
			var low := str(facts[i]).to_lower()
			if not KEEP_FACTS.any(func(k): return low.contains(k)):
				drop = i
				break
		facts.remove_at(drop)


## ¿Sabe cómo se llama el jugador? Los vecinos de siempre de la Bahía, sí; los demás solo si
## se lo dijo (se presentó, se lo contó alguien de confianza…).
func knows_name(npc_id: String) -> bool:
	if bool(get_mem(npc_id).get("knows_name", false)):
		return true
	return str(WorldDB.get_entity("npc", npc_id).get("origin", "")).begins_with("act0")


## El jugador acaba de decir su nombre (o alguien se lo presentó).
func learn_name(npc_id: String) -> void:
	if not knows_name(npc_id):
		set_fields(npc_id, {"knows_name": true})
		add_facts(npc_id, ["El jugador se llama %s." % PlayerProfile.player_name()])


## "hace 5 min: te dio un puñetazo" (para el prompt).
func describe_recent(npc_id: String, rumors: bool = false) -> String:
	var out := PackedStringArray()
	var now := WorldClock.absolute_minutes()
	for e in get_mem(npc_id).recent:
		if bool(e.get("rumor", false)) != rumors:
			continue
		var ago := int(now - float(e.at))
		if ago > 60 * 24 * 3:
			continue  # de hace días: si fue importante, ya es un recuerdo (facts)
		var when := "ahora mismo" if ago < 2 else ("hace %d min" % ago if ago < 120 else "hace %d h" % (ago / 60))
		out.append("- %s: %s" % [when, e.text])
	return "\n".join(out)


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
	_trim_facts(m.facts)
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
	_trim_facts(m.facts)
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


## Algo que `a` vivió con otro vecino `b` (una charla, un favor): así se conocen de verdad.
func add_bond(a: String, b: String, note: String) -> void:
	var m := get_mem(a)
	var bonds: Dictionary = m.get("bonds", {})
	var entry: Dictionary = bonds.get(b, {"notes": []})
	var notes: Array = entry.get("notes", [])
	notes.append(note.left(120))
	entry.notes = notes.slice(-4)
	bonds[b] = entry
	set_fields(a, {"bonds": bonds})


## Texto compacto para meter en el prompt.
func describe(npc_id: String) -> String:
	var m := get_mem(npc_id)
	if not m.met:
		var rumors := describe_recent(npc_id, true)
		return "Nunca has hablado con esta persona." + (("\nLo que te han contado otros (rumores: tú NO lo viviste ni lo viste):\n" + rumors) if not rumors.is_empty() else "")
	var facts := "ninguno" if m.facts.is_empty() else "- " + "\n- ".join(PackedStringArray(m.facts))
	var out := "Relación con el jugador: %d (de -100 a 100). Conversaciones anteriores: %d.\nLo que recuerdas:\n%s" % [
		int(m.relationship), int(m.conversations), facts]
	if int(m.get("owed", 0)) > 0:
		out += "\nEl jugador te debe %s." % Wallet.text(int(m.owed))
	var recent := describe_recent(npc_id)
	if not recent.is_empty():
		out += "\nLo que ha pasado hace poco entre tú y el jugador (real, lo viviste):\n" + recent
	var heard := describe_recent(npc_id, true)
	if not heard.is_empty():
		out += "\nLo que te han contado otros (rumores: tú NO lo viviste ni lo viste):\n" + heard
	return out


func _empty() -> Dictionary:
	return {"met": false, "relationship": 0, "conversations": 0, "facts": [], "history": [],
		"possessions": [], "lent": [], "following": false, "refuse_until": 0, "whereabouts": {}, "recent": [], "owed": 0}

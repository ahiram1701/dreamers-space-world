extends Node
## Conversaciones con PNJs, turno a turno. La IA interpreta al PNJ y además "observa"
## al jugador: lo que el PNJ aprende va a NPCMemory y lo que revela el jugador, a PlayerProfile.
##
## Uso:  var t := await StoryDirector.talk("npc_marina", "¿Qué pasa con el faro?", "Acto 0, al atardecer")
##       t = { ok, source: "ai" | "fallback", line, emotion, choices: [{text, tone}], end_conversation }

signal turn_started(npc_id: String)
signal turn_finished(npc_id: String, turn: Dictionary)


func talk(npc_id: String, player_input: String, scene_context: String) -> Dictionary:
	turn_started.emit(npc_id)
	var npc := WorldDB.get_entity("npc", npc_id)
	if npc.is_empty():
		return {"ok": false, "error": "PNJ desconocido: %s" % npc_id}

	var messages := [{"role": "system", "content": _system_prompt(npc, scene_context)}]
	for h in NPCMemory.get_mem(npc_id).history:
		# Las respuestas anteriores del PNJ van en JSON: si van como texto plano, algunos
		# modelos (p. ej. DeepSeek) imitan ese estilo y dejan de responder en JSON.
		var content: String = h.text if h.who == "player" else JSON.stringify({"line": h.text})
		messages.append({"role": "user" if h.who == "player" else "assistant", "content": content})
	var said := player_input.strip_edges()
	messages.append({"role": "user", "content": said if not said.is_empty() else _opening(npc_id)})

	var res := await ContentGenerator.request_valid("dialogue_turn", messages)
	var turn: Dictionary = res.data if res.ok else _fallback_turn(npc, res.errors)
	turn["ok"] = true
	turn["source"] = "ai" if res.ok else "fallback"

	# Un respaldo no es algo que el PNJ haya "dicho": no ensucia su memoria (salvo presentarse)
	if res.ok or not NPCMemory.get_mem(npc_id).met:
		NPCMemory.record_turn(npc_id, said, turn.line, turn.get("new_facts", []), int(turn.relationship_delta))
	if not said.is_empty():  # solo lo que el jugador dice o elige revela su carácter
		PlayerProfile.apply_signals(turn.get("trait_signals", []))
	turn_finished.emit(npc_id, turn)
	return turn


func end_conversation(npc_id: String) -> void:
	NPCMemory.end_conversation(npc_id)


## Sin IA: el PNJ al menos usa su propio saludo la primera vez, y el jugador ve por qué.
func _fallback_turn(npc: Dictionary, errors: Array) -> Dictionary:
	var turn := ContentGenerator.load_fallback("dialogue_turn")
	if not NPCMemory.get_mem(npc.id).met:
		turn.line = npc.get("greeting", turn.line)
	var reason := str(errors[0]) if not errors.is_empty() else "sin respuesta"
	turn["error"] = reason.replace("[", "(").replace("]", ")").left(140)  # se muestra con BBCode
	return turn


## Los modelos a veces repiten o inventan la consecuencia de una opción: se reparte
## una de cada (en orden) entre las que falten, para que todas las ramas sean posibles.
static func _ensure_distinct(choices: Array, field: String, allowed: Array) -> void:
	var used := []
	for c in choices:
		if c[field] in allowed and not (c[field] in used):
			used.append(c[field])
		else:
			c[field] = ""
	for c in choices:
		if c[field] == "":
			for a in allowed:
				if not (a in used):
					c[field] = a
					used.append(a)
					break


# --- El Despertar ---------------------------------------------------------------------

const ACT0_NEIGHBORS := ["npc_marina", "npc_teo", "npc_samir"]
const ORIGIN_GUIDE := """ORÍGENES POSIBLES (elige UNO según quién es el jugador y con quién conectó):
- future_probe: una sonda enviada desde el año 2190 está enterrada bajo el faro; su núcleo emite el pulso.
- failed_experiment: bajo el faro hay un laboratorio sellado de un proyecto de física de los años 80 que abrió la brecha.
- branch_transmission: otra versión del jugador, desde otra rama, transmite por la frecuencia que capta Samir los planos del Ancla.
- alien_artifact: un objeto de origen no humano estabiliza una brecha natural bajo el faro.
- natural_anomaly: una microbrecha natural que la lente del faro amplifica por accidente.
Pistas: escépticos → explicaciones de laboratorio o naturales; curiosos → sonda o artefacto; quien conectó con Samir → transmisión; con Marina → el faro; con Teo → las filtraciones de memoria."""


## Pide a la IA el Despertar de ESTE jugador. Siempre devuelve uno válido (IA o respaldo).
func generate_awakening() -> Dictionary:
	var neighbors := PackedStringArray()
	for id in ACT0_NEIGHBORS:
		var npc := WorldDB.get_entity("npc", id)
		if not npc.is_empty():
			neighbors.append("%s (%s): %s" % [npc.name, npc.occupation, NPCMemory.describe(id)])
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEres el narrador de EL DESPERTAR: el momento en que el jugador descubre la brecha bajo el faro y obtiene el Ancla. Escribe en segunda persona, con detalle sensorial y explicaciones físicas creíbles. Nada sobrenatural."},
		{"role": "user", "content": """Son las 3:33. El jugador entra en el faro durante el pulso.

QUIÉN ES EL JUGADOR: %s

LO QUE RECUERDA CADA VECINO DE ÉL:
%s

%s

Crea su Despertar:
- "narration": lo que vive (el pulso, la dilatación temporal alrededor del faro, el descubrimiento de la fuente).
- "anchor": el dispositivo que le permite viajar; "base" es el objeto del pueblo sobre el que se construye (o "none").
- "canon_facts": 2-3 hechos que serán verdad para siempre en este mundo.
- "choices": exactamente una opción por consecuencia (jump_alone, jump_with_companion, seal_behind), escritas para esta historia.
- "destination_hint": a qué tipo de lugar o época le llevará su primer salto.""" % [
			PlayerProfile.describe(), "\n".join(neighbors), ORIGIN_GUIDE]},
	]
	var res := await ContentGenerator.request_valid("awakening", messages)
	var data: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("awakening")
	data["source"] = "ai" if res.ok else "fallback"
	_ensure_distinct(data.choices, "consequence", ContentValidator.archetypes().awakening_consequence)
	if not res.ok:
		push_warning("El Despertar usó respaldo: %s" % [res.errors])
	return data


## Aplica la decisión: canon, Ancla, compañero, stats y raíz del árbol temporal.
## No salta: eso lo hace Travel.jump_new() justo después.
func apply_awakening(data: Dictionary, choice_index: int) -> Dictionary:
	var choice: Dictionary = data.choices[clampi(choice_index, 0, data.choices.size() - 1)]
	var consequence: String = choice.consequence
	var companion := _closest_neighbor() if consequence == "jump_with_companion" else ""
	GameState.awaken(companion, consequence == "seal_behind")

	for fact in data.canon_facts:
		WorldDB.add_canon(fact)
	WorldDB.add_canon("En El Despertar, el jugador decidió: %s" % choice.text)

	var anchor_id := WorldDB.add_entity("item", {
		"name": data.anchor.name, "kind": "technology", "effect": "none", "power": 100,
		"lore": data.anchor.description, "tags": ["ancla", data.anchor.base],
	}, "awakening")
	WorldDB.set_state("awakening", {
		"origin": data.origin, "title": data.title, "anchor_id": anchor_id,
		"consequence": consequence, "choice": choice.text, "destination_hint": data.destination_hint,
	})

	if not companion.is_empty():
		NPCMemory.add_facts(companion, ["Decidió cruzar la brecha junto al jugador en El Despertar."], 15)
	TimelineManager.create_root("El Despertar", GameState.HOME, "present")
	return {"consequence": consequence, "companion": companion, "anchor_id": anchor_id}


# --- El final -------------------------------------------------------------------------

## La revelación del origen de la señal y los tres finales, escritos con TODO lo vivido.
func generate_finale() -> Dictionary:
	var awakening: Dictionary = WorldDB.get_state("awakening", {})
	var places := PackedStringArray()
	for n in TimelineManager.visited_locations():
		places.append(Travel.location_name(n.location_id))
	var quests := PackedStringArray()
	for q in Quests.all_quests():
		if q.status == "done":
			quests.append(q.title)
	var companion := WorldDB.get_entity("npc", GameState.companion())
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEres el narrador del FINAL. Cierra la historia de este jugador con coherencia total con el canon, en segunda persona, con emoción contenida y física creíble."},
		{"role": "user", "content": """El jugador ha reunido las coordenadas completas de la transmisión de radio que Samir captaba cada noche a las 3:33 en Bahía de las Horas, y ha llegado a su origen.

Origen de su Ancla: %s (%s)
Decisión en El Despertar: %s
Compañero: %s
Lugares recorridos: %s
Misiones completadas: %s
Quién es: %s

Escribe:
- "revelation": qué es realmente el origen de la señal y por qué el jugador. Debe encajar con el origen del Ancla y el canon.
- "source_voice": lo que dice la propia señal (o quien la emite) al jugador.
- "choices": exactamente tres, una por final: close_the_loop (convertirse en el emisor y cerrar el bucle causal), return_home (volver a Bahía de las Horas y apagar el Ancla), keep_traveling (dejar el emisor y seguir explorando). Cada una con su "epilogue": cómo termina la historia, mencionando detalles de su viaje.""" % [
			awakening.get("origin", "?"), awakening.get("title", ""), awakening.get("choice", "?"),
			companion.get("name", "nadie"), ", ".join(places), ", ".join(quests), PlayerProfile.describe()]},
	]
	var res := await ContentGenerator.request_valid("finale", messages)
	var data: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("finale")
	data["source"] = "ai" if res.ok else "fallback"
	_ensure_distinct(data.choices, "ending", ContentValidator.archetypes().ending)
	return data


## Guarda el final elegido. El mundo queda "completado", pero se puede seguir jugando.
func apply_ending(data: Dictionary, choice_index: int) -> Dictionary:
	var choice: Dictionary = data.choices[clampi(choice_index, 0, data.choices.size() - 1)]
	GameState.set_ending(choice.ending)
	WorldDB.add_canon("Final: %s" % choice.text)
	WorldDB.set_state("finale", {"title": data.title, "ending": choice.ending, "epilogue": choice.epilogue})
	return {"ending": choice.ending, "epilogue": choice.epilogue, "title": data.title}


## El vecino con mejor relación (a igualdad, el que más ha hablado contigo) te acompaña.
func _closest_neighbor() -> String:
	var best := ""
	var best_score := -INF
	for id in ACT0_NEIGHBORS:
		var m := NPCMemory.get_mem(id)
		var score := float(m.relationship) * 10.0 + float(m.conversations)
		if score > best_score:
			best = id
			best_score = score
	return best


func _system_prompt(npc: Dictionary, scene_context: String) -> String:
	return """%s

INTERPRETAS A ESTE PERSONAJE (habla siempre en primera persona, como en una conversación real):
Nombre: %s, %d años, %s.
Personalidad: %s.
Objetivos: %s.
Secreto (no lo reveles a la ligera; solo si hay mucha confianza o motivo): %s

TU MEMORIA SOBRE EL JUGADOR:
%s

QUIÉN ES EL JUGADOR (según cómo ha jugado):
%s

ESCENA: %s

CÓMO RESPONDER (JSON):
- "line": lo que dices ahora, natural y breve (1 a 4 frases). Reacciona a lo último que dijo el jugador.
- "emotion": cómo te sientes al decirlo.
- "choices": 2 a 4 respuestas posibles PARA EL JUGADOR, variadas en tono; al menos una que permita despedirse.
- "new_facts": 0 a 2 cosas importantes que acabas de aprender del jugador o que acaban de pasar (en tercera persona).
- "relationship_delta": cuánto mejora o empeora tu opinión del jugador por lo que acaba de decir.
- "trait_signals": qué rasgos ha mostrado el jugador con su ÚLTIMO mensaje (vacío si no aplica).
- "end_conversation": true solo si la conversación termina de forma natural.""" % [
		ContentGenerator.world_rules_prompt(),
		npc.name, int(npc.age), npc.occupation,
		", ".join(PackedStringArray(npc.personality)),
		"; ".join(PackedStringArray(npc.goals)),
		npc.secret,
		NPCMemory.describe(npc.id),
		PlayerProfile.describe(),
		scene_context,
	]


func _opening(npc_id: String) -> String:
	if NPCMemory.get_mem(npc_id).met:
		return "(El jugador vuelve a acercarse para hablar contigo. Salúdale teniendo en cuenta lo que recuerdas.)"
	return "(El jugador se acerca a ti por primera vez. Preséntate a tu manera.)"

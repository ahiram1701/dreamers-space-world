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
		messages.append({"role": "user" if h.who == "player" else "assistant", "content": h.text})
	var said := player_input.strip_edges()
	messages.append({"role": "user", "content": said if not said.is_empty() else _opening(npc_id)})

	var res := await ContentGenerator.request_valid("dialogue_turn", messages)
	var turn: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("dialogue_turn")
	turn["ok"] = true
	turn["source"] = "ai" if res.ok else "fallback"
	if not res.ok:
		push_warning("StoryDirector usó respaldo: %s" % [res.errors])

	NPCMemory.record_turn(npc_id, said, turn.line, turn.get("new_facts", []), int(turn.relationship_delta))
	if not said.is_empty():  # solo lo que el jugador dice o elige revela su carácter
		PlayerProfile.apply_signals(turn.get("trait_signals", []))
	turn_finished.emit(npc_id, turn)
	return turn


func end_conversation(npc_id: String) -> void:
	NPCMemory.end_conversation(npc_id)


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

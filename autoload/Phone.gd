extends Node
## El celular del jugador: contactos (la gente cuyo número tienes), mensajes y llamadas.
## Los mensajes los contesta la IA como en un chat (con un retraso realista); también te escriben
## por iniciativa propia cuando tienen algo que contarte. Quien duerme, está muy enojado o no te
## soporta no contesta.

signal message_received(npc_id: String, text: String)
signal message_sent(npc_id: String, text: String)

const MAX_MESSAGES := 30
const NIGHT_FROM := 23.5
const NIGHT_TO := 7.0
const OWN_INITIATIVE_EVERY := 180.0   # minutos de juego entre mensajes que te mandan sin que escribas
const PER_CONTACT_EVERY := 12 * 60.0

## Lo asigna la escena: contexto del lugar (para que el PNJ sepa la hora, el tiempo…).
var scene_context: Callable = func(): return ""

var _pending: Array = []         # respuestas que llegan más tarde: {npc_id, text, notes, at_ms}
var _waiting_morning: Array = [] # mensajes escritos de noche: se contestan por la mañana
var _busy := {}
var _last_check := -1.0


# --- Contactos ------------------------------------------------------------------------------

## ¿Lleva el jugador un celular encima? (si lo da o se le rompe, no hay llamadas ni mensajes)
func has_phone() -> bool:
	for id in Inventory.items():
		if WorldDB.get_entity("item", id).get("effect", "") == "phone":
			return true
	return false


## Da al jugador su celular (al empezar un mundo). No duplica.
func ensure_phone() -> void:
	if not WorldDB.is_loaded() or WorldDB.get_state("phone_given", false):
		return
	WorldDB.set_state("phone_given", true)
	var id := WorldDB.add_entity("item", {"name": "Celular", "kind": "technology", "effect": "phone", "power": 0,
		"lore": "Tu celular de siempre, con la pantalla un poco rayada. Llamadas, mensajes, el banco y el mapa.", "tags": ["celular"]}, "start")
	Inventory.add(id)


func contacts() -> Array:
	var out := []
	var all: Dictionary = WorldDB.get_state("memories", {})
	for id in all:
		if bool(NPCMemory.get_mem(id).get("phone", false)) and not WorldDB.get_entity("npc", id).is_empty():
			out.append(id)
	out.sort_custom(func(a, b): return _last_at(a) > _last_at(b))
	return out


func add_contact(npc_id: String) -> void:
	NPCMemory.set_fields(npc_id, {"phone": true})


func messages(npc_id: String) -> Array:
	return NPCMemory.get_mem(npc_id).get("messages", [])


func _last_at(npc_id: String) -> float:
	var m := messages(npc_id)
	return float(m[-1].at) if not m.is_empty() else -1.0


func _push(npc_id: String, from: String, text: String) -> void:
	var list: Array = messages(npc_id).duplicate()
	list.append({"from": from, "text": text, "at": WorldClock.absolute_minutes(), "read": from == "player"})
	while list.size() > MAX_MESSAGES:
		list.pop_front()
	NPCMemory.set_fields(npc_id, {"messages": list})


func unread(npc_id: String = "") -> int:
	var n := 0
	for id in ([npc_id] if not npc_id.is_empty() else contacts()):
		for m in messages(id):
			if m.from == "npc" and not m.get("read", true):
				n += 1
	return n


func mark_read(npc_id: String) -> void:
	var list: Array = messages(npc_id).duplicate(true)
	for m in list:
		m["read"] = true
	NPCMemory.set_fields(npc_id, {"messages": list})


# --- ¿Contesta? -----------------------------------------------------------------------------

func _asleep(npc_id: String) -> bool:
	var h := WorldClock.hour()
	return (h >= NIGHT_FROM or h < NIGHT_TO) and not NPCMemory.is_following(npc_id)


## Motivo por el que no contesta una llamada ("" si contesta).
func call_refusal(npc_id: String) -> String:
	var name: String = WorldDB.get_entity("npc", npc_id).get("name", "Nadie").split(" ")[0]
	if not has_phone():
		return "No llevas el celular."
	if _asleep(npc_id):
		return "%s no contesta. A estas horas debe de estar durmiendo." % name
	if NPCMemory.refusal_left(npc_id) > 0 or int(NPCMemory.get_mem(npc_id).relationship) <= -45:
		return "%s ve tu llamada y la rechaza." % name
	return ""


## Contexto de una llamada o un chat: no estás con esa persona.
func remote_context(npc_id: String, call: bool) -> String:
	var lines := PackedStringArray([str(scene_context.call()) if scene_context.is_valid() else "", WorldClock.describe()])
	lines.append("TU SITUACIÓN: NO estás con el jugador. %s No puedes darle ni recibir objetos ahora; si quieres verle, quedan en un sitio (go_to) o vas hacia él (approach)." % (
		"Hablan por teléfono (llamada de voz)." if call else "Se escriben por mensajes de texto del celular: contesta como en un chat, corto y natural (1 a 3 frases, sin acotaciones)."))
	if not call:
		var chat := PackedStringArray()
		for m in messages(npc_id).slice(-8):
			chat.append("%s: %s" % ["Jugador" if m.from == "player" else "Tú", m.text])
		if not chat.is_empty():
			lines.append("CHAT RECIENTE:\n" + "\n".join(chat))
	return "\n".join(lines)


# --- Mensajes -------------------------------------------------------------------------------

## El jugador escribe. La respuesta llega sola más tarde (message_received).
func send(npc_id: String, text: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or not has_phone():
		return
	_push(npc_id, "player", text)
	message_sent.emit(npc_id, text)
	if _asleep(npc_id):
		_waiting_morning.append(npc_id)  # lo leerá al despertar
		return
	if NPCMemory.refusal_left(npc_id) > 0 or int(NPCMemory.get_mem(npc_id).relationship) <= -45:
		return  # te deja en visto
	_reply(npc_id, text)


func _reply(npc_id: String, text: String) -> void:
	if _busy.get(npc_id, false):
		return
	_busy[npc_id] = true
	var turn: Dictionary = await StoryDirector.talk(npc_id, "(Por mensaje) " + text, remote_context(npc_id, false))
	StoryDirector.end_conversation(npc_id)
	_busy[npc_id] = false
	if not turn.get("ok", false) or turn.get("source", "") != "ai":
		return
	# Se escribe con calma: entre 5 y 20 segundos, según lo largo
	_pending.append({"npc_id": npc_id, "text": str(turn.line), "at_ms": Time.get_ticks_msec() + int(clampf(str(turn.line).length() * 90.0, 5000.0, 20000.0))})


func _deliver(npc_id: String, text: String) -> void:
	_push(npc_id, "npc", text)
	message_received.emit(npc_id, text)


func _process(_delta: float) -> void:
	if not WorldDB.is_loaded():
		return
	var now := Time.get_ticks_msec()
	for p in _pending.duplicate():
		if now >= p.at_ms:
			_pending.erase(p)
			_deliver(p.npc_id, p.text)
	if not _waiting_morning.is_empty() and not _asleep(_waiting_morning[0]):
		var id: String = _waiting_morning.pop_front()
		var last := messages(id)
		if not last.is_empty() and last[-1].from == "player":
			_reply(id, last[-1].text)
	# Que te escriban por iniciativa propia (cada pocas horas de juego, con algo que contar)
	var minutes := WorldClock.absolute_minutes()
	if _last_check < 0.0:
		_last_check = minutes
	if minutes - _last_check >= 30.0:
		_last_check = minutes
		_maybe_text_first()


func _maybe_text_first() -> void:
	if Settings.use_mock or not Settings.has_api_key() or not has_phone():
		return
	var now := WorldClock.absolute_minutes()
	if now - float(WorldDB.get_state("phone_last_initiative", -1e9)) < OWN_INITIATIVE_EVERY:
		return
	for id in contacts():
		if _asleep(id) or _busy.get(id, false) or now - float(NPCMemory.get_mem(id).get("texted_at", -1e9)) < PER_CONTACT_EVERY:
			continue
		var recent: Array = NPCMemory.get_mem(id).recent
		var news: String = recent[-1].text if not recent.is_empty() and now - float(recent[-1].at) < 600.0 else ""
		var friendly := int(NPCMemory.get_mem(id).relationship) >= 15
		if news.is_empty() and not (friendly and randf() < 0.3):
			continue
		WorldDB.set_state("phone_last_initiative", now)
		NPCMemory.set_fields(id, {"texted_at": now})
		_busy[id] = true
		var why := ("Te acabas de enterar de esto y se lo quieres comentar o preguntar: «%s»." % news) if not news.is_empty() \
			else "Hace un rato que no saben el uno del otro y te apetece escribirle (por algo de tu vida, del pueblo o de lo raro que está pasando)."
		var turn: Dictionary = await StoryDirector.talk(id, "(Esto no lo escribe el jugador: decides TÚ mandarle un mensaje por el celular. %s Escribe solo tu mensaje.)" % why,
			remote_context(id, false))
		StoryDirector.end_conversation(id)
		_busy[id] = false
		if turn.get("ok", false) and turn.get("source", "") == "ai":
			_deliver(id, str(turn.line))
		return

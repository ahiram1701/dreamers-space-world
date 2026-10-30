extends Node
## Objetos que lleva el jugador (ids de entidades "item" de WorldDB).
## Los objetos con efecto se gastan al usarlos; los demás (como el Ancla) son recuerdos.

signal changed
signal used(item_id: String, message: String)

const EFFECT_LABELS := {
	"none": "Sin efecto", "heal": "Cura", "restore_temporal_energy": "Recarga el Ancla",
	"reduce_paradox": "Reduce la inestabilidad", "reveal_secret": "Revela un secreto",
	"unlock_location": "Coordenadas: próximo salto gratis", "boost_reputation": "Mejora la confianza de quien está cerca",
	"light": "Da luz", "nourish": "Se come", "hydrate": "Se bebe", "phone": "Celular", "signal": "Capta señales",
	"warmth": "Abriga", "tool": "Herramienta",
}
## Efectos que no gastan el objeto al usarlo (una linterna se enciende y se apaga, no desaparece).
const KEEP := ["light", "phone", "signal", "warmth", "tool"]

## Encender o apagar la luz que llevas (el jugador la muestra).
signal light_toggled(on: bool)
## Abrir el celular / pedir una acción con F ("Enciendo la radio y escucho").
signal phone_requested
signal action_requested(text: String)


func items() -> Array:
	return WorldDB.get_state("inventory", [])


func has(item_id: String) -> bool:
	return item_id in items()


func add(item_id: String) -> void:
	var list := items()
	if not (item_id in list):
		list.append(item_id)
		WorldDB.set_state("inventory", list)
		changed.emit()


func remove(item_id: String) -> void:
	var list := items()
	list.erase(item_id)
	WorldDB.set_state("inventory", list)
	changed.emit()


## Busca un objeto del jugador por nombre aproximado ("la radio" → "Radio de onda corta").
func find_by_name(text: String) -> String:
	var wanted := _words(text)
	if wanted.is_empty():
		return ""
	var best := ""
	var best_hits := 0
	for id in items():
		var name_words := _words(WorldDB.get_entity("item", id).get("name", ""))
		var hits := 0
		for w in wanted:
			for n in name_words:
				if n.begins_with(w) or w.begins_with(n):
					hits += 1
					break
		if hits > best_hits:
			best = id
			best_hits = hits
	return best


## El Ancla no se puede regalar ni perder: sin ella no hay viaje.
func is_anchor(item_id: String) -> bool:
	return item_id == WorldDB.get_state("awakening", {}).get("anchor_id", "")


## "Prestado por Samir" o "" si es tuyo.
func lent_label(item_id: String) -> String:
	var owner: String = WorldDB.get_entity("item", item_id).get("lent_by", "")
	if owner.is_empty():
		return ""
	return "prestado por %s" % WorldDB.get_entity("npc", owner).get("name", "alguien")


func _words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for w in text.to_lower().replace("«", " ").replace("»", " ").replace(",", " ").replace(".", " ").split(" ", false):
		if w.length() >= 3 and not (w in ["del", "las", "los", "una", "uno", "con", "para", "mi", "tu", "the"]):
			out.append(w)
	return out


func is_usable(item_id: String) -> bool:
	return WorldDB.get_entity("item", item_id).get("effect", "none") != "none"


## Aplica el efecto del objeto. `nearby_npcs`: PNJs del lugar actual (para secretos y confianza).
## Devuelve el mensaje para el jugador.
func use(item_id: String, nearby_npcs: Array = []) -> String:
	var item := WorldDB.get_entity("item", item_id)
	if item.is_empty() or not has(item_id):
		return ""
	var power := maxi(int(item.get("power", 20)), 10)
	var msg := ""
	match item.get("effect", "none"):
		"heal":
			GameState.change_stat("health", power)
			msg = "Recuperas salud (+%d)." % power
		"restore_temporal_energy":
			GameState.change_stat("energy", power)
			msg = "El Ancla absorbe la energía (+%d)." % power
		"reduce_paradox":
			GameState.change_stat("instability", -power)
			msg = "Tu estado se estabiliza (−%d de inestabilidad)." % power
		"unlock_location":
			GameState.grant_free_jump()
			msg = "Las coordenadas quedan grabadas en el Ancla: tu próximo salto no gastará energía."
		"reveal_secret":
			msg = _reveal_secret(nearby_npcs)
		"boost_reputation":
			for npc_id in nearby_npcs:
				NPCMemory.add_facts(npc_id, [], 15)
			msg = "La gente de aquí te mira con otros ojos." if not nearby_npcs.is_empty() else "No hay nadie cerca a quien impresionar."
		"nourish":
			Body.change("hunger", clampf(power * 1.5, 20.0, 60.0))
			msg = "Te comes %s." % item.get("name", "eso")
		"hydrate":
			Body.change("thirst", clampf(power * 2.0, 25.0, 70.0))
			msg = "Te bebes %s." % item.get("name", "eso")
		"light":
			var on := not bool(WorldDB.get_state("light_on", false))
			WorldDB.set_state("light_on", on)
			light_toggled.emit(on)
			msg = ("Enciendes %s." if on else "Apagas %s.") % item.get("name", "la luz")
		"phone":
			phone_requested.emit()
			return ""
		"signal":
			action_requested.emit("Enciendo «%s» y busco alguna señal" % item.get("name", "la radio"))
			return ""
		"warmth":
			var wearing := str(WorldDB.get_state("wearing", ""))
			WorldDB.set_state("wearing", "" if wearing == item_id else item_id)
			msg = ("Te quitas %s." if wearing == item_id else "Te pones %s.") % item.get("name", "eso")
		"tool":
			msg = "Llevas %s a mano: úsalo con F (\"corto…\", \"arreglo…\")." % item.get("name", "la herramienta")
		_:
			return "%s no tiene ningún uso ahora mismo." % item.get("name", "Este objeto")
	if item.get("effect", "none") in KEEP:
		used.emit(item_id, msg)
		return msg
	remove(item_id)
	used.emit(item_id, msg)
	return msg


func _reveal_secret(nearby_npcs: Array) -> String:
	for npc_id in nearby_npcs:
		var npc := WorldDB.get_entity("npc", npc_id)
		if not npc.is_empty():
			NPCMemory.add_facts(npc_id, ["El jugador conoce su secreto."], 0)
			return "Descubres algo sobre %s: %s" % [npc.name, npc.secret]
	return "Los datos están cifrados con referencias a gente que no está aquí."

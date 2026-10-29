extends Node
## Objetos que lleva el jugador (ids de entidades "item" de WorldDB).
## Los objetos con efecto se gastan al usarlos; los demás (como el Ancla) son recuerdos.

signal changed
signal used(item_id: String, message: String)

const EFFECT_LABELS := {
	"none": "Sin efecto", "heal": "Cura", "restore_temporal_energy": "Recarga el Ancla",
	"reduce_paradox": "Reduce la inestabilidad", "reveal_secret": "Revela un secreto",
	"unlock_location": "Coordenadas: próximo salto gratis", "boost_reputation": "Mejora la confianza de quien está cerca",
}


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
		_:
			return "%s no tiene ningún uso ahora mismo." % item.get("name", "Este objeto")
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

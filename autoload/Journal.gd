extends Node
## Diario del jugador: pistas, promesas y lugares que alguien le ha contado.
## Entrada: { text, by (id de PNJ o ""), at (fecha) }

signal added(entry: Dictionary)

const MAX_ENTRIES := 60


func entries() -> Array:
	return WorldDB.get_state("journal", [])


func add(text: String, by: String = "") -> void:
	var list := entries()
	for e in list:
		if e.text == text:
			return
	var entry := {"text": text, "by": by, "at": Time.get_datetime_string_from_system()}
	list.append(entry)
	while list.size() > MAX_ENTRIES:
		list.pop_front()
	WorldDB.set_state("journal", list)
	added.emit(entry)

extends Node
## Diario del jugador: pistas, promesas y lugares que alguien le ha contado.
## Entrada: { text, by (id de PNJ o ""), at (fecha) }

signal added(entry: Dictionary)

const MAX_ENTRIES := 60


const MAX_LOG := 60


## Registro: todo lo que te pasó y te dijeron (los avisos que se van de la pantalla y las frases
## que suelta la gente), para poder volver a leerlo en el Cuaderno.
func log_event(text: String, kind: String = "info") -> void:
	if not WorldDB.is_loaded() or text.strip_edges().is_empty():
		return
	var list: Array = WorldDB.get_state("log", [])
	list.append({"text": text, "kind": kind, "at": WorldClock.absolute_minutes()})
	while list.size() > MAX_LOG:
		list.pop_front()
	WorldDB.set_state("log", list)


func log_entries() -> Array:
	return WorldDB.get_state("log", []) if WorldDB.is_loaded() else []


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

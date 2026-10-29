extends Node
## La base de datos del mundo de CADA jugador: lo que hace que dos partidas sean juegos distintos.
## Hoy se guarda como JSON en user://worlds/<id>/world.json. La interfaz pública
## (create/load/add/get/query) está pensada para cambiar a SQLite sin tocar a quien la usa.

signal entity_added(type: String, id: String)
signal world_loaded(world_id: String)

const ROOT := "user://worlds/"
const FORMAT_VERSION := 1
const LAST_WORLD_PATH := "user://last_world.txt"

var world_id: String = ""
var _data: Dictionary = {}


func is_loaded() -> bool:
	return not world_id.is_empty()


func create_world(display_name: String) -> String:
	var id := "w%d_%04x" % [int(Time.get_unix_time_from_system()), randi() % 0x10000]
	world_id = id
	_data = {
		"format_version": FORMAT_VERSION,
		"name": display_name,
		"created_at": Time.get_datetime_string_from_system(),
		"entities": {},  # type -> { entity_id -> entidad }
		"canon": [],     # hechos confirmados que la IA no puede contradecir
		"state": {},     # memorias de PNJ, perfil del jugador, progreso de actos...
	}
	save()
	_remember_last(id)
	world_loaded.emit(world_id)
	return id


func load_world(id: String) -> bool:
	var path := _path(id)
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Mundo corrupto: %s" % path)
		return false
	world_id = id
	_data = parsed
	_remember_last(id)
	world_loaded.emit(world_id)
	return true


func last_world_id() -> String:
	if not FileAccess.file_exists(LAST_WORLD_PATH):
		return ""
	var id := FileAccess.get_file_as_string(LAST_WORLD_PATH).strip_edges()
	return id if FileAccess.file_exists(_path(id)) else ""


func list_worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out
	for id in dir.get_directories():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path(id)))
		if typeof(parsed) == TYPE_DICTIONARY:
			var state: Dictionary = parsed.get("state", {})
			var game: Dictionary = state.get("game", {})
			var location: String = game.get("location", "home")
			var place: String = "Bahía de las Horas" if location == "home" \
				else parsed.get("entities", {}).get("location", {}).get(location, {}).get("name", "?")
			out.append({
				"id": id, "name": parsed.get("name", id), "created_at": parsed.get("created_at", ""),
				"place": place, "awakened": game.get("awakened", false),
				"fragments": int(game.get("fragments", 0)), "ending": game.get("ending", ""),
			})
	out.sort_custom(func(a, b): return a.created_at > b.created_at)
	return out


## origin: qué decisión/evento creó esta entidad (el mundo es la historia del jugador).
## forced_id: solo para el contenido base escrito a mano (p. ej. los PNJs del Acto 0).
func add_entity(type: String, data: Dictionary, origin: String, forced_id: String = "") -> String:
	assert(is_loaded(), "WorldDB: no hay mundo cargado")
	var bucket: Dictionary = _data.entities.get_or_add(type, {})
	var id := forced_id if not forced_id.is_empty() else "%s_%d" % [type, bucket.size() + 1]
	var entity := data.duplicate(true)
	entity["id"] = id
	entity["type"] = type
	entity["origin"] = origin
	entity["created_at"] = Time.get_datetime_string_from_system()
	bucket[id] = entity
	save()
	entity_added.emit(type, id)
	return id


## Añade o cambia campos de una entidad existente (p. ej. los PNJs que viven en un lugar).
func update_entity(type: String, id: String, fields: Dictionary) -> void:
	var entity: Dictionary = _data.get("entities", {}).get(type, {}).get(id, {})
	if entity.is_empty():
		return
	entity.merge(fields, true)
	save()


## Borra un mundo del disco (lo usan las pruebas para no dejar basura).
func delete_world(id: String) -> void:
	var dir := ROOT + id
	DirAccess.remove_absolute(_path(id))
	DirAccess.remove_absolute(dir)
	if id == world_id:
		world_id = ""
		_data = {}


func get_entity(type: String, id: String) -> Dictionary:
	return _data.get("entities", {}).get(type, {}).get(id, {})


## Filtra por tipo y, opcionalmente, por una etiqueta.
func query(type: String, tag: String = "") -> Array:
	var all: Array = _data.get("entities", {}).get(type, {}).values()
	if tag.is_empty():
		return all
	return all.filter(func(e): return tag in e.get("tags", []))


func add_canon(fact: String) -> void:
	_data.canon.append(fact)
	save()


func canon() -> Array:
	return _data.get("canon", [])


## Estado libre por mundo. Devuelve una copia: para cambiarlo, usa set_state().
func get_state(key: String, default: Variant = null) -> Variant:
	var value = _data.get("state", {}).get(key, default)
	return value.duplicate(true) if value is Dictionary or value is Array else value


func set_state(key: String, value: Variant) -> void:
	_data.get_or_add("state", {})[key] = value
	save()


func save() -> void:
	if not is_loaded():
		return
	DirAccess.make_dir_recursive_absolute(ROOT + world_id)
	var f := FileAccess.open(_path(world_id), FileAccess.WRITE)
	if f == null:
		push_error("No se pudo guardar el mundo: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(_data, "\t"))


func _path(id: String) -> String:
	return ROOT + id + "/world.json"


func set_last_world_id(id: String) -> void:
	_remember_last(id)


func _remember_last(id: String) -> void:
	var f := FileAccess.open(LAST_WORLD_PATH, FileAccess.WRITE)
	if f:
		f.store_string(id)

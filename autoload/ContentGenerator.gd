extends Node
## Pide a la IA nuevas entidades, las valida y las guarda en el mundo del jugador.
## Si la IA falla dos veces, usa contenido de respaldo: el juego nunca se queda bloqueado.
##
## Uso:  var r := await ContentGenerator.generate("npc", "alguien que trabaja en el muelle", "act0:muelle")
##       r = { ok, id, entity, source: "ai" | "fallback", errors }

signal generation_started(type: String)
signal generation_finished(result: Dictionary)

const BIBLE_PATH := "res://data/world_bible.json"
const FALLBACK_DIR := "res://data/fallback/"
const TYPE_NAMES := {"npc": "un personaje (PNJ)", "location": "un lugar", "item": "un objeto"}

var _bible: String = ""


func generate(type: String, hint: String, origin: String, context: Dictionary = {}) -> Dictionary:
	generation_started.emit(type)
	var messages := [
		{"role": "system", "content": world_rules_prompt() + "\n\nEres el diseñador de mundos: creas contenido NUEVO y original."},
		{"role": "user", "content": _user_prompt(type, hint, context)},
	]
	var res := await request_valid(type, messages)
	if res.ok:
		return _finish(type, res.data, origin, "ai", res.errors)

	var fallback := load_fallback(type)
	if fallback.is_empty():
		var fail := {"ok": false, "id": "", "entity": {}, "source": "none", "errors": res.errors}
		generation_finished.emit(fail)
		return fail
	return _finish(type, fallback, origin, "fallback", res.errors)


## Pide a la IA un JSON del tipo `spec_type` y lo valida; si no es válido le devuelve
## sus errores una vez para que se corrija. Lo usan también StoryDirector y futuros sistemas.
## Devuelve { ok, data, errors }.
func request_valid(spec_type: String, messages: Array) -> Dictionary:
	var schema := ContentValidator.to_json_schema(spec_type)
	var errors: Array = []
	for _attempt in 2:
		var res := await AIClient.chat(messages, schema, spec_type)
		if not res.ok:
			errors.append(res.error)
			break  # error de red/API: reintentar no ayuda, AIClient ya reintentó
		var check := ContentValidator.validate(spec_type, res.data)
		if check.ok:
			return {"ok": true, "data": check.data, "errors": errors}
		errors.append_array(check.errors)
		messages.append({"role": "assistant", "content": res.text})
		messages.append({"role": "user", "content":
			"Tu JSON tiene estos errores, corrígelos y responde solo con el JSON:\n- " + "\n- ".join(PackedStringArray(check.errors))})
	return {"ok": false, "data": null, "errors": errors}


## Reglas fijas del multiverso + canon de ESTE mundo. Base de todos los prompts de sistema.
func world_rules_prompt() -> String:
	if _bible.is_empty():
		_bible = FileAccess.get_file_as_string(BIBLE_PATH)
	var canon := WorldDB.canon()
	var canon_text := "(aún no hay hechos canónicos)" if canon.is_empty() else "- " + "\n- ".join(PackedStringArray(canon))
	return """Trabajas para un videojuego que crece con cada jugador.
Respondes SIEMPRE con un único objeto JSON válido, sin texto adicional.
Escribe los textos en idioma: %s.

REGLAS DEL MULTIVERSO:
%s

HECHOS CANÓNICOS DE ESTE MUNDO (no los contradigas):
%s""" % [Settings.language, _bible, canon_text]


func load_fallback(spec_type: String) -> Dictionary:
	var path := FALLBACK_DIR + spec_type + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _finish(type: String, data: Dictionary, origin: String, source: String, errors: Array) -> Dictionary:
	var id := WorldDB.add_entity(type, data, origin)
	var result := {"ok": true, "id": id, "entity": WorldDB.get_entity(type, id), "source": source, "errors": errors}
	generation_finished.emit(result)
	return result


func _user_prompt(type: String, hint: String, context: Dictionary) -> String:
	# Nombres ya usados, para que la IA no repita personajes o lugares
	var existing := WorldDB.query(type).map(func(e): return e.get("name", ""))
	return """Crea %s para este mundo.
Petición: %s
Contexto actual: %s
Nombres que YA existen (no los repitas): %s""" % [
		TYPE_NAMES.get(type, type), hint, JSON.stringify(context), ", ".join(PackedStringArray(existing))]

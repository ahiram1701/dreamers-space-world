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
	# No todos los modelos respetan "format": el formato también va escrito en el prompt
	messages = messages.duplicate(true)
	var format_text := "\n\nFORMATO DE RESPUESTA: un único objeto JSON con estas claves (claves y valores de lista EXACTAMENTE como aparecen, en inglés; los textos, en español):\n" \
		+ ContentValidator.describe_format(spec_type)
	if not messages.is_empty() and messages[0].role == "system":
		messages[0].content += format_text
	else:
		messages.push_front({"role": "system", "content": format_text.strip_edges()})
	var errors: Array = []
	for _attempt in 2:
		var res := await AIClient.chat(messages, schema, spec_type)
		if not res.ok:
			errors.append(res.error)
			break  # error de red/API: reintentar no ayuda, AIClient ya reintentó
		if typeof(res.data) != TYPE_DICTIONARY:
			res.data = _extract_json(res.text)  # algunos modelos envuelven el JSON en texto
		var check := ContentValidator.validate(spec_type, res.data)
		if check.ok:
			return {"ok": true, "data": check.data, "errors": errors, "warnings": check.warnings}
		errors.append_array(check.errors)
		messages.append({"role": "assistant", "content": res.text})
		messages.append({"role": "user", "content":
			"Tu JSON tiene estos errores, corrígelos y responde solo con el JSON:\n- " + "\n- ".join(PackedStringArray(check.errors))})
	push_warning("IA (%s) sin respuesta válida: %s" % [spec_type, errors])
	return {"ok": false, "data": null, "errors": errors}


## Saca el primer objeto JSON de un texto ("Aquí tienes: ```json {...} ```" → {...}).
func _extract_json(text: String) -> Variant:
	var start := text.find("{")
	var end := text.rfind("}")
	if start == -1 or end <= start:
		return null
	return JSON.parse_string(text.substr(start, end - start + 1))


## Reglas fijas del multiverso + canon de ESTE mundo. Base de todos los prompts de sistema.
## Reglas extra por tipo: lo que se describe tiene que poder construirse.
const EXTRA_RULES := {
	"location": """
REGLAS DEL LUGAR:
- "points_of_interest": de 3 a 5 sitios concretos, cada uno con "name" (nombre propio corto) y "kind" (qué es, de la lista). El juego construye cada uno con esa forma: si dices "lighthouse" habrá un faro con puerta; si dices "console", una consola.
- "description": solo puede mencionar cosas que estén en points_of_interest o en el paisaje (bioma, cielo, edificios genéricos). Nada de salas, sótanos ni aparatos que no estén en la lista.
- "problem": qué le pasa a la gente de aquí, concreto y humano (se rompió algo, falta algo, alguien se perdió), con lo que el jugador puede ayudar.""",
	"npc": """
REGLAS DE LA PERSONA:
- "workplace": el nombre EXACTO de uno de los puntos de interés del lugar (contexto: puntos_de_interes) donde trabaja o pasa el día. Su oficio debe encajar con ese sitio.
- "greeting": cómo saluda a un desconocido que no ha visto nunca: no sabe su nombre ni de dónde viene.""",
}


func world_rules_prompt() -> String:
	if _bible.is_empty():
		_bible = FileAccess.get_file_as_string(BIBLE_PATH)
	var canon := WorldDB.canon()
	var canon_text := "(aún no hay hechos canónicos)" if canon.is_empty() else "- " + "\n- ".join(PackedStringArray(canon))
	return """Trabajas para un videojuego que crece con cada jugador.
Respondes SIEMPRE con un único objeto JSON válido, sin texto adicional.
Escribe los textos en idioma: %s. Usa ESPAÑOL LATINOAMERICANO NEUTRO: "ustedes" (nunca "vosotros", ni "os", "vuestro", "habéis"), "celular", "computadora", "carro", "manejar", "agarrar", "platicar", "enojado", "lentes", "jugo", "departamento"; nunca "vale", "coger", "móvil", "ordenador", "coche", "conducir", "tío", "mola", "guay", "enfadado". Sin modismos de un país concreto.
HORAS: siempre en formato de 12 horas y sin ambigüedad: «a las 3 de la mañana», «a las 3:33 a. m.», «a las 5 de la tarde»; nunca «15:00» ni «a las 3» a secas.
ESTILO: concreto y cotidiano; frases cortas; di qué se ve, qué pasa y qué está en juego. Nada de jerga técnica o mística (cuántico, coherencia, espacio-tiempo, frecuencia, resonancia, nodo, singularidad).

REGLAS DEL MULTIVERSO:
%s

HECHOS CANÓNICOS DE ESTE MUNDO (no los contradigas):
%s""" % [Settings.language, _bible, canon_text]


func load_fallback(spec_type: String) -> Dictionary:
	var path := FALLBACK_DIR + spec_type + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return PoiCatalog.normalize_location(parsed) if spec_type == "location" else parsed


func _finish(type: String, data: Dictionary, origin: String, source: String, errors: Array) -> Dictionary:
	if type == "location":
		data = PoiCatalog.normalize_location(data)
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
Nombres que YA existen (no los repitas): %s%s""" % [
		TYPE_NAMES.get(type, type), hint, JSON.stringify(context), ", ".join(PackedStringArray(existing)), EXTRA_RULES.get(type, "")]

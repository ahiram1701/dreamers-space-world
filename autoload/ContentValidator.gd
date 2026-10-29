extends Node
## Única fuente de verdad sobre la forma de cada entidad del mundo.
## De SPECS sale tanto el JSON schema que se envía a Ollama como la validación posterior.
##
## Tipos de campo: string, int, float, bool, color (#rrggbb), enum (valores de archetypes.json),
## array (items + min/max), object (fields). "opt": true marca un campo opcional.

const ARCHETYPES_PATH := "res://data/archetypes.json"

const SPECS := {
	"npc": {
		"name": {"t": "string", "min": 2, "max": 40},
		"age": {"t": "int", "min": 5, "max": 900},
		"occupation": {"t": "string", "min": 2, "max": 80},
		"personality": {"t": "array", "min": 1, "max": 5, "items": {"t": "string", "min": 2, "max": 30}},
		"goals": {"t": "array", "min": 1, "max": 3, "items": {"t": "string", "min": 3, "max": 120}},
		"secret": {"t": "string", "min": 3, "max": 200},
		"greeting": {"t": "string", "min": 2, "max": 240},
		"appearance": {"t": "object", "fields": {
			"body": {"t": "enum", "from": "npc_body"},
			"outfit": {"t": "enum", "from": "npc_outfit"},
			"primary_color": {"t": "color"},
			"secondary_color": {"t": "color"},
		}},
		"tags": {"t": "array", "min": 0, "max": 6, "items": {"t": "string", "min": 2, "max": 24}, "opt": true},
	},
	"location": {
		"name": {"t": "string", "min": 2, "max": 50},
		"kind": {"t": "enum", "from": "location_kind"},
		"biome": {"t": "enum", "from": "biome"},
		"era": {"t": "enum", "from": "era"},
		"description": {"t": "string", "min": 10, "max": 500},
		"gravity": {"t": "float", "min": 0.1, "max": 3.0},
		"seed": {"t": "int", "min": 0, "max": 2147483647},
		"sky_color": {"t": "color"},
		"points_of_interest": {"t": "array", "min": 1, "max": 6, "items": {"t": "string", "min": 2, "max": 60}},
		"tags": {"t": "array", "min": 0, "max": 6, "items": {"t": "string", "min": 2, "max": 24}, "opt": true},
	},
	"item": {
		"name": {"t": "string", "min": 2, "max": 40},
		"kind": {"t": "enum", "from": "item_kind"},
		"effect": {"t": "enum", "from": "item_effect"},
		"power": {"t": "int", "min": 0, "max": 100},
		"lore": {"t": "string", "min": 5, "max": 300},
		"tags": {"t": "array", "min": 0, "max": 6, "items": {"t": "string", "min": 2, "max": 24}, "opt": true},
	},
	# No es una entidad del mundo: es la respuesta de un PNJ en una conversación.
	"dialogue_turn": {
		"line": {"t": "string", "min": 1, "max": 600},
		"emotion": {"t": "enum", "from": "emotion"},
		"choices": {"t": "array", "min": 2, "max": 4, "items": {"t": "object", "fields": {
			"text": {"t": "string", "min": 2, "max": 120},
			"tone": {"t": "enum", "from": "tone"},
		}}},
		"new_facts": {"t": "array", "min": 0, "max": 2, "items": {"t": "string", "min": 3, "max": 160}, "opt": true},
		"relationship_delta": {"t": "int", "min": -10, "max": 10},
		"trait_signals": {"t": "array", "min": 0, "max": 3, "opt": true, "items": {"t": "object", "fields": {
			"trait": {"t": "enum", "from": "player_trait"},
			"delta": {"t": "int", "min": -3, "max": 3},
		}}},
		"end_conversation": {"t": "bool"},
	},
	# El momento en que el jugador descubre la brecha. Una vez por partida.
	"awakening": {
		"origin": {"t": "enum", "from": "awakening_origin"},
		"title": {"t": "string", "min": 2, "max": 60},
		"narration": {"t": "string", "min": 80, "max": 1500},
		"source_description": {"t": "string", "min": 20, "max": 400},
		"anchor": {"t": "object", "fields": {
			"name": {"t": "string", "min": 2, "max": 40},
			"description": {"t": "string", "min": 10, "max": 300},
			"base": {"t": "enum", "from": "anchor_base"},
		}},
		"canon_facts": {"t": "array", "min": 2, "max": 3, "items": {"t": "string", "min": 10, "max": 200}},
		"choices": {"t": "array", "min": 2, "max": 3, "items": {"t": "object", "fields": {
			"text": {"t": "string", "min": 5, "max": 140},
			"consequence": {"t": "enum", "from": "awakening_consequence"},
		}}},
		"destination_hint": {"t": "string", "min": 10, "max": 300},
	},
	# Misión local. El motor resuelve target_index contra las listas reales del lugar
	# (puntos de interés, PNJs u objetos), así la IA no puede inventar objetivos imposibles.
	"quest": {
		"title": {"t": "string", "min": 3, "max": 60},
		"description": {"t": "string", "min": 10, "max": 300},
		"objective": {"t": "enum", "from": "quest_objective"},
		"target_index": {"t": "int", "min": 0, "max": 5},
		"completion_text": {"t": "string", "min": 5, "max": 300},
	},
	# El origen de la señal: revelación final y los tres finales con su epílogo.
	"finale": {
		"title": {"t": "string", "min": 2, "max": 60},
		"revelation": {"t": "string", "min": 80, "max": 1500},
		"source_voice": {"t": "string", "min": 10, "max": 400},
		"choices": {"t": "array", "min": 3, "max": 3, "items": {"t": "object", "fields": {
			"text": {"t": "string", "min": 5, "max": 140},
			"ending": {"t": "enum", "from": "ending"},
			"epilogue": {"t": "string", "min": 40, "max": 900},
		}}},
	},
}

## Tipos que se guardan en WorldDB (el resto de SPECS son respuestas efímeras).
const ENTITY_TYPES := ["npc", "location", "item"]

var _archetypes: Dictionary = {}


func types() -> Array:
	return ENTITY_TYPES


func archetypes() -> Dictionary:
	if _archetypes.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ARCHETYPES_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			parsed.erase("_comment")
			_archetypes = parsed
	return _archetypes


## Devuelve { ok, data (normalizada: ints convertidos, números acotados), errors: Array[String] }.
## Errores "blandos" (número fuera de rango, texto largo) se corrigen; los "duros" invalidan.
func validate(type: String, data: Variant) -> Dictionary:
	if not SPECS.has(type):
		return {"ok": false, "data": null, "errors": ["Tipo desconocido: %s" % type]}
	var errors: Array[String] = []
	var clean = _check({"t": "object", "fields": SPECS[type]}, data, type, errors)
	return {"ok": errors.is_empty(), "data": clean, "errors": errors}


func to_json_schema(type: String) -> Dictionary:
	return _schema({"t": "object", "fields": SPECS[type]})


func _check(spec: Dictionary, value: Variant, path: String, errors: Array[String]) -> Variant:
	match spec.t:
		"string":
			if typeof(value) != TYPE_STRING:
				errors.append("%s: se esperaba texto" % path)
				return null
			var s: String = value.strip_edges()
			if s.length() < spec.get("min", 0):
				errors.append("%s: texto demasiado corto" % path)
			return s.left(spec.get("max", 10000))
		"int", "float":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				errors.append("%s: se esperaba un número" % path)
				return null
			var n = clampf(float(value), spec.min, spec.max)
			return int(n) if spec.t == "int" else n
		"bool":
			if typeof(value) != TYPE_BOOL:
				errors.append("%s: se esperaba true/false" % path)
			return bool(value)
		"color":
			if typeof(value) != TYPE_STRING or not Color.html_is_valid(value):
				errors.append("%s: color inválido (usa #rrggbb)" % path)
				return null
			return "#" + Color.html(value).to_html(false)
		"enum":
			var allowed: Array = archetypes().get(spec.from, [])
			if not (value in allowed):
				errors.append("%s: '%s' no es válido, usa uno de %s" % [path, value, allowed])
				return null
			return value
		"array":
			if typeof(value) != TYPE_ARRAY:
				errors.append("%s: se esperaba una lista" % path)
				return []
			var out := []
			for i in mini(value.size(), spec.max):
				out.append(_check(spec.items, value[i], "%s[%d]" % [path, i], errors))
			if out.size() < spec.min:
				errors.append("%s: se necesitan al menos %d elementos" % [path, spec.min])
			return out
		"object":
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("%s: se esperaba un objeto" % path)
				return {}
			var out := {}
			for key in spec.fields:
				var field: Dictionary = spec.fields[key]
				if not value.has(key):
					if not field.get("opt", false):
						errors.append("%s.%s: falta" % [path, key])
					continue
				out[key] = _check(field, value[key], "%s.%s" % [path, key], errors)
			return out  # las claves desconocidas se descartan a propósito
	errors.append("%s: spec con tipo desconocido '%s'" % [path, spec.t])
	return null


func _schema(spec: Dictionary) -> Dictionary:
	match spec.t:
		"string":
			return {"type": "string"}
		"color":
			return {"type": "string", "pattern": "^#[0-9a-fA-F]{6}$"}
		"int":
			return {"type": "integer", "minimum": spec.min, "maximum": spec.max}
		"float":
			return {"type": "number", "minimum": spec.min, "maximum": spec.max}
		"bool":
			return {"type": "boolean"}
		"enum":
			return {"type": "string", "enum": archetypes().get(spec.from, [])}
		"array":
			return {"type": "array", "items": _schema(spec.items), "minItems": spec.min, "maxItems": spec.max}
		"object":
			var props := {}
			var required := []
			for key in spec.fields:
				props[key] = _schema(spec.fields[key])
				if not spec.fields[key].get("opt", false):
					required.append(key)
			return {"type": "object", "properties": props, "required": required}
	return {}

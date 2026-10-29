extends SceneTree
## Pruebas rápidas del validador, sin red:
##   godot --headless --path . -s tests/test_validator.gd

var _failed := 0


func _init() -> void:
	var v = load("res://autoload/ContentValidator.gd").new()

	for type in ["npc", "location", "item", "dialogue_turn", "awakening"]:
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/fallback/%s.json" % type))
		var r: Dictionary = v.validate(type, data)
		_expect(r.ok, "%s de respaldo es válido %s" % [type, r.errors])
		_expect(not v.to_json_schema(type).is_empty(), "%s genera JSON schema" % type)

	# Los vecinos del Acto 0 están escritos a mano: deben cumplir el mismo esquema que la IA
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		var r: Dictionary = v.validate("npc", entry.entity)
		_expect(r.ok, "PNJ base %s es válido %s" % [entry.id, r.errors])

	var npc = JSON.parse_string(FileAccess.get_file_as_string("res://data/fallback/npc.json"))
	npc.age = 99999.0                 # fuera de rango y float → se acota a int
	npc.appearance.body = "dragon"    # no existe en archetypes → se repara con el valor por defecto
	npc.erase("secret")               # campo esencial ausente → error duro
	npc["hack"] = "x"                 # clave desconocida → se descarta
	var r: Dictionary = v.validate("npc", npc)
	_expect(not r.ok, "detecta npc inválido")
	_expect(r.data.age == 900 and typeof(r.data.age) == TYPE_INT, "acota age a int 900")
	_expect(not r.data.has("hack"), "descarta claves desconocidas")
	_expect(r.errors.size() == 1 and "secret" in r.errors[0], "solo lo esencial es error duro: %s" % [r.errors])
	_expect(r.data.appearance.body == "average", "enum inválido → valor por defecto")

	# Lo que devuelve un modelo real (gpt-oss en Ollama Cloud): valores traducidos, opciones como
	# texto, decimales y rasgos como texto. Debe aceptarse reparado, no tirarse entero.
	var real := {
		"line": "¡Hey! Soy Teo.", "emotion": "animado", "relationship_delta": 0.2, "end_conversation": "false",
		"choices": ["¿Qué me recomiendas?", {"text": "Me voy ya.", "tone": "curioso"}, {"text": "¿Viste algo raro?", "tone": "Intrigado"}],
		"trait_signals": ["curiosidad", {"trait": "Empatía", "delta": 2}],
	}
	r = v.validate("dialogue_turn", real)
	_expect(r.ok, "acepta una respuesta real imperfecta %s" % [r.errors])
	_expect(r.data.emotion == "happy" and r.data.choices[1].tone == "curious" and r.data.choices[2].tone == "curious", "traduce sinónimos en español")
	_expect(r.data.choices.size() == 3 and r.data.choices[0].text == "¿Qué me recomiendas?", "convierte opciones de texto en objetos")
	_expect(r.data.relationship_delta == 0 and r.data.end_conversation == false, "repara números y booleanos")
	_expect(r.data.trait_signals.size() == 1 and r.data.trait_signals[0].trait == "empathy", "descarta rasgos inválidos y repara los demás")
	_expect(not v.describe_format("dialogue_turn").is_empty(), "describe el formato para el prompt")

	# Sin lo esencial no hay respuesta válida
	r = v.validate("dialogue_turn", {"emotion": "happy", "choices": []})
	_expect(not r.ok, "sin frase ni opciones, la respuesta se rechaza")

	v.free()
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

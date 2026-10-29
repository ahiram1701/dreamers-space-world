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
	npc.appearance.body = "dragon"    # no existe en archetypes → error duro
	npc.erase("secret")               # campo requerido ausente
	npc["hack"] = "x"                 # clave desconocida → se descarta
	var r: Dictionary = v.validate("npc", npc)
	_expect(not r.ok, "detecta npc inválido")
	_expect(r.data.age == 900 and typeof(r.data.age) == TYPE_INT, "acota age a int 900")
	_expect(not r.data.has("hack"), "descarta claves desconocidas")
	_expect(r.errors.size() == 2, "exactamente 2 errores duros (body, secret): %s" % [r.errors])

	v.free()
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

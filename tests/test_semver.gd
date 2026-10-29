extends SceneTree
## Pruebas de SemVer, sin red:
##   godot --headless --path . -s tests/test_semver.gd

var _failed := 0


func _init() -> void:
	var S = load("res://scripts/util/SemVer.gd")

	_expect(S.parse("v0.2.0") == {"major": 0, "minor": 2, "patch": 0, "pre": ""}, "parse acepta prefijo v")
	_expect(S.parse("1.2.3-beta.2").pre == "beta.2", "parse extrae pre-release")
	_expect(S.parse("1.2.3+build.7").pre == "", "ignora metadatos de build")
	for bad in ["", "1.2", "1.2.3.4", "a.b.c", "1.2.-3", "1.2.3-", "latest"]:
		_expect(S.parse(bad).is_empty(), "rechaza '%s'" % bad)

	_expect(S.compare("0.2.0", "0.10.0") == -1, "0.2.0 < 0.10.0 (numérico, no alfabético)")
	_expect(S.compare("v1.0.0", "1.0.0") == 0, "v1.0.0 == 1.0.0")
	_expect(S.compare("1.0.0", "1.0.0-alpha") == 1, "estable > pre-release")
	_expect(S.compare("1.0.0-alpha", "1.0.0-alpha.1") == -1, "alpha < alpha.1")
	_expect(S.compare("1.0.0-alpha.2", "1.0.0-alpha.10") == -1, "alpha.2 < alpha.10")
	_expect(S.compare("1.0.0-alpha", "1.0.0-beta") == -1, "alpha < beta")
	_expect(S.compare("1.0.0-1", "1.0.0-alpha") == -1, "numérico < alfanumérico")
	_expect(S.compare("2.0.0", "1.99.99") == 1, "major manda")

	_expect(S.is_newer("v0.3.0", "0.2.0"), "hay update de 0.2.0 a 0.3.0")
	_expect(not S.is_newer("v0.2.0", "0.2.0"), "misma versión: sin update")
	_expect(not S.is_newer("v0.1.9", "0.2.0"), "versión más vieja: sin update")
	_expect(not S.is_newer("basura", "0.2.0"), "tag inválido: sin update")

	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

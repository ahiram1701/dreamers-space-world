class_name SemVer
extends RefCounted
## Versionado semántico mínimo (MAJOR.MINOR.PATCH[-pre][+build]) para comparar versiones del juego.
## Puro y sin estado: se prueba en CI sin red (tests/test_semver.gd).


## Devuelve {major, minor, patch, pre} o {} si el texto no es una versión válida. Acepta "v0.2.0".
static func parse(text: String) -> Dictionary:
	var s := text.strip_edges().trim_prefix("v").get_slice("+", 0)  # los metadatos de build no cuentan
	var pre := ""
	var dash := s.find("-")
	if dash != -1:
		pre = s.substr(dash + 1)
		s = s.substr(0, dash)
		if pre.is_empty():
			return {}
	var parts := s.split(".")
	if parts.size() != 3:
		return {}
	for p in parts:
		if not p.is_valid_int() or int(p) < 0:
			return {}
	return {"major": int(parts[0]), "minor": int(parts[1]), "patch": int(parts[2]), "pre": pre}


## -1 si a < b, 0 si son iguales (o alguna no es válida), 1 si a > b.
static func compare(a: String, b: String) -> int:
	var x := parse(a)
	var y := parse(b)
	if x.is_empty() or y.is_empty():
		return 0
	for k in ["major", "minor", "patch"]:
		if x[k] != y[k]:
			return 1 if x[k] > y[k] else -1
	if x.pre == y.pre:
		return 0
	if x.pre.is_empty():
		return 1  # 1.0.0 > 1.0.0-alpha
	if y.pre.is_empty():
		return -1
	return _compare_pre(x.pre, y.pre)


## true solo si `candidate` es válida y estrictamente más nueva que `current`.
static func is_newer(candidate: String, current: String) -> bool:
	return not parse(candidate).is_empty() and not parse(current).is_empty() and compare(candidate, current) > 0


# Reglas semver: identificadores separados por "."; numéricos se comparan como números
# y son menores que los alfanuméricos; con prefijo igual, el más corto es menor.
static func _compare_pre(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in mini(pa.size(), pb.size()):
		var na := pa[i].is_valid_int()
		var nb := pb[i].is_valid_int()
		if na and nb:
			if int(pa[i]) != int(pb[i]):
				return 1 if int(pa[i]) > int(pb[i]) else -1
		elif na != nb:
			return -1 if na else 1
		elif pa[i] != pb[i]:
			return 1 if pa[i] > pb[i] else -1
	if pa.size() == pb.size():
		return 0
	return 1 if pa.size() > pb.size() else -1

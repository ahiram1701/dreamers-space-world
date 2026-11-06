class_name Names
extends RefCounted
## Nombres, apellidos y oficios con su forma masculina y femenina y su rango de edad
## (data/names.json). Así nadie se llama Joaquín y es «maestra jubilada» con 30 años.

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/names.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return str(list[rng.randi() % list.size()]) if not list.is_empty() else "?"


static func first(fem: bool, rng: RandomNumberGenerator, kid: bool = false) -> String:
	var key := ("kids_" if kid else "") + ("female" if fem else "male")
	return _pick(data().get(key, []), rng)


static func surname(rng: RandomNumberGenerator) -> String:
	return _pick(data().get("surnames", []), rng)


static func full(fem: bool, rng: RandomNumberGenerator) -> String:
	return first(fem, rng) + " " + surname(rng)


## Un oficio para esa persona. `where`: "street" (gente de la calle), "house" (trabaja fuera),
## "home" (en casa), "elder" (jubilados). Devuelve {job, age}.
static func job(fem: bool, rng: RandomNumberGenerator, where: String = "street") -> Dictionary:
	var pool: Array = data().get("jobs", []).filter(func(j): return j.get(where, false))
	if pool.is_empty():
		pool = data().get("jobs", [])
	var j: Dictionary = pool[rng.randi() % pool.size()]
	return {"job": j.f if fem else j.m, "age": rng.randi_range(int(j.min), int(j.max))}


## ¿Es un nombre de mujer? Primero las listas; si no está, la terminación.
static func is_female_name(full_name: String) -> bool:
	var f := full_name.strip_edges().split(" ")[0]
	for k in ["female", "kids_female"]:
		if f in data().get(k, []):
			return true
	for k in ["male", "kids_male"]:
		if f in data().get(k, []):
			return false
	var low := f.to_lower()
	return low.ends_with("a") and not low in ["luca", "nicola", "joshua", "elías", "matías"]


static func _entry_for(job_text: String) -> Dictionary:
	var low := job_text.strip_edges().to_lower()
	for j in data().get("jobs", []):
		if low == str(j.m).to_lower() or low == str(j.f).to_lower():
			return j
	return {}


## Pone el oficio en el género de la persona («maestra jubilada» → «maestro jubilado»). Oficios que
## no están en la lista: cambia la última vocal de cada palabra conocida (-o/-a, -or/-ora).
static func fit_job(job_text: String, fem: bool) -> String:
	var e := _entry_for(job_text)
	if not e.is_empty():
		return e.f if fem else e.m
	var words := job_text.split(" ")
	var out := PackedStringArray()
	for i in words.size():
		var w := words[i]
		# Solo el sustantivo del oficio (la primera palabra) y adjetivos como «jubilado»; nunca
		# nombres propios ni lo que va detrás («dependienta de Ferretería» no toca «Ferretería»).
		var adj := w.to_lower().contains("jubilad") or w.to_lower().contains("retirad")
		var known := _entry_for(w)
		if i == 0 and not known.is_empty() and not str(known.m).contains(" "):
			out.append(known.f if fem else known.m)
			continue
		out.append(_fit_word(w, fem) if i == 0 or adj else w)
	return " ".join(out)


const _NEUTRAL := ["de", "del", "la", "el", "los", "las", "y", "en", "a", "con", "por", "para", "casa", "tienda", "barrio",
	"policía", "guía", "artista", "taxista", "electricista", "periodista", "dentista", "estudiante", "comerciante", "agente",
	"pianista", "jefa", "jefe", "cuida", "trabaja", "vende", "ayuda", "atiende"]


static func _fit_word(w: String, fem: bool) -> String:
	var low := w.to_lower()
	if low in _NEUTRAL or low.length() < 4:
		return w
	if fem:
		if low.ends_with("o"):
			return w.left(-1) + "a"
		if low.ends_with("or"):
			return w + "a"
	else:
		if low.ends_with("ora"):
			return w.left(-1)
		if low.ends_with("a") and not low.ends_with("ista"):
			return w.left(-1) + "o"
	return w


## Rango de edad que pega con un oficio ([] si no se sabe). «jubilado» siempre mayor.
static func age_range(job_text: String) -> Array:
	var e := _entry_for(job_text)
	if not e.is_empty():
		return [int(e.min), int(e.max)]
	var low := job_text.to_lower()
	if low.contains("jubilad") or low.contains("retirad"):
		return [62, 86]
	if low.contains("estudiante"):
		return [16, 26]
	return []

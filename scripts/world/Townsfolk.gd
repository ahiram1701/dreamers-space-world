class_name Townsfolk
extends RefCounted
## El padrón del lugar: todas las personas con nombre que viven o trabajan aquí, con su género,
## edad, oficio, casa y trabajo, y qué relación tienen entre ellas. En un pueblo pequeño todos se
## conocen al menos de vista; la familia, los compañeros y los de toda la vida, mucho más.

## Relaciones de los personajes del acto 0 (lo que la IA debe saber de ellos entre sí).
const ACT0_BONDS := {
	"npc_marina|npc_teo": "Teo le sirve el café cada mañana; se tienen cariño y se cuentan las cosas raras del pueblo",
	"npc_marina|npc_samir": "Samir le arregla la radio del faro; se conocen de hace años y se respetan",
	"npc_samir|npc_teo": "Samir pasa por la cafetería casi a diario; son amigos y se echan bromas",
}


## Todos los vecinos con nombre del lugar actual: [{id, name, fem, age, job, home, work}].
static func roster(scene: LocationScene) -> Array:
	var place := GameState.current_location()
	var ids := {}
	if scene:
		for id in scene._npcs:
			ids[id] = true
	for door in WorldDB.get_state("households", {}).get(place, {}):
		for id in WorldDB.get_state("households", {})[place][door]:
			ids[id] = true
	for door in WorldDB.get_state("shop_staff", {}).get(place, {}):
		ids[WorldDB.get_state("shop_staff", {})[place][door]] = true
	for r in Actions.residents_here(place):
		ids[str(r.get("id", ""))] = true
	var out := []
	for id in ids:
		var e := WorldDB.get_entity("npc", str(id))
		if e.is_empty() or str(e.get("name", "?")) == "?":
			continue
		out.append({"id": str(id), "name": str(e.name), "fem": e.get("appearance", {}).get("figure", "") == "feminine",
			"age": int(e.get("age", 0)), "job": str(e.get("occupation", "")), "home": _home_label(scene, str(id)),
			"work": _work_label(scene, str(id))})
	return out


static func _door_label(scene: LocationScene, door: String) -> String:
	if scene == null or door.is_empty() or not scene._interiors.doors().has(door):
		return ""
	return str(scene._interiors.doors()[door].label)


static func _home_label(scene: LocationScene, id: String) -> String:
	return _door_label(scene, Households.home_of(id))


static func _work_label(scene: LocationScene, id: String) -> String:
	var staff: Dictionary = WorldDB.get_state("shop_staff", {}).get(GameState.current_location(), {})
	for door in staff:
		if staff[door] == id:
			return _door_label(scene, door)
	return ""


## Qué relación tiene `a` con `b`, en una frase desde el punto de vista de `a`.
static func bond(a: String, b: String, folk: Array = []) -> String:
	var key := "|".join(PackedStringArray([a, b] if a < b else [b, a]))
	var parts := PackedStringArray()
	if ACT0_BONDS.has(key):
		parts.append(ACT0_BONDS[key])
	var ha := Households.home_of(a)
	if not ha.is_empty() and ha == Households.home_of(b):
		parts.append("vive contigo (es de tu familia)")
	var learned: Dictionary = NPCMemory.get_mem(a).get("bonds", {}).get(b, {})
	for n in learned.get("notes", []).slice(-2):
		parts.append(str(n))
	if parts.is_empty():
		var ra: Dictionary = {}
		var rb: Dictionary = {}
		for p in folk:
			if p.id == a:
				ra = p
			elif p.id == b:
				rb = p
		if not ra.is_empty() and not rb.is_empty() and not str(ra.work).is_empty() and ra.work == rb.work:
			parts.append("trabajan juntos")
		else:
			parts.append("le conoces de vista, es del pueblo")
	return "; ".join(parts)


## Texto para el prompt: la gente del lugar que `npc_id` conoce, empezando por los más cercanos
## y por quien el jugador acaba de nombrar (`mentioned`: lo último que dijo).
static func context_for(scene: LocationScene, npc_id: String, mentioned: String = "", limit: int = 14) -> String:
	var folk := roster(scene)
	if folk.size() <= 1:
		return ""
	var low := mentioned.to_lower()
	var scored := []
	for p in folk:
		if p.id == npc_id:
			continue
		var b := bond(npc_id, p.id, folk)
		var score := 0.0
		if not low.is_empty() and low.contains(str(p.name).split(" ")[0].to_lower()):
			score += 100.0
		if not b.begins_with("le conoces de vista"):
			score += 50.0
		if p.id.begins_with("npc_"):
			score += 20.0
		scored.append({"p": p, "b": b, "s": score})
	scored.sort_custom(func(x, y): return x.s > y.s)
	var lines := PackedStringArray()
	for s in scored.slice(0, limit):
		var p: Dictionary = s.p
		var where := ""
		if not str(p.work).is_empty():
			where += ", trabaja en %s" % p.work
		if not str(p.home).is_empty():
			where += ", vive en %s" % p.home
		lines.append("- %s (%s, %d años, %s%s): %s." % [p.name, "mujer" if p.fem else "hombre", p.age, p.job, where, s.b])
	var more := folk.size() - 1 - mini(limit, scored.size())
	return "GENTE DEL LUGAR QUE CONOCES (es un sitio pequeño: a todos ellos los conoces; nunca digas que no conoces a alguien de esta lista)%s:\n%s\nSi te preguntan por alguien que NO está en esta lista ni en tu memoria, di con naturalidad que no te suena." % [
		(" — y %d vecinos más a los que conoces de vista" % more) if more > 0 else "", "\n".join(lines)]

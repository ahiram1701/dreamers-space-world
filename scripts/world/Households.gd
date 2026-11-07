class_name Households
extends Node
## Quién vive en cada casa y qué hace dentro según la hora. Cada casa tiene su hogar (una
## persona sola, una pareja, una familia con hijos, una pareja mayor) que se crea la primera vez
## que hace falta y se queda en el mundo. Al entrar en una casa, la gente que está en ese
## momento aparece haciendo lo suyo: de noche duerme, a mediodía come, por la tarde está en el
## sofá. Quien trabaja fuera no está en su horario; los niños, en la escuela.
## También recuerda a quien entró de visita (la gente de paso que se mete en un edificio).


var scene: LocationScene
var _spawned := {}   # npc_id -> TownNPC de la casa donde estás ahora


# --- Quién vive dónde ------------------------------------------------------------------

static func _all() -> Dictionary:
	return WorldDB.get_state("households", {})


## Ids de la gente que vive en esa puerta ([] si aún no se ha creado).
static func members(door: String) -> Array:
	return _all().get(GameState.current_location(), {}).get(door, [])


## Puerta de la casa donde vive alguien ("" si no se sabe).
static func home_of(npc_id: String) -> String:
	var here: Dictionary = _all().get(GameState.current_location(), {})
	for door in here:
		if npc_id in here[door]:
			return door
	return ""


## Hogar de una casa: lo crea si no existe. `owner`: si ya se sabe quién vive ahí (un vecino con
## nombre), vive solo/a. Devuelve los ids.
func ensure(door: String, owner: String = "") -> Array:
	var all := _all()
	var place := GameState.current_location()
	var here: Dictionary = all.get(place, {})
	if here.has(door):
		return here[door]
	var ids: Array = [owner] if not owner.is_empty() else _create(door, place)
	here[door] = ids
	all[place] = here
	WorldDB.set_state("households", all)
	return ids


func _create(door: String, place: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(place + "/" + door)
	var kind: String = ["single", "couple", "family", "family", "elders"][rng.randi() % 5]
	var surname := Names.surname(rng)
	var ids := []
	var adults := 1 if kind == "single" else 2
	for a in adults:
		var fem: bool = rng.randf() < 0.5 if a == 0 or ids.is_empty() else not _is_fem(ids[0])
		var first := Names.first(fem, rng)
		var elder: bool = kind == "elders"
		var at_home: bool = elder or rng.randf() < 0.3
		var j := Names.job(fem, rng, "elder" if elder else ("home" if at_home else "house"))
		var job: String = j.job
		var look := _look(rng, fem, "elderly" if elder else ["slim", "average", "sturdy", "tall"][rng.randi() % 4])
		var id := Actions.build_npc("%s %s" % [first, surname], job, "Vive en esta casa con su familia." if adults > 1 else "Vive solo/a en esta casa.",
			"¿Sí? ¿Qué se te ofrece?", look)
		if id.is_empty():
			continue
		WorldDB.update_entity("npc", id, {"age": int(j.age) if elder else clampi(int(j.age), 26, 58),
			"home_door": door, "works_away": not at_home, "household_role": "adulto"})
		ids.append(id)
	if kind == "family":
		for k in 1 + rng.randi() % 2:
			var fem := rng.randf() < 0.5
			var first := Names.first(fem, rng, true)
			var id := Actions.build_npc("%s %s" % [first, surname], "estudiante", "Un niño/a que vive aquí con sus padres.",
				"¡Hola! ¿Eres amigo de mis papás?", _look(rng, fem, "child"))
			if id.is_empty():
				continue
			WorldDB.update_entity("npc", id, {"age": rng.randi_range(6, 13), "home_door": door, "works_away": true, "household_role": "niño"})
			ids.append(id)
	return ids


static func _is_fem(id: String) -> bool:
	return WorldDB.get_entity("npc", id).get("appearance", {}).get("figure", "") == "feminine"


static func _look(rng: RandomNumberGenerator, fem: bool, body: String) -> Dictionary:
	return {"figure": "feminine" if fem else "masculine", "body": body,
		"outfit": ["casual", "casual", "street", "formal"][rng.randi() % 4],
		"primary_color": Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.6), rng.randf_range(0.35, 0.8)).to_html(false),
		"secondary_color": Color.from_hsv(rng.randf(), 0.2, rng.randf_range(0.3, 0.8)).to_html(false)}


# --- Qué hace cada uno según la hora ------------------------------------------------------

## { home: bool, spot: "bed"|"kitchen"|"table"|"sofa", activity: texto, gesture } para esa hora.
## Cada persona lleva su horario un poco desplazado (no todos se acuestan a la vez).
static func plan(entity: Dictionary, hour: float) -> Dictionary:
	var shift := float(hash(str(entity.get("id", ""))) % 60) / 60.0 - 0.5
	var h := fposmod(hour - shift, 24.0)
	var kid: bool = entity.get("household_role", "") == "niño"
	var away: bool = entity.get("works_away", false)
	var bed_at := 21.0 if kid else 23.0
	if h >= bed_at or h < 7.0:
		return {"home": true, "spot": "bed", "activity": "durmiendo", "gesture": "sleep"}
	if h < 8.0:
		return {"home": true, "spot": "table", "activity": "desayunando", "gesture": "sit_eat"}
	if away and h < (14.0 if kid else 18.0):
		return {"home": false, "activity": "en la escuela" if kid else "trabajando fuera de casa"}
	if h < 12.5:
		return {"home": true, "spot": "kitchen", "activity": "limpiando la casa", "gesture": "wipe"}
	if h < 13.5:
		return {"home": true, "spot": "kitchen", "activity": "preparando la comida", "gesture": "cook"}
	if h < 15.0:
		return {"home": true, "spot": "table", "activity": "comiendo", "gesture": "sit_eat"}
	if h < 18.0:
		if kid:
			return {"home": true, "spot": "table", "activity": "haciendo la tarea", "gesture": "sit_read"}
		return {"home": true, "spot": "sofa", "activity": "leyendo en el sofá", "gesture": "sit_read"}
	if h < 20.0:
		return {"home": true, "spot": "kitchen" if not kid else "sofa", "activity": "preparando la cena" if not kid else "viendo la tele", "gesture": "cook" if not kid else "sit"}
	if h < 21.0:
		return {"home": true, "spot": "table", "activity": "cenando", "gesture": "sit_eat"}
	return {"home": true, "spot": "sofa", "activity": "viendo la tele", "gesture": "sit"}


# --- Visitas: gente de paso que entró en un edificio --------------------------------------

## Alguien de paso entra por esa puerta: se queda dentro un rato (lo verás si entras).
static func add_guest(door: String, look: Dictionary, fem: bool, minutes: float) -> void:
	var all: Dictionary = WorldDB.get_state("guests", {})
	var place := GameState.current_location()
	var here: Dictionary = all.get(place, {})
	var list: Array = here.get(door, []).filter(func(g): return float(g.until) > WorldClock.absolute_minutes())
	if list.size() >= 4:
		list.pop_front()
	list.append({"look": look, "fem": fem, "until": WorldClock.absolute_minutes() + minutes})
	here[door] = list
	all[place] = here
	WorldDB.set_state("guests", all)


static func guests(door: String) -> Array:
	var here: Dictionary = WorldDB.get_state("guests", {}).get(GameState.current_location(), {})
	return here.get(door, []).filter(func(g): return float(g.until) > WorldClock.absolute_minutes())


static func remove_guest(door: String, look: Dictionary) -> void:
	var all: Dictionary = WorldDB.get_state("guests", {})
	var here: Dictionary = all.get(GameState.current_location(), {})
	var list: Array = here.get(door, [])
	for g in list:
		if g.look == look:
			list.erase(g)
			break
	here[door] = list
	WorldDB.set_state("guests", all)


# --- En la escena --------------------------------------------------------------------------

## Antes de construir la casa: su hogar existe y hay camas para todos.
func prepare(door: String, kind: String) -> void:
	if kind == "house":
		scene._interiors.set_door_option(door, "sleepers", ensure(door, scene.owner_of_door(door)).size())


## Entras en un edificio: aparece quien está dentro ahora, haciendo lo que le toca.
func populate(door: String, kind: String) -> void:
	clear()
	var used := {}   # cuántos sitios de cada tipo ya están ocupados
	if kind == "house":
		for id in ensure(door, scene.owner_of_door(door)):
			if scene._npcs.has(id):
				continue  # un vecino con su propia rutina (la escena lo coloca)
			var entity := WorldDB.get_entity("npc", id)
			if entity.is_empty():
				continue
			var p := plan(entity, WorldClock.hour())
			if not p.home:
				continue
			var npc := TownNPC.new()
			scene.add_child(npc)
			npc.setup(entity)
			npc.redress(false)  # en casa, sin abrigo ni impermeable
			scene._npcs[id] = npc
			_spawned[id] = npc
			place(npc, p, used)
	if has_staff(kind):  # la tienda, la peluquería, la fonda…: quien atiende, en su horario
		var h := WorldClock.hour()
		if (Shops.is_open(kind, h) if Shops.is_shop(kind) else (h >= 9.0 and h < 20.0)):
			var id := ensure_staff(door, kind)
			var entity := WorldDB.get_entity("npc", id)
			if not entity.is_empty() and not scene._npcs.has(id):
				var npc := TownNPC.new()
				scene.add_child(npc)
				npc.setup(entity)
				npc.redress(false)
				scene._npcs[id] = npc
				_spawned[id] = npc
				var spot: Vector3 = scene._interiors.npc_spot(1 if kind == "cafe" else 0)  # (en la cafetería, la barra es de Teo)
				npc.settle(spot + Vector3(0, 0.1, 0), spot + Vector3(0, 0, 2), "", "atendiendo")
				get_tree().create_timer(1.2).timeout.connect(func():
					if is_instance_valid(npc):
						npc.say(["¡Hola! Pasa, pasa.", "Buenas, ¿te ayudo en algo?", "¡Bienvenido/a! Mira con calma."][randi() % 3], 3.5))
	for g in guests(door):  # de visita o de cliente: sentados donde haya sitio
		var npc := TownNPC.new()
		scene.add_child(npc)
		npc.setup({"id": "guest_%d" % _spawned.size(), "name": "?", "appearance": g.look})
		npc.set_meta("passerby", {"look": g.look, "fem": g.fem, "door": door})
		_spawned[npc.npc_id] = npc
		place(npc, {"spot": "table" if kind != "house" else "sofa", "activity": "de visita" if kind == "house" else "sentado/a", "gesture": "sit"}, used)


## Pone a alguien en su sitio de la casa (la i-ésima cama, silla…) haciendo su actividad.
func place(npc: TownNPC, p: Dictionary, used: Dictionary) -> void:
	var what: String = p.get("spot", "")
	var i: int = used.get(what, 0)
	used[what] = i + 1
	var spot: Dictionary = scene._interiors.activity_spot(what, i)
	if spot.is_empty():
		spot = scene._interiors.activity_spot("", i)
	if spot.is_empty():
		return
	var gesture: String = p.get("gesture", "")
	if what == "bed" and scene._interiors.activity_spot("bed", i).is_empty():
		gesture = "sit"  # más gente que camas: se queda dormido en el sofá
		spot = scene._interiors.activity_spot("sofa", 0)
	if spot.is_empty():
		return
	npc.settle(spot.pos, spot.face, gesture, str(p.get("activity", "")))


## Pasa la hora estando tú dentro: cada uno cambia de actividad (o sale a trabajar).
func refresh(door: String) -> void:
	var used := {}
	for id in _spawned.keys():
		var npc: TownNPC = _spawned[id]
		if not is_instance_valid(npc) or npc.talking or npc.is_following() or npc.has_meta("passerby"):
			continue
		var p := plan(WorldDB.get_entity("npc", id), WorldClock.hour())
		if not p.home:  # se va (a trabajar, a la escuela): sale por la puerta
			_spawned.erase(id)
			npc.say(["Me voy, que llego tarde.", "Hasta luego.", "Nos vemos."][randi() % 3], 3.0)
			scene.npc_go(id, scene._interiors.door_position(door) + Vector3(randf_range(-5, 5), 0, randf_range(6, 10)), func():
				scene._npcs.erase(id)
				npc.queue_free())
			continue
		if p.activity != npc.activity:
			place(npc, p, used)


## Sales del edificio: la gente que se queda dentro deja de existir en la escena (su ficha sigue).
func clear() -> void:
	for id in _spawned.keys():
		var npc: TownNPC = _spawned[id]
		if not is_instance_valid(npc):
			continue
		if npc.is_following() or not InteriorManager.is_interior_pos(npc.global_position):
			continue  # salió contigo o va de camino: sigue en la escena
		scene._npcs.erase(npc.npc_id)  # (si le hablaste, ya tiene ficha propia)
		npc.queue_free()
	_spawned.clear()


const STAFF := {"clothes": ["dependienta de la tienda de ropa", "dependiente de la tienda de ropa"], "salon": ["peluquera", "peluquero"]}


## ¿Ese tipo de sitio tiene a alguien atendiendo? (la cafetería ya tiene a su vecino de siempre)
static func has_staff(kind: String) -> bool:
	return STAFF.has(kind) or (Shops.is_shop(kind) and not Shops.info(kind).get("staff", []).is_empty())


## Quien trabaja en la tienda o la peluquería (se crea una vez y se queda).
func ensure_staff(door: String, kind: String) -> String:
	var all: Dictionary = WorldDB.get_state("shop_staff", {})
	var place := GameState.current_location()
	var here: Dictionary = all.get(place, {})
	if here.has(door) and not WorldDB.get_entity("npc", here[door]).is_empty():
		return here[door]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(place + "/staff/" + door)
	var fem := rng.randf() < 0.6
	var name := Names.full(fem, rng)
	var jobs: Array = STAFF.get(kind, Shops.info(kind).get("staff", ["dependienta", "dependiente"]))
	var job: String = "%s de %s" % [jobs[0 if fem else 1], Shops.label(kind)] if not STAFF.has(kind) else jobs[0 if fem else 1]
	var id := Actions.build_npc(name, job, "Trabaja aquí de 9:00 a 20:00 y conoce a medio pueblo.", "¡Hola! Pasa, pasa. ¿Qué buscas?",
		_look(rng, fem, ["slim", "average"][rng.randi() % 2]).merged({"outfit": "formal" if kind == "clothes" else "casual"}, true))
	here[door] = id
	all[place] = here
	WorldDB.set_state("shop_staff", all)
	return id


## Quien atiende en el sitio donde estás (o null).
func staff_here() -> TownNPC:
	var id: String = WorldDB.get_state("shop_staff", {}).get(GameState.current_location(), {}).get(scene._interiors.current_door(), "")
	var npc: TownNPC = _spawned.get(id)
	return npc if npc and is_instance_valid(npc) else null


## Hay alguien de la casa dentro ahora (para reaccionar si entras sin permiso): el primer adulto.
func owner_here() -> String:
	for id in _spawned:
		var npc: TownNPC = _spawned[id]
		if is_instance_valid(npc) and not npc.has_meta("passerby") and WorldDB.get_entity("npc", id).get("household_role", "") != "niño":
			return id
	for id in _spawned:
		if not _spawned[id].has_meta("passerby"):
			return id
	return ""


func spawned() -> Dictionary:
	return _spawned

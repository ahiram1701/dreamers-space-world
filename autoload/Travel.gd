extends Node
## Saltos entre ramas. Un salto a lo desconocido hace que la IA cree un lugar NUEVO
## (habitantes, objetos y una misión) que se queda para siempre en el mundo del jugador.
## Mientras exploras, el siguiente destino se genera en segundo plano para que saltar sea inmediato.
##
## Uso:  var r := await Travel.jump_new()      → r = { ok, location_id, error }
##       get_tree().change_scene_to_file(Travel.scene_for(r.location_id))

signal travel_started(target: String)
signal travel_finished(location_id: String)
signal pregeneration_finished

const TOWN_SCENE := "res://scenes/act0_town/Act0Town.tscn"
const LOCATION_SCENE := "res://scenes/generated_location/GeneratedLocation.tscn"
const SPACE_SCENE := "res://scenes/space/SpaceScene.tscn"
const SPACE := "space"   # location_id del espacio (volando en tu nave)
const NPCS_PER_LOCATION := 2
const ITEMS_PER_LOCATION := 2
const FINALE_HINT := "El origen de la transmisión que el jugador lleva siguiendo desde Bahía de las Horas: el punto donde convergen todas las ramas que ha visitado. Una zona de anomalía sin cielo ni suelo normales, junto a la brecha original."

var _pregenerating := false


func scene_for(location_id: String) -> String:
	if location_id == SPACE:
		return SPACE_SCENE
	return TOWN_SCENE if location_id == GameState.HOME else LOCATION_SCENE


# --- En nave: despegar, volar por el sistema y aterrizar -------------------------------------
# No es un salto del Ancla: es un viaje físico por este universo (no gasta energía del Ancla,
# gasta combustible).

## Despegas: la nave sale contigo al espacio (deja de estar aparcada aquí). `passengers`: ids de
## los PNJ que van a bordo (bajan contigo donde aterrices).
func launch(ship_entry: Dictionary, passengers: Array = []) -> void:
	var e := ship_entry.duplicate(true)
	var from := GameState.current_location()
	if e.has("id"):
		Creations.remove(str(e.id))
	e.erase("pos")
	WorldDB.set_state("space", {"ship": e, "from": from, "passengers": passengers.duplicate()})
	GameState.set_location(SPACE)


## Quién viaja contigo en la nave (ids de PNJ).
func passengers() -> Array:
	var space: Dictionary = WorldDB.get_state("space", {})
	return space.get("passengers", [])


## Volar directo a un lugar ya conocido (con F: «vuelvo al pueblo»): despegas, el piloto
## automático cruza el sistema y aterrizas. Gasta combustible y tiempo; no pasa por el espacio.
func fly_direct(ship_entry: Dictionary, to_location: String, passengers: Array = []) -> Dictionary:
	var e := ship_entry.duplicate(true)
	var fuel := float(e.get("fuel", 1.0))  # (0..1)
	if fuel < 0.12:
		return _fail("A la nave le queda muy poco combustible para un viaje así.")
	if e.has("id"):
		Creations.remove(str(e.id))
	e.erase("pos")
	e.erase("id")
	e["fuel"] = fuel - 0.12
	travel_started.emit(to_location)
	WorldDB.set_state("arrival_ship", {"to": to_location, "ship": e, "passengers": passengers.duplicate()})
	WorldDB.set_state("space", {})
	GameState.set_location(to_location)
	WorldClock.advance(50)
	for n in TimelineManager.visited_locations():
		if n.location_id == to_location:
			TimelineManager.move_to(n.id)
			break
	travel_finished.emit(to_location)
	return {"ok": true, "location_id": to_location, "error": ""}


## Aterrizas en un planeta o te acoplas a una estación: el lugar de su superficie (se genera la
## primera vez, con la IA) y tu nave aparcada a tu lado. Devuelve {ok, location_id, error}.
func land(planet_name: String) -> Dictionary:
	var sys := StarSystem.get_or_create()
	var planet := {}
	for p in sys.planets:
		if p.name == planet_name:
			planet = p
	if planet.is_empty():
		return _fail("No existe %s." % planet_name)
	if not StarSystem.can_land(planet):
		return _fail("%s no tiene superficie donde aterrizar." % planet.name)
	var location_id: String = planet.get("location_id", "")
	if location_id.is_empty() or (location_id != GameState.HOME and WorldDB.get_entity("location", location_id).is_empty()):
		travel_started.emit(planet.name)
		var station: bool = planet.kind == "station"
		var hint := ("Una estación espacial en órbita (%s): muelles de atraque, pasillos y gente que vive y trabaja allí. Llegas acoplando tu nave." % planet.name) if station 			else ("La superficie del planeta %s (%s, gravedad %.1f g): el lugar donde aterrizas con tu nave. Coherente con este sistema solar y con la época del mundo." % [planet.name, StarSystem.KINDS[planet.kind].label, float(planet.gravity)])
		var loc := await ContentGenerator.generate("location", hint, "landing:" + planet.name, {"planeta": planet.name, "tipo": planet.kind})
		if not loc.ok:
			return _fail("No se pudo calcular el lugar de aterrizaje: %s" % ", ".join(PackedStringArray(loc.errors)))
		location_id = loc.id
		var fields := {"gravity": float(planet.gravity), "picked": [], "npc_ids": [], "item_ids": [], "recharged": false, "planet": planet.name}
		if station:
			fields["kind"] = "space_station"
		else:
			fields["kind"] = "planet_surface"
			fields["biome"] = StarSystem.KINDS[planet.kind].biome
		WorldDB.update_entity("location", location_id, fields)
		planet["location_id"] = location_id
		StarSystem.save(sys)
		var where := {"lugar": loc.entity.name, "descripcion": loc.entity.description}
		var people := []
		for role in ["alguien que vive o trabaja en %s", "otra persona de %s, con otro oficio y otro carácter", "alguien de paso por %s"].slice(0, 2 if station else 3):
			var npc := await ContentGenerator.generate("npc", role % loc.entity.name, "location:" + location_id, where)
			if npc.ok:
				people.append(npc.id)
		if not people.is_empty():
			WorldDB.update_entity("location", location_id, {"npc_ids": people})
	var space: Dictionary = WorldDB.get_state("space", {})
	WorldDB.set_state("arrival_ship", {"to": location_id, "ship": space.get("ship", {}), "passengers": space.get("passengers", [])})
	WorldDB.set_state("space", {})
	GameState.set_location(location_id)
	if location_id != GameState.HOME and TimelineManager.visited_locations().all(func(n): return n.location_id != location_id):
		TimelineManager.branch("Aterrizas en %s" % planet.name, location_id, WorldDB.get_entity("location", location_id).get("era", ""))
	travel_finished.emit(location_id)
	return {"ok": true, "location_id": location_id, "error": ""}


## Salto a una rama nueva: usa el destino pregenerado si existe; si no, lo genera ahora.
func jump_new() -> Dictionary:
	if not GameState.can_travel("new"):
		return _fail("El Ancla no tiene energía suficiente. Busca un punto de recarga.")
	travel_started.emit("new")
	if _pregenerating:
		await pregeneration_finished
	var location_id: String = WorldDB.get_state("pending_jump", "")
	WorldDB.set_state("pending_jump", "")
	if location_id.is_empty() or WorldDB.get_entity("location", location_id).is_empty():
		var bundle := await _generate_bundle(_next_hint(), false)
		if not bundle.ok:
			return bundle
		location_id = bundle.location_id
	return _arrive_new(location_id, GameState.travel_cost("new"))


## El salto final: cuando la brújula tiene fuerza suficiente, te lleva a casa (a Bahía de las
## Horas), y allí se juega la escena de la vuelta.
func jump_finale() -> Dictionary:
	if not GameState.has_all_fragments():
		return _fail("La brújula aún no tiene fuerza para llegar a casa.")
	if not GameState.can_travel("finale"):
		return _fail("El Ancla no tiene energía suficiente para un salto tan largo.")
	travel_started.emit("finale")
	GameState.travel(GameState.HOME, GameState.travel_cost("finale"), false)
	WorldDB.set_state("homecoming", true)
	for n in TimelineManager.visited_locations():
		if n.location_id == GameState.HOME:
			TimelineManager.move_to(n.id)
			break
	travel_finished.emit(GameState.HOME)
	return {"ok": true, "location_id": GameState.HOME, "error": ""}


## Volver a un lugar ya visitado (o a casa). No genera nada nuevo.
func go_to(location_id: String) -> Dictionary:
	if location_id == GameState.current_location():
		return _fail("Ya estás aquí.")
	if not GameState.can_travel(location_id):
		return _fail("El Ancla no tiene energía suficiente para ese salto.")
	travel_started.emit(location_id)
	GameState.travel(location_id, GameState.travel_cost(location_id), false)
	for n in TimelineManager.visited_locations():
		if n.location_id == location_id:
			TimelineManager.move_to(n.id)
			break
	travel_finished.emit(location_id)
	return {"ok": true, "location_id": location_id, "error": ""}


## Genera en segundo plano el próximo destino (si no hay uno ya preparado).
## Las escenas la llaman al llegar; no hace falta esperarla.
func pregenerate() -> void:
	if _pregenerating or not GameState.is_awakened() or GameState.has_all_fragments():
		return
	var pending: String = WorldDB.get_state("pending_jump", "")
	if not pending.is_empty() and not WorldDB.get_entity("location", pending).is_empty():
		return
	_pregenerating = true
	var bundle := await _generate_bundle(_next_hint(), false)
	if bundle.ok:
		WorldDB.set_state("pending_jump", bundle.location_id)
	_pregenerating = false
	pregeneration_finished.emit()


func is_pregenerating() -> bool:
	return _pregenerating


## Destinos conocidos para el panel del Ancla: [{location_id, name, cost}] sin el actual.
func known_destinations() -> Array:
	var out := []
	for n in TimelineManager.visited_locations():
		if n.location_id == GameState.current_location():
			continue
		out.append({"location_id": n.location_id, "name": location_name(n.location_id),
			"cost": GameState.travel_cost(n.location_id)})
	return out


func location_name(location_id: String) -> String:
	if location_id == GameState.HOME:
		return "Bahía de las Horas"
	return WorldDB.get_entity("location", location_id).get("name", "un lugar desconocido")


# --- Interno --------------------------------------------------------------------------

## Lugar + habitantes + objetos + misión. El lugar existe en WorldDB aunque aún no se visite.
func _generate_bundle(hint: String, finale: bool) -> Dictionary:
	var awakening: Dictionary = WorldDB.get_state("awakening", {})
	var from := location_name(GameState.current_location())
	var context := {
		"origen_del_ancla": awakening.get("origin", ""),
		"viene_de": from,
		"saltos_realizados": TimelineManager.depth(),
		"fragmentos_de_coordenadas": GameState.fragments(),
		"jugador": PlayerProfile.describe("?"),
	}
	var loc := await ContentGenerator.generate("location", hint, "jump_from:" + from, context)
	if not loc.ok:
		return _fail("No se pudo calcular el destino: %s" % ", ".join(PackedStringArray(loc.errors)))
	if finale:
		WorldDB.update_entity("location", loc.id, {"finale": true, "kind": "anomaly_zone", "biome": "void"})
		return {"ok": true, "location_id": loc.id, "error": ""}

	var where := {"lugar": loc.entity.name, "descripcion": loc.entity.description, "epoca": loc.entity.era,
		"puntos_de_interes": loc.entity.get("points_of_interest", []), "problema": loc.entity.get("problem", "")}
	var npc_ids: Array = []
	for i in NPCS_PER_LOCATION:
		var npc := await ContentGenerator.generate("npc",
			"alguien que vive, trabaja o investiga en %s" % loc.entity.name, "location:" + loc.id, where)
		if npc.ok:
			npc_ids.append(npc.id)
	var item_ids: Array = []
	for i in ITEMS_PER_LOCATION:
		var item := await ContentGenerator.generate("item",
			"un objeto útil o valioso que se puede encontrar en %s" % loc.entity.name, "location:" + loc.id, where)
		if item.ok:
			item_ids.append(item.id)
	WorldDB.update_entity("location", loc.id, {"npc_ids": npc_ids, "item_ids": item_ids, "picked": [], "recharged": false})
	await Quests.create_for_location(loc.id)
	return {"ok": true, "location_id": loc.id, "error": ""}


func _arrive_new(location_id: String, cost: int) -> Dictionary:
	var loc := WorldDB.get_entity("location", location_id)
	GameState.travel(location_id, cost, true)
	TimelineManager.branch("Salto a %s" % loc.get("name", "?"), location_id, loc.get("era", ""))
	travel_finished.emit(location_id)
	return {"ok": true, "location_id": location_id, "error": ""}


func _next_hint() -> String:
	if TimelineManager.depth() == 0:
		var hint: String = WorldDB.get_state("awakening", {}).get("destination_hint", "")
		if not hint.is_empty():
			return hint
	var told := Actions.take_revealed_place()  # un lugar del que alguien te habló
	if not told.is_empty():
		return "%s: %s" % [told.name, told.hint]
	return "Un lugar nuevo en otra rama del multiverso, coherente con todo lo vivido. Cuanto más lejos ha llegado el jugador, más exótico y espacial puede ser (planetas, estaciones, futuros lejanos)."


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "location_id": "", "error": msg}

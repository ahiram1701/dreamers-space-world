extends Node
## Saltos entre ramas. Un salto a lo desconocido hace que la IA cree un lugar NUEVO
## (y sus habitantes) que se queda para siempre en el mundo del jugador: así crece el juego.
##
## Uso:  var r := await Travel.jump_new()      → r = { ok, location_id, error }
##       get_tree().change_scene_to_file(Travel.scene_for(r.location_id))

signal travel_started(target: String)
signal travel_finished(location_id: String)

const TOWN_SCENE := "res://scenes/act0_town/Act0Town.tscn"
const LOCATION_SCENE := "res://scenes/generated_location/GeneratedLocation.tscn"
const NPCS_PER_LOCATION := 2


func scene_for(location_id: String) -> String:
	return TOWN_SCENE if location_id == GameState.HOME else LOCATION_SCENE


## Salto a una rama nueva: genera el lugar y sus PNJs, paga el coste y cuelga un nodo del árbol.
func jump_new() -> Dictionary:
	if not GameState.can_travel("new"):
		return _fail("El Ancla no tiene energía suficiente. Busca un punto de recarga.")
	travel_started.emit("new")

	var awakening: Dictionary = WorldDB.get_state("awakening", {})
	var first_jump := TimelineManager.depth() == 0
	var hint: String = awakening.get("destination_hint", "") if first_jump \
		else "Un lugar nuevo en otra rama del multiverso, coherente con todo lo vivido. Cuanto más lejos ha llegado el jugador, más exótico y espacial puede ser."
	var from := _location_name(GameState.current_location())
	var context := {
		"origen_del_ancla": awakening.get("origin", ""),
		"viene_de": from,
		"saltos_realizados": TimelineManager.depth(),
		"jugador": PlayerProfile.describe(),
	}
	var loc := await ContentGenerator.generate("location", hint, "jump_from:" + from, context)
	if not loc.ok:
		return _fail("No se pudo calcular el destino: %s" % ", ".join(PackedStringArray(loc.errors)))

	var npc_ids: Array = []
	for i in NPCS_PER_LOCATION:
		var npc := await ContentGenerator.generate("npc",
			"alguien que vive, trabaja o investiga en %s" % loc.entity.name,
			"location:" + loc.id,
			{"lugar": loc.entity.name, "descripcion": loc.entity.description, "epoca": loc.entity.era})
		if npc.ok:
			npc_ids.append(npc.id)
	WorldDB.update_entity("location", loc.id, {"npc_ids": npc_ids, "recharged": false})

	GameState.travel(loc.id, GameState.travel_cost("new"), true)
	TimelineManager.branch("Salto a %s" % loc.entity.name, loc.id, loc.entity.era)
	travel_finished.emit(loc.id)
	return {"ok": true, "location_id": loc.id, "error": ""}


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


## Destinos conocidos para el panel del Ancla: [{location_id, name, cost}] sin el actual.
func known_destinations() -> Array:
	var out := []
	for n in TimelineManager.visited_locations():
		if n.location_id == GameState.current_location():
			continue
		out.append({"location_id": n.location_id, "name": _location_name(n.location_id),
			"cost": GameState.travel_cost(n.location_id)})
	return out


func _location_name(location_id: String) -> String:
	if location_id == GameState.HOME:
		return "Bahía de las Horas"
	return WorldDB.get_entity("location", location_id).get("name", "un lugar desconocido")


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "location_id": "", "error": msg}

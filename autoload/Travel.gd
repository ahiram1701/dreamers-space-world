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
const NPCS_PER_LOCATION := 2
const ITEMS_PER_LOCATION := 2
const FINALE_HINT := "El origen de la transmisión que el jugador lleva siguiendo desde Bahía de las Horas: el punto donde convergen todas las ramas que ha visitado. Una zona de anomalía sin cielo ni suelo normales, junto a la brecha original."

var _pregenerating := false


func scene_for(location_id: String) -> String:
	return TOWN_SCENE if location_id == GameState.HOME else LOCATION_SCENE


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


## El salto final: solo con todas las coordenadas. Lleva al origen de la señal.
func jump_finale() -> Dictionary:
	if not GameState.has_all_fragments():
		return _fail("Faltan fragmentos de coordenadas.")
	if not GameState.can_travel("finale"):
		return _fail("El Ancla no tiene energía suficiente para un salto tan largo.")
	travel_started.emit("finale")
	var bundle := await _generate_bundle(FINALE_HINT, true)
	if not bundle.ok:
		return bundle
	return _arrive_new(bundle.location_id, GameState.travel_cost("finale"))


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
		"jugador": PlayerProfile.describe(),
	}
	var loc := await ContentGenerator.generate("location", hint, "jump_from:" + from, context)
	if not loc.ok:
		return _fail("No se pudo calcular el destino: %s" % ", ".join(PackedStringArray(loc.errors)))
	if finale:
		WorldDB.update_entity("location", loc.id, {"finale": true, "kind": "anomaly_zone", "biome": "void"})
		return {"ok": true, "location_id": loc.id, "error": ""}

	var where := {"lugar": loc.entity.name, "descripcion": loc.entity.description, "epoca": loc.entity.era}
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
	return "Un lugar nuevo en otra rama del multiverso, coherente con todo lo vivido. Cuanto más lejos ha llegado el jugador, más exótico y espacial puede ser (planetas, estaciones, futuros lejanos)."


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "location_id": "", "error": msg}

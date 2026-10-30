extends Node
## Hace real lo que la IA dice que pasa. Si un PNJ acepta prestarte su radio, aquí aparece la
## radio en tu inventario. Es el único sitio donde la IA toca el inventario, los stats, las
## misiones y el diario, y por eso pone los límites (poder de los objetos, stats acotados…).
##
## Uso:  var notes := Actions.execute("npc_samir", turn.actions)  → ["Samir te presta: Radio"]
##       npc_id vacío = acción del jugador en el mundo (tecla F).

## La escena escucha esto para mover al PNJ (seguir, ir a un sitio, darse la vuelta…).
signal npc_action(npc_id: String, action: Dictionary)
signal performed(notes: Array)
## La escena construye lo colocado (una balsa, una hoguera…) y quita lo talado o roto.
signal object_placed(entry: Dictionary)
signal feature_removed(feature_id: String)

## Lo asigna la escena: dónde está el jugador. { pos: Vector3, yaw: float, water: Vector3 o INF }
var player_pose: Callable = func(): return {"pos": Vector3.ZERO, "yaw": 0.0, "water": Vector3.INF}
## Lo asigna la escena: id del elemento de tipo `kind` (tree, rock…) más cercano al jugador, o "".
var feature_finder: Callable = func(_kind: String) -> String: return ""

const MAX_GIFT_POWER := 40          # un vecino no te da un objeto legendario por pedirlo
const MAX_GIFTS_PER_TURN := 2       # "te pongo el café y te presto el boli", pero no una tienda entera
const MAX_REFUSAL_MINUTES := 30
const STAT_LABELS := {"health": "salud", "energy": "energía del Ancla", "instability": "inestabilidad"}
const MAX_PLACED_PER_PLACE := 40
const PLACEABLE_NAMES := {"boat": "Bote", "raft": "Balsa", "campfire": "Hoguera", "tent": "Tienda de campaña",
	"shelter": "Refugio", "table": "Mesa", "chair": "Silla", "bed": "Cama", "fence": "Valla", "sign": "Cartel",
	"torch": "Antorcha", "box": "Caja", "garden": "Huerto", "other": "Construcción"}


func execute(npc_id: String, actions: Array) -> Array:
	var notes := []
	var gifts := 0
	for a in actions:
		var note := ""
		match a.get("type", ""):
			"give_item":
				if gifts >= MAX_GIFTS_PER_TURN:
					continue
				gifts += 1
				note = _give_item(npc_id, a)
			"take_item":
				note = _take_item(npc_id, str(a.get("target", a.get("item_name", ""))))
			"follow_player":
				if not npc_id.is_empty() and not NPCMemory.is_following(npc_id):
					NPCMemory.set_fields(npc_id, {"following": true})
					note = "%s te acompaña." % _name(npc_id)
			"stop_following":
				if not npc_id.is_empty() and NPCMemory.is_following(npc_id):
					NPCMemory.set_fields(npc_id, {"following": false})
					note = "%s deja de seguirte." % _name(npc_id)
			"go_to":
				# "Te acompaño al muelle" llega como follow + go_to: si te sigue, va contigo
				if not npc_id.is_empty() and a.has("target") and not NPCMemory.is_following(npc_id):
					note = "%s se dirige a: %s." % [_name(npc_id), a.target]
			"change_stat":
				note = _change_stat(a)
			"reveal_place":
				note = _reveal_place(npc_id, a)
			"give_quest":
				if not npc_id.is_empty():
					var title := str(a.get("target", a.get("text", "Un encargo"))).left(60)
					if not Quests.create_custom(npc_id, title, str(a.get("text", title))).is_empty():
						note = "Nuevo encargo de %s: %s" % [_name(npc_id), title]
			"complete_quest":
				if not npc_id.is_empty() and not Quests.complete_custom(npc_id).is_empty():
					note = "Encargo cumplido."
			"refuse_contact":
				if not npc_id.is_empty():
					var minutes := clampi(absi(int(a.get("amount", 5))), 1, MAX_REFUSAL_MINUTES)
					NPCMemory.set_fields(npc_id, {"refuse_until": int(Time.get_unix_time_from_system()) + minutes * 60})
					note = "%s no quiere saber nada de ti por ahora." % _name(npc_id)
			"journal":
				if a.has("text"):
					Journal.add(a.text, npc_id)
					note = "Anotado en tu diario."
			"update_item":
				note = _update_item(npc_id, a)
			"remove_item":
				note = _remove_item(str(a.get("target", a.get("item_name", ""))))
			"place_object":
				note = _place_object(a)
			"affect_nearby":
				note = _affect_nearby(a)
		npc_action.emit(npc_id, a)
		if not note.is_empty():
			notes.append(note)
	if not notes.is_empty():
		performed.emit(notes)
	return notes


## El jugador entrega un objeto concreto desde el diálogo (botón "Dar objeto").
func player_gives(npc_id: String, item_id: String) -> String:
	if not Inventory.has(item_id):
		return ""
	return _hand_over(npc_id, item_id)


func _give_item(npc_id: String, a: Dictionary) -> String:
	var item_name := str(a.get("item_name", a.get("target", ""))).strip_edges()
	if item_name.length() < 2:
		return ""
	var who := _name(npc_id) if not npc_id.is_empty() else ""
	# Si es algo que el jugador le dio antes, se lo devuelve (el mismo objeto, no una copia)
	if not npc_id.is_empty():
		var back := _find_in(NPCMemory.get_mem(npc_id).possessions, item_name)
		if not back.is_empty():
			var owned: Array = NPCMemory.get_mem(npc_id).possessions
			owned.erase(back)
			NPCMemory.set_fields(npc_id, {"possessions": owned})
			Inventory.add(back)
			return "%s te devuelve: %s" % [who, WorldDB.get_entity("item", back).name]

	# Ya te lo prestó o te lo dio y lo sigues teniendo: no aparece una copia
	if not npc_id.is_empty():
		for id in Inventory.items():
			var it := WorldDB.get_entity("item", id)
			if it.get("origin", "") == "npc:%s" % npc_id and _same_thing(it.get("name", ""), item_name):
				return ""

	var effect: String = a.get("item_effect", "none")
	var lore := str(a.get("item_description", ""))
	if lore.length() < 5:
		lore = ("Te lo dio %s." % who) if not who.is_empty() else "Lo encontraste tú."
	var check := ContentValidator.validate("item", {
		"name": item_name, "kind": "tool", "effect": effect,
		"power": 0 if effect == "none" else randi_range(15, MAX_GIFT_POWER), "lore": lore,
		"tags": ["regalo"] if not npc_id.is_empty() else ["hallazgo"]})
	if not check.ok:
		return ""
	var lent := bool(a.get("lent", false)) and not npc_id.is_empty()
	var origin := ("npc:%s" % npc_id) if not npc_id.is_empty() else "world:%s" % GameState.current_location()
	var id := WorldDB.add_entity("item", check.data, origin)
	if lent:
		WorldDB.update_entity("item", id, {"lent_by": npc_id})
		var lent_list: Array = NPCMemory.get_mem(npc_id).lent
		lent_list.append(id)
		NPCMemory.set_fields(npc_id, {"lent": lent_list})
	Inventory.add(id)
	if npc_id.is_empty():
		return "Consigues: %s" % item_name
	NPCMemory.add_facts(npc_id, ["%s al jugador: %s." % ["Le prestaste" if lent else "Le diste", item_name]])
	return "%s te %s: %s" % [who, "presta" if lent else "da", item_name]


## Reparar, modificar o mejorar algo que llevas: el mismo objeto cambia (no aparece otro).
func _update_item(npc_id: String, a: Dictionary) -> String:
	var id := Inventory.find_by_name(str(a.get("target", a.get("item_name", ""))))
	if id.is_empty() or Inventory.is_anchor(id):
		return ""
	var item := WorldDB.get_entity("item", id)
	var old_name: String = item.get("name", "")
	var fields := {}
	var new_name := str(a.get("item_name", "")).strip_edges()
	if new_name.length() >= 2 and new_name != item.name:
		fields["name"] = new_name.left(70)
	var lore := str(a.get("item_description", "")).strip_edges()
	if lore.length() >= 5:
		fields["lore"] = lore.left(300)
	var effect: String = a.get("item_effect", "none")
	if effect != "none" and effect != item.get("effect", "none"):
		fields["effect"] = effect
		fields["power"] = maxi(int(item.get("power", 0)), randi_range(15, MAX_GIFT_POWER))
	if fields.is_empty():
		return ""
	WorldDB.update_entity("item", id, fields)
	Inventory.changed.emit()
	var shown: String = fields.get("name", item.name)
	if not npc_id.is_empty():
		NPCMemory.add_facts(npc_id, ["Le arreglaste o cambiaste al jugador: %s." % shown])
		return "%s cambia tu %s: ahora es %s" % [_name(npc_id), old_name, shown]
	return "%s → %s" % [old_name, shown] if fields.has("name") else "%s ha cambiado." % old_name


## Gastar, comer, romper o usar como material algo que llevas.
func _remove_item(item_name: String) -> String:
	var id := Inventory.find_by_name(item_name)
	if id.is_empty() or Inventory.is_anchor(id):
		return ""
	var item := WorldDB.get_entity("item", id)
	Inventory.remove(id)
	var owner: String = item.get("lent_by", "")
	if not owner.is_empty():  # era prestado: su dueño lo sabrá
		var lent_list: Array = NPCMemory.get_mem(owner).lent
		lent_list.erase(id)
		NPCMemory.set_fields(owner, {"lent": lent_list})
		NPCMemory.add_facts(owner, ["El jugador gastó o rompió %s, que le habías prestado." % item.name], -10)
	return "Ya no tienes: %s" % item.name


## Construir o colocar algo en el mundo delante del jugador. Queda guardado en el lugar.
func _place_object(a: Dictionary) -> String:
	var kind := ContentValidator._match_enum(str(a.get("target", "other")), ContentValidator.archetypes().placeable)
	if kind.is_empty():
		kind = "other"
	var pose: Dictionary = player_pose.call() if player_pose.is_valid() else {"pos": Vector3.ZERO, "yaw": 0.0}
	var pos: Vector3 = pose.pos
	var yaw: float = pose.yaw
	if kind in ["boat", "raft"] and pose.get("water", Vector3.INF) != Vector3.INF:
		pos = pose.water  # las barcas se botan en el agua más cercana
	else:
		pos += Vector3(sin(yaw), 0, cos(yaw)) * 2.5
	var label := str(a.get("item_name", "")).strip_edges()
	var entry := {"kind": kind, "name": label if label.length() >= 2 else PLACEABLE_NAMES.get(kind, "Construcción"),
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "yaw": yaw}
	var all: Dictionary = WorldDB.get_state("placed", {})
	var here: Array = all.get(GameState.current_location(), [])
	if here.size() >= MAX_PLACED_PER_PLACE:
		return ""
	here.append(entry)
	all[GameState.current_location()] = here
	WorldDB.set_state("placed", all)
	object_placed.emit(entry)
	return "Construyes: %s" % entry.name


## Talar, romper, arrancar o cosechar lo que tiene cerca el jugador. No vuelve a aparecer.
func _affect_nearby(a: Dictionary) -> String:
	var kind := ContentValidator._match_enum(str(a.get("target", "tree")), ContentValidator.archetypes().world_feature)
	if kind.is_empty():
		return ""
	var id: String = feature_finder.call(kind) if feature_finder.is_valid() else ""
	if id.is_empty():
		return ""
	var all: Dictionary = WorldDB.get_state("removed", {})
	var here: Array = all.get(GameState.current_location(), [])
	if not (id in here):
		here.append(id)
	all[GameState.current_location()] = here
	WorldDB.set_state("removed", all)
	feature_removed.emit(id)
	return {"tree": "El árbol cae.", "rock": "La roca se parte.", "bush": "Arrancas el arbusto.", "crop": "Cosechas."}.get(kind, "")


## Lo colocado y lo quitado en un lugar (para reconstruir la escena igual que la dejaste).
func placed_here(location_id: String) -> Array:
	return WorldDB.get_state("placed", {}).get(location_id, [])


func removed_here(location_id: String) -> Array:
	return WorldDB.get_state("removed", {}).get(location_id, [])


func _take_item(npc_id: String, item_name: String) -> String:
	if npc_id.is_empty():
		return ""
	var id := Inventory.find_by_name(item_name)
	if id.is_empty():
		return ""
	return _hand_over(npc_id, id)


func _hand_over(npc_id: String, item_id: String) -> String:
	if Inventory.is_anchor(item_id):
		return "El Ancla no se separa de ti."
	var item := WorldDB.get_entity("item", item_id)
	Inventory.remove(item_id)
	if item.get("lent_by", "") == npc_id:  # devolver algo prestado
		WorldDB.update_entity("item", item_id, {"lent_by": ""})
		var lent_list: Array = NPCMemory.get_mem(npc_id).lent
		lent_list.erase(item_id)
		NPCMemory.set_fields(npc_id, {"lent": lent_list})
		NPCMemory.add_facts(npc_id, ["El jugador te devolvió %s." % item.name], 5)
		return "Devuelves %s a %s." % [item.name, _name(npc_id)]
	var owned: Array = NPCMemory.get_mem(npc_id).possessions
	owned.append(item_id)
	NPCMemory.set_fields(npc_id, {"possessions": owned})
	NPCMemory.add_facts(npc_id, ["El jugador te dio %s." % item.name], 3)
	return "Le das %s a %s." % [item.name, _name(npc_id)]


func _change_stat(a: Dictionary) -> String:
	var stat := ContentValidator._match_enum(str(a.get("target", "health")), ContentValidator.archetypes().stat)
	var amount := int(a.get("amount", 0))
	if stat.is_empty() or amount == 0:
		return ""
	if not GameState.is_awakened():
		return "Te sientes mejor." if amount > 0 and stat == "health" else ""
	GameState.change_stat(stat, amount)
	return "%s %+d" % [STAT_LABELS[stat].capitalize(), amount]


func _reveal_place(npc_id: String, a: Dictionary) -> String:
	var place := str(a.get("target", a.get("item_name", ""))).strip_edges()
	if place.is_empty():
		return ""
	var hint := str(a.get("text", place))
	var revealed: Array = WorldDB.get_state("revealed_places", [])
	for r in revealed:
		if r.name == place:
			return ""
	revealed.append({"name": place, "hint": hint, "by": npc_id, "used": false})
	WorldDB.set_state("revealed_places", revealed)
	Journal.add("Lugar: %s — %s" % [place, hint], npc_id)
	return "Nuevo lugar en tu diario: %s" % place


## Lugar revelado que aún no has visitado (Travel lo usa como pista del próximo salto).
func take_revealed_place() -> Dictionary:
	var revealed: Array = WorldDB.get_state("revealed_places", [])
	for r in revealed:
		if not r.used:
			r.used = true
			WorldDB.set_state("revealed_places", revealed)
			return r
	return {}


## "Radio de válvulas averiada" y "Radio de válvulas" son lo mismo; "Radio" y "Linterna", no.
func _same_thing(a: String, b: String) -> bool:
	var wa := Inventory._words(a)
	var wb := Inventory._words(b)
	if wa.is_empty() or wb.is_empty():
		return false
	return wa[0].left(5) == wb[0].left(5)


func _find_in(ids: Array, item_name: String) -> String:
	var wanted := item_name.to_lower()
	for id in ids:
		var n: String = WorldDB.get_entity("item", id).get("name", "").to_lower()
		if n == wanted or n.contains(wanted) or wanted.contains(n):
			return id
	return ""


func _name(npc_id: String) -> String:
	return WorldDB.get_entity("npc", npc_id).get("name", "Alguien")

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
## Un PNJ te ha cobrado algo (el diálogo muestra el botón Pagar).
signal charged(npc_id: String, total: int)
## Alguien nuevo se queda a vivir en el lugar / se abre un sitio nuevo (la escena los construye).
signal resident_added(entry: Dictionary)
signal place_added(entry: Dictionary)
## La escena construye lo colocado (una balsa, una hoguera…) y quita lo talado o roto.
signal object_placed(entry: Dictionary)
signal feature_removed(feature_id: String)

## Lo asigna la escena: dónde está el jugador. { pos: Vector3, yaw: float, water: Vector3 o INF }
var player_pose: Callable = func(): return {"pos": Vector3.ZERO, "yaw": 0.0, "water": Vector3.INF}
## Lo asigna la escena: id del elemento de tipo `kind` (tree, rock…) más cercano al jugador, o "".
var feature_finder: Callable = func(_kind: String) -> String: return ""
## Lo asigna la escena: un solar libre para un edificio nuevo → { pos: Vector3, yaw: float } o {}.
var lot_finder: Callable = func(): return {}
## Lo asigna la escena: dónde trabaja un PNJ → { place: id de puerta o sitio, label: "la cafetería" }.
var workplace_finder: Callable = func(_npc_id: String): return {"place": "", "label": "su negocio"}
## Lo asigna la escena: dónde aparece y a dónde llega alguien nuevo → { from: Vector3, to: Vector3 }.
var arrival_spot: Callable = func(): return {"from": Vector3(20, 0, 0), "to": Vector3(2, 0, 0)}

const MAX_RESIDENTS := 15
const MAX_NEW_PLACES := 8
const INTERIOR_OF := {"shop": "shop", "bakery": "shop", "market": "shop", "bar": "cafe", "workshop": "workshop",
	"office": "office", "clinic": "office", "house": "house"}

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
	var spawned := 0  # como mucho una persona y un sitio nuevos por acción
	var built := 0
	for a in actions:
		var note := ""
		match a.get("type", ""):
			"give_item":
				if gifts >= MAX_GIFTS_PER_TURN:
					continue
				gifts += 1
				note = _give_item(npc_id, a)
				if not note.is_empty() and not npc_id.is_empty() and int(a.get("price", 0)) > 0:
					note += " " + _charge(npc_id, int(a.price), str(a.get("item_name", "")))  # te lo pone y te lo cobra
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
					var reward := int(a.get("price", 0))
					if not Quests.create_custom(npc_id, title, str(a.get("text", title)), reward).is_empty():
						note = "Nuevo encargo de %s: %s%s" % [_name(npc_id), title, (" (paga %s)" % Wallet.text(reward)) if reward > 0 else ""]
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
			"npc_react":  # alguien reacciona a lo que hace el jugador (tecla F): lo anima la escena
				var who := npc_from(str(a.get("target", "")))
				if not who.is_empty():
					note = _npc_react(who, a)
					npc_action.emit(who, a)
				if not note.is_empty():
					notes.append(note)
				continue
			"give_to_npc":
				note = _give_to_npc(a)
			"change_need":
				note = _change_need(a)
			"pay":  # el jugador paga (tecla F: "le pago el café a Teo")
				note = _pay(npc_from(str(a.get("target", ""))) if npc_id.is_empty() else npc_id, int(a.get("price", 0)))
			"earn":  # le pagan por un trabajo o una venta
				Wallet.reason = str(a.get("text", "Ingreso")).left(40)
				var got := Wallet.earn(int(a.get("price", 0)))
				note = ("Ganas %s." % Wallet.text(got)) if got > 0 else ""
			"charge":  # un PNJ te cobra: se paga con el botón Pagar o diciéndolo
				if not npc_id.is_empty():
					note = _charge(npc_id, int(a.get("price", 0)), str(a.get("text", a.get("target", ""))))
			"pay_player":
				if not npc_id.is_empty():
					Wallet.reason = "De " + _name(npc_id)
					var got := Wallet.earn(int(a.get("price", 0)))
					if got > 0:
						NPCMemory.add_event(npc_id, "Le pagaste %s al jugador." % Wallet.text(got))
						note = "%s te paga %s." % [_name(npc_id).split(" ")[0], Wallet.text(got)]
			"spawn_npc":
				if spawned > 0:
					continue
				spawned += 1
				note = _spawn_npc(a)
			"create_place":
				if built > 0:
					continue
				built += 1
				note = _create_place(a)
			"share_number":
				if not npc_id.is_empty() and not bool(NPCMemory.get_mem(npc_id).get("phone", false)):
					Phone.add_contact(npc_id)
					note = "Tienes el número de %s." % _name(npc_id).split(" ")[0]
			"hire_player":
				if not npc_id.is_empty() and not (Jobs.has_job() and Jobs.job().employer == npc_id):  # ya trabajas para él/ella
					var wp: Dictionary = workplace_finder.call(npc_id) if workplace_finder.is_valid() else {"place": "", "label": "su negocio"}
					var wage := int(a.get("price", 0))
					if wage <= 0:
						wage = 80
					var j := Jobs.hire(npc_id, str(a.get("target", "Ayudante")), wage, int(a.get("start_hour", 9)), int(a.get("end_hour", 15)),
						str(wp.get("place", "")), str(wp.get("label", "su negocio")), str(a.get("text", "")))
					Phone.add_contact(npc_id)
					note = "Trabajo nuevo: %s en %s, de %02d:00 a %02d:00, %s el turno." % [j.title, j.place_label, j.start_hour, j.end_hour, Wallet.text(j.wage)]
			"quit_job":
				if Jobs.has_job() and (npc_id.is_empty() or Jobs.job().employer == npc_id):
					Jobs.quit("El jugador dejó el trabajo." if npc_id.is_empty() else "Despediste al jugador.")
					note = "Ya no trabajas ahí."
			"leave", "go_inside":
				if not npc_id.is_empty() and NPCMemory.is_following(npc_id):
					NPCMemory.set_fields(npc_id, {"following": false})
		npc_action.emit(npc_id, a)
		if not note.is_empty():
			notes.append(note)
	if not notes.is_empty():
		performed.emit(notes)
	return notes


const NEED_NOTES := {"hunger": ["Te quitas el hambre.", "Comes algo."], "thirst": ["Sacias la sed.", "Bebes algo."],
	"rest": ["Descansas de verdad.", "Descansas un poco."], "hygiene": ["Te quedas limpio/a.", "Te aseas un poco."]}


## Comer, beber, descansar, lavarse… "amount" de -30 a 30 (30 = una comida completa, una ducha).
func _change_need(a: Dictionary) -> String:
	var need := ContentValidator._match_enum(str(a.get("target", "")), ContentValidator.archetypes().need)
	var amount := int(a.get("amount", 0))
	if need.is_empty() or amount == 0:
		return ""
	Body.change(need, amount * 3.0)
	if amount < 0:
		return ""
	return NEED_NOTES[need][0 if amount >= 20 else 1]


## Pagar a alguien. Si no te llega, no se paga (y la nota lo dice).
func _pay(to: String, price: int) -> String:
	price = clampi(price, 0, Wallet.MAX_PER_ACTION)
	if price <= 0:
		return ""
	Wallet.reason = ("Pago a " + _name(to)) if not to.is_empty() else "Pago"
	if not Wallet.pay(price):
		return "No te llega: llevas %s." % Wallet.text()
	if not to.is_empty():
		var owed := int(NPCMemory.get_mem(to).get("owed", 0))
		NPCMemory.set_fields(to, {"owed": maxi(owed - price, 0)})
		NPCMemory.add_event(to, "El jugador te pagó %s." % Wallet.text(price))
		return "Pagas %s a %s." % [Wallet.text(price), _name(to).split(" ")[0]]
	return "Pagas %s." % Wallet.text(price)


## El PNJ te cobra algo: queda pendiente hasta que pagues (botón Pagar en la conversación).
func _charge(npc_id: String, price: int, what: String) -> String:
	price = clampi(price, 0, Wallet.MAX_PER_ACTION)
	if price <= 0:
		return ""
	var owed := int(NPCMemory.get_mem(npc_id).get("owed", 0)) + price
	NPCMemory.set_fields(npc_id, {"owed": owed})
	charged.emit(npc_id, owed)
	return "%s te cobra %s%s." % [_name(npc_id).split(" ")[0], Wallet.text(price), (" (%s)" % what) if not what.strip_edges().is_empty() else ""]


## Gente que la IA creó en este lugar (se reconstruye al volver).
func residents_here(location_id: String) -> Array:
	return WorldDB.get_state("residents", {}).get(location_id, [])


func places_added_here(location_id: String) -> Array:
	return WorldDB.get_state("places_added", {}).get(location_id, [])


const OUTFIT_WORDS := {"lab_coat": ["médic", "medic", "doctor", "enfermer", "científ", "farmac", "veterin"],
	"work_uniform": ["fontaner", "mecán", "mecan", "electric", "poli", "guardia", "cartero", "repartid", "pescador", "obrer", "bomber", "camarer"],
	"formal": ["abogad", "alcald", "banquer", "notari", "director", "concejal"], "ragged": ["mendig", "vagabund"]}
const TRAIT_WORDS := {"amable": "amable", "simpátic": "simpático/a", "seri": "serio/a", "gruñ": "gruñón/a", "callad": "callado/a",
	"hablad": "hablador/a", "nervios": "nervioso/a", "tranquil": "tranquilo/a", "desconfiad": "desconfiado/a", "alegre": "alegre",
	"brusc": "brusco/a", "tímid": "tímido/a", "curios": "curioso/a", "orgullos": "orgulloso/a", "honrad": "honrado/a",
	"pícar": "pícaro/a", "bromista": "bromista", "educad": "educado/a", "torpe": "torpe", "eficaz": "eficaz", "profesional": "profesional"}


## Alguien nuevo que encaja aquí ("llamo a un fontanero"). Se monta la entidad sin otra llamada a la IA.
func _spawn_npc(a: Dictionary) -> String:
	var place := GameState.current_location()
	if residents_here(place).size() >= MAX_RESIDENTS:
		return ""
	var full_name := str(a.get("name", a.get("item_name", ""))).strip_edges()
	var job := str(a.get("occupation", a.get("target", "vecino/a"))).strip_edges()
	if full_name.length() < 2:
		return ""
	var line := str(a.get("line", "Hola, ¿qué tal?"))
	var id := build_npc(full_name, job, str(a.get("text", "")).strip_edges(), line)
	if id.is_empty():
		return ""
	Phone.add_contact(id)  # lo llamaste tú: tienes su número
	var spot: Dictionary = arrival_spot.call() if arrival_spot.is_valid() else {"from": Vector3.ZERO, "to": Vector3.ZERO}
	var to: Vector3 = spot.get("to", Vector3.ZERO)
	var entry := add_resident(id, spot.get("home", to))  # donde vive (fuera, aunque llegue a un interior)
	resident_added.emit(entry.merged({"arrive_from": spot.get("from", to), "arrive_to": to, "line": line}))
	return "Llega %s (%s)." % [full_name, job.to_lower()]


## Monta un PNJ completo y válido a partir de nombre, oficio y una descripción (sin llamar a la IA).
## `look`: aspecto ya decidido (un transeúnte que pasa a ser vecino conserva el suyo).
func build_npc(full_name: String, job: String, desc: String, line: String, look: Dictionary = {}) -> String:
	var place := GameState.current_location()
	var low := (job + " " + desc).to_lower()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(full_name + place)
	var outfit := "casual"
	for o in OUTFIT_WORDS:
		if OUTFIT_WORDS[o].any(func(w): return low.contains(w)):
			outfit = o
	var traits := []
	for w in TRAIT_WORDS:
		if low.contains(w):
			traits.append(TRAIT_WORDS[w])
	var first := full_name.split(" ")[0].to_lower()
	var appearance := {"figure": "feminine" if first.ends_with("a") and not first in ["luca", "nicola", "joshua"] else "masculine",
		"outfit": outfit, "primary_color": Color.from_hsv(rng.randf(), 0.45, 0.55).to_html(false),
		"secondary_color": Color.from_hsv(rng.randf(), 0.25, 0.8).to_html(false), "body": ["slim", "average", "sturdy", "tall"][rng.randi() % 4]}
	appearance.merge(look, true)
	var data := {
		"name": full_name.left(40), "age": rng.randi_range(22, 66), "occupation": job.left(80),
		"personality": traits.slice(0, 3) if not traits.is_empty() else ["natural"],
		"goals": ["Hacer bien su trabajo de %s" % job.to_lower()], "secret": "Nada especial, de momento.",
		"greeting": line.left(240), "appearance": appearance, "tags": ["vecino"],
	}
	var check := ContentValidator.validate("npc", data)
	if not check.ok:
		return ""
	check.data["description"] = desc.left(300)
	return WorldDB.add_entity("npc", check.data, "world:%s" % place)


## Alguien se queda a vivir en el lugar actual (se reconstruye al volver).
func add_resident(id: String, home: Vector3) -> Dictionary:
	var place := GameState.current_location()
	var here := residents_here(place)
	var entry := {"id": id, "home": [snappedf(home.x, 0.01), snappedf(home.y, 0.01), snappedf(home.z, 0.01)]}
	here.append(entry)
	var all: Dictionary = WorldDB.get_state("residents", {})
	all[place] = here
	WorldDB.set_state("residents", all)
	return entry


## Un sitio nuevo: un edificio con letrero, puerta e interior, en un solar libre.
func _create_place(a: Dictionary) -> String:
	var place := GameState.current_location()
	var here := places_added_here(place)
	if here.size() >= MAX_NEW_PLACES:
		return ""
	var kind := ContentValidator._match_enum(str(a.get("target", "shop")), ContentValidator.archetypes().place_kind)
	if kind.is_empty():
		kind = "shop"
	var label := str(a.get("item_name", a.get("name", ""))).strip_edges()
	if label.length() < 2:
		return ""
	var lot: Dictionary = lot_finder.call() if lot_finder.is_valid() else {}
	if lot.is_empty():
		return "No hay sitio libre para %s." % label
	var pos: Vector3 = lot.pos
	var entry := {"name": label.left(50), "kind": kind, "interior": INTERIOR_OF.get(kind, "house"), "text": str(a.get("text", "")).left(200),
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "yaw": float(lot.get("yaw", 0.0)),
		"seed": hash(label + place)}
	here.append(entry)
	var all: Dictionary = WorldDB.get_state("places_added", {})
	all[place] = here
	WorldDB.set_state("places_added", all)
	place_added.emit(entry)
	return "Ahora hay %s aquí." % label


## Baúles: lo que guardaste en algo que construiste (persistente).
func stash(key: String) -> Array:
	return WorldDB.get_state("stashes", {}).get(key, [])


func stash_put(key: String, item_id: String) -> bool:
	if not Inventory.has(item_id) or Inventory.is_anchor(item_id):
		return false
	var all: Dictionary = WorldDB.get_state("stashes", {})
	var list: Array = all.get(key, [])
	list.append(item_id)
	all[key] = list
	WorldDB.set_state("stashes", all)
	Inventory.remove(item_id)
	return true


func stash_take(key: String, item_id: String) -> bool:
	var all: Dictionary = WorldDB.get_state("stashes", {})
	var list: Array = all.get(key, [])
	if not (item_id in list):
		return false
	list.erase(item_id)
	all[key] = list
	WorldDB.set_state("stashes", all)
	Inventory.add(item_id)
	return true


## Lo que le debes a alguien.
func owed(npc_id: String) -> int:
	return int(NPCMemory.get_mem(npc_id).get("owed", 0))


## Pagar lo pendiente (botón Pagar del diálogo).
func settle(npc_id: String) -> String:
	var debt := owed(npc_id)
	if debt <= 0:
		return ""
	return _pay(npc_id, debt)


## Id de un PNJ a partir de lo que diga la IA: "npc:npc_teo", "npc_teo", "Teo" o "Teo Vidal".
func npc_from(text: String) -> String:
	var t := text.strip_edges().trim_prefix("npc:").to_lower()
	if t.is_empty():
		return ""
	var npcs := WorldDB.query("npc")
	for e in npcs:
		if str(e.get("id", "")) == t:
			return t
	# "npc_tomas_arriaga", "Tomas", "tomás": sin acentos, sin prefijo y con espacios
	var plain := _plain(t.trim_prefix("npc_").replace("_", " "))
	for e in npcs:
		var n := _plain(str(e.get("name", "")))
		if not n.is_empty() and (n == plain or n.split(" ")[0] == plain.split(" ")[0] or plain.contains(n.split(" ")[0])):
			return str(e.id)
	return ""


static func _plain(text: String) -> String:
	var out := text.to_lower().strip_edges()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"]]:
		out = out.replace(pair[0], pair[1])
	return out


## Lo que el PNJ siente y recuerda de lo que le acabas de hacer (lo escribe el motor, no la IA).
func _npc_react(who: String, a: Dictionary) -> String:
	var delta := clampi(int(a.get("amount", 0)), -30, 30)
	var memory := str(a.get("text", "")).strip_edges()
	if memory.is_empty():
		memory = str(a.get("narration", "")).strip_edges()
	if not memory.is_empty():
		NPCMemory.add_event(who, memory.left(200), delta)
	elif delta != 0:
		NPCMemory.add_event(who, "Algo que hizo el jugador te afectó.", delta)
	var line := str(a.get("line", "")).strip_edges()
	return ("%s: «%s»" % [_name(who).split(" ")[0], line]) if not line.is_empty() else ""


func _give_to_npc(a: Dictionary) -> String:
	var who := npc_from(str(a.get("target", "")))
	var id := Inventory.find_by_name(str(a.get("item_name", a.get("text", ""))))
	if who.is_empty() or id.is_empty():
		return ""
	return player_gives(who, id)


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
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "yaw": yaw,
		"id": "p%d" % (Time.get_ticks_usec() % 100000000), "function": str(a.get("function", "none"))}
	# Su forma: las piezas que describió la IA (una antena, un generador…), acotadas
	var parts := []
	for p in a.get("parts", []):
		if p is Dictionary and p.get("size", []).size() == 3 and p.get("pos", []).size() == 3:
			parts.append({"shape": str(p.get("shape", "box")), "size": p.size, "pos": p.pos, "color": str(p.get("color", "#8b6b4a"))})
	if not parts.is_empty():
		entry["parts"] = parts.slice(0, 14)
	if entry.function == "none" and kind in ["chair", "bed", "campfire", "box", "torch"]:
		entry.function = {"chair": "seat", "bed": "bed", "campfire": "heat", "box": "storage", "torch": "light"}[kind]
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
	# "target": un tipo ("tree") o el id concreto que la escena le dio a la IA ("tree_12_-4")
	var raw := str(a.get("target", "tree")).strip_edges()
	var is_id := raw.contains("_") and raw.get_slice("_", 1).is_valid_int()
	var kind := ContentValidator._match_enum(raw.get_slice("_", 0) if is_id else raw, ContentValidator.archetypes().world_feature)
	if kind.is_empty():
		return ""
	var id: String = feature_finder.call(raw if is_id else kind) if feature_finder.is_valid() else ""
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

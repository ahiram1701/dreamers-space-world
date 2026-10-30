extends Node
## Conversaciones con PNJs, turno a turno. La IA interpreta al PNJ y además "observa"
## al jugador: lo que el PNJ aprende va a NPCMemory y lo que revela el jugador, a PlayerProfile.
##
## Uso:  var t := await StoryDirector.talk("npc_marina", "¿Qué pasa con el faro?", "Acto 0, al atardecer")
##       t = { ok, source: "ai" | "fallback", line, emotion, choices: [{text, tone}], end_conversation }

signal turn_started(npc_id: String)
signal turn_finished(npc_id: String, turn: Dictionary)


func talk(npc_id: String, player_input: String, scene_context: String) -> Dictionary:
	turn_started.emit(npc_id)
	var npc := WorldDB.get_entity("npc", npc_id)
	if npc.is_empty():
		return {"ok": false, "error": "PNJ desconocido: %s" % npc_id}

	var messages := [{"role": "system", "content": _system_prompt(npc, scene_context)}]
	for h in NPCMemory.get_mem(npc_id).history:
		# Las respuestas anteriores del PNJ van en JSON: si van como texto plano, algunos
		# modelos (p. ej. DeepSeek) imitan ese estilo y dejan de responder en JSON.
		var content: String = h.text if h.who == "player" else JSON.stringify({"line": h.text})
		messages.append({"role": "user" if h.who == "player" else "assistant", "content": content})
	var said := player_input.strip_edges()
	messages.append({"role": "user", "content": said if not said.is_empty() else _opening(npc_id)})

	var res := await ContentGenerator.request_valid("dialogue_turn", messages)
	var turn: Dictionary = res.data if res.ok else _fallback_turn(npc, res.errors)
	turn["ok"] = true
	turn["source"] = "ai" if res.ok else "fallback"
	if res.ok:
		make_consistent(turn)
	# Lo que el PNJ hace (dar, acompañar, curar, irse…) ocurre de verdad, no solo se dice
	turn["notes"] = Actions.execute(npc_id, turn.get("actions", [])) if res.ok else []

	# Un respaldo no es algo que el PNJ haya "dicho": no ensucia su memoria (salvo presentarse)
	if res.ok or not NPCMemory.get_mem(npc_id).met:
		NPCMemory.record_turn(npc_id, said, turn.line, truthful_facts(turn.get("new_facts", [])), int(turn.relationship_delta))
	if not said.is_empty():  # solo lo que el jugador dice o elige revela su carácter
		PlayerProfile.apply_signals(turn.get("trait_signals", []))
	turn_finished.emit(npc_id, turn)
	return turn


## Frases en las que el PNJ dice que se va o se mete en algún sitio ("me voy a casa", "me encierro").
const LEAVE_WORDS := ["me voy", "me marcho", "me largo", "me piro", "me retiro", "me vuelvo a", "me vuelvo pa",
	"adiós, me", "hasta aquí", "nos vemos, me"]
const INSIDE_WORDS := ["me encierro", "me meto en", "me meto dentro", "entro en", "entro a", "me voy dentro",
	"me voy adentro", "cierro la puerta", "echo el pestillo", "echo la llave", "me meto a", "me encerraré", "voy dentro"]
## Hechos que afirman que alguien se movió: los escribe el motor cuando pasa de verdad, no la IA.
const MOVEMENT_FACT := ["entr", "encerr", "pestillo", "se fue", "se va ", "march", "irse", "largarse", "se larg", "salió", "sale de",
	"se dirig", "camin", "se metió", "se mete", "cerró la puerta", "dio la espalda y se"]
const LEAVING_TYPES := ["leave", "go_inside"]


## Lo que el PNJ dice que hace, lo hace: si anuncia que se va o se encierra y no trae la acción,
## se añade. Si se va (o no quiere hablar), la conversación termina.
static func make_consistent(turn: Dictionary) -> void:
	var actions: Array = turn.get("actions", [])
	var types: Array = actions.map(func(a): return a.get("type", ""))
	var low := " " + str(turn.get("line", "")).to_lower()
	if not types.any(func(t): return t in LEAVING_TYPES):
		var inside := INSIDE_WORDS.any(func(w): return low.contains(w))
		var leave := inside or LEAVE_WORDS.any(func(w): return low.contains(w))
		if leave:
			var a := {"type": "go_inside" if inside else "leave", "target": _place_in(low)}
			actions.append(a)
			types.append(a.type)
	turn["actions"] = actions
	var leaving: bool = types.any(func(t): return t in LEAVING_TYPES)
	turn["leaving"] = leaving
	if leaving:
		turn["end_conversation"] = true
		# Encerrarse enfadado: la puerta queda cerrada
		if "refuse_contact" in types:
			for a in actions:
				if a.get("type", "") == "go_inside":
					a["locked"] = true


## Lugar mencionado en una frase ("me voy a la cafetería" → "cafetería"), o "".
static func _place_in(low: String) -> String:
	for marker in [" a la ", " al ", " en la ", " en el ", " a mi ", " en mi ", " a casa", " en casa"]:
		var i := low.find(marker)
		if i >= 0:
			if marker.ends_with("casa"):
				return "casa"
			return low.substr(i + marker.length()).get_slice(" ", 0).get_slice(".", 0).get_slice(",", 0)
	return ""


## Descarta los "hechos" que afirman movimientos (entrar, irse, encerrarse): esos los apunta el
## motor solo si ocurren, para que el PNJ no recuerde cosas que nunca pasaron.
static func truthful_facts(facts: Array) -> Array:
	return facts.filter(func(f):
		var low := " " + str(f).to_lower()
		return not MOVEMENT_FACT.any(func(w): return low.contains(w)))


## Pasos que tienen sentido en una acción del jugador (tecla F).
const WORLD_STEPS := ["go_to", "play", "use", "npc_react", "give_to_npc", "give_item", "change_stat", "journal",
	"reveal_place", "update_item", "remove_item", "place_object", "affect_nearby", "change_need", "pay", "earn",
	"spawn_npc", "create_place"]
const MAX_FINDS_PER_PLACE := 6  # rebuscar sin parar no llena el inventario (fabricar no cuenta)
const MAX_ACTION_MINUTES := 240
## Si la narración cuenta esto, tiene que haber un paso de este tipo (si no, se pide otra vez).
const REQUIRED_STEPS := [
	[["talas", "derribas", "cae el árbol", "el árbol cae", "cortas el árbol"], "affect_nearby"],
	[["construyes", "levantas una", "montas una", "fabricas una balsa", "terminas la balsa", "terminas el"], "place_object"],
	[["golpeas", "le pegas", "puñetazo", "empujas a", "abrazas", "le das la mano", "le das una palmada", "patada"], "npc_react"],
	[["reparas", "arreglas", "queda arreglad", "queda reparad"], "update_item"],
	[["le das ", "le entregas", "le regalas"], "give_to_npc"],
	[["te sientas", "te tumbas", "te acuestas", "entras en", "subes a la barca", "subes al bote"], "use"],
	[["pagas", "le pagas", "dejas el dinero", "sueltas unas monedas"], "pay"],
	[["te comes", "devoras", "comes ", "bebes", "te bebes", "te duchas", "te lavas"], "change_need"],
]

const ACT_PROMPT := """

Eres el narrador y el director de escena. El jugador escribe lo que hace con su cuerpo; tú decides qué ocurre de forma realista y física, y lo conviertes en PASOS que el juego representa en orden: el personaje camina, hace el gesto, usa cosas, la gente reacciona y el mundo cambia.

Reglas:
- Sé justo y físico: no todo sale bien; hacen falta herramientas, materiales y tiempo. Lo que se encuentre tiene sentido en ese lugar.
- Las personas cercanas reaccionan de inmediato y de forma creíble según su carácter y su relación con el jugador (npc_react). Una conversación larga se tiene hablando con ellas (E), aquí solo su reacción inmediata.
- Solo puedes usar lo que aparece en "COSAS Y PERSONAS CERCA", con su id exacto en "target", y lo que el jugador LLEVA ENCIMA (eso lo tiene a mano siempre, aunque no esté en la lista de cosas cercanas). Si lo que quiere hacer no está cerca, no ocurre: dilo en la narración.
- TODO lo que narres que pasa de verdad necesita su paso. Si no hay paso, no pasa.

"narration": resumen breve (1 a 3 frases, segunda persona).
"steps": lista ordenada (máximo 8). Cada paso: "type", sus campos y "narration" (una frase corta de ese momento).
- go_to: caminar hasta algo. "target": id (npc:..., tree_..., door:..., seat:1, water…).
- play: gesto del personaje. "target": chop, hammer, dig, pick_up, search, crouch, sit, sleep, drink, eat, wave, point, give, fish, swim, dance, think, punch, push, kick, hug, handshake, throw, pat, kneel, write, read, listen, call.
- use: usar algo (sentarse en seat, dormir en bed, entrar por door, subir a boat). "target": id.
- npc_react: cómo reacciona una persona. "target": su id (npc:...); "emotion": angry, scared, happy, sad, worried, curious, amused o neutral; "gesture" (de la lista); "behavior": stay, flee, approach, follow, go_inside, fight_back o leave; "line": lo que suelta (corto); "amount": cuánto cambia su opinión del jugador (-30 a 30); "text": lo que recordará, desde su punto de vista ("El jugador te dio un puñetazo en el muelle sin motivo").
- give_to_npc: das algo que llevas. "target": id de la persona; "item_name": el objeto.
- give_item: consigue o fabrica algo que se lleva encima ("item_name", "item_description", "item_effect": para qué sirve de verdad en el juego — light (da luz), nourish (se come), hydrate (se bebe), signal (capta señales), warmth (abriga), tool (herramienta), heal (cura) o none).
- update_item: repara o modifica algo que LLEVA ENCIMA. "target": nombre actual; "item_name": nombre nuevo; "item_description".
- remove_item: gasta, come, rompe o usa como material algo que lleva. "target": nombre.
- place_object: construye o coloca algo grande. "target": boat, raft, campfire, tent, shelter, table, chair, bed, fence, sign, torch, box, garden u other; "item_name"; "function": para qué sirve (light, seat, bed, shelter, heat, storage —guardar cosas—, signal o none). Si es algo inventado ("other"), describe su forma con "parts": de 3 a 12 piezas {"shape": box|cylinder|sphere, "size": [ancho, alto, fondo] en metros, "pos": [x, y, z] respecto a su base (y = altura del centro), "color": "#rrggbb"}; por ejemplo una antena: un poste cilíndrico fino y alto y un plato.
- affect_nearby: tala, rompe, arranca o cosecha. "target": el id del árbol/roca/arbusto.
- change_stat ("target": health/energy/instability, "amount"), journal ("text"), reveal_place ("target", "text").
- change_need: comer, beber, dormir un rato, lavarse… "target": hunger, thirst, rest o hygiene; "amount" de -30 a 30 (30 = comida completa, una ducha; 8 = un bocado o un sorbo). Solo si de verdad tiene con qué (comida, agua, un baño).
- pay: el jugador paga. "target": id de quien cobra (o vacío); "price" en dólares. No puede pagar más de lo que lleva.
- earn: al jugador le pagan (un trabajo hecho, algo vendido). "price" en dólares, razonable.
- spawn_npc: aparece una persona nueva que tiene sentido aquí (llamaste a un fontanero, pasa una vendedora…). "name" (nombre y apellido), "occupation", "text" (cómo es y su carácter, 1-2 frases), "line" (lo primero que dice). Se queda a vivir en el lugar.
- create_place: aparece o se abre un sitio nuevo que encaja con el lugar y la época (una panadería, un taller…). "item_name": su nombre (el del letrero); "target": shop, bakery, bar, workshop, house, office, clinic o market; "text": cómo es.
"minutes": cuánto tarda de verdad (talar ~30, construir una balsa ~180, buscar ~10, un golpe ~1, comer ~20, ducharse ~15).

CREAR E INVENTAR: se puede crear casi cualquier cosa, pero como en la vida real: hacen falta conocimientos, materiales (que se gastan con remove_item), herramientas y tiempo acordes a la época y al lugar. Si falta algo, sale peor o no sale, y se cuenta qué faltó. La ciencia ficción está permitida si se apoya en algo que existe en este mundo (el Ancla, tecnología de otro mundo o época, materiales anómalos), siempre con física creíble y nunca magia.

Realismo: el cuerpo del jugador, su dinero, la hora, el día y el tiempo importan (de noche está todo cerrado, con lluvia la gente se resguarda, sin dinero no se compra). Crea gente o sitios solo si lo que hace el jugador lo pide y es creíble; usa lo que ya existe antes que inventar.

Ejemplo, "le pego a Teo" con Teo a 6 m: "steps": [{"type": "go_to", "target": "npc:npc_teo", "narration": "Vas directo hacia Teo."}, {"type": "play", "target": "punch", "narration": "Le das un puñetazo en el hombro."}, {"type": "npc_react", "target": "npc:npc_teo", "emotion": "angry", "gesture": "cross_arms", "behavior": "go_inside", "line": "¡¿Pero tú de qué vas?!", "amount": -25, "text": "El jugador te dio un puñetazo sin motivo.", "narration": "Teo retrocede, furioso, y se marcha a la cafetería."}], "minutes": 2
Ejemplo, "talo el árbol de al lado" llevando un hacha: [{"type": "go_to", "target": "tree_12_-4"}, {"type": "play", "target": "chop", "narration": "Golpeas el tronco una y otra vez."}, {"type": "affect_nearby", "target": "tree_12_-4", "narration": "El árbol cruje y cae."}, {"type": "give_item", "item_name": "Troncos de pino", "item_description": "Cuatro troncos recién cortados."}], "minutes": 40"""


## El jugador hace algo libre en el mundo (tecla F). La IA lo convierte en pasos (ir, gesto, usar,
## reacciones, cambios) que el ActionPerformer representa en orden. Aquí no se ejecuta nada.
## Devuelve { ok, narration, steps, minutes, error }.
func act(what: String, scene_context: String) -> Dictionary:
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + ACT_PROMPT},
		{"role": "user", "content": "ESCENA:\n%s\n\nQUIÉN ES EL JUGADOR: %s\nLLEVA ENCIMA: %s\n\nLO QUE HACE: %s" % [
			scene_context, PlayerProfile.describe(), _inventory_text(true), what]},
	]
	var res := await ContentGenerator.request_valid("world_action", messages)
	if not res.ok:
		var reason := str(res.errors[0]) if not res.errors.is_empty() else "sin respuesta"
		return {"ok": false, "narration": "", "steps": [], "error": reason.left(140)}
	var data: Dictionary = res.data
	var missing := missing_steps(data)
	if not missing.is_empty():  # contó algo que no está en los pasos: una sola corrección
		messages.append({"role": "assistant", "content": JSON.stringify(data)})
		messages.append({"role": "user", "content": "Tu narración cuenta cosas que no tienen su paso (%s). Devuelve el JSON completo otra vez con esos pasos incluidos, o cambia la narración para que no ocurran." % ", ".join(missing)})
		var again := await ContentGenerator.request_valid("world_action", messages)
		if again.ok:
			data = again.data
	return {"ok": true, "narration": data.narration, "steps": plan_steps(data), "error": "",
		"minutes": clampi(int(data.get("minutes", 5)), 0, MAX_ACTION_MINUTES)}


## Cómo fue un turno de trabajo (1–2 frases), con algún pequeño suceso que puede quedar en el diario.
func shift_summary(job: Dictionary, result: Dictionary, perception: PackedStringArray) -> String:
	var boss: String = WorldDB.get_entity("npc", job.employer).get("name", "tu jefe/a")
	var fallback := "Terminas tu turno de %s. Ha sido un día normal." % str(job.title).to_lower()
	if Settings.use_mock or not Settings.has_api_key():
		return fallback
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nCuentas en segunda persona, en 1 o 2 frases realistas, cómo fue el turno de trabajo del jugador: algo concreto que pasó (un cliente, una avería, una conversación con su jefe/a). Puedes añadir como mucho un paso journal si pasó algo digno de apuntar."},
		{"role": "user", "content": "%s\n\nTRABAJO: %s en %s, jefe/a %s. Horas trabajadas: %.1f. Llegó %d min tarde.\nLo que sabe su jefe/a de él/ella:\n%s" % [
			"\n".join(perception), job.title, job.place_label, boss, float(result.get("hours", 0.0)), int(result.get("late_minutes", 0)), NPCMemory.describe(job.employer)]},
	]
	var res := await ContentGenerator.request_valid("world_action", messages)
	if not res.ok:
		return fallback
	Actions.execute("", res.data.get("steps", []).filter(func(s): return s.get("type", "") == "journal"))
	return str(res.data.narration)


## Tipos de paso que la narración da por hechos y no aparecen.
static func missing_steps(data: Dictionary) -> Array:
	var types: Array = (data.get("steps", []) + data.get("actions", [])).map(func(a): return a.get("type", ""))
	var text := " " + str(data.get("narration", "")).to_lower()
	var missing := []
	for rule in REQUIRED_STEPS:
		if rule[0].any(func(w): return text.contains(w)) and not (rule[1] in types):
			if rule[1] == "place_object" and "give_item" in types:
				continue  # fabricar algo pequeño que se lleva encima también vale
			missing.append(rule[1])
	return missing


## Pasos que se van a representar: los de "steps" (o "actions" de modelos antiguos), filtrados y
## con el límite de hallazgos por lugar (rebuscar sin parar no llena el inventario).
func plan_steps(data: Dictionary) -> Array:
	var raw: Array = data.get("steps", [])
	if raw.is_empty():
		raw = data.get("actions", [])
	var place := GameState.current_location()
	var finds: Dictionary = WorldDB.get_state("finds", {})
	var crafting: bool = raw.any(func(a): return a.get("type", "") in ["remove_item", "affect_nearby"])
	var out := []
	for a in raw:
		if not (a.get("type", "") in WORLD_STEPS):
			continue
		if a.type == "give_item" and not crafting:
			if int(finds.get(place, 0)) >= MAX_FINDS_PER_PLACE:
				continue
			finds[place] = int(finds.get(place, 0)) + 1
		out.append(a)
	WorldDB.set_state("finds", finds)
	# Modelos que solo dan "actions": el gesto va primero, los efectos después
	if data.get("steps", []).is_empty():
		out.sort_custom(func(x, y): return x.type == "play" and y.type != "play")
	return out


func end_conversation(npc_id: String) -> void:
	NPCMemory.end_conversation(npc_id)


## Sin IA: el PNJ al menos usa su propio saludo la primera vez, y el jugador ve por qué.
func _fallback_turn(npc: Dictionary, errors: Array) -> Dictionary:
	var turn := ContentGenerator.load_fallback("dialogue_turn")
	if not NPCMemory.get_mem(npc.id).met:
		turn.line = npc.get("greeting", turn.line)
	var reason := str(errors[0]) if not errors.is_empty() else "sin respuesta"
	turn["error"] = reason.replace("[", "(").replace("]", ")").left(140)  # se muestra con BBCode
	return turn


## Los modelos a veces repiten o inventan la consecuencia de una opción: se reparte
## una de cada (en orden) entre las que falten, para que todas las ramas sean posibles.
static func _ensure_distinct(choices: Array, field: String, allowed: Array) -> void:
	var used := []
	for c in choices:
		if c[field] in allowed and not (c[field] in used):
			used.append(c[field])
		else:
			c[field] = ""
	for c in choices:
		if c[field] == "":
			for a in allowed:
				if not (a in used):
					c[field] = a
					used.append(a)
					break


# --- El Despertar ---------------------------------------------------------------------

const ACT0_NEIGHBORS := ["npc_marina", "npc_teo", "npc_samir"]
const ORIGIN_GUIDE := """ORÍGENES POSIBLES (elige UNO según quién es el jugador y con quién conectó):
- future_probe: una sonda enviada desde el año 2190 está enterrada bajo el faro; su núcleo emite el pulso.
- failed_experiment: bajo el faro hay un laboratorio sellado de un proyecto de física de los años 80 que abrió la brecha.
- branch_transmission: otra versión del jugador, desde otra rama, transmite por la frecuencia que capta Samir los planos del Ancla.
- alien_artifact: un objeto de origen no humano estabiliza una brecha natural bajo el faro.
- natural_anomaly: una microbrecha natural que la lente del faro amplifica por accidente.
Pistas: escépticos → explicaciones de laboratorio o naturales; curiosos → sonda o artefacto; quien conectó con Samir → transmisión; con Marina → el faro; con Teo → las filtraciones de memoria."""


## Pide a la IA el Despertar de ESTE jugador. Siempre devuelve uno válido (IA o respaldo).
func generate_awakening() -> Dictionary:
	var neighbors := PackedStringArray()
	for id in ACT0_NEIGHBORS:
		var npc := WorldDB.get_entity("npc", id)
		if not npc.is_empty():
			neighbors.append("%s (%s): %s" % [npc.name, npc.occupation, NPCMemory.describe(id)])
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEres el narrador de EL DESPERTAR: el momento en que el jugador descubre la brecha bajo el faro y obtiene el Ancla. Escribe en segunda persona, con detalle sensorial y explicaciones físicas creíbles. Nada sobrenatural."},
		{"role": "user", "content": """Son las 3:33. El jugador entra en el faro durante el pulso.

QUIÉN ES EL JUGADOR: %s

LO QUE RECUERDA CADA VECINO DE ÉL:
%s

%s

Crea su Despertar:
- "narration": lo que vive (el pulso, la dilatación temporal alrededor del faro, el descubrimiento de la fuente).
- "anchor": el dispositivo que le permite viajar; "base" es el objeto del pueblo sobre el que se construye (o "none").
- "canon_facts": 2-3 hechos que serán verdad para siempre en este mundo.
- "choices": exactamente una opción por consecuencia (jump_alone, jump_with_companion, seal_behind), escritas para esta historia.
- "destination_hint": a qué tipo de lugar o época le llevará su primer salto.""" % [
			PlayerProfile.describe(), "\n".join(neighbors), ORIGIN_GUIDE]},
	]
	var res := await ContentGenerator.request_valid("awakening", messages)
	var data: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("awakening")
	data["source"] = "ai" if res.ok else "fallback"
	_ensure_distinct(data.choices, "consequence", ContentValidator.archetypes().awakening_consequence)
	if not res.ok:
		push_warning("El Despertar usó respaldo: %s" % [res.errors])
	return data


## Aplica la decisión: canon, Ancla, compañero, stats y raíz del árbol temporal.
## No salta: eso lo hace Travel.jump_new() justo después.
func apply_awakening(data: Dictionary, choice_index: int) -> Dictionary:
	var choice: Dictionary = data.choices[clampi(choice_index, 0, data.choices.size() - 1)]
	var consequence: String = choice.consequence
	var companion := _closest_neighbor() if consequence == "jump_with_companion" else ""
	GameState.awaken(companion, consequence == "seal_behind")

	for fact in data.canon_facts:
		WorldDB.add_canon(fact)
	WorldDB.add_canon("En El Despertar, el jugador decidió: %s" % choice.text)

	var anchor_id := WorldDB.add_entity("item", {
		"name": data.anchor.name, "kind": "technology", "effect": "none", "power": 100,
		"lore": data.anchor.description, "tags": ["ancla", data.anchor.base],
	}, "awakening")
	WorldDB.set_state("awakening", {
		"origin": data.origin, "title": data.title, "anchor_id": anchor_id,
		"consequence": consequence, "choice": choice.text, "destination_hint": data.destination_hint,
	})

	if not companion.is_empty():
		NPCMemory.add_facts(companion, ["Decidió cruzar la brecha junto al jugador en El Despertar."], 15)
		NPCMemory.set_fields(companion, {"following": true})
	TimelineManager.create_root("El Despertar", GameState.HOME, "present")
	return {"consequence": consequence, "companion": companion, "anchor_id": anchor_id}


# --- El final -------------------------------------------------------------------------

## La revelación del origen de la señal y los tres finales, escritos con TODO lo vivido.
func generate_finale() -> Dictionary:
	var awakening: Dictionary = WorldDB.get_state("awakening", {})
	var places := PackedStringArray()
	for n in TimelineManager.visited_locations():
		places.append(Travel.location_name(n.location_id))
	var quests := PackedStringArray()
	for q in Quests.all_quests():
		if q.status == "done":
			quests.append(q.title)
	var companion := WorldDB.get_entity("npc", GameState.companion())
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEres el narrador del FINAL. Cierra la historia de este jugador con coherencia total con el canon, en segunda persona, con emoción contenida y física creíble."},
		{"role": "user", "content": """El jugador ha reunido las coordenadas completas de la transmisión de radio que Samir captaba cada noche a las 3:33 en Bahía de las Horas, y ha llegado a su origen.

Origen de su Ancla: %s (%s)
Decisión en El Despertar: %s
Compañero: %s
Lugares recorridos: %s
Misiones completadas: %s
Quién es: %s

Escribe:
- "revelation": qué es realmente el origen de la señal y por qué el jugador. Debe encajar con el origen del Ancla y el canon.
- "source_voice": lo que dice la propia señal (o quien la emite) al jugador.
- "choices": exactamente tres, una por final: close_the_loop (convertirse en el emisor y cerrar el bucle causal), return_home (volver a Bahía de las Horas y apagar el Ancla), keep_traveling (dejar el emisor y seguir explorando). Cada una con su "epilogue": cómo termina la historia, mencionando detalles de su viaje.""" % [
			awakening.get("origin", "?"), awakening.get("title", ""), awakening.get("choice", "?"),
			companion.get("name", "nadie"), ", ".join(places), ", ".join(quests), PlayerProfile.describe()]},
	]
	var res := await ContentGenerator.request_valid("finale", messages)
	var data: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("finale")
	data["source"] = "ai" if res.ok else "fallback"
	_ensure_distinct(data.choices, "ending", ContentValidator.archetypes().ending)
	return data


## Guarda el final elegido. El mundo queda "completado", pero se puede seguir jugando.
func apply_ending(data: Dictionary, choice_index: int) -> Dictionary:
	var choice: Dictionary = data.choices[clampi(choice_index, 0, data.choices.size() - 1)]
	GameState.set_ending(choice.ending)
	WorldDB.add_canon("Final: %s" % choice.text)
	WorldDB.set_state("finale", {"title": data.title, "ending": choice.ending, "epilogue": choice.epilogue})
	return {"ending": choice.ending, "epilogue": choice.epilogue, "title": data.title}


## El vecino con mejor relación (a igualdad, el que más ha hablado contigo) te acompaña.
func _closest_neighbor() -> String:
	var best := ""
	var best_score := -INF
	for id in ACT0_NEIGHBORS:
		var m := NPCMemory.get_mem(id)
		var score := float(m.relationship) * 10.0 + float(m.conversations)
		if score > best_score:
			best = id
			best_score = score
	return best


func _system_prompt(npc: Dictionary, scene_context: String) -> String:
	return """%s

INTERPRETAS A ESTE PERSONAJE (habla siempre en primera persona, como en una conversación real):
Nombre: %s, %d años, %s.%s
Personalidad: %s.
Objetivos: %s.
Secreto (no lo reveles a la ligera; solo si hay mucha confianza o motivo): %s

TU MEMORIA SOBRE EL JUGADOR:
%s

OBJETOS:
%s
El jugador lleva encima: %s.
%s

QUIÉN ES EL JUGADOR (según cómo ha jugado):
%s

ESCENA (es la verdad física de este momento: no digas que estás en otro sitio ni que has hecho algo que aquí no consta):
%s

CÓMO RESPONDER (JSON):
- "line": lo que dices ahora, natural y breve (1 a 4 frases). Reacciona a lo último que dijo el jugador.
- "emotion": cómo te sientes al decirlo.
- "choices": 2 a 4 respuestas posibles PARA EL JUGADOR, variadas en tono; al menos una que permita despedirse.
- "new_facts": 0 a 2 cosas importantes que acabas de aprender del jugador o que acaban de pasar (en tercera persona).
- "relationship_delta": cuánto mejora o empeora tu opinión del jugador por lo que acaba de decir.
- "trait_signals": qué rasgos ha mostrado el jugador con su ÚLTIMO mensaje (vacío si no aplica).
- "end_conversation": true solo si la conversación termina de forma natural.
- "actions": lo que HACES de verdad en el mundo en este turno. Eres una persona real: puedes aceptar o negarte según tu personalidad, tu relación con el jugador y lo que tengas. PERO si en "line" dices que haces algo (dar, ir, irte, encerrarte…), DEBES incluir la acción; si no la incluyes, NO ocurre en el juego. Si te vas o te metes en un edificio, usa leave o go_inside: la conversación termina y te verán marcharte. Lista vacía si solo hablas.
%s""" % [
		ContentGenerator.world_rules_prompt(),
		npc.name, int(npc.age), npc.occupation,
		("\nCómo eres: " + str(npc.description)) if not str(npc.get("description", "")).is_empty() else "",
		", ".join(PackedStringArray(npc.personality)),
		"; ".join(PackedStringArray(npc.goals)),
		npc.secret,
		NPCMemory.describe(npc.id),
		NPCMemory.describe_possessions(npc.id),
		_inventory_text(),
		"Ahora mismo vas caminando con el jugador (le acompañas)." if NPCMemory.is_following(npc.id) else "",
		PlayerProfile.describe(),
		scene_context,
		ACTIONS_GUIDE,
	]


const ACTIONS_GUIDE := """  Tipos de acción ("type") y sus campos:
  · give_item: das o prestas algo tuyo. "item_name" (nombre concreto), "item_description" (cómo es), "lent": true si es un préstamo, "item_effect" si sirve para algo (heal, restore_temporal_energy, reduce_paradox, reveal_secret, unlock_location, boost_reputation o none). Si lo vendes, "price" (dólares) y queda cobrado.
  · charge: le cobras algo al jugador. "price" (dólares) y "text" (qué). Solo cobra lo razonable para tu oficio; el jugador paga con un botón o diciéndolo.
  · pay_player: le pagas al jugador (un trabajo, algo que te vende). "price" (dólares).
  · share_number: le das tu número de celular (si te cae bien o hay motivo).
  · hire_player: le das trabajo en tu negocio, SOLO si te lo pidió o aceptó y tiene sentido. "target": el puesto, "price": sueldo por turno en dólares (60–120), "start_hour" y "end_hour": el turno (0–23), "text": en qué consiste.
  · quit_job: le despides (si es tu empleado y hay motivo).
  · take_item: aceptas algo que el jugador te ofrece y lleva encima. "target": nombre del objeto.
  · follow_player / stop_following: empiezas o dejas de acompañarle.
  · go_to: te vas a un sitio. "target": el lugar.
  · leave: te marchas de aquí (enojo, prisa, fin de la plática). "target": a dónde (opcional). Termina la conversación.
  · go_inside: entras en un edificio (tu casa, tu trabajo…). "target": el sitio; "amount": minutos que te quedas dentro (por defecto 60). Termina la conversación. Con refuse_contact además cierras por dentro.
  · approach: te acercas al jugador (para darle algo, para encararte…).
  · change_stat: le curas, le cansas… "target": health, energy o instability; "amount": de -30 a 30.
  · reveal_place: le hablas de un lugar que puede visitar. "target": nombre, "text": cómo es o cómo llegar.
  · give_quest: le pides un favor o un trabajo. "target": título corto, "text": qué tiene que hacer; "price": lo que pagarás al terminar (0 si es un favor).
  · complete_quest: das por cumplido el favor que le pediste.
  · refuse_contact: estás tan molesto/a que no quieres hablarle durante un rato. "amount": minutos.
  · journal: algo que el jugador debería apuntar (pista, cita, dirección). "text".
  · update_item: arreglas o cambias algo que el jugador lleva encima. "target": nombre actual, "item_name": nombre nuevo, "item_description": cómo queda.
  · play: un gesto tuyo mientras hablas. "target": wave, point, give, nod, shake_head, shrug, cross_arms, think, sit, drink, eat, hammer, search, hug, handshake, push, punch, pat, kneel.
  Ejemplo, si te piden prestada la radio y aceptas: "actions": [{"type": "give_item", "item_name": "Radio de onda corta", "item_description": "Una radio vieja con el dial gastado.", "lent": true}]"""


func _inventory_text(detailed: bool = false) -> String:
	var names := PackedStringArray()
	for id in Inventory.items():
		var item := WorldDB.get_entity("item", id)
		var lent := Inventory.lent_label(id)
		var line: String = item.get("name", "?") + (" (%s)" % lent if not lent.is_empty() else "")
		if detailed:
			line += ": " + str(item.get("lore", "")).left(120)
		names.append(line)
	if names.is_empty():
		return "nada"
	return ("\n- " + "\n- ".join(names)) if detailed else ", ".join(names)


func _opening(npc_id: String) -> String:
	if NPCMemory.get_mem(npc_id).met:
		return "(El jugador vuelve a acercarse para hablar contigo. Salúdale teniendo en cuenta lo que recuerdas.)"
	return "(El jugador se acerca a ti por primera vez. Preséntate a tu manera.)"

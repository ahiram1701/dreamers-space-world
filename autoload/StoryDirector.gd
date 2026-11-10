extends Node
## Conversaciones con PNJs, turno a turno. La IA interpreta al PNJ y además "observa"
## al jugador: lo que el PNJ aprende va a NPCMemory y lo que revela el jugador, a PlayerProfile.
##
## Uso:  var t := await StoryDirector.talk("npc_marina", "¿Qué pasa con el faro?", "Acto 0, al atardecer")
##       t = { ok, source: "ai" | "fallback", line, emotion, choices: [{text, tone}], end_conversation }

signal turn_started(npc_id: String)
signal turn_finished(npc_id: String, turn: Dictionary)


## remote: por teléfono o mensaje (no se puede dar, irse ni empujar a nadie a distancia).
## npc_initiative: el mensaje lo empieza el PNJ (lo que se le pide no es algo que dijo el jugador).
const REMOTE_ACTIONS := ["share_number", "give_quest", "complete_quest", "journal", "reveal_place", "refuse_contact", "go_to"]


func talk(npc_id: String, player_input: String, scene_context: String, remote: bool = false, npc_initiative: bool = false) -> Dictionary:
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
	messages.append({"role": "user", "content": player_words(said) if not said.is_empty() else _opening(npc_id)})

	var res := await ContentGenerator.request_valid("dialogue_turn", messages)
	var turn: Dictionary = res.data if res.ok else _fallback_turn(npc, res.errors)
	turn["ok"] = true
	turn["source"] = "ai" if res.ok else "fallback"
	if res.ok:
		split_action(turn)
		var app: Dictionary = npc.get("appearance", {})
		var pl := PlayerLook.current() if WorldDB.is_loaded() else {}
		var dropped := strip_clothes(turn, app.get("layers", []), str(app.get("outfit", "casual")),
			PlayerLook.layers() if WorldDB.is_loaded() else [], str(pl.get("outfit", "casual")))
		if not dropped.is_empty():
			print_debug("[ropa] quitado de %s: %s" % [npc_id, dropped])
		make_consistent(turn)
	# Se presenta: a partir de ahora sabe su nombre. Si no lo sabe, no puede usarlo.
	var pname := PlayerProfile.player_name()
	var said_low := said.to_lower()
	if not npc_initiative and pname.length() >= 2 and (_has_word(said, pname, false) or said_low.contains("me llamo") or said_low.contains("mi nombre es")):
		NPCMemory.learn_name(npc_id)
	if res.ok and not NPCMemory.knows_name(npc_id):
		turn.line = strip_name(str(turn.line), pname)
	if res.ok:
		var fixed := check_places(str(turn.line), scene_context)
		if not fixed.dropped.is_empty() and not str(fixed.text).strip_edges().is_empty():
			print_debug("[sitios inventados] %s" % [fixed.dropped])
			turn.line = fixed.text
	# Lo que el PNJ hace (dar, acompañar, curar, irse…) ocurre de verdad, no solo se dice
	if remote:
		turn["actions"] = (turn.get("actions", []) as Array).filter(func(a): return str(a.get("type", "")) in REMOTE_ACTIONS)
	turn["notes"] = Actions.execute(npc_id, turn.get("actions", [])) if res.ok else []

	# Un respaldo no es algo que el PNJ haya "dicho": no ensucia su memoria (salvo presentarse)
	if res.ok or not NPCMemory.get_mem(npc_id).met:
		NPCMemory.record_turn(npc_id, "" if npc_initiative else said, turn.line, truthful_facts(turn.get("new_facts", [])), int(turn.relationship_delta))
	if not said.is_empty() and not npc_initiative:  # solo lo que el jugador dice o elige revela su carácter
		PlayerProfile.apply_signals(turn.get("trait_signals", []))
	turn_finished.emit(npc_id, turn)
	return turn


## Quita el nombre del jugador de una frase de alguien que no lo sabe («Hola, Ana, pasa» → «Hola, pasa»).
## ¿Aparece `word` como palabra entera? (con acentos: «José» al final sí cuenta; «Ana» en
## «mañana» no). Con case_sensitive, solo con su mayúscula (así «Luz» no borra «la luz del faro»).
static func _has_word(text: String, word: String, case_sensitive: bool = true) -> bool:
	if word.length() < 2:
		return false
	var flags := "" if case_sensitive else "(?i)"
	return RegEx.create_from_string(flags + "(?<![\\p{L}\\p{N}])" + _escape_re(word) + "(?![\\p{L}\\p{N}])").search(text) != null


static func strip_name(line: String, pname: String) -> String:
	if pname.length() < 2 or not _has_word(line, pname):
		return line
	var re := RegEx.create_from_string(",?\\s*(?<![\\p{L}\\p{N}])" + _escape_re(pname) + "(?![\\p{L}\\p{N}])")
	var out := re.sub(line, "", true)
	out = out.replace(" ,", ",").replace(",,", ",").replace(",.", ".").replace(",!", "!").replace(",?", "?").replace("¿,", "¿").replace("¡,", "¡")
	out = out.strip_edges().trim_prefix(",").strip_edges()
	return (out.substr(0, 1).to_upper() + out.substr(1)) if not out.is_empty() else line


static func _escape_re(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in ".^$*+?()[]{}|\\" else c
	return out


## Lo que el jugador escribe entre asteriscos es lo que HACE, no lo que dice: «*le doy un abrazo*».
static func player_words(said: String) -> String:
	var re := RegEx.create_from_string(r"\*([^*]{2,})\*")
	var out := re.sub(said, "(el jugador hace: $1)", true).strip_edges()
	return out


## Primera persona → tercera en las acotaciones que la IA mete en la frase («le doy un sorbo a mi
## café» → «le da un sorbo a su café»). Lo que no se sabe pasar se queda tal cual.
const FIRST_TO_THIRD := {"doy": "da", "miro": "mira", "tomo": "toma", "sonrío": "sonríe", "suspiro": "suspira",
	"levanto": "levanta", "señalo": "señala", "dejo": "deja", "pongo": "pone", "saco": "saca",
	"niego": "niega", "asiento": "asiente", "bebo": "bebe", "quedo": "queda", "acerco": "acerca", "río": "ríe",
	"encojo": "encoge", "giro": "gira", "vuelvo": "vuelve", "cojo": "coge", "agarro": "agarra", "aparto": "aparta",
	"cruzo": "cruza", "froto": "frota", "rasco": "rasca", "apoyo": "apoya", "sirvo": "sirve", "limpio": "limpia",
	"enciendo": "enciende", "apago": "apaga", "abro": "abre", "cierro": "cierra", "guardo": "guarda", "hago": "hace",
	"paso": "pasa", "echo": "echa", "muevo": "mueve", "inclino": "inclina", "golpeo": "golpea", "busco": "busca",
	"me": "se", "mi": "su", "mis": "sus", "conmigo": "consigo"}
static func _third_person(text: String) -> String:
	var out := PackedStringArray()
	for w in text.split(" "):
		var core := w.to_lower().rstrip(",.;:!?")
		if FIRST_TO_THIRD.has(core):
			var rep: String = FIRST_TO_THIRD[core]
			if w.substr(0, 1) != w.substr(0, 1).to_lower():
				rep = rep.capitalize()
			out.append(rep + w.substr(core.length()))
			continue
		out.append(w)
	return " ".join(out)


## Separa de la frase las acotaciones («*se ríe*», «—Le doy un sorbo al café—»): lo que dice va en
## "line" y lo que hace en "action", en tercera persona, para que no se lea como si te hablara a ti.
static func split_action(turn: Dictionary) -> void:
	var line := str(turn.get("line", ""))
	var found := PackedStringArray()
	var action := str(turn.get("action", "")).strip_edges()
	if not action.is_empty():
		found.append(action)
	for pattern in [r"\*([^*]{3,})\*", "—([^—]{6,})—", r"\(([^()]{6,})\)"]:
		var re := RegEx.create_from_string(pattern)
		for m in re.search_all(line):
			var inner := m.get_string(1).strip_edges().rstrip(".")
			# Un inciso de diálogo normal («—dice—») no es una acotación larga; estas sí lo son
			if inner.split(" ").size() >= 3:
				found.append(inner)
				line = line.replace(m.get_string(0), " ")
	line = line.replace("  ", " ").replace(". .", ".").replace(" .", ".").replace(" ,", ",").strip_edges()
	while line.begins_with("—") or line.begins_with("-"):
		line = line.substr(1).strip_edges()
	if line.length() < 1:
		line = "…"
	turn["line"] = line
	if found.is_empty():
		turn.erase("action")
		return
	var parts := PackedStringArray()
	for f in found:
		var t := _third_person(f).strip_edges()
		parts.append(t.substr(0, 1).to_upper() + t.substr(1))
	turn["action"] = ". ".join(parts) + "."


## Quita lo que contradice la ropa real: en la acotación, prendas que el PNJ no lleva («se ajusta
## el cuello del impermeable»); en lo que dice, prendas del jugador que no lleva («deja tu
## abrigo»). Devuelve las frases quitadas.
static func strip_clothes(turn: Dictionary, npc_layers: Array, npc_outfit: String, player_layers: Array, player_outfit: String) -> Array:
	var dropped := []
	var action := str(turn.get("action", ""))
	if not action.is_empty():
		var keep := PackedStringArray()
		for s in _sentences(action):
			var putting_on := ActionMapper.WEAR.any(func(w): return s.to_lower().contains(w))
			if putting_on or Wardrobe.mentions_missing(s, npc_layers, npc_outfit).is_empty():
				keep.append(s)
			else:
				dropped.append(s)
		if keep.is_empty():
			turn.erase("action")
		else:
			turn["action"] = " ".join(keep)
	var line := str(turn.get("line", ""))
	var keep_line := PackedStringArray()
	for s in _sentences(line):
		var low := " " + s.to_lower()
		var bad := false
		for id in Wardrobe.mentions_missing(s, player_layers, player_outfit):
			for n in Wardrobe.garment(id).names:
				if low.contains("tu " + str(n)) or low.contains("tus " + str(n)) or low.contains("ese " + str(n)) or low.contains("esa " + str(n)):
					bad = true
		if bad:
			dropped.append(s)
		else:
			keep_line.append(s)
	if not keep_line.is_empty() and keep_line.size() < _sentences(line).size():
		turn["line"] = " ".join(keep_line)
	return dropped


## Frases de un texto (cortando tras . ! ? …), con su puntuación.
static func _sentences(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for i in text.length():
		var ch := text[i]
		cur += ch
		if ch in [".", "!", "?", "…"] and (i + 1 >= text.length() or text[i + 1] == " "):
			if not cur.strip_edges().is_empty():
				out.append(cur.strip_edges())
			cur = ""
	if not cur.strip_edges().is_empty():
		out.append(cur.strip_edges())
	return out


## Frases en las que el PNJ dice que se va o se mete en algún sitio ("me voy a casa", "me encierro").
const LEAVE_WORDS := ["me voy", "me marcho", "me largo", "me piro", "me retiro", "me vuelvo a", "me vuelvo pa",
	"adiós, me", "hasta aquí", "nos vemos, me"]
const INSIDE_WORDS := ["me encierro", "me meto en", "me meto dentro", "entro en", "entro a", "me voy dentro",
	"me voy adentro", "cierro la puerta", "echo el pestillo", "echo la llave", "me meto a", "me encerraré", "voy dentro"]
## Hechos que afirman que alguien se movió: los escribe el motor cuando pasa de verdad, no la IA.
const MOVEMENT_FACT := ["entr", "encerr", "pestillo", "se fue", "se va ", "march", "irse", "largarse", "se larg", "salió", "sale de",
	"se dirig", "camin", "se metió", "se mete", "cerró la puerta", "dio la espalda y se"]
const LEAVING_TYPES := ["leave", "go_inside", "guide_player"]
const GUIDE_WORDS := ["te llevo", "le llevo", "sígueme", "sigueme", "vamos a ver a", "te acompaño a", "te acompaño con", "ven conmigo", "acompáñame"]
## Lo que sigue a «me voy…», «entro…» cuando NO es moverse («me voy a tomar un café contigo»,
## «me vuelvo a equivocar», «entro a trabajar a las 9», «no entro en detalles»).
const FIGURATIVE_AFTER := ["a tomar", "a decir", "a contar", "a explicar", "a equivocar", "a poner", "a ver si", "al grano",
	"a dormir contigo", "a trabajar", "en detalles", "en razón", "en materia", "en pánico", "en calor", "a hablar",
	"a preguntar", "a pensar", "a quedar", "a sentar", "a acordar", "a callar", "a tranquilizar", "contigo"]


## ¿Dice de verdad una de estas cosas? (no negada: «no me voy», «nunca entro»; ni en sentido figurado)
static func says_really(low: String, words: Array) -> bool:
	for w in words:
		var from := 0
		while true:
			var i := low.find(w, from)
			if i < 0:
				break
			from = i + 1
			var before := low.substr(maxi(0, i - 14), mini(i, 14))
			if [" no ", "nunca ", "jamás ", "jamas ", " ni "].any(func(n): return (" " + before).contains(n)):
				continue
			var after := low.substr(i + w.length(), 22).strip_edges()
			# («entro a» + «trabajar»: la «a» ya va en la palabra buscada)
			if FIGURATIVE_AFTER.any(func(f): return after.begins_with(f) or (f.begins_with("a ") and after.begins_with(f.substr(2)))):
				continue
			return true
	return false


## Lo que el PNJ dice que hace, lo hace: si anuncia que se va o se encierra y no trae la acción,
## se añade. Si se va (o no quiere hablar), la conversación termina.
static func make_consistent(turn: Dictionary) -> void:
	var actions: Array = turn.get("actions", [])
	var types: Array = actions.map(func(a): return a.get("type", ""))
	var low := " " + str(turn.get("line", "")).to_lower()
	# «Te llevo», «sígueme», «vamos con…»: lo dice, así que lo hace (antes, sin su acción, no pasaba nada)
	if not types.any(func(t): return t in LEAVING_TYPES) and says_really(low, GUIDE_WORDS):
		var where := ""
		for marker in [" con ", " a la ", " al ", " a ver a ", " hasta "]:
			var i := low.find(marker, low.find(GUIDE_WORDS.filter(func(w): return low.contains(w))[0]))
			if i >= 0:
				where = low.substr(i + 1).get_slice(".", 0).get_slice(",", 0).get_slice("!", 0).strip_edges()
				break
		if not where.is_empty():
			var g := {"type": "guide_player", "target": where}
			actions.append(g)
			types.append(g.type)
	if not types.any(func(t): return t in LEAVING_TYPES):
		var inside := says_really(low, INSIDE_WORDS)
		var leave := inside or says_really(low, LEAVE_WORDS)
		if leave:
			var a := {"type": "go_inside" if inside else "leave", "target": _place_in(low)}
			actions.append(a)
			types.append(a.type)
	# Un favor que pide en voz alta queda apuntado aunque se le olvide la acción give_quest
	var said: String = str(turn.get("line", ""))
	if not "give_quest" in types and says_really(low, REQUEST_WORDS) and not turn.get("location_quest_offer", false):
		var sentence := _sentence_with(said, REQUEST_WORDS)
		if not sentence.is_empty():
			var q := {"type": "give_quest", "target": ContentValidator.fit_text(sentence.trim_prefix("¿").trim_suffix("?"), 60), "text": sentence}
			if ["tráeme", "traeme", "me traes", "me traerías", "me consigues", "consígueme", "consigueme", "me puedes traer", "llévale"].any(func(w): return low.contains(w)):
				q["quest_kind"] = "bring_item"
			actions.append(q)
			types.append("give_quest")
	# La hora que dijo («a las 3 de la mañana») va en el encargo aunque la IA no la pusiera, pero
	# solo si la dice en la MISMA frase que el pedido (no «tráeme pan; la panadería abre a las 7»)
	for a in actions:
		if a.get("type", "") == "give_quest" and a.get("at_hour") == null:
			var at := parse_at_hour(str(a.get("text", "")).to_lower())
			if at >= 0.0:
				a["at_hour"] = at
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


## La frase de `text` que contiene alguna de `words` (o "").
static func _sentence_with(text: String, words: Array) -> String:
	var low := text.to_lower()
	for w in words:
		var i := low.find(w)
		if i < 0:
			continue
		var start := 0
		for mark in [". ", "! ", "? ", "\n"]:
			var j := low.rfind(mark, i)
			if j >= 0:
				start = maxi(start, j + mark.length())
		var end := text.length()
		for mark in [".", "!", "?", "\n"]:
			var j := text.find(mark, i)
			if j >= 0:
				end = mini(end, j + 1)
		return text.substr(start, end - start).strip_edges()
	return ""


## «a las 3 de la mañana» → 3.0, «a las 5:30 p. m.» → 17.5, «a las 3» → la próxima 3 (de
## madrugada o de tarde, la que llegue antes). -1 si no dice hora.
const HOUR_WORDS := {"una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
	"nueve": 9, "diez": 10, "once": 11, "doce": 12}


## Devuelve la hora (3.0 = 3 a. m.); si dice «mañana» (el día, no «de la mañana»), +24.
static func parse_at_hour(low: String) -> float:
	var text := low
	for word in HOUR_WORDS:  # «a las tres y media» → «a las 3:30»
		text = text.replace("a las " + word, "a las %d" % HOUR_WORDS[word]).replace("a la " + word, "a la %d" % HOUR_WORDS[word])
	text = text.replace(" y media", ":30").replace(" y cuarto", ":15").replace(" menos cuarto", ":-15")
	var re := RegEx.create_from_string("a las? (\\d{1,2})(?:[:.](-?\\d{2}))?\\s*(a\\. ?m\\.|am|p\\. ?m\\.|pm|de la mañana|de la madrugada|de la tarde|de la noche|del mediodía)?")
	var m := re.search(text)
	if m == null:
		return -1.0
	var h := float(m.get_string(1))
	if h > 24.0:
		return -1.0
	var mins := float(m.get_string(2)) if not m.get_string(2).is_empty() else 0.0
	if mins < 0.0:
		h -= 1.0
		mins += 60.0
	var suffix := m.get_string(3)
	var tomorrow := RegEx.create_from_string("(^|[^a-záéíóú])mañana(?! *(a\\. ?m|am))").search(text.replace("de la mañana", "")) != null
	if suffix.contains("noche") and h == 12.0:
		h = 0.0  # las 12 de la noche son las 0:00
	elif suffix.begins_with("p") or suffix.contains("tarde") or suffix.contains("noche"):
		if h < 12.0:
			h += 12.0
	elif suffix.begins_with("a") or suffix.contains("mañana") or suffix.contains("madrugada"):
		if h == 12.0:
			h = 0.0
	elif suffix.is_empty() and h <= 12.0:
		var now := WorldClock.hour()
		var am := fposmod(h - now, 24.0)
		var pm := fposmod(h + 12.0 - now, 24.0)
		if pm < am:
			h += 12.0
	return fmod(h + mins / 60.0, 24.0) + (24.0 if tomorrow else 0.0)


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


## Pedidos en voz alta: si el PNJ los dice, el encargo queda apuntado.
const REQUEST_WORDS := ["tráeme", "traeme", "¿me traes", "¿me traerías", "¿me consigues", "consígueme", "consigueme",
	"¿me puedes traer", "¿me puedes conseguir", "necesito que me traigas", "necesito que me consigas",
	"necesito que vayas", "llévale", "te encargo", "encuéntrame"]

## Pasos que tienen sentido en una acción del jugador (tecla F).
const WORLD_STEPS := ["go_to", "play", "use", "npc_react", "give_to_npc", "give_item", "change_stat", "journal",
	"reveal_place", "update_item", "remove_item", "place_object", "affect_nearby", "change_need", "pay", "earn",
	"spawn_npc", "create_place", "sleep", "wait", "climb", "move_to", "force_door", "travel", "ride", "land",
	"interact", "drive_to", "buy", "call", "swim_to", "learn", "share_number", "take_item", "get_out"]
const MAX_FINDS_PER_PLACE := 6  # rebuscar sin parar no llena el inventario (fabricar no cuenta)
const MAX_ACTION_MINUTES := 240
## Si la narración cuenta esto, tiene que haber un paso de este tipo (si no, se pide otra vez).
const REQUIRED_STEPS := [
	[["talas", "derribas", "cae el árbol", "el árbol cae", "cortas el árbol"], "affect_nearby"],
	[["construyes", "levantas una", "montas una", "fabricas una balsa", "terminas la balsa", "terminas el"], "place_object"],
	[["golpeas", "le pegas", "puñetazo", "empujas a", "abrazas", "le das la mano", "le das una palmada", "patada"], "npc_react"],
	[["reparas", "arreglas", "queda arreglad", "queda reparad"], "update_item"],
	[["le das ", "le entregas", "le regalas"], "give_to_npc"],
	[["te sientas", "te tumbas", "te acuestas", "subes a la barca", "subes al bote"], "use"],
	[["trepas", "subes al techo", "subes a la azotea", "llegas al techo", "estás en el techo"], "climb"],
	[["fuerzas la puerta", "haces palanca", "te cuelas por"], "force_door"],
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
- Si el jugador quiere hacer algo físicamente posible, busca CÓMO con estos pasos (interact sirve para casi cualquier cosa que haya cerca). No lo niegues por falta de un paso exacto.
- La gente está donde dice "LA GENTE DE CERCA" y lleva en las manos SOLO lo que dice ahí. No le pongas a nadie una escoba, un trapo, una taza ni nada que no lleve, ni la sitúes en otro sitio. Los vehículos que existen son los de "VEHÍCULOS CERCA"; nada más.

"narration": resumen breve (1 a 3 frases, segunda persona).
"steps": lista ordenada (máximo 8). Cada paso: "type", sus campos y "narration" (una frase corta de ese momento).
- go_to: caminar hasta algo. "target": id (npc:..., tree_..., door:..., seat:1, water…).
- play: gesto del personaje. "target": chop, hammer, dig, pick_up, search, crouch, sit, sleep, drink, eat, wave, point, give, fish, swim, dance, think, punch, push, kick, hug, handshake, throw, pat, kneel, write, read, listen, call.
- use: usar algo (sentarse en seat, dormir en bed, entrar o TOCAR en door —en casa ajena se toca y abre quien esté—, subir a boat). "target": id.
- climb: subir al techo de un edificio o bajar de él. "target": "roof:<id de la puerta>" (p. ej. "roof:casa_2"; tu casa: "roof:home") o "down" para bajar. Sin escalera solo se trepa hasta ~7 m.
- move_to: subirse encima de algo cercano (una banca, una mesa, una roca) o ponerse en un sitio. "target": id; "on": true para quedar encima.
- force_door: forzar una puerta cerrada o, de noche, colarse por una ventana. "target": "door:<id>"; "window": true si es por la ventana. Hace ruido: los de dentro o quien pase pueden oírte, y luego todos lo sabrán.
- npc_react: cómo reacciona una persona. "target": su id (npc:...); "emotion": angry, scared, happy, sad, worried, curious, amused o neutral; "gesture" (de la lista); "behavior": stay, flee, approach, follow, go_inside, fight_back, leave, guide (te lleva a un sitio: pon el sitio en "item_name"), ride (se sube a tu vehículo); "line": lo que suelta (corto); "amount": cuánto cambia su opinión del jugador (-30 a 30); "text": lo que recordará, desde su punto de vista ("El jugador te dio un puñetazo en el muelle sin motivo").
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
- sleep: dormir. "until_hour": hora a la que se despierta (0–24; 3.5 = 3:30, 15 = 3 de la tarde) o "hours": cuántas horas. "target": "home" si va a dormir a su casa (el juego le lleva, entra y se acuesta en su cama), "bed" para la cama más cercana; "floor": true SOLO si quiere dormir en el suelo. Hace pasar el tiempo él solo ("minutes": 0).
- travel: ir a otro lugar. "target": "location:<id>" de "OTROS LUGARES A LOS QUE PUEDE VIAJAR" (va en su nave o con el Ancla) o el nombre de un sitio de "SITIOS DE ESTE LUGAR" aunque esté lejos ("regreso al pueblo" = "pueblo"/la plaza).
- interact: usar cualquier COSA de la lista (thing:N, object:N…): encender o apagar (la tele, una lámpara), abrir, mirar, tocar, sentarse… "target": id; "verb": turn_on, turn_off, open, close, use o look.
- drive_to: ir en vehículo a un sitio (sube a tu coche o a uno cercano, conduce y gasta gasolina). "target": un sitio de este lugar.
- buy: comprar algo de verdad en un local de aquí (con su precio y su horario). "item_name": lo que compra.
- call: llamar por teléfono a alguien que conoce. "target": npc:id.
- swim_to: nadar hasta un sitio con agua (la isla, el muelle). "target": el sitio.
- learn: aprender algo de alguien o practicando ("Teo me enseña a hacer café"). "item_name": la habilidad; "target": npc:id si se lo enseña alguien.
- land: (solo en el espacio, en la nave) aterrizar. "target": el nombre del planeta o la estación; la nave va sola hasta allí si está lejos.
- ride: una persona se sube al vehículo del jugador (o al más cercano). "target": su id (npc:...). Úsalo cuando el jugador le pide que suba y ella acepta.
- wait: esperar sin dormir (hasta una hora o unas horas), mismos campos. Hace pasar el tiempo él solo ("minutes": 0).
"minutes": cuánto tarda de verdad (talar ~30, construir una balsa ~180, buscar ~10, un golpe ~1, comer ~20, ducharse ~15).
Ejemplo, "subo al techo de mi casa": "steps": [{"type": "climb", "target": "roof:home", "narration": "Trepas por la reja y el alféizar hasta el techo."}], "minutes": 2
Ejemplo, "duermo hasta las 3:30 am": "steps": [{"type": "sleep", "until_hour": 3.5, "narration": "Te acomodas y cierras los ojos."}], "minutes": 0

CREAR E INVENTAR: se puede crear casi cualquier cosa, pero como en la vida real: hacen falta conocimientos, materiales (que se gastan con remove_item), herramientas y tiempo acordes a la época y al lugar. Si falta algo, sale peor o no sale, y se cuenta qué faltó. La ciencia ficción está permitida si se apoya en algo que existe en este mundo (el Ancla, tecnología de otro mundo o época, materiales anómalos), siempre con física creíble y nunca magia.

Realismo: el cuerpo del jugador, su dinero, la hora, el día y el tiempo importan (de noche está todo cerrado, con lluvia la gente se resguarda, sin dinero no se compra). Crea gente o sitios solo si lo que hace el jugador lo pide y es creíble; usa lo que ya existe antes que inventar.

Ejemplo, "le pego a Teo" con Teo a 6 m: "steps": [{"type": "go_to", "target": "npc:npc_teo", "narration": "Vas directo hacia Teo."}, {"type": "play", "target": "punch", "narration": "Le das un puñetazo en el hombro."}, {"type": "npc_react", "target": "npc:npc_teo", "emotion": "angry", "gesture": "cross_arms", "behavior": "go_inside", "line": "¡¿Pero tú de qué vas?!", "amount": -25, "text": "El jugador te dio un puñetazo sin motivo.", "narration": "Teo retrocede, furioso, y se marcha a la cafetería."}], "minutes": 2
Ejemplo, "talo el árbol de al lado" llevando un hacha: [{"type": "go_to", "target": "tree_12_-4"}, {"type": "play", "target": "chop", "narration": "Golpeas el tronco una y otra vez."}, {"type": "affect_nearby", "target": "tree_12_-4", "narration": "El árbol cruje y cae."}, {"type": "give_item", "item_name": "Troncos de pino", "item_description": "Cuatro troncos recién cortados."}], "minutes": 40"""


## Lo que la escena sabe de la gente cercana ({name, held, place}) y de sus sitios: para quitar de
## la narración lo que la IA se invente (una escoba que nadie lleva, alguien donde no está).
var people_facts: Callable
var place_names: Callable

## Objetos de mano que la IA suele inventar: nombre -> palabras.
const PROPS := {"escoba": ["escoba"], "trapo": ["trapo", "paño", "bayeta"], "taza": ["taza", "tazón"], "libro": ["libro"],
	"bandeja": ["bandeja"], "celular": ["celular", "teléfono", "móvil"], "periódico": ["periódico"], "paraguas": ["paraguas"],
	"cigarro": ["cigarro", "cigarrillo"], "llave inglesa": ["llave inglesa"], "martillo": ["martillo"], "destornillador": ["destornillador"],
	"herramientas": ["caja de herramientas"], "caña": ["caña de pescar"], "red": ["red de pesca"], "botella": ["botella"], "vaso": ["vaso"],
	"cubo": ["cubo", "balde", "cubeta"], "cesta": ["cesta", "canasta"], "bolsa": ["bolsa"], "linterna": ["linterna"], "guitarra": ["guitarra"],
	"mapa": ["mapa"], "cuaderno": ["cuaderno", "libreta"], "pluma": ["pluma", "bolígrafo", "lápiz"], "radio": ["radio portátil"], "cuchillo": ["cuchillo"]}
## Señales de que la frase dice que alguien lo tiene o lo usa.
const HOLD_HINTS := ["con su ", "con una ", "con un ", "en la mano", "en las manos", "sostiene", "sujeta", "lleva ", "agarra", "aprieta",
	"deja ", "apoya", "levanta", "guarda", "barre", "limpia con", "seca con", "hojea", "bebe de", "sorbe", "blande", "agita", "sacude", "se lleva", "saca "]


## Quita de un texto las frases que contradicen lo que hay: una persona con un objeto que no lleva,
## o en un sitio donde no está. people: [{name, held, place}]; places: nombres de sitios.
## Devuelve {text, dropped: [frases]}.
static func check_world_claims(text: String, people: Array, places: Array = []) -> Dictionary:
	var kept := PackedStringArray()
	var dropped := []
	for sentence in _sentences(text):
		var low := " " + sentence.to_lower() + " "
		var bad := false
		for p in people:
			var nm := str(p.get("name", ""))
			if nm.length() < 3 or not low.contains(nm):
				continue
			var held := str(p.get("held", ""))
			for key in PROPS:
				if held.contains(key):
					continue
				if PROPS[key].any(func(w): return low.contains(w)) and HOLD_HINTS.any(func(h): return low.contains(h)):
					bad = true
			var at := str(p.get("place", ""))
			for pl in places:
				var name := str(pl)
				if name.length() < 4 or at.contains(name):
					continue
				for pre in [" en el ", " en la ", " está en ", " desde el ", " desde la "]:
					if low.contains(pre + name + " ") or low.contains(pre + name + ","):
						bad = true
		if bad:
			dropped.append(sentence)
		else:
			kept.append(sentence)
	return {"text": " ".join(kept), "dropped": dropped}


## Partes de un edificio que la IA tiende a inventar («bajas al cuarto de aparejos»).
const ROOM_WORDS := ["cuarto de", "sótano", "sotano", "laboratorio", "pasadizo", "túnel", "tunel", "bodega",
	"trastienda", "ático", "desván", "desvan", "cámara secreta", "habitación secreta", "pasaje secreto",
	"búnker", "bunker", "subterráneo", "subterraneo", "cripta", "trampilla del suelo"]


## Quita las frases que llevan al jugador (o hablan de) sitios que no existen: un cuarto, un
## sótano, un laboratorio… que no aparecen en `known` (lo que de verdad hay: nombres y
## descripciones de la escena). Devuelve {text, dropped: [frases]}.
static func check_places(text: String, known: String) -> Dictionary:
	var known_low := known.to_lower()
	var kept := PackedStringArray()
	var dropped := []
	for sentence in _sentences(text):
		var low := sentence.to_lower()
		var plain := low
		for f in ["cuarto de hora", "cuarto de siglo", "cuarto de kilo", "cuarto de litro", "cuarto de vuelta", "cuarto de luna"]:
			plain = plain.replace(f, "")
		var bad := ROOM_WORDS.any(func(w): return plain.contains(w) and not known_low.contains(w))
		if bad:
			dropped.append(sentence)
		else:
			kept.append(sentence)
	return {"text": " ".join(kept), "dropped": dropped}


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
	# Lo que contradice lo que hay (una escoba que nadie lleva, alguien donde no está) no se cuenta
	if people_facts.is_valid():
		var people: Array = people_facts.call()
		var places: Array = place_names.call() if place_names.is_valid() else []
		var c := check_world_claims(str(data.narration), people, places)
		if not c.dropped.is_empty():
			print_debug("[inventado] quitado de la narración: %s" % [c.dropped])
			data["narration"] = c.text if not str(c.text).strip_edges().is_empty() else "Lo intentas."
		for s in data.get("steps", []):
			if s is Dictionary and s.has("narration"):
				var cs := check_world_claims(str(s.narration), people, places)
				s["narration"] = cs.text
	# Ni cuartos ni sótanos que no existen
	var cp := check_places(str(data.narration), scene_context)
	if not cp.dropped.is_empty() and not str(cp.text).strip_edges().is_empty():
		data["narration"] = cp.text
	var steps := plan_steps(data)
	if steps.is_empty() and data.has("_dropped"):  # usó pasos que no existen: una vez más, con la lista buena
		messages.append({"role": "assistant", "content": JSON.stringify(data)})
		messages.append({"role": "user", "content": "Esos pasos no existen (%s). Usa solo estos tipos: %s. Devuelve el JSON completo otra vez." % [", ".join(PackedStringArray(data._dropped)), ", ".join(PackedStringArray(WORLD_STEPS))]})
		var again2 := await ContentGenerator.request_valid("world_action", messages)
		if again2.ok:
			data = again2.data
			steps = plan_steps(data)
	var passes_time := steps.any(func(s): return s.get("type", "") in ["sleep", "wait"])  # el paso ya mueve el reloj
	return {"ok": true, "narration": data.narration, "steps": steps, "error": "",
		"minutes": 0 if passes_time else clampi(int(data.get("minutes", 5)), 0, MAX_ACTION_MINUTES)}


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
	var dropped := []
	for a in raw:
		if not (a.get("type", "") in WORLD_STEPS):
			dropped.append(str(a.get("type", "?")))
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
	if not dropped.is_empty():
		print_debug("[F] pasos desconocidos quitados: %s" % [dropped])
		data["_dropped"] = dropped
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
const ORIGIN_GUIDE := """LA HISTORIA (es la misma para todos; tú la cuentas para ESTE jugador):
- Junto a la puerta del faro hay una grieta en el aire, natural y diminuta; la lente del faro la amplifica cada noche a las 3:33. Esta noche se abre del todo y arrastra al jugador lejos de casa, a otro mundo.
- Lo que le queda es su Ancla: una brújula de bolsillo hecha con algo del pueblo ("base"), que siempre apunta a casa. Pero le falta fuerza para un salto tan largo: tendrá que volver tramo a tramo, con ayuda de la gente que encuentre.
- Si un vecino está con él, le agarra la mano en el último segundo ("companion_line": lo que le grita).
- TODO pasa FUERA, delante de la puerta del faro: no entra, no hay sótanos, cuartos, laboratorios ni pasadizos. Nada de jerga (cuántico, coherencia, espacio-tiempo, frecuencia).
TOMAS QUE EXISTEN ("shot"): lighthouse (el faro entero, de noche), lamp (la lámpara de arriba, que se enciende sola), door (la puerta del faro y tú delante), crack (la grieta en el aire junto a la puerta), breach (la grieta abierta, enorme, tirando de todo), sea (el mar, quieto, como congelado), sky (el cielo), town (las luces del pueblo a lo lejos), player (tu cara, de cerca), companion (el vecino que corre hacia ti), watch (la brújula en tu mano)."""


## Pide a la IA el Despertar de ESTE jugador. Siempre devuelve uno válido (IA o respaldo).
## Frase de respaldo de cada toma, por si la de la IA no casa con lo que se ve.
const NEUTRAL_BEATS := {
	"lighthouse": "Son las 3:33. La lámpara del faro, apagada desde hace años, parpadea sola.",
	"lamp": "Arriba, la luz gira sin corriente.",
	"sea": "El mar se aplana de golpe. Ya no se oyen las olas.",
	"crack": "Junto a la puerta, el aire se dobla: una grieta del tamaño de una moneda.",
	"breach": "La grieta se abre y tira de todo. Te agachas para no caer.",
	"companion": "Alguien corre hacia ti.",
	"watch": "En tu mano, la brújula gira y se queda apuntando al pueblo.",
	"pier": "Las tablas del muelle crujen bajo tus pies.",
	"town": "En el pueblo se enciende una ventana.",
	"neighbor": "Alguien baja la calle y te reconoce.",
	"player": "Respiras hondo.",
	"sky": "Arriba, las estrellas de siempre.",
	"door": "La puerta del faro, cerrada, como siempre.",
}


## El vecino que vendría a por ti: el que más te aprecia.
func awakening_friend() -> String:
	return _closest_neighbor()


## Alinea lo que escribió la IA con las tomas decididas por el motor: una frase por toma, en
## ese orden; lo que la IA añada de más se descarta, y lo que falte se cubre con la frase neutra.
static func align_beats(ai_beats: Array, plan: Array) -> Array:
	var out := []
	var used := {}
	for i in plan.size():
		var shot := str(plan[i].shot)
		var line := ""
		for j in ai_beats.size():
			if not used.has(j) and str(ai_beats[j].get("shot", "")) == shot:
				line = str(ai_beats[j].get("line", ""))
				used[j] = true
				break
		if line.strip_edges().is_empty():
			line = str(NEUTRAL_BEATS.get(shot, ""))
		out.append({"shot": shot, "line": line})
	return out


func generate_awakening(plan: Array = []) -> Dictionary:
	var neighbors := PackedStringArray()
	for id in ACT0_NEIGHBORS:
		var npc := WorldDB.get_entity("npc", id)
		if not npc.is_empty():
			neighbors.append("%s (%s): %s" % [npc.name, npc.occupation, NPCMemory.describe(id)])
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEres el guionista de EL DESPERTAR, una escena de cine corta: el momento en que la brecha arrastra al jugador lejos de casa. Segunda persona, frases cortas y concretas: qué se ve, qué se oye, qué hace. Que se entienda a la primera."},
		{"role": "user", "content": """Son las 3:33 de la madrugada. El jugador está fuera, delante de la puerta del faro.

QUIÉN ES EL JUGADOR: %s

LO QUE RECUERDA CADA VECINO DE ÉL:
%s

EL FARO (lo único que hay): %s

%s

LAS TOMAS DE LA ESCENA (ya decididas: esto es lo que se VERÁ, en este orden):
%s

Escribe:
- "beats": EXACTAMENTE una por cada toma de arriba, en el mismo orden y con el mismo "shot", con "line" (una o dos frases, máx. 130 caracteres) que cuente SOLO lo que se ve en esa toma. No añadas personas, objetos ni sucesos que no estén en su descripción.
- "anchor": la brújula que te queda; "name" corto y "description" de 1-2 frases (de qué está hecha y qué hace: apunta a casa); "base" es el objeto del pueblo del que sale.
- "companion_line": lo que te grita %s al agarrarte la mano (si no viene nadie, déjalo vacío).
- "canon_facts": 2-3 hechos que serán verdad para siempre.
- "destination_hint": a qué tipo de lugar te arrastra la brecha.""" % [
			PlayerProfile.describe(), "\n".join(neighbors), InteriorBuilder.DESCRIPTIONS.get("lighthouse", ""), ORIGIN_GUIDE,
			_plan_text(plan), _friend_name(plan)]},
	]
	var res := await ContentGenerator.request_valid("awakening", messages)
	var data: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("awakening")
	data["source"] = "ai" if res.ok else "fallback"
	_clean_beats(data)
	if not plan.is_empty():
		data["beats"] = align_beats(data.beats, plan)
	# La decisión es concreta y sale de lo que se ve: agarrar o no la mano de quien llegó corriendo.
	# Si nadie vino (no hay toma del vecino), no hay a quién agarrar.
	var comes := plan.is_empty() or plan.any(func(p): return p.shot == "companion")
	var friend := _closest_neighbor() if comes else ""
	var first := str(WorldDB.get_entity("npc", friend).get("name", "")).get_slice(" ", 0)
	data["companion"] = friend
	data["choices"] = [
		{"text": "Agarrar la mano de %s" % first, "consequence": "jump_with_companion"},
		{"text": "Soltarte: que %s no se arriesgue por ti" % first, "consequence": "jump_alone"},
	] if not first.is_empty() else [{"text": "Dejarte llevar", "consequence": "jump_alone"}]
	data["narration"] = "\n".join(PackedStringArray(data.beats.map(func(b): return str(b.line))))
	if not res.ok:
		push_warning("El Despertar usó respaldo: %s" % [res.errors])
	return data


static func _plan_text(plan: Array) -> String:
	if plan.is_empty():
		return "(elige tú: lighthouse, lamp, sea, crack, breach, watch)"
	var lines := PackedStringArray()
	for i in plan.size():
		lines.append("%d. shot \"%s\": %s" % [i + 1, plan[i].shot, plan[i].does])
	return "\n".join(lines)


func _friend_name(plan: Array) -> String:
	if not plan.is_empty() and not plan.any(func(p): return p.shot == "companion"):
		return "nadie"
	return str(WorldDB.get_entity("npc", _closest_neighbor()).get("name", "el vecino")).get_slice(" ", 0)


## Quita de una escena las frases que hablan de sitios que no existen (cuartos, sótanos…).
func _clean_beats(data: Dictionary) -> void:
	var known: String = InteriorBuilder.DESCRIPTIONS.get("lighthouse", "") + " faro puerta lámpara galería mar muelle pueblo"
	var keep := []
	for b in data.get("beats", []):
		var c := check_places(str(b.get("line", "")), known)
		if not str(c.text).strip_edges().is_empty():
			b["line"] = c.text
			keep.append(b)
	data["beats"] = keep


## Aplica la decisión: canon, Ancla, compañero, stats y raíz del árbol temporal.
## No salta: eso lo hace Travel.jump_new() justo después.
func apply_awakening(data: Dictionary, choice_index: int) -> Dictionary:
	var choice: Dictionary = data.choices[clampi(choice_index, 0, data.choices.size() - 1)]
	var consequence: String = choice.consequence
	var companion := str(data.get("companion", _closest_neighbor())) if consequence == "jump_with_companion" else ""
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
func generate_finale(plan: Array = []) -> Dictionary:
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
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEres el guionista del FINAL: la vuelta a casa, una escena de cine corta. Segunda persona, frases cortas y concretas, emoción contenida. Coherencia total con el canon."},
		{"role": "user", "content": """Después de muchos saltos, la brújula del jugador por fin tiene fuerza para el último: vuelve a Bahía de las Horas, al muelle, de madrugada, junto al faro.

Origen de su Ancla: %s (%s)
Decisión en El Despertar: %s
Compañero: %s
Lugares recorridos: %s
Misiones completadas: %s
Quién es: %s

Escribe:
- "beats": EXACTAMENTE una por cada toma de esta lista (ya decidida: es lo que se VERÁ), en el mismo orden y con el mismo "shot", con "line" (máx. 130 caracteres) que cuente SOLO lo que se ve en esa toma; puedes recordar en pensamiento a dos o tres personas que te ayudaron:
%s
- "choices": exactamente tres, una por final, con "text" corto (máx. 90 caracteres): stay_home (quedarte en casa para siempre), go_back_for_someone (volver a por alguien que te ayudó y traerle o quedarte con él), keep_traveling (guardar la brújula y seguir viajando, ahora por gusto). Cada una con su "epilogue": cómo termina, nombrando a la gente y los sitios de su viaje.""" % [
			awakening.get("origin", "?"), awakening.get("title", ""), awakening.get("choice", "?"),
			companion.get("name", "nadie"), ", ".join(places), ", ".join(quests), PlayerProfile.describe(), _plan_text(plan)]},
	]
	var res := await ContentGenerator.request_valid("finale", messages)
	var data: Dictionary = res.data if res.ok else ContentGenerator.load_fallback("finale")
	data["source"] = "ai" if res.ok else "fallback"
	_clean_beats(data)
	if not plan.is_empty():
		data["beats"] = align_beats(data.beats, plan)
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
Nombre: %s. Eres %s, %d años, %s.%s
TU ROPA AHORA MISMO (es lo que llevas de verdad; no menciones, toques ni te ajustes ninguna otra prenda): %s.
Personalidad: %s.
Objetivos: %s.
Secreto (no lo reveles a la ligera; solo si hay mucha confianza o motivo): %s

TU MEMORIA SOBRE EL JUGADOR:
%s

ENCARGOS QUE LE HAS HECHO AL JUGADOR (recuérdalos; si ya cumplió uno pendiente, usa complete_quest):
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
- "line": SOLO lo que dices en voz alta, natural y breve (1 a 4 frases), sin acotaciones (nada de *…*, —…— ni paréntesis). Reacciona a lo último que dijo el jugador. Lo que el jugador pone entre paréntesis como «el jugador hace: …» es lo que HACE, no lo que dice.
- "action" (opcional): lo que haces mientras hablas, en TERCERA persona y breve, como una acotación de teatro («Da un sorbo al café y mira hacia el faro»). Nunca en primera persona ni dirigido al jugador. Tu cuerpo LO HACE DE VERDAD en el juego, así que solo cosas que se puedan ver: un gesto (asiente, niega con la cabeza, se encoge de hombros, cruza los brazos, bebe, come, señala, saluda, bosteza, se rasca la barbilla, limpia, cocina, escribe, lee, mira el celular, abraza, da la mano, da una palmada, se agacha, se sienta si hay asiento), una cara (sonríe, se ríe, frunce el ceño, suspira), mirar hacia algo o alguien que exista aquí, dar unos pasos hacia algo de A TU ALREDEDOR, o ponerte o quitarte una prenda. Lo demás no se mostrará.
- NO INVENTES: ni prendas u objetos que el jugador no lleva (mira cómo le ves), ni prendas tuyas que no estén en TU ROPA, ni cosas del entorno (toldos, bancas, fuentes, puestos, coches…) que no estén en A TU ALREDEDOR, ni puertas, pasadizos, cuartos o partes de un sitio que no estén en su descripción, ni gente que no esté en GENTE DEL LUGAR o en tu memoria. Si no lo sabes, no lo afirmes.
- "emotion": cómo te sientes al decirlo.
- "choices": 2 a 4 respuestas posibles PARA EL JUGADOR, variadas en tono; al menos una que permita despedirse.
- "new_facts": 0 a 2 cosas importantes que acabas de aprender del jugador o que acaban de pasar (en tercera persona). Incluye lo que el jugador afirma de sí mismo (p. ej. «El jugador dice que no notó nada raro»).
- LO QUE EL JUGADOR VIO, OYÓ O SINTIÓ: solo lo que conste en tu memoria o lo que él/ella te diga. Si te dice que no notó nada, que está bien o que no sabe, créetelo y responde en consecuencia: no hables como si lo hubiera vivido («si te vuelve a pasar…»). Tus preguntas no son hechos.
- RUMORES: lo que otros te contaron no lo viviste tú; en esas frases, «tú/te» es quien te lo contó.
- "relationship_delta": cuánto mejora o empeora tu opinión del jugador por lo que acaba de decir.
- "trait_signals": qué rasgos ha mostrado el jugador con su ÚLTIMO mensaje (vacío si no aplica).
- "end_conversation": true solo si la conversación termina de forma natural.
- "actions": lo que HACES de verdad en el mundo en este turno. Eres una persona real: puedes aceptar o negarte según tu personalidad, tu relación con el jugador y lo que tengas. PERO si en "line" dices que haces algo (dar, ir, irte, encerrarte…), DEBES incluir la acción; si no la incluyes, NO ocurre en el juego. Si te vas o te metes en un edificio, usa leave o go_inside: la conversación termina y te verán marcharte. Lista vacía si solo hablas.
%s""" % [
		ContentGenerator.world_rules_prompt(),
		npc.name, "mujer" if npc.get("appearance", {}).get("figure", "") == "feminine" else "hombre", int(npc.age), npc.occupation,
		("\nCómo eres: " + str(npc.description)) if not str(npc.get("description", "")).is_empty() else "",
		Wardrobe.describe(npc.get("appearance", {})),
		", ".join(PackedStringArray(npc.personality)),
		"; ".join(PackedStringArray(npc.goals)),
		npc.secret,
		NPCMemory.describe(npc.id),
		Quests.describe_for_npc(npc.id),
		NPCMemory.describe_possessions(npc.id),
		_inventory_text(),
		"Ahora mismo vas caminando con el jugador (le acompañas)." if NPCMemory.is_following(npc.id) else "",
		PlayerProfile.describe(npc.id),
		scene_context,
		ACTIONS_GUIDE,
	]


const ACTIONS_GUIDE := """  Tipos de acción ("type") y sus campos:
  · give_item: das o prestas algo tuyo. UN give_item POR CADA OBJETO: «café y galletas» son dos give_item, cada uno con su precio. "item_name" (nombre concreto), "item_description" (cómo es), "lent": true si es un préstamo, "item_effect" si sirve para algo (heal, restore_temporal_energy, reduce_paradox, reveal_secret, unlock_location, boost_reputation o none). Si lo vendes, "price" (dólares) y queda cobrado.
  · charge: le cobras algo al jugador. "price" (dólares) y "text" (qué). Solo cobra lo razonable para tu oficio; el jugador paga con un botón o diciéndolo.
  · pay_player: le pagas al jugador (un trabajo, algo que te vende). "price" (dólares).
  · share_number: le das tu número de celular (si te cae bien o hay motivo).
  · hire_player: le das trabajo en tu negocio, SOLO si te lo pidió o aceptó y tiene sentido. "target": el puesto, "price": sueldo por turno en dólares (60–120), "start_hour" y "end_hour": el turno (0–23), "text": en qué consiste.
  · quit_job: le despides (si es tu empleado y hay motivo).
  · take_item: aceptas algo que el jugador te ofrece y lleva encima. "target": nombre del objeto.
  · follow_player / stop_following: empiezas o dejas de acompañarle.
  · ride_with_player: te subes con el jugador al vehículo en el que va (o al que hay a su lado), SOLO si en VEHÍCULOS CERCA hay uno con sitio. Te bajas con get_out. Si no hay ningún vehículo cerca, dilo: no lo inventes.
  · go_to: te vas a un sitio. "target": el lugar.
  · leave: te marchas de aquí (enojo, prisa, fin de la plática). "target": a dónde (opcional). Termina la conversación.
  · go_inside: entras en un edificio (tu casa, tu trabajo…). "target": el sitio; "amount": minutos que te quedas dentro (por defecto 60). Termina la conversación. Con refuse_contact además cierras por dentro.
  · invite_in: invitas al jugador a pasar a tu casa (solo si te tocó a la puerta y quieres; si no, le atiendes en el umbral).
  · approach: te acercas al jugador (para darle algo, para encararte…).
  · guide_player: le llevas tú a un sitio de este lugar ("llévame al faro", "¿me enseñas dónde está la panadería?"). "target": el sitio. Terminas la conversación y echas a andar delante; si se queda atrás, le esperas. Solo a sitios que existen aquí, o con una persona de aquí ("target": "con Marina", "con las vecinas"). Si no sabes dónde está, dilo.
  · change_stat: le curas, le cansas… "target": health, energy o instability; "amount": de -30 a 30.
  · reveal_place: le hablas de un lugar que puede visitar. "target": nombre, "text": cómo es o cómo llegar.
  · give_quest: le pides un favor o un trabajo. SIEMPRE que en "line" le pidas algo, inclúyelo; si no, no queda apuntado. "target": título corto, "text": qué tiene que hacer; "price": lo que pagarás al terminar (0 si es un favor); "quest_kind": bring_item (traerte un objeto: "item_name"), go_to (ir a un sitio: "place"), be_there (estar en "place" a una hora: "at_hour") o custom; "at_hour" si dijiste una hora (3 = 3 de la mañana, 15 = 3 de la tarde) y dila igual en "line".
  · complete_quest: das por cumplido un favor que le pediste y que ya hizo. "target": su título.
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
	var ago := WorldClock.absolute_minutes() - float(NPCMemory.get_mem(npc_id).get("last_talk", -1e9))
	if ago < 30.0:
		return "(El jugador vuelve a hablarte: acaban de hablar hace %d min. No le saludes como si no le hubieras visto; sigue con naturalidad.)" % maxi(int(ago), 1)
	if NPCMemory.get_mem(npc_id).met:
		return "(El jugador vuelve a acercarse para hablar contigo. Salúdale teniendo en cuenta lo que recuerdas.)"
	return "(El jugador se acerca a ti por primera vez. Preséntate a tu manera.)"

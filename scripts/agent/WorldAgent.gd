class_name WorldAgent
extends RefCounted
## El agente creador: la IA del juego trabaja como un programador dentro del mundo. Recibe lo que
## el jugador quiere hacer («construyo un carrito con ruedas», «hago una caseta para el perro»,
## «pongo una lámpara junto a la banca») y, paso a paso, usa herramientas (WorldTools): mira
## alrededor, busca modelos, crea piezas, les da comportamientos, revisa cómo quedó y corrige,
## hasta terminar. Cada paso es una respuesta JSON {thought, tool, args}; el resultado de la
## herramienta vuelve como mensaje y la IA sigue. Máximo MAX_STEPS pasos.

const MAX_STEPS := 12
signal progress(text: String)

var scene: LocationScene
var tools: WorldTools
## Para pruebas: Callable(messages) -> Dictionary {tool, args} (sustituye a la IA).
var responder: Callable


func _init(s: LocationScene) -> void:
	scene = s
	tools = WorldTools.new(s)


## ¿Lo que pide el jugador es crear o cambiar el mundo (y no una acción normal)?
const CREATE_WORDS := ["construyo", "construir", "fabrico", "fabricar", "armo ", "armar ", "monto un", "monto una", "hago un", "hago una",
	"creo un", "creo una", "invento", "diseño", "levanto un", "levanto una", "instalo", "coloco un", "coloco una", "pongo un", "pongo una",
	"pinto ", "decoro", "amueblo", "edifico", "ensamblo", "improviso un", "improviso una", "planto un", "le pongo", "le añado", "le agrego",
	"quito el ", "quito la ", "desarmo", "agrando", "muevo el ", "muevo la "]


static func wants_to_create(text: String) -> bool:
	var low := " " + text.to_lower() + " "
	return CREATE_WORDS.any(func(w): return low.contains(" " + w) or low.contains(w))


func system_prompt() -> String:
	var spec := PackedStringArray()
	for t in WorldTools.SPEC:
		spec.append("- %s %s: %s" % [t, WorldTools.SPEC[t][0], WorldTools.SPEC[t][1]])
	var beh := PackedStringArray()
	for b in Behaviors.TYPES:
		beh.append("%s (%s)" % [b, Behaviors.TYPES[b]])
	return """%s

ERES EL MOTOR DE ESTE MUNDO: un programador dentro del juego que lo va modificando para que lo que el jugador hace exista de verdad. Todo es posible si es realista: con lo que hay a mano, el tiempo que lleva y las leyes de este mundo. Construyes con herramientas, paso a paso, como en un editor 3D.

HERRAMIENTAS (responde SIEMPRE con UN solo JSON {"thought": "qué piensas hacer", "tool": "…", "args": {…}}):
%s

COMPORTAMIENTOS (attach): %s

CÓMO TRABAJAR:
1. Empieza con look_around para ver dónde estás y qué hay.
2. Si existe un modelo que sirve (search_catalog), úsalo; si no, constrúyelo con piezas a escala real (una silla mide ~0.9 m, una mesa 0.75 m, una puerta 2 m, una rueda de bici 0.66 m, la de un coche 0.65 m).
3. Las piezas se apoyan en el suelo: pos.y es el centro de la pieza, así que una caja de 1 m de alto va en y = 0.5. «z» es hacia delante del objeto.
4. Dale los comportamientos que necesita para funcionar (un banco: seat; una lámpara: light; un carrito: wheels + engine o pedals; una caseta con puerta: una pieza con role "door" + door).
5. Si una herramienta da ERROR, corrige y vuelve a intentarlo. Revisa con inspect si dudas.
6. Realismo: si se necesitan materiales que el jugador no lleva y no hay en el entorno, haz algo más sencillo con lo que hay o explica en done qué falta. Gasta materiales con "uses". Nada mágico salvo que este mundo lo permita.
7. Termina con done: narración en segunda persona («Clavas las tablas y…»), 1–3 frases, y "minutes": cuánto tiempo te llevó.""" % [
		ContentGenerator.world_rules_prompt(), "\n".join(spec), "; ".join(beh)]


## Hace lo que pide el jugador. Devuelve {ok, narration, minutes, created, steps, error}.
func run(request: String, context: String = "") -> Dictionary:
	if not responder.is_valid() and (Settings.use_mock or not Settings.has_api_key()):
		return await _local(request)
	var messages := [
		{"role": "system", "content": system_prompt()},
		{"role": "user", "content": "%s\n\nEL JUGADOR QUIERE: %s" % [context, request]},
	]
	var log := []
	var errors := 0
	for step in MAX_STEPS:
		var reply := await _ask(messages)
		if not reply.ok:
			errors += 1
			if errors >= 2:
				return {"ok": false, "error": reply.error, "created": tools.created, "steps": log}
			messages.append({"role": "user", "content": "Tu respuesta no era un JSON válido {\"thought\", \"tool\", \"args\"}. Repite con el formato correcto."})
			continue
		var tool := str(reply.data.get("tool", ""))
		var args: Dictionary = reply.data.get("args", {}) if reply.data.get("args", {}) is Dictionary else {}
		messages.append({"role": "assistant", "content": JSON.stringify(reply.data)})
		if tool == "done":
			var minutes := clampi(int(args.get("minutes", 10)), 0, 24 * 60)
			return {"ok": true, "narration": str(args.get("narration", "Listo.")), "minutes": minutes, "created": tools.created, "steps": log}
		progress.emit(_progress_text(tool, args))
		var result := tools.call_tool(tool, args)
		log.append({"tool": tool, "args": args, "result": result})
		messages.append({"role": "user", "content": "RESULTADO de %s:\n%s" % [tool, result]})
	var made := tools.created.size()
	return {"ok": made > 0, "narration": "Le dedicas un buen rato." if made > 0 else "No consigues terminarlo.", "minutes": 30,
		"created": tools.created, "steps": log, "error": "" if made > 0 else "demasiados pasos"}


func _ask(messages: Array) -> Dictionary:
	if responder.is_valid():
		var d = responder.call(messages)
		return {"ok": d is Dictionary, "data": d, "error": "" if d is Dictionary else "respuesta inválida"}
	var schema := {"type": "object", "properties": {
		"thought": {"type": "string"},
		"tool": {"type": "string", "enum": WorldTools.SPEC.keys()},
		"args": {"type": "object"}}, "required": ["tool", "args"]}
	var r := await AIClient.chat(messages, schema, "agent_step")
	if not r.ok:
		return r
	var data = r.data
	if typeof(data) != TYPE_DICTIONARY:
		data = ContentGenerator._extract_json(r.text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("tool"):
		return {"ok": false, "error": "JSON inválido"}
	return {"ok": true, "data": data}


func _progress_text(tool: String, args: Dictionary) -> String:
	match tool:
		"look_around":
			return "Miras alrededor…"
		"search_catalog":
			return "Piensas qué usar…"
		"spawn":
			return "Construyes %s…" % str(args.get("name", "algo")).to_lower()
		"attach":
			return "Lo ajustas para que funcione…"
		"modify":
			return "Lo corriges…"
	return "Trabajas en ello…"


# --- Sin IA: lo más común, a mano ---------------------------------------------------------------

## Recetas sencillas para cuando no hay IA (o en pruebas): un banco, una mesa, una caseta…
const RECIPES := {
	"banco": {"name": "Banco", "behaviors": ["seat"], "parts": [
		{"shape": "box", "size": [1.6, 0.08, 0.45], "pos": [0, 0.45, 0], "material": "wood", "color": "#8b6b4a"},
		{"shape": "box", "size": [0.08, 0.45, 0.4], "pos": [-0.7, 0.22, 0], "material": "wood", "color": "#6b4f35"},
		{"shape": "box", "size": [0.08, 0.45, 0.4], "pos": [0.7, 0.22, 0], "material": "wood", "color": "#6b4f35"}]},
	"mesa": {"name": "Mesa", "behaviors": [], "parts": [
		{"shape": "box", "size": [1.2, 0.06, 0.8], "pos": [0, 0.75, 0], "material": "wood", "color": "#8b6b4a"},
		{"shape": "box", "size": [0.07, 0.72, 0.07], "pos": [-0.55, 0.36, -0.35]}, {"shape": "box", "size": [0.07, 0.72, 0.07], "pos": [0.55, 0.36, -0.35]},
		{"shape": "box", "size": [0.07, 0.72, 0.07], "pos": [-0.55, 0.36, 0.35]}, {"shape": "box", "size": [0.07, 0.72, 0.07], "pos": [0.55, 0.36, 0.35]}]},
	"caseta": {"name": "Caseta", "behaviors": ["door"], "parts": [
		{"shape": "box", "size": [2.0, 0.1, 2.0], "pos": [0, 0.05, 0], "material": "wood"},
		{"shape": "box", "size": [2.0, 2.0, 0.08], "pos": [0, 1.0, -1.0], "material": "wood"},
		{"shape": "box", "size": [0.08, 2.0, 2.0], "pos": [-1.0, 1.0, 0], "material": "wood"},
		{"shape": "box", "size": [0.08, 2.0, 2.0], "pos": [1.0, 1.0, 0], "material": "wood"},
		{"shape": "box", "size": [0.6, 2.0, 0.08], "pos": [-0.7, 1.0, 1.0], "material": "wood"},
		{"shape": "box", "size": [0.6, 2.0, 0.08], "pos": [0.7, 1.0, 1.0], "material": "wood"},
		{"shape": "box", "size": [0.8, 1.9, 0.05], "pos": [0, 0.95, 1.0], "material": "wood", "color": "#6b4f35", "role": "door"},
		{"shape": "ramp", "size": [2.3, 0.6, 2.3], "pos": [0, 2.3, 0], "material": "wood", "color": "#7a3b2e"}]},
	"carrito": {"name": "Carrito", "behaviors": ["wheels", "pedals", "seat"], "parts": [
		{"shape": "box", "size": [1.0, 0.1, 1.6], "pos": [0, 0.4, 0], "material": "wood"},
		{"shape": "box", "size": [0.9, 0.5, 0.08], "pos": [0, 0.7, -0.6], "material": "wood"},
		{"shape": "wheel", "size": [0.5, 0.08, 0.5], "pos": [-0.55, 0.25, 0.55], "material": "rubber", "color": "#222222"},
		{"shape": "wheel", "size": [0.5, 0.08, 0.5], "pos": [0.55, 0.25, 0.55], "material": "rubber", "color": "#222222"},
		{"shape": "wheel", "size": [0.5, 0.08, 0.5], "pos": [-0.55, 0.25, -0.55], "material": "rubber", "color": "#222222"},
		{"shape": "wheel", "size": [0.5, 0.08, 0.5], "pos": [0.55, 0.25, -0.55], "material": "rubber", "color": "#222222"}]},
}


func _local(request: String) -> Dictionary:
	await scene.get_tree().process_frame
	var low := request.to_lower()
	for key in RECIPES:
		if low.contains(key):
			var r: Dictionary = RECIPES[key]
			var res := tools.spawn({"name": r.name, "parts": r.parts})
			if res.begins_with("ERROR"):
				return {"ok": false, "error": res, "created": [], "steps": []}
			var id: String = tools.created[-1]
			for b in r.behaviors:
				tools.attach(id, b, {})
			return {"ok": true, "narration": "Con lo que tienes a mano, armas un %s sencillo." % key, "minutes": 30, "created": tools.created, "steps": []}
	# Algo del catálogo que se llame así
	var found := Creations.search(request.replace("pongo", "").replace("coloco", ""), 1)
	if not found.is_empty():
		tools.spawn({"name": str(found[0].name).capitalize(), "model": found[0].model})
		return {"ok": true, "narration": "Colocas %s." % found[0].name, "minutes": 5, "created": tools.created, "steps": []}
	return {"ok": false, "error": "sin IA solo sé hacer: " + ", ".join(PackedStringArray(RECIPES.keys())), "created": [], "steps": []}

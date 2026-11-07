class_name Examine
extends RefCounted
## Interactuar con (casi) todo lo que se ve (v0.9.0):
##  - Leer un letrero: el texto entero en un panel (y queda anotado en el diario).
##  - Examinar cualquier cosa del mundo (lo que la escena cataloga con Decor.landmark): la IA lo
##    describe en una o dos frases, coherente con el lugar (sin IA, una descripción sencilla). Se
##    guarda la descripción: si lo vuelves a mirar, es la misma.
##  - Tomar objetos pequeños (una radio, una lata, un libro): pasan a tu inventario.
## Las acciones de examinar ceden ante puertas, personas y muebles (prioridad baja).

const SCHEMA := {"type": "object", "properties": {"description": {"type": "string"}}, "required": ["description"]}
## Cosas que no se examinan con su propio aviso (ya tienen el suyo o se mueven).
const SKIP_KINDS := ["traffic", "forage", "fishing", "balcony", "gallery", "sign"]

static var _cache := {}   # etiqueta + posición -> descripción


## Un letrero que se lee: «Leer: <título>» → el texto completo.
static func sign(parent: Node3D, at: Vector3, title: String, text: String) -> Interactable:
	var short := title if title.length() <= 28 else title.left(26) + "…"
	var it := Interactable.create(parent, at, 1.6, "Leer: %s" % short, func(p): read(p, title, text))
	it.name = "Letrero"
	it.pick_priority = 0.5
	return it


## Muestra un texto para leer (un letrero, una nota) y lo apunta en el diario.
static func read(player: Node, title: String, text: String) -> void:
	var scene: Node = player.get_parent() if player else null
	if scene == null:
		return
	var ui: Variant = scene.get("_ui")
	if ui:
		ui.block(true)
	var panel := NarrativePanel.new()
	scene.add_child(panel)
	panel.present("[b]%s[/b]\n\n%s" % [title.replace("[", "("), text.replace("[", "(")], "", ["Cerrar"])
	await panel.chosen
	panel.queue_free()
	if ui:
		ui.block(false)
	Journal.log_event("Leíste «%s»: %s" % [title, text.left(160)], "info")


## Cualquier cosa catalogada: «Examinar: una farola».
static func attach(parent: Node3D, pos: Vector3, label: String, kind: String) -> void:
	if kind in SKIP_KINDS or label.length() < 3:
		return
	var short := label.get_slice(",", 0).get_slice(":", 0)
	if short.length() > 30:
		short = short.left(28) + "…"
	var it := Interactable.create(parent, pos + Vector3(0, 1.0, 0), 1.3, "Examinar: %s" % short, func(p): examine(p, label, pos))
	it.name = "Examinar"
	it.pick_priority = -1.2  # no tapa puertas, personas ni muebles


static func examine(player: Node, label: String, pos: Vector3) -> void:
	var scene: Node = player.get_parent() if player else null
	if scene == null:
		return
	var key := "%s@%d,%d" % [label, int(pos.x), int(pos.z)]
	var ui: Variant = scene.get("_ui")
	if _cache.has(key):
		if ui:
			ui.toast(_cache[key])
		return
	if player.has_method("play_gesture"):
		player.play_gesture("think", 2.0)
	var text := await describe(scene, label, pos)
	_cache[key] = text
	if ui:
		ui.toast(text)


## Una o dos frases sobre lo que ves, coherentes con el sitio (la IA, o sin ella una sencilla).
static func describe(scene: Node, label: String, pos: Vector3) -> String:
	var around := ""
	if scene.has_method("surroundings_described"):
		around = str(scene.call("surroundings_described", pos))
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\nDescribe en 1 o 2 frases cortas (segunda persona, presente, realista y concreto) lo que ve el jugador al examinar de cerca un objeto. Solo detalles físicos plausibles de ESE objeto en ESE lugar: material, estado, marcas, olor, algo pequeño que llama la atención. No inventes personas, objetos ocultos ni sucesos. JSON: {\"description\": \"...\"}"},
		{"role": "user", "content": "LUGAR: %s\nALREDEDOR: %s\nOBJETO: %s" % [GameState.current_location(), around.left(600), label]},
	]
	var r: Dictionary = await AIClient.chat(messages, SCHEMA, "examine")
	if r.ok and r.data is Dictionary and str(r.data.get("description", "")).length() > 8:
		return str(r.data.description)
	return "Te fijas bien: %s. Nada fuera de lo normal." % label


## Algo pequeño que se puede llevar: «Tomar: una radio». Una vez tomado, no vuelve a aparecer.
static func takeable(node: Node3D, item_name: String, desc: String, effect: String = "none") -> void:
	var key := "%s_%d_%d_%d" % [GameState.current_location(), int(node.global_position.x * 10.0), int(node.global_position.y * 10.0), int(node.global_position.z * 10.0)] if node.is_inside_tree() else ""
	var taken: Dictionary = WorldDB.get_state("taken_props", {})
	if not key.is_empty() and taken.has(key):
		node.queue_free()
		return
	var it := Interactable.create(node, Vector3(0, 0.4, 0), 1.0, "Tomar: %s" % item_name.to_lower(), func(p):
		var t: Dictionary = WorldDB.get_state("taken_props", {})
		if not key.is_empty():
			t[key] = true
			WorldDB.set_state("taken_props", t)
		Actions.execute("", [{"type": "give_item", "item_name": item_name, "item_description": desc, "item_effect": effect}])
		if p and p.has_method("play_gesture"):
			p.play_gesture("pick_up", 1.0)
		var ui: Variant = p.get_parent().get("_ui") if p else null
		if ui:
			ui.toast("Tomas %s." % item_name.to_lower())
		node.queue_free(), node)
	it.name = "Tomar"
	it.pick_priority = 0.3

class_name Toggle
extends RefCounted
## Cosas que se encienden y se apagan (o se abren y se cierran): lámparas, la tele… Con E o con F
## («enciendo la tele»). El estado se guarda (al volver, sigue como lo dejaste) y se ve.

static func _key(node: Node3D) -> String:
	var p := node.global_position * 10.0
	return "%s|%d,%d,%d" % [GameState.current_location(), int(p.x), int(p.y), int(p.z)]


static func is_on(node: Node3D) -> bool:
	return bool(node.get_meta("toggle_on", false))


## Hace que `node` se pueda encender y apagar. `apply(on)` cambia lo que se ve.
static func make(node: Node3D, what: String, apply: Callable, verbs: Array = ["Encender", "Apagar"]) -> void:
	var states: Dictionary = WorldDB.get_state("obj_state", {})
	var on := bool(states.get(_key(node), false)) if node.is_inside_tree() else false
	node.set_meta("toggle_on", on)
	node.set_meta("toggle_apply", apply)
	node.set_meta("toggle_name", what)
	node.set_meta("toggle_verbs", verbs)
	node.add_to_group("things")
	if not node.has_meta("thing"):
		node.set_meta("thing", what)
	apply.call(on)
	var it := Interactable.create(node, Vector3(0, 0.9, 0), 1.2, "%s %s" % [verbs[1] if on else verbs[0], what], func(_p): set_on(node, not is_on(node)))
	it.name = "Interruptor"
	node.set_meta("toggle_it", it)


## Lo enciende (o apaga). Devuelve una frase de lo que pasó.
static func set_on(node: Node3D, on: bool) -> String:
	if not is_instance_valid(node) or not node.has_meta("toggle_apply"):
		return ""
	var what := str(node.get_meta("toggle_name"))
	var verbs: Array = node.get_meta("toggle_verbs")
	if is_on(node) == on:
		return "%s ya está %s." % [what.capitalize(), "encendida" if on else "apagada"]
	node.set_meta("toggle_on", on)
	(node.get_meta("toggle_apply") as Callable).call(on)
	var states: Dictionary = WorldDB.get_state("obj_state", {})
	states[_key(node)] = on
	WorldDB.set_state("obj_state", states)
	var it: Variant = node.get_meta("toggle_it", null)
	if it and is_instance_valid(it):
		(it as Interactable).set_prompt("%s %s" % [verbs[1] if on else verbs[0], what])
	Sfx.at(node, "knock", node.global_position + Vector3(0, 0.8, 0))
	var done := {"Encender": "Enciendes", "Apagar": "Apagas", "Abrir": "Abres", "Cerrar": "Cierras"}
	return "%s %s." % [done.get(verbs[0] if on else verbs[1], "Usas"), what]

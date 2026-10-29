extends Node
## Árbol de líneas temporales del jugador. Muchos mundos: nada se reescribe, cada salto o
## decisión importante cuelga una rama nueva del nodo actual. La raíz es El Despertar.
##
## Nodo: { id, parent, label, location_id, era, created_at }

signal branched(node: Dictionary)


func has_root() -> bool:
	return not _tree().nodes.is_empty()


func create_root(label: String, location_id: String, era: String) -> Dictionary:
	var t := _tree()
	t.nodes = {}
	var node := _make(t, "", label, location_id, era)
	t.current = node.id
	_save(t)
	branched.emit(node)
	return node


## Cuelga un nodo nuevo del actual y lo convierte en el actual.
func branch(label: String, location_id: String, era: String) -> Dictionary:
	var t := _tree()
	var node := _make(t, t.current, label, location_id, era)
	t.current = node.id
	_save(t)
	branched.emit(node)
	return node


## Moverse a un nodo existente (volver a un lugar) no crea rama: la ruta ya existe.
func move_to(node_id: String) -> void:
	var t := _tree()
	if t.nodes.has(node_id):
		t.current = node_id
		_save(t)


func current() -> Dictionary:
	var t := _tree()
	return t.nodes.get(t.current, {})


func nodes() -> Array:
	return _tree().nodes.values()


func get_node_data(node_id: String) -> Dictionary:
	return _tree().nodes.get(node_id, {})


## Primer nodo de cada lugar visitado, en orden de visita (para "volver a…").
func visited_locations() -> Array:
	var seen := {}
	var out := []
	var all := nodes()
	all.sort_custom(func(a, b): return int(a.seq) < int(b.seq))
	for n in all:
		if not seen.has(n.location_id):
			seen[n.location_id] = true
			out.append(n)
	return out


## Profundidad de la rama actual: cuánto te has alejado de El Despertar.
func depth() -> int:
	var d := 0
	var n := current()
	while not n.is_empty() and not str(n.parent).is_empty():
		d += 1
		n = get_node_data(n.parent)
	return d


func _make(t: Dictionary, parent: String, label: String, location_id: String, era: String) -> Dictionary:
	var seq := int(t.get("seq", 0)) + 1
	t.seq = seq
	var node := {
		"id": "t%d" % seq, "seq": seq, "parent": parent, "label": label,
		"location_id": location_id, "era": era, "created_at": Time.get_datetime_string_from_system(),
	}
	t.nodes[node.id] = node
	return node


func _tree() -> Dictionary:
	var t: Dictionary = WorldDB.get_state("timeline", {})
	if not t.has("nodes"):
		t = {"nodes": {}, "current": "", "seq": 0}
	return t


func _save(t: Dictionary) -> void:
	WorldDB.set_state("timeline", t)

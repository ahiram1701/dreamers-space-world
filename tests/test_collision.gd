extends SceneTree
## Nada sólido se atraviesa: construye el pueblo del Acto 0 y todos los tipos de interior y
## comprueba que cada modelo colocado (casas, árboles, rocas, muebles, farolas…) tiene colisión.
## Solo se libran las alfombras, las lámparas de techo, lo diminuto y los personajes (que tienen la suya).
##   godot --headless --path . -s tests/test_collision.gd

const PASSABLE := ["Carpet", "Light_Ceiling"]

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de colisiones")

	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 3:
		await process_frame
	var missing := _without_collision(town)
	_expect(missing.is_empty(), "el pueblo: todo lo sólido tiene colisión %s" % [missing.slice(0, 8)])

	var builder = load("res://procgen/InteriorBuilder.gd")
	for kind in builder.ROOMS:
		var holder := Node3D.new()
		root.add_child(holder)
		var room: Dictionary = builder.build(holder, kind, 12345, Vector3(0, -400, 0))
		missing = _without_collision(holder)
		_expect(missing.is_empty(), "interior «%s»: muebles sólidos %s" % [kind, missing.slice(0, 8)])
		_expect(not room.npc_spots.is_empty() and room.spawn.distance_to(room.npc_spots[0]) > 1.5,
			"interior «%s»: el sitio del PNJ no tapa la entrada" % kind)
		holder.queue_free()

	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


## Modelos colocados (AssetLibrary.place deja el meta "size") sin ningún cuerpo físico.
func _without_collision(node: Node) -> Array:
	var out := []
	for n in node.find_children("*", "Node3D", true, false):
		if not n.has_meta("size") or _exempt(n):
			continue
		var size: Vector3 = n.get_meta("size")
		if size.y < 0.25 or maxf(size.x, size.z) < 0.25:
			continue  # diminuto: una taza, un libro
		if n.position.y > 0.3 and n.get_parent() is Node3D and not n.get_parent().has_meta("size") and size.y < 0.6:
			continue  # encima de una mesa o un estante (las radios del taller)
		if n.find_children("*", "CollisionObject3D", true, false).is_empty():
			out.append("%s (%.1f m)" % [_model_name(n), size.y])
	return out


func _exempt(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is CharacterBody3D or p.get_script() == load("res://scripts/world/Boat.gd"):
			return true  # personajes y barcas tienen su propia colisión
		p = p.get_parent()
	var name := _model_name(n)
	return PASSABLE.any(func(k): return name.begins_with(k))


func _model_name(n: Node) -> String:
	for c in n.get_children():
		if not (c is CollisionObject3D):
			return str(c.name)
	return str(n.name)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

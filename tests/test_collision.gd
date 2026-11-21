extends SceneTree
## Nada sólido se atraviesa: construye el pueblo del Acto 0 y todos los tipos de interior y
## comprueba que cada modelo colocado (casas, árboles, rocas, muebles, farolas…) tiene colisión.
## Solo se libran las alfombras, las lámparas de techo, las flores y la hierba, lo diminuto y los
## personajes (que tienen la suya).
##   godot --headless --path . -s tests/test_collision.gd

const PASSABLE := ["Carpet", "Light_Ceiling", "Flowers", "Grass", "Plant_", "Bonfire"]  # (las flores, la hierba alta, los helechos y el fuego se atraviesan)

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
	# v0.15.0: y al revés, lo que se atraviesa no tiene cuerpo
	var walls := _passable_with_body(town)
	_expect(walls.is_empty(), "las flores, la hierba, los helechos y el fuego se atraviesan %s" % [walls.slice(0, 8)])
	# La cueva: su puerta se alcanza andando (antes quedaba dentro del montículo)
	var doors: Dictionary = town.get("_interiors").doors()
	_expect(doors.has("cueva"), "la cueva tiene puerta")
	if doors.has("cueva"):
		var door: Vector3 = town.get("_interiors").door_position("cueva")
		var reach := _reachable(town, door)
		_expect(reach < 1.5, "a la puerta de la cueva se llega a pie (a %.1f m)" % reach)

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

	# La mina de un mundo generado: su boca no está tapada por el montículo
	var poi := Node3D.new()
	root.add_child(poi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mine: Dictionary = load("res://procgen/PoiCatalog.gd").build(poi, "mine", rng, Color("#8a8478"))
	poi.position = Vector3(300, -200, 300)
	await physics_frame
	await physics_frame
	var mouth: Vector3 = poi.global_position + (mine.door.offset as Vector3) + Vector3(-0.6, 0, 0.8)  # (al lado de la vagoneta)
	var im = load("res://scripts/world/InteriorManager.gd")
	_expect(im.is_free(poi, mouth, [], 0.3), "delante de la boca de la mina hay sitio para estar de pie")
	poi.queue_free()

	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:  # (que acabe lo pendiente: cerrar justo tras liberar la escena podía fallar)
		await process_frame
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


## Lo que debería atravesarse y tiene cuerpo.
func _passable_with_body(node: Node) -> Array:
	var out := []
	for n in node.find_children("*", "Node3D", true, false):
		if not n.has_meta("size"):
			continue
		var name := _model_name(n)
		if not (["Flowers", "Grass", "Plant_", "Bonfire"].any(func(k): return name.begins_with(k))):
			continue
		for c in n.get_children():
			if c is StaticBody3D:
				out.append(name)
	return out


## A qué distancia de `to` se puede quedar de pie el jugador (barriendo hacia fuera).
func _reachable(scene: Node3D, to: Vector3) -> float:
	var im = load("res://scripts/world/InteriorManager.gd")
	for r in [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 3.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var p := to + Vector3(cos(a) * r, 0, sin(a) * r)
			p.y = scene.ground_at(p.x, p.z) + 0.05
			if im.is_free(scene, p, [], 0.3):
				return r
	return INF


func _exempt(n: Node) -> bool:
	if n.get_parent() != null and n.get_parent().get_children().any(func(c): return c is AnimatableBody3D):
		return true  # un coche que circula: su cuerpo va aparte (y se mueve con él)
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
			return load("res://procgen/AssetLibrary.gd").model_name_of(c)
	return str(n.name)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

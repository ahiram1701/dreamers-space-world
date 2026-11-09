class_name WorldTools
extends RefCounted
## Las herramientas del agente creador (WorldAgent): lo que la IA puede hacer en el mundo, como un
## programador con su API. Cada herramienta valida sus argumentos, no puede romper la partida ni
## tocar nada fuera del juego, y devuelve un texto con lo que pasó (o el error) para que la IA
## siga razonando.

const RANGE := 40.0   # lejos que puede crear o tocar algo desde el jugador (m)

## Descripción para el prompt: nombre → [argumentos, qué hace].
const SPEC := {
	"look_around": ["{radius}", "Mira alrededor: tu posición, hacia dónde miras, lo que hay (sitios, puertas, cosas, gente) y lo creado cerca con su id."],
	"search_catalog": ["{query}", "Busca modelos 3D ya hechos (muebles, plantas, rocas, barcos, herramientas, edificios, sci-fi…). Devuelve \"model\" y su altura real."],
	"spawn": ["{name, model?, parts?, at?, offset?, yaw?, scale?, height?, color?, uses?}", "Crea algo. O un \"model\" del catálogo, o \"parts\": lista de piezas {shape, size [x,y,z] m, pos [x,y,z] m desde el centro de su base (y hacia arriba, z hacia delante), rot [x,y,z] grados, color, material, role}. shape: box, cylinder, sphere, capsule, cone, torus, ramp, wheel. material: wood, metal, glass, fabric, stone, plastic, rubber, paint, emissive. role \"door\" = puerta que abre. \"at\": \"front\" (delante del jugador, por defecto), el nombre de un sitio o cosa, o un id creado; \"offset\": [x,y,z] desde ahí. \"uses\": materiales del inventario que se gastan. Devuelve su id."],
	"attach": ["{id, behavior, params?}", "Le da un comportamiento a algo creado. behavior: seat, bed, container, light, heat, door, sign, machine, rigid, float, sound, wheels, engine, pedals, thruster, cockpit, tank, rule. REGLAS (behavior rule, se pueden poner varias): params {when: weather|night|day|hour|player_near|use, value, do: [{act, value}], undo: [{act, value}]}; act: light_on, light_off, toggle_light, open, close, sound, say, color, give, wait. Ej.: «si llueve, enciende la luz» = {when: \"weather\", value: \"rain\", do: [{act: \"light_on\"}], undo: [{act: \"light_off\"}]}."],
	"modify": ["{id, move?, yaw?, scale?, color?, name?, add_parts?, remove_parts?}", "Cambia algo creado: move [x,y,z] lo desplaza, yaw lo gira (grados), add_parts añade piezas, remove_parts quita por índice."],
	"remove": ["{id}", "Quita algo que se creó (no edificios ni cosas de otros)."],
	"inspect": ["{id}", "Lee cómo es algo creado: piezas, tamaño, comportamientos."],
	"create_item": ["{name, description, effect?, model?}", "Crea un objeto que el jugador lleva en el inventario. effect: none, heal, nourish, hydrate, light, tool, warmth, signal."],
	"spawn_npc": ["{name, occupation, description, greeting}", "Aparece una persona nueva que se queda a vivir aquí (nombre y oficio coherentes con su género)."],
	"remember": ["{fact}", "Apunta un hecho nuevo del mundo (canon) para que todos lo sepan."],
	"done": ["{narration}", "Terminaste: cuenta en segunda persona y en 1–3 frases lo que hizo el jugador y cómo quedó."],
}

var scene: LocationScene
var created: Array = []   # ids creados en esta petición


func _init(s: LocationScene) -> void:
	scene = s


func call_tool(tool: String, args: Dictionary) -> String:
	if not SPEC.has(tool):
		return "ERROR: no existe la herramienta «%s». Usa una de: %s." % [tool, ", ".join(PackedStringArray(SPEC.keys()))]
	match tool:
		"look_around":
			return look_around(clampf(float(args.get("radius", 20.0)), 5.0, 60.0))
		"search_catalog":
			return search_catalog(str(args.get("query", "")))
		"spawn":
			return spawn(args)
		"attach":
			return attach(str(args.get("id", "")), str(args.get("behavior", "")), args.get("params", {}))
		"modify":
			return modify(args)
		"remove":
			return remove(str(args.get("id", "")))
		"inspect":
			return inspect(str(args.get("id", "")))
		"create_item":
			return create_item(args)
		"spawn_npc":
			return spawn_npc(args)
		"remember":
			var fact := ContentValidator.fit_text(str(args.get("fact", "")).strip_edges(), 200)
			if fact.length() < 5:
				return "ERROR: el hecho está vacío."
			WorldDB.add_canon(fact)
			return "Apuntado: %s" % fact
	return "OK"


# --- Mirar ------------------------------------------------------------------------------------

func look_around(radius: float) -> String:
	var p := scene._player.global_position
	var f := scene._player.view_forward()
	var lines := PackedStringArray()
	lines.append("Estás en %s (%s). Miras hacia (%.1f, %.1f). Suelo a %.1f m." % [
		scene._interiors.current_label() if scene._interiors.is_inside() else scene.place_near(p), GameState.current_location(), f.x, f.z, p.y])
	var around := scene.surroundings_described(p, radius)
	if not around.is_empty():
		lines.append(around)
	var near := Creations.describe_near(p, radius)
	lines.append("CREADO CERCA: " + (", ".join(near) if not near.is_empty() else "nada"))
	var free := _free_ahead(p, f)
	lines.append("Espacio libre delante: %.0f m." % free)
	lines.append("Inventario: " + _inventory())
	return "\n".join(lines)


func _free_ahead(p: Vector3, f: Vector3) -> float:
	var space := scene.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.8, 0), p + Vector3(0, 0.8, 0) + f * 30.0, Layers.WORLD)
	var hit := space.intersect_ray(q)
	return 30.0 if hit.is_empty() else (hit.position as Vector3).distance_to(p + Vector3(0, 0.8, 0))


func _inventory() -> String:
	var names := PackedStringArray()
	for id in Inventory.items():
		names.append(str(WorldDB.get_entity("item", id).get("name", "?")))
	return ", ".join(names) if not names.is_empty() else "nada"


func search_catalog(query: String) -> String:
	if query.strip_edges().length() < 3:
		return "ERROR: escribe qué buscas (p. ej. «silla», «barco», «roca»)."
	var found := Creations.search(query)
	if found.is_empty():
		return "No hay modelos de «%s»: constrúyelo con parts." % query
	var lines := PackedStringArray()
	for m in found:
		lines.append("%s — %s, %.1f m [%s]" % [m.model, m.name, float(m.height), ", ".join(PackedStringArray(m.tags))])
	return "\n".join(lines)


# --- Crear y cambiar ---------------------------------------------------------------------------

## Dónde va algo: delante del jugador, junto a un sitio o cosa, o junto a algo creado.
func _where(args: Dictionary) -> Vector3:
	var p := scene._player.global_position
	var f := scene._player.view_forward()
	var at := str(args.get("at", "front"))
	var base := p + f * 2.5
	if at != "front" and not at.is_empty():
		var c := Creations.get_entry(at)
		if not c.is_empty():
			base = Vector3(c.pos[0], c.pos[1], c.pos[2])
		else:
			var q := scene.position_of_name(at, p)
			if q != Vector3.INF:
				base = q
	var off := Creations._vec(args.get("offset", [0, 0, 0]), Vector3.ZERO)
	# offset en el marco del jugador: x a la derecha, z hacia delante
	var right := f.cross(Vector3.UP).normalized()
	base += right * off.x + f * off.z + Vector3(0, off.y, 0)
	if base.distance_to(p) > RANGE:
		base = p + (base - p).limit_length(RANGE)
	var g: float = scene.ground_at(base.x, base.z)
	return Vector3(base.x, (g if off.y == 0.0 else base.y) if not scene._interiors.is_inside() else p.y + off.y, base.z)


func spawn(args: Dictionary) -> String:
	var name := str(args.get("name", "")).strip_edges().left(40)
	if name.is_empty():
		return "ERROR: ponle un nombre (\"name\")."
	var model := str(args.get("model", ""))
	var parts: Array = args.get("parts", []) if args.get("parts", []) is Array else []
	if model.is_empty() and parts.is_empty():
		return "ERROR: da un \"model\" del catálogo (search_catalog) o una lista de \"parts\"."
	if not model.is_empty() and Creations.model_info(model).is_empty():
		return "ERROR: el modelo «%s» no está en el catálogo. Búscalo con search_catalog." % model
	if parts.size() > Creations.MAX_PARTS:
		return "ERROR: máximo %d piezas (diste %d)." % [Creations.MAX_PARTS, parts.size()]
	var clean := []
	for i in parts.size():
		var r := _clean_part(parts[i])
		if r.has("error"):
			return "ERROR en la pieza %d: %s" % [i, r.error]
		clean.append(r)
	# Materiales que se gastan
	var spent := PackedStringArray()
	for u in (args.get("uses", []) if args.get("uses", []) is Array else []):
		var id := _find_item(str(u))
		if id.is_empty():
			return "ERROR: no llevas «%s». Lo que llevas: %s." % [u, _inventory()]
	for u in (args.get("uses", []) if args.get("uses", []) is Array else []):
		var id := _find_item(str(u))
		spent.append(str(WorldDB.get_entity("item", id).get("name", u)))
		Inventory.remove(id)
	var pos := _where(args)
	var yaw := deg_to_rad(float(args.get("yaw", 0.0))) + atan2(scene._player.view_forward().x, scene._player.view_forward().z) + PI
	var entry := {"name": name, "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "yaw": snappedf(yaw, 0.001),
		"scale": clampf(float(args.get("scale", 1.0)), 0.1, 20.0), "behaviors": [], "by": "agent"}
	if not model.is_empty():
		entry["model"] = model
		if args.has("height"):
			entry["height"] = clampf(float(args.height), 0.05, 60.0)
	if not clean.is_empty():
		entry["parts"] = clean
	if Color.html_is_valid(str(args.get("color", ""))):
		entry["color"] = str(args.color)
	var saved := Creations.add(entry)
	if saved.is_empty():
		return "ERROR: aquí ya hay demasiadas cosas creadas (%d)." % Creations.MAX_HERE
	Creations.build(scene, saved)
	created.append(saved.id)
	return "Creado %s «%s» en (%.1f, %.1f, %.1f)%s." % [saved.id, name, pos.x, pos.y, pos.z,
		(", gastando " + ", ".join(spent)) if not spent.is_empty() else ""]


func _clean_part(p: Variant) -> Dictionary:
	if not p is Dictionary:
		return {"error": "cada pieza es un objeto {shape, size, pos…}"}
	var shape := str(p.get("shape", "box"))
	if not shape in Creations.SHAPES:
		return {"error": "shape «%s» no existe (%s)" % [shape, ", ".join(PackedStringArray(Creations.SHAPES))]}
	var size := Creations._vec(p.get("size", null), Vector3(-1, -1, -1))
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return {"error": "size debe ser [x, y, z] en metros, mayores que 0"}
	if size.x > 30.0 or size.y > 30.0 or size.z > 30.0:
		return {"error": "ninguna pieza puede medir más de 30 m"}
	var pos := Creations._vec(p.get("pos", [0, size.y / 2.0, 0]), Vector3(0, size.y / 2.0, 0))
	if pos.length() > 40.0:
		return {"error": "pos demasiado lejos del centro (máx. 40 m)"}
	var out := {"shape": shape, "size": [size.x, size.y, size.z], "pos": [pos.x, pos.y, pos.z]}
	var rot := Creations._vec(p.get("rot", null), Vector3.INF)
	if rot != Vector3.INF:
		out["rot"] = [rot.x, rot.y, rot.z]
	out["color"] = str(p.color) if Color.html_is_valid(str(p.get("color", ""))) else "#8b6b4a"
	var mat := str(p.get("material", "wood"))
	out["material"] = mat if mat in Creations.MATERIALS else "wood"
	if p.has("role"):
		out["role"] = str(p.role).left(20)
	return out


func _find_item(text: String) -> String:
	var low := text.to_lower()
	for id in Inventory.items():
		if str(WorldDB.get_entity("item", id).get("name", "")).to_lower().contains(low):
			return id
	return ""


func _rebuild(id: String) -> void:
	var old := Creations.node_of(scene, id)
	if old:
		old.get_parent().remove_child(old)
		old.queue_free()
	var e := Creations.get_entry(id)
	if not e.is_empty():
		Creations.build(scene, e)


func attach(id: String, behavior: String, params: Variant) -> String:
	var e := Creations.get_entry(id)
	if e.is_empty():
		return "ERROR: no hay nada creado con id «%s» (mira look_around)." % id
	if not Behaviors.TYPES.has(behavior):
		return "ERROR: comportamiento «%s» no existe. Hay: %s." % [behavior, ", ".join(PackedStringArray(Behaviors.TYPES.keys()))]
	if behavior == "rule":
		var err := Behaviors.check_rule(params if params is Dictionary else {})
		if not err.is_empty():
			return "ERROR en la regla: %s" % err
	var bs: Array = e.get("behaviors", []).filter(func(b): return b.get("type", "") != behavior or behavior == "rule")
	bs.append({"type": behavior, "params": params if params is Dictionary else {}})
	var problem := _vehicle_problem(e, bs)
	Creations.update(id, {"behaviors": bs})
	_rebuild(id)
	return "«%s» ahora: %s.%s" % [e.name, Behaviors.TYPES[behavior], (" OJO: " + problem) if not problem.is_empty() else ""]


## Lo que le falta a algo para moverse de verdad (piezas de rueda, cabina…).
func _vehicle_problem(e: Dictionary, bs: Array) -> String:
	var types: Array = bs.map(func(b): return str(b.get("type", "")))
	var wheels: int = e.get("parts", []).filter(func(p): return p.get("shape", "") == "wheel").size()
	if ("wheels" in types or "engine" in types) and not "float" in types and not "thruster" in types and wheels < 2:
		return "para rodar necesita al menos 2 piezas con shape \"wheel\" (tiene %d)." % wheels
	if "thruster" in types and not "cockpit" in types:
		return "para pilotarlo hace falta una cabina (cockpit)."
	return ""


func modify(args: Dictionary) -> String:
	var id := str(args.get("id", ""))
	var e := Creations.get_entry(id)
	if e.is_empty():
		return "ERROR: no hay nada creado con id «%s»." % id
	var fields := {}
	if args.has("move"):
		var m := Creations._vec(args.move, Vector3.ZERO).limit_length(20.0)
		var pos := Vector3(e.pos[0], e.pos[1], e.pos[2]) + m
		fields["pos"] = [pos.x, pos.y if m.y != 0.0 else scene.ground_at(pos.x, pos.z), pos.z]
	if args.has("yaw"):
		fields["yaw"] = float(e.get("yaw", 0.0)) + deg_to_rad(float(args.yaw))
	if args.has("scale"):
		fields["scale"] = clampf(float(args.scale), 0.1, 20.0)
	if args.has("name"):
		fields["name"] = str(args.name).left(40)
	if args.has("color") and Color.html_is_valid(str(args.color)):
		fields["color"] = str(args.color)
	var parts: Array = e.get("parts", []).duplicate(true)
	if args.get("remove_parts", []) is Array and not args.get("remove_parts", []).is_empty():
		var drop: Array = args.remove_parts.map(func(x): return int(x))
		var kept := []
		for i in parts.size():
			if not i in drop:
				kept.append(parts[i])
		parts = kept
		fields["parts"] = parts
	if args.get("add_parts", []) is Array and not args.get("add_parts", []).is_empty():
		for p in args.add_parts:
			var r := _clean_part(p)
			if r.has("error"):
				return "ERROR en una pieza nueva: %s" % r.error
			parts.append(r)
		if parts.size() > Creations.MAX_PARTS:
			return "ERROR: máximo %d piezas." % Creations.MAX_PARTS
		fields["parts"] = parts
	if fields.is_empty():
		return "ERROR: no dijiste qué cambiar."
	Creations.update(id, fields)
	_rebuild(id)
	return "Cambiado «%s»: %s." % [e.name, ", ".join(PackedStringArray(fields.keys()))]


func remove(id: String) -> String:
	var e := Creations.get_entry(id)
	if e.is_empty():
		return "ERROR: no hay nada creado con id «%s» (solo se puede quitar lo creado)." % id
	var n := Creations.node_of(scene, id)
	if n:
		n.queue_free()
	Creations.remove(id)
	return "Quitado «%s»." % e.name


func inspect(id: String) -> String:
	var e := Creations.get_entry(id)
	if e.is_empty():
		return "ERROR: no hay nada creado con id «%s»." % id
	var out := "%s «%s»: %s; %d piezas; comportamientos: %s." % [id, e.name, e.get("model", "piezas"), e.get("parts", []).size(),
		", ".join(PackedStringArray(e.get("behaviors", []).map(func(b): return str(b.type))))]
	for i in mini(e.get("parts", []).size(), 20):
		var p: Dictionary = e.parts[i]
		out += "\n  %d: %s %s en %s %s %s" % [i, p.shape, p.size, p.pos, p.get("material", ""), p.get("role", "")]
	return out


func create_item(args: Dictionary) -> String:
	var name := str(args.get("name", "")).strip_edges().left(40)
	if name.is_empty():
		return "ERROR: falta el nombre."
	var effect := str(args.get("effect", "none"))
	if not effect in ["none", "heal", "nourish", "hydrate", "light", "tool", "warmth", "signal"]:
		effect = "none"
	var data := {"name": name, "kind": "tool" if effect in ["tool", "light"] else "consumable", "effect": effect, "power": 15,
		"lore": ContentValidator.fit_text(str(args.get("description", "")), 500), "tags": ["creado"]}
	if not Creations.model_info(str(args.get("model", ""))).is_empty():
		data["model"] = str(args.model)
	var id := WorldDB.add_entity("item", data, "agent")
	Inventory.add(id)
	return "Ahora llevas «%s»." % name


func spawn_npc(args: Dictionary) -> String:
	var name := str(args.get("name", "")).strip_edges()
	var job := str(args.get("occupation", "vecino del barrio"))
	if name.split(" ").size() < 1 or name.length() < 3:
		return "ERROR: dale nombre y apellido."
	var id := Actions.build_npc(name, job, ContentValidator.fit_text(str(args.get("description", "")), 500), ContentValidator.fit_text(str(args.get("greeting", "Hola.")), 240))
	if id.is_empty():
		return "ERROR: no se pudo crear a esa persona."
	Actions.add_resident(id, _where(args))
	var e := WorldDB.get_entity("npc", id)
	return "Aparece %s (%s, %d años)." % [e.name, e.occupation, e.age]

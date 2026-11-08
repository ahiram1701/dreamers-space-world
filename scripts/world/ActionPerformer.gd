class_name ActionPerformer
extends Node
## Hace, paso a paso y a la vista, lo que el jugador escribió con F: caminar hasta algo, hacer el
## gesto (talar, golpear, abrazar…), usar un mueble o una puerta, que la otra persona reaccione
## y los cambios en el mundo (el árbol cae al terminar de talar, no antes).
##
## Uso: var notes := await performer.perform(steps, func(text): mostrar(text))
## Moverse con WASD cancela lo que queda.

signal step_started(text: String)

## Duración de cada gesto (segundos reales). Los que no están: 2.5 s.
const DURATION := {"chop": 4.0, "hammer": 4.0, "dig": 4.0, "search": 3.5, "fish": 5.0, "punch": 1.2, "push": 1.2,
	"kick": 1.2, "hug": 3.0, "handshake": 2.0, "pat": 1.6, "give": 2.2, "wave": 2.0, "throw": 1.5, "eat": 3.5,
	"drink": 3.0, "write": 3.5, "read": 4.0, "listen": 4.0, "call": 4.0, "kneel": 3.0, "think": 3.0, "dance": 5.0}
## Gestos que se quedan hasta que el jugador se mueve.
const HOLD := ["sit", "sleep"]   # (agacharse dura lo que dura: no te deja agachado)
## Sonido al golpear con cada gesto (y cada cuánto se repite).
const IMPACT := {"chop": ["chop", 0.9], "hammer": ["knock", 0.7], "dig": ["step_sand", 0.8], "punch": ["hit", 0.0],
	"push": ["hit", 0.0], "kick": ["hit", 0.0]}
## Dónde pararse según lo que haya que alcanzar.
const REACH := {"npc": 1.1, "tree": 1.3, "rock": 1.4, "bush": 1.0, "door": 0.9, "seat": 1.0, "bed": 1.3, "boat": 1.8,
	"water": 0.6, "object": 1.2, "exit": 0.9}
const WORD_KIND := {"árbol": "tree", "arbol": "tree", "roca": "rock", "piedra": "rock", "arbusto": "bush",
	"silla": "seat", "sofá": "seat", "cama": "bed", "barca": "boat", "bote": "boat", "agua": "water", "mar": "water", "puerta": "door"}
const EFFECTS := ["give_item", "update_item", "remove_item", "place_object", "affect_nearby", "change_stat", "journal",
	"reveal_place", "npc_react", "give_to_npc", "change_need", "pay", "earn", "spawn_npc", "create_place", "share_number", "take_item", "get_out"]

var scene: LocationScene
var player: Player

var _busy := false
var _cancelled := false
var _focus: Dictionary = {}   # lo último con lo que se está interactuando


func is_busy() -> bool:
	return _busy


func cancel() -> void:
	_cancelled = true


func perform(steps: Array, on_step: Callable = Callable()) -> Array:
	_busy = true
	_cancelled = false
	_focus = {}
	var notes := []
	player.frame_action(true)
	player.auto_walk_done.connect(_on_walk_done)
	for i in steps.size():
		if _cancelled or not is_instance_valid(player):
			break
		var s: Dictionary = steps[i]
		var text := str(s.get("narration", "")).strip_edges()
		if not text.is_empty():
			step_started.emit(text)
			if on_step.is_valid():
				on_step.call(text)
		notes.append_array(await _do_step(s, steps.slice(i + 1)))
	if player.auto_walk_done.is_connected(_on_walk_done):
		player.auto_walk_done.disconnect(_on_walk_done)
	player.frame_action(false)
	_busy = false
	return notes


func _on_walk_done(arrived: bool) -> void:
	if not arrived:
		_cancelled = true  # el jugador tomó el control


func _do_step(s: Dictionary, rest: Array) -> Array:
	var type: String = s.get("type", "")
	match type:
		"go_to":
			var e := scene.resolve_target(str(s.get("target", "")))
			if e.is_empty():
				var p := scene.place_position(str(s.get("target", "")))
				if p != Vector3.INF:
					await player.auto_walk_to(p, 2.0)
				return []
			await _reach(e)
			return []
		"play":
			var g := _gesture(s.get("target", s.get("gesture", "")))
			if g.is_empty():
				return []
			if g in scene.CONTACT_GESTURES:
				await _reach_contact_target(rest)
			if g in ["sit", "sleep"] and not _focus.is_empty() and _focus.node is Interactable and _focus.kind in ["seat", "bed"]:
				_focus.node.use(player)  # sentarse EN el banco, no en el aire a su lado
				await get_tree().create_timer(1.2).timeout
				return []
			await _gesture_and_wait(g)
			return []
		"climb":
			return await _climb(str(s.get("target", "")))
		"move_to":
			var e := scene.resolve_target(str(s.get("target", "")))
			if e.is_empty():
				return []
			await _reach(e)
			if _cancelled or not bool(s.get("on", true)) or not is_instance_valid(e.node):
				return []
			player.play_gesture("climb", 0.8)
			await get_tree().create_timer(0.7).timeout
			player.global_position = _top_of(e.node) + Vector3(0, 0.05, 0)
			player.velocity = Vector3.ZERO
			return []
		"force_door":
			var id := str(s.get("target", "")).trim_prefix("door:")
			if not scene._interiors.doors().has(id):
				id = _nearest_door()
			if id.is_empty():
				return []
			await player.auto_walk_to(scene._interiors.door_position(id), 0.9)
			if _cancelled:
				return []
			var note: String = await scene._door_rules.force(id, bool(s.get("window", false)))
			return [note] if not note.is_empty() else []
		"sleep", "wait":
			var minutes := rest_minutes(s, type == "sleep")
			var bed: Node3D = null
			if type == "sleep" and not _focus.is_empty() and _focus.kind == "bed" and _focus.node is Node3D:
				bed = (_focus.node as Node3D).get_parent() as Node3D
			if type == "sleep" and bed == null and not bool(s.get("floor", false)):
				# «Me voy a dormir a mi casa»: primero vas a tu casa y entras; luego, a la cama
				var where := str(s.get("target", s.get("where", ""))).to_lower()
				if where in ["home", "casa", "mi casa", "door:home", "bed", "cama"] or where.begins_with("door:"):
					var door := where.trim_prefix("door:")
					if door in ["home", "casa", "mi casa", "bed", "cama", ""]:
						door = scene._interiors.door_of_kind("home")
					if not door.is_empty() and scene._interiors.current_door() != door and scene._interiors.doors().has(door):
						if scene._interiors.is_inside():
							await scene._interiors.leave()
							await scene._interiors.wait_idle()
						await player.auto_walk_to(scene._interiors.door_position(door), 1.0)
						if _cancelled:
							return []
						scene._interiors.try_enter(door)
						await get_tree().create_timer(0.3).timeout
						await scene._interiors.wait_idle()
					elif door.is_empty() and not scene._interiors.is_inside():
						return ["Aquí no tienes casa a la que ir a dormir."]
				bed = scene._interiors.nearest_bed(player.global_position)
			if bed and type == "sleep":
				var to := bed.global_position
				await player.auto_walk_to(to, 1.3)
				if _cancelled:
					return []
				await scene._interiors.sleep(bed, minutes)
				return []
			await scene._interiors.rest(minutes, bed, type == "sleep")
			return []
		"travel":
			var target := str(s.get("target", ""))
			var loc := scene.travel_destination_for(target)
			if loc.is_empty():
				# Un sitio de este mismo lugar («el pueblo» cuando ya estás en él, «la plaza»…)
				var p := scene.place_position(target)
				if p == Vector3.INF and target.to_lower().contains("pueblo"):
					p = scene.place_position("plaza")
				if p == Vector3.INF:
					return ["No sabes cómo llegar a «%s»." % target]
				if p.distance_to(player.global_position) > 250.0:
					return await _long_walk(p)
				await player.auto_walk_to(p, 2.0)
				return []
			var note: String = await scene.travel_to(loc)
			return [note] if not note.is_empty() else []
		"interact":
			return await _interact(s)
		"drive_to":
			return await _drive_to(str(s.get("target", "")))
		"buy":
			return await _buy(str(s.get("item_name", s.get("target", ""))))
		"call":
			var cid := str(s.get("target", "")).trim_prefix("npc:")
			if cid.is_empty() or WorldDB.get_entity("npc", cid).is_empty():
				cid = Actions.npc_from(str(s.get("target", "")))
			if cid.is_empty():
				return ["No sabes a quién llamar."]
			if not bool(NPCMemory.get_mem(cid).get("met", false)):
				return ["No tienes el número de %s." % str(WorldDB.get_entity("npc", cid).get("name", "esa persona")).get_slice(" ", 0)]
			if scene.has_method("start_call"):
				scene.start_call(cid)
			return []
		"swim_to":
			var where := str(s.get("target", ""))
			var water := scene.resolve_target("water")
			if not water.is_empty():
				await player.auto_walk_to(water.pos, 0.4)
			var dest := scene.place_position(where)
			Body.change("hygiene", 10.0)
			Body.change("rest", -8.0)
			if dest != Vector3.INF:
				return ["Nadas hasta %s." % where] + await _long_walk(dest)
			return ["Nadas un rato."]
		"learn":
			var skill := str(s.get("item_name", s.get("text", "")))
			var teacher := str(s.get("target", "")).trim_prefix("npc:")
			if PlayerProfile.learn(skill, teacher):
				Journal.log_event("Aprendiste: %s." % skill, "info")
				return ["Aprendes %s." % skill.to_lower()]
			return []
		"ride":
			var rid := str(s.get("target", "")).trim_prefix("npc:")
			if not scene._npcs.has(rid):
				var e := scene.resolve_target(str(s.get("target", "")))
				if e.is_empty() or e.kind != "npc":
					return []
				rid = str(e.id).trim_prefix("npc:")
			var note: String = scene.npc_board(rid)
			var who := str(WorldDB.get_entity("npc", rid).get("name", "")).get_slice(" ", 0)
			return [] if note.begins_with("va hacia") else ["%s: %s." % [who, note]]
		"use":
			var e := scene.resolve_target(str(s.get("target", "")))
			if e.is_empty() or e.node == null:
				return []
			await _reach(e)
			if _cancelled:
				return []
			if e.node is Interactable:
				e.node.use(player)
			elif e.node is TownNPC:
				pass  # "usar" a alguien no tiene sentido; la reacción va aparte
			await get_tree().create_timer(0.8).timeout
			await scene._interiors.wait_idle()  # si era una puerta, que acabe de entrar antes del paso siguiente
			return []
		"give_to_npc":
			var e := scene.resolve_target(str(s.get("target", "")))
			if not e.is_empty():
				await _reach(e)
				if _cancelled:
					return []
				await _gesture_and_wait("give")
			return Actions.execute("", [s])
		"npc_react":
			var e := scene.resolve_target(str(s.get("target", "")))
			if not e.is_empty() and e.kind == "npc" and e.node.global_position.distance_to(player.global_position) > 6.0:
				return []  # demasiado lejos para enterarse
			var notes := Actions.execute("", [s])
			await get_tree().create_timer(0.9).timeout
			return notes
		"affect_nearby":
			# Talar "el árbol de al lado": si no hay ninguno a mano, primero va hasta el más cercano
			var e := scene.resolve_target(str(s.get("target", "tree")))
			if not e.is_empty() and e.pos.distance_to(player.global_position) > 3.0:
				await _reach(e)
			if _cancelled:
				return []
			if not e.is_empty() and e.kind in ["tree", "rock", "bush", "crop"]:
				s = s.duplicate()
				s["target"] = e.id  # justo ese, no otro
			return Actions.execute("", [s])
		_:
			if type in EFFECTS:
				return Actions.execute("", [s])
	return []


## Usar una cosa cualquiera: encender o apagar (la tele, una lámpara), abrir, sentarse… o, si no
## hay nada que hacer con ella, mirarla de cerca.
func _interact(s: Dictionary) -> Array:
	var e := scene.resolve_target(str(s.get("target", "")))
	if e.is_empty():
		return ["No ves eso por aquí."]
	await _reach(e)
	if _cancelled:
		return []
	var verb := str(s.get("verb", "use")).to_lower()
	var node: Variant = e.get("node")
	var holder: Node = node.get_parent() if node is Interactable and node.get_parent() and node.get_parent().has_meta("toggle_apply") else node
	if holder is Node3D and (holder as Node3D).has_meta("toggle_apply"):
		player.play_gesture("open", 0.8)
		var on := not (verb in ["turn_off", "off", "close", "apagar", "cerrar"]) if verb != "use" else not Toggle.is_on(holder)
		return [Toggle.set_on(holder, on)]
	if node is Interactable:
		(node as Interactable).use(player)
		await get_tree().create_timer(0.8).timeout
		return []
	Examine.examine(player, str(e.label), e.pos)
	return []


## Ir en vehículo: sube a tu coche (o a uno cercano: si no es tuyo, es robo), conduce hasta allí
## y gasta gasolina. Un trayecto largo pasa en un fundido.
func _drive_to(target: String) -> Array:
	var dest := scene.place_position(target)
	if dest == Vector3.INF and target.to_lower().contains("pueblo"):
		dest = scene.place_position("plaza")
	if dest == Vector3.INF:
		return ["No sabes cómo llegar a «%s»." % target]
	var v: Node3D = player.riding if player.riding is Vehicle else null
	if v == null:
		var best := 60.0
		for c in scene.get_children():
			if c is Vehicle and not c.pedals and c.global_position.distance_to(player.global_position) < best:
				var mine := str(c.get("owner_id")) in ["player", ""]
				if mine or v == null:
					v = c
					best = c.global_position.distance_to(player.global_position) - (30.0 if mine else 0.0)
		if v == null:
			return ["No hay ningún vehículo cerca para ir hasta allí."]
		await player.auto_walk_to(v.global_position, 2.2)
		if _cancelled:
			return []
		v.call("_on_use", player)
		await get_tree().create_timer(0.8).timeout
	var dist := v.global_position.distance_to(dest)
	var fuel_used := dist * 0.00012
	v.set("fuel", maxf(float(v.get("fuel")) - fuel_used, 0.0))
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(fade)
	add_child(layer)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.6)
	await tw.finished
	WorldClock.advance(dist / 11.0 / 60.0)
	var road := dest + (v.global_position - dest).normalized() * 6.0
	road.y = scene.ground_at(road.x, road.z) + 0.6 if scene.has_method("ground_at") else road.y
	(v as RigidBody3D).linear_velocity = Vector3.ZERO
	(v as RigidBody3D).angular_velocity = Vector3.ZERO
	var dir := (dest - road)
	dir.y = 0.0
	v.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), road)
	await get_tree().create_timer(0.3).timeout
	tw = create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.6)
	await tw.finished
	layer.queue_free()
	return ["Conduces hasta %s (%d min)." % [target, roundi(dist / 11.0 / 60.0)]]


## Comprar de verdad: vas al local que lo vende, con su precio y su horario.
func _buy(what: String) -> Array:
	var low := what.to_lower()
	var kind := ""
	var entry := {}
	for k in Shops.data().kinds:
		for it in Shops.info(k).get("items", []):
			var n := str(it.name).to_lower()
			if not low.is_empty() and (n.contains(low) or low.contains(n) or low.contains(n.get_slice(" ", 0))):
				kind = k
				entry = it
				break
		if not kind.is_empty():
			break
	if kind.is_empty():
		return ["Aquí no venden «%s»." % what]
	var door: String = scene._interiors.door_of_kind(kind)
	if door.is_empty():
		return ["Aquí no hay %s." % Shops.label(kind)]
	if not Shops.is_open(kind, WorldClock.hour()):
		return ["%s está cerrado: abre %s." % [Shops.label(kind).capitalize(), Shops.hours_text(kind)]]
	if scene._interiors.current_door() != door:
		if scene._interiors.is_inside():
			await scene._interiors.leave()
			await scene._interiors.wait_idle()
		await player.auto_walk_to(scene._interiors.door_position(door), 1.0)
		if _cancelled:
			return []
		scene._interiors.try_enter(door)
		await get_tree().create_timer(0.3).timeout
		await scene._interiors.wait_idle()
	if entry.get("menu", false) or Shops.info(kind).get("menu", false):
		return ["En %s se pide a la mesera: siéntate a una mesa." % Shops.label(kind)]
	var id := Shops.buy(entry)
	if id.is_empty():
		return ["No te alcanza: %s cuesta %s." % [str(entry.name).to_lower(), Wallet.text(int(entry.price))]]
	player.play_gesture("give", 1.2)
	return ["Compras %s por %s." % [str(entry.name).to_lower(), Wallet.text(int(entry.price))]]


## Ir a pie muy lejos (fuera del pueblo, al otro lado del mapa): fundido, el reloj avanza lo que
## se tardaría andando y apareces allí.
func _long_walk(p: Vector3) -> Array:
	var d := p.distance_to(player.global_position)
	var minutes := d / 1.4 / 60.0
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(fade)
	add_child(layer)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.6)
	await tw.finished
	WorldClock.advance(minutes)
	player.global_position = InteriorManager.free_spot_near(scene, p, Vector3.ZERO, [player]) + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.4).timeout
	tw = create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.6)
	await tw.finished
	layer.queue_free()
	return ["Caminas un buen rato (%d min)." % roundi(minutes)]


## La puerta más cercana al jugador ("" si no hay ninguna a 25 m).
func _nearest_door() -> String:
	var best := ""
	var best_d := 25.0
	for id in scene._interiors.doors():
		var d: float = scene._interiors.door_position(id).distance_to(player.global_position)
		if d < best_d:
			best = id
			best_d = d
	return best


## Lo más alto de algo (para subirse encima de una banca o una roca).
static func _top_of(node: Node3D) -> Vector3:
	var holder: Node3D = node.get_parent() as Node3D if node is Interactable and node.get_parent() is Node3D else node
	var top := -INF
	for v in holder.find_children("*", "VisualInstance3D", true, false) + [holder]:
		if v is VisualInstance3D:
			var box: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
			top = maxf(top, box.end.y)
	return Vector3(holder.global_position.x, top if top > -INF else holder.global_position.y + 0.5, holder.global_position.z)


## Subir al techo de un edificio (trepando, o con una escalera si es alto) o bajar de él.
const CLIMB_FREE := 7.0
var _roofs := {}   # puerta -> StaticBody3D de la azotea (se crea al subir por primera vez)
var on_roof := ""


func _climb(target: String) -> Array:
	var low := target.to_lower()
	if low in ["down", "bajar", "abajo", "suelo"] or (not on_roof.is_empty() and low.is_empty()):
		return await _climb_down()
	var id := low.trim_prefix("roof:").trim_prefix("door:")
	if id in ["home", "casa", "mi casa", "tu casa"]:
		id = scene._interiors.door_of_kind("home")
	if not scene._interiors.doors().has(id):
		id = _nearest_door()
	if id.is_empty() or scene._interiors.is_inside():
		return ["Desde aquí no hay techo al que subir."]
	var b: Dictionary = scene._interiors.doors()[id].get("building", {})
	if b.is_empty():
		return ["No ves por dónde subir a ese techo."]
	var height: float = b.size.y
	var ladder := not Inventory.find_by_name("escalera").is_empty()
	if height > CLIMB_FREE and not ladder:
		return ["El techo está a unos %d m y la pared es lisa: no hay por dónde trepar. Con una escalera, sí." % int(height)]
	var door := scene._interiors.door_position(id)
	var yaw: float = b.yaw
	var front := Vector3(sin(yaw), 0, cos(yaw))
	var right := front.cross(Vector3.UP).normalized()
	# A un lado de la puerta, pegado a la fachada
	var wall_spot: Vector3 = door + right * 1.6 - front * 0.4
	await player.auto_walk_to(wall_spot, 0.6)
	if _cancelled:
		return []
	player.face_towards(wall_spot - front)
	player.play_gesture("climb", 2.6)
	Sfx.at(scene, "step_sand", player.global_position + Vector3(0, 1.2, 0))
	await get_tree().create_timer(2.4).timeout
	if _cancelled:
		player.stop_gesture()
		return []
	var top: float = b.base.y + height
	if not _roofs.has(id):
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(b.size.x - 0.6, 1.5), 0.3, maxf(b.size.z - 0.6, 1.5))
		cs.shape = shape
		body.add_child(cs)
		scene.add_child(body)
		body.global_position = Vector3(b.base.x, top - 0.15, b.base.z)
		body.rotation.y = yaw
		_roofs[id] = body
	player.global_position = Vector3(b.base.x, top + 0.1, b.base.z) + front * maxf(b.size.z / 2.0 - 1.4, 0.0)
	player.velocity = Vector3.ZERO
	player.stop_gesture()
	on_roof = id
	return ["Estás en el techo de %s%s." % [scene._interiors.door_label(id), " (subiste con la escalera)" if height > CLIMB_FREE else ""]]


func _climb_down() -> Array:
	if on_roof.is_empty():
		return []
	var id := on_roof
	on_roof = ""
	var b: Dictionary = scene._interiors.doors()[id].building
	var front := Vector3(sin(b.yaw), 0, cos(b.yaw))
	player.play_gesture("climb", 2.2)
	await get_tree().create_timer(2.0).timeout
	var right := front.cross(Vector3.UP).normalized()
	var below: Vector3 = scene._interiors.door_position(id) + right * 1.6 + front * 0.8
	player.global_position = InteriorManager.free_spot_near(scene, below, front, [player]) + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO
	player.stop_gesture()
	return ["Bajas del techo."]


## Camina hasta algo (a la distancia adecuada) y se gira hacia ello.
func _reach(e: Dictionary) -> void:
	_focus = e
	var target: Vector3 = e.pos
	if e.kind == "npc" and is_instance_valid(e.node):
		target = e.node.global_position
	var reach: float = REACH.get(e.kind, 1.2)
	if e.kind == "tree" or e.kind == "rock":
		var size: Vector3 = e.node.get_meta("size", Vector3.ONE) if is_instance_valid(e.node) else Vector3.ONE
		reach = clampf(minf(size.x, size.z) * 0.2, 0.7, 1.8) if e.kind == "tree" else maxf(size.x, size.z) * 0.5 + 0.6
	if Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length() > reach + 0.2:
		var ok := await player.auto_walk_to(target, reach)
		if not ok:
			return
	if is_instance_valid(player):
		player.face_towards(e.node.global_position if e.kind == "npc" and is_instance_valid(e.node) else target)


## Para un golpe o un abrazo hace falta tener delante a la persona: la busca en los pasos siguientes.
func _reach_contact_target(rest: Array) -> void:
	if not _focus.is_empty() and _focus.kind == "npc":
		await _reach(_focus)
		return
	for s in rest:
		if s.get("type", "") in ["npc_react", "give_to_npc"]:
			var e := scene.resolve_target(str(s.get("target", "")))
			if not e.is_empty() and e.kind == "npc":
				await _reach(e)
			return


func _gesture_and_wait(g: String) -> void:
	if _cancelled:
		return
	if g in HOLD:
		player.play_gesture(g)
		player.hold_position = true
		await get_tree().create_timer(1.2).timeout
		return
	var dur: float = DURATION.get(g, 2.5)
	player.play_gesture(g, dur)
	var impact: Array = IMPACT.get(g, [])
	var t := 0.0
	var next_hit := 0.45 if not impact.is_empty() else INF
	while t < dur and not _cancelled:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if t >= next_hit:
			var at := player.global_position + Vector3(0, 1.1, 0)
			if not _focus.is_empty():
				at = (player.global_position + _focus.pos) / 2.0 + Vector3(0, 1.0, 0)
			Sfx.at(scene, impact[0], at)
			next_hit = t + impact[1] if impact[1] > 0.0 else INF
	if _cancelled:
		player.stop_gesture()


func _gesture(text: Variant) -> String:
	return ContentValidator._match_enum(str(text), ContentValidator.archetypes().gesture)


## Plan sin IA: con lo que se entiende del texto, el personaje al menos lo intenta
## (va hasta lo que nombra y hace el gesto), sin cambiar el mundo.
## Cuántos minutos duerme o espera un paso: hasta una hora ("until_hour"), unas horas ("hours")
## o, si no dice, dormir hasta las 8 (mínimo 3 h) / esperar una hora.
static func rest_minutes(s: Dictionary, sleeping: bool) -> float:
	if s.has("until_hour") and s.until_hour != null:
		var m := fposmod(float(s.until_hour) - WorldClock.hour(), 24.0) * 60.0
		return m if m >= 5.0 else m + 24.0 * 60.0
	if s.has("hours") and s.hours != null:
		return float(s.hours) * 60.0
	if sleeping:
		return maxf(fposmod(8.0 - WorldClock.hour(), 24.0) * 60.0, 180.0)
	return 60.0


## "hasta las 3:30 am", "hasta las 7 de la tarde", "unas 2 horas" → {until_hour} / {hours} (o {}).
static func parse_rest(text: String) -> Dictionary:
	var low := text.to_lower()
	var re := RegEx.create_from_string("hasta (?:las |la )?(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|a\\.m\\.|pm|p\\.m\\.|de la mañana|de la madrugada|de la tarde|de la noche)?")
	var m := re.search(low)
	if m:
		var h := float(m.get_string(1))
		var mins := float(m.get_string(2)) if not m.get_string(2).is_empty() else 0.0
		var suffix := m.get_string(3)
		if (suffix.begins_with("p") or suffix.contains("tarde") or suffix.contains("noche")) and h < 12.0:
			h += 12.0
		elif (suffix.begins_with("a") or suffix.contains("mañana") or suffix.contains("madrugada")) and h == 12.0:
			h = 0.0
		return {"until_hour": fmod(h + mins / 60.0, 24.0)}
	var hm := RegEx.create_from_string("(\\d{1,2}(?:[.,]\\d)?) ?(?:horas|hora|h\\b)").search(low)
	if hm:
		return {"hours": clampf(float(hm.get_string(1).replace(",", ".")), 0.1, 16.0)}
	return {}


static func local_plan(what: String, scene_ref: LocationScene, guess: String) -> Array:
	var steps := []
	var low := what.to_lower()
	# Dormir o esperar (aunque no haya IA): "duermo hasta las 3:30 am", "espero 2 horas"
	var rest := parse_rest(low)
	var sleeping := ["duermo", "dormir", "me duermo", "me acuesto", "siesta", "descanso"].any(func(w): return low.contains(w))
	var waiting := ["espero", "esperar", "aguardo"].any(func(w): return low.contains(w))
	if sleeping or (waiting and not rest.is_empty()):
		var step := {"type": "sleep" if sleeping else "wait"}
		step.merge(rest)
		if sleeping and ["mi casa", "a casa", "en casa", "mi cama", "en la cama", "mi cuarto"].any(func(w): return low.contains(w)):
			step["target"] = "home"
		elif sleeping and ["cama"].any(func(w): return low.contains(w)):
			step["target"] = "bed"
		elif sleeping and ["suelo", "aquí", "aqui", "en el piso", "en la arena", "en el pasto"].any(func(w): return low.contains(w)):
			step["floor"] = true
		return [step]
	# Encender o apagar algo de aquí: «enciendo la tele», «apago la lámpara»
	for pair in [[["enciendo", "prendo", "encender", "prender"], "turn_on"], [["apago", "apagar"], "turn_off"]]:
		if (pair[0] as Array).any(func(w): return low.contains(w)):
			for id in scene_ref.nearby_targets():
				var e: Dictionary = scene_ref.nearby_targets()[id]
				var lab := str(e.label).to_lower().get_slice(" (", 0)  # «la tele (apagada)» → «la tele»
				var noun := lab.get_slice(" ", lab.get_slice_count(" ") - 1)
				if e.kind == "thing" and (e.node as Node).has_meta("toggle_apply") and noun.length() > 2 and low.contains(noun):
					return [{"type": "interact", "target": id, "verb": pair[1]}]
	# Ir en coche: «manejo hasta la granja», «voy en coche al lago»
	if ["manejo", "conduzco", "en coche", "en auto", "en carro", "maneja", "conducir"].any(func(w): return low.contains(w)):
		for nm in scene_ref._places:
			if low.contains(str(nm).to_lower()):
				return [{"type": "drive_to", "target": nm}]
	# Comprar: «compro pan»
	if ["compro ", "comprar "].any(func(w): return low.contains(w)):
		var it := low.get_slice("compr", 1).get_slice(" ", 1)
		return [{"type": "buy", "item_name": low.substr(low.find("compr")).get_slice(" ", 1) if it.length() < 3 else it}]
	# Llamar por teléfono: «llamo a Marina»
	if ["llamo a", "llamar a", "le llamo", "la llamo"].any(func(w): return low.contains(w)):
		for nid in scene_ref._npcs:
			var first := str(WorldDB.get_entity("npc", nid).get("name", "")).to_lower().get_slice(" ", 0)
			if first.length() > 2 and low.contains(first):
				return [{"type": "call", "target": "npc:" + str(nid)}]
	# Viajar o volver a otro sitio: «regreso al pueblo», «vuelvo a casa», «vamos a Kepra»
	if ["regreso", "regresar", "vuelvo", "volver", "voy a", "vamos a", "viajo", "viajar", "ir a", "llévame", "llevame"].any(func(w): return low.contains(w)):
		var dests := scene_ref.travel_destinations()
		for nm in dests:
			if low.contains(nm):
				return [{"type": "travel", "target": "location:" + dests[nm]}]
		for nm in scene_ref._places:
			if low.contains(str(nm).to_lower()):
				return [{"type": "travel", "target": nm}]
		if low.contains("pueblo"):
			return [{"type": "travel", "target": "pueblo"}]
	# «Súbete al coche», «sube al auto, Samir»
	if ["súbete", "subete", "sube al", "sube a la", "suban", "súbanse"].any(func(w): return low.contains(w)):
		var targets0 := scene_ref.nearby_targets()
		for id in targets0:
			var e0: Dictionary = targets0[id]
			if e0.kind == "npc" and low.contains(str(e0.label).get_slice(",", 0).to_lower().get_slice(" ", 0)):
				return [{"type": "ride", "target": id}]
		for nid in scene_ref._npcs:  # alguien con nombre aunque no esté en la lista de cercanos
			var nm := str(WorldDB.get_entity("npc", nid).get("name", "")).to_lower().get_slice(" ", 0)
			if nm.length() > 2 and low.contains(nm):
				return [{"type": "ride", "target": "npc:" + str(nid)}]
		for id in targets0:
			var e1: Dictionary = targets0[id]
			if e1.kind == "npc" and NPCMemory.is_following(str(id).trim_prefix("npc:")):
				return [{"type": "ride", "target": id}]
	# Subir al techo o bajar de él; forzar una puerta o colarse por una ventana
	if ["techo", "azotea", "tejado"].any(func(w): return low.contains(w)):
		if ["bajo", "bajar", "me bajo"].any(func(w): return low.contains(w)):
			return [{"type": "climb", "target": "down"}]
		return [{"type": "climb", "target": "roof:home" if ["mi casa", "casa mía"].any(func(w): return low.contains(w)) else ""}]
	if ["fuerzo", "forzar", "forzo", "me cuelo", "colarme", "por la ventana", "hago palanca"].any(func(w): return low.contains(w)):
		return [{"type": "force_door", "target": "", "window": low.contains("ventana")}]
	var targets := scene_ref.nearby_targets()
	var pick := ""
	for id in targets:
		var e: Dictionary = targets[id]
		var name: String = str(e.label).get_slice(",", 0).to_lower()
		if e.kind == "npc" and low.contains(name.get_slice(" ", 0)):
			pick = id
			break
	if pick.is_empty():
		for word in WORD_KIND:
			if low.contains(word):
				var best := INF
				for id in targets:
					var d: float = targets[id].pos.distance_to(scene_ref._player.global_position)
					if targets[id].kind == WORD_KIND[word] and d < best:
						pick = id
						best = d
				break
	if not pick.is_empty():
		steps.append({"type": "go_to", "target": pick})
	if not guess.is_empty():
		steps.append({"type": "play", "target": guess})
	return steps

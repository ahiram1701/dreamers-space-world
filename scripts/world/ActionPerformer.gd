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
const HOLD := ["sit", "sleep", "crouch"]
## Sonido al golpear con cada gesto (y cada cuánto se repite).
const IMPACT := {"chop": ["chop", 0.9], "hammer": ["knock", 0.7], "dig": ["step_sand", 0.8], "punch": ["hit", 0.0],
	"push": ["hit", 0.0], "kick": ["hit", 0.0]}
## Dónde pararse según lo que haya que alcanzar.
const REACH := {"npc": 1.1, "tree": 1.3, "rock": 1.4, "bush": 1.0, "door": 0.9, "seat": 1.0, "bed": 1.3, "boat": 1.8,
	"water": 0.6, "object": 1.2, "exit": 0.9}
const WORD_KIND := {"árbol": "tree", "arbol": "tree", "roca": "rock", "piedra": "rock", "arbusto": "bush",
	"silla": "seat", "sofá": "seat", "cama": "bed", "barca": "boat", "bote": "boat", "agua": "water", "mar": "water", "puerta": "door"}
const EFFECTS := ["give_item", "update_item", "remove_item", "place_object", "affect_nearby", "change_stat", "journal",
	"reveal_place", "npc_react", "give_to_npc", "change_need", "pay", "earn", "spawn_npc", "create_place"]

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
static func local_plan(what: String, scene_ref: LocationScene, guess: String) -> Array:
	var steps := []
	var low := what.to_lower()
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

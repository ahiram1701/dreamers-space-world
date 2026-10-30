class_name InteractionSystem
extends Node
## Decide con qué interactúa el jugador al pulsar E. Las zonas (PNJs, puertas, sillas, objetos)
## solo se apuntan y se borran de una lista al entrar y salir; cada frame se elige la mejor:
## la más cercana y centrada respecto a donde miras, con línea de visión y en la misma planta.
## Así una silla no "roba" la conversación con quien tienes delante y salir de una zona no
## deja al jugador sin objetivo.
##
## Cada candidato implementa:
##   interaction_prompt() -> String     "Hablar con Marina", "Salir"…
##   interaction_point() -> Vector3     dónde está (para distancia, ángulo y visibilidad)
## y opcionalmente interaction_owner() -> Node (su cuerpo físico: no tapa su propia visibilidad).

signal target_changed(target: Node)

const MAX_ANGLE := deg_to_rad(75.0)
const CLOSE := 0.9            # tan cerca que da igual hacia dónde mires
const MAX_HEIGHT_DIFF := 2.5  # otra planta u otro interior
const PERSON_BONUS := 0.6     # a la misma distancia, una persona gana a un mueble

var player: Player
var target: Node = null

var _candidates: Array[Node] = []
var _prompt: Label
var _layer: CanvasLayer


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.72
	_prompt.anchor_bottom = 0.72
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.visible = false
	_layer.add_child(_prompt)


func add_candidate(node: Node) -> void:
	if not (node in _candidates):
		_candidates.append(node)


func remove_candidate(node: Node) -> void:
	_candidates.erase(node)


func candidates() -> Array[Node]:
	return _candidates


func _physics_process(_delta: float) -> void:
	var best := pick()
	if best != target:
		target = best
		target_changed.emit(target)
	var show := target != null and player.controls_enabled and player.riding == null
	_prompt.visible = show
	if show:
		_prompt.text = "[E]  " + str(target.call("interaction_prompt"))


## El mejor candidato ahora mismo (o null). Público para los tests.
func pick() -> Node:
	_candidates = _candidates.filter(func(c): return is_instance_valid(c) and c.is_inside_tree())
	var head := player.global_position + Vector3(0, 1.5, 0)
	var forward := player.view_forward()
	var best: Node = null
	var best_score := INF
	for c in _candidates:
		if c.has_method("can_interact") and not c.call("can_interact"):
			continue
		var p: Vector3 = c.call("interaction_point")
		if absf(p.y - player.global_position.y - 1.0) > MAX_HEIGHT_DIFF:
			continue
		var flat := Vector3(p.x - head.x, 0, p.z - head.z)
		var d := flat.length()
		var angle := 0.0 if d < 0.01 else forward.angle_to(flat / d)
		if angle > MAX_ANGLE and d > CLOSE:
			continue
		if not _visible(head, p, c):
			continue
		var score := d + angle * 1.6 - (PERSON_BONUS if c is TownNPC else 0.0)
		if score < best_score:
			best_score = score
			best = c
	return best


## Nada sólido entre la cabeza del jugador y el objetivo (salvo el propio objetivo).
func _visible(from: Vector3, to: Vector3, c: Node) -> bool:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	if hit.position.distance_to(to) < 0.7:
		return true  # choca con lo que hay justo en el objetivo (el mueble, la fachada de la puerta)
	var own: Node = c.call("interaction_owner") if c.has_method("interaction_owner") else c
	var n: Node = hit.collider
	while n != null:
		if n == own or n == c:
			return true
		n = n.get_parent()
	return false

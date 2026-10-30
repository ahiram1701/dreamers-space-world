class_name Interactable
extends Area3D
## Algo con lo que se interactúa con E: una puerta, una cama, una silla, una barca…
## Al acercarse se apunta como candidato del InteractionSystem del jugador (que elige el mejor
## y muestra el aviso "[E] Entrar") y, al pulsar E, llama a `on_use(player)`.

var prompt := "Usar"
var on_use: Callable
## El objeto físico al que pertenece (la silla, la barca): no tapa su propia visibilidad.
## Vacío para las que no son de un objeto (puertas, salidas).
var owner_node: Node = null
## Desactivado (p. ej. una puerta cerrada con pestillo sigue mostrando su aviso, pero no abre).
var enabled := true


static func create(parent: Node3D, pos: Vector3, radius: float, prompt_text: String, callback: Callable, owner_of: Node = null) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.on_use = callback
	it.position = pos
	it.owner_node = owner_of
	var cs := CollisionShape3D.new()
	cs.shape = SphereShape3D.new()
	cs.shape.radius = radius
	it.add_child(cs)
	parent.add_child(it)
	return it


func _ready() -> void:
	add_to_group("interactables")
	Layers.zone(self)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func set_prompt(text: String) -> void:
	prompt = text


func interaction_prompt() -> String:
	return prompt


func interaction_point() -> Vector3:
	return global_position


func interaction_owner() -> Node:
	return owner_node


func can_interact() -> bool:
	return enabled


func use(player: Node) -> void:
	if on_use.is_valid():
		on_use.call(player)


func _on_enter(body: Node3D) -> void:
	if body is Player:
		body.interaction.add_candidate(self)


func _on_exit(body: Node3D) -> void:
	if body is Player:
		body.interaction.remove_candidate(self)


func _exit_tree() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		p.interaction.remove_candidate(self)

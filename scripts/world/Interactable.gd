class_name Interactable
extends Area3D
## Algo con lo que se interactúa con E: una puerta, una cama, una silla, una barca…
## Al acercarse muestra el aviso ("[E] Entrar") y, al pulsar E, llama a `on_use(player)`.

var prompt := "Usar"
var on_use: Callable

var _hint: Label3D


static func create(parent: Node3D, pos: Vector3, radius: float, prompt_text: String, callback: Callable) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.on_use = callback
	it.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = SphereShape3D.new()
	cs.shape.radius = radius
	it.add_child(cs)
	parent.add_child(it)
	return it


func _ready() -> void:
	_hint = Label3D.new()
	_hint.text = "[E] " + prompt
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.font_size = 36
	_hint.outline_size = 8
	_hint.fixed_size = true  # mismo tamaño en pantalla, esté cerca o lejos
	_hint.pixel_size = 0.0012
	_hint.position.y = 1.6
	_hint.visible = false
	_hint.no_depth_test = true
	add_child(_hint)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func set_prompt(text: String) -> void:
	prompt = text
	if _hint:
		_hint.text = "[E] " + text


func use(player: Node) -> void:
	if on_use.is_valid():
		on_use.call(player)


func _on_enter(body: Node3D) -> void:
	if body is Player:
		body.interact_target = self
		_hint.visible = true


func _on_exit(body: Node3D) -> void:
	if body is Player:
		if body.interact_target == self:
			body.interact_target = null
		_hint.visible = false

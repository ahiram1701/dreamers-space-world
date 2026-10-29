extends Control
## Menú principal: empezar una vida nueva (= un mundo nuevo y único) o continuar la última.

const TOWN := "res://scenes/act0_town/Act0Town.tscn"
const DEV := "res://scenes/dev/AITestScene.tscn"

var _name: LineEdit
var _status: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color("#141a2e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Dreamer's Space World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Todos empiezan igual. Nadie termina en el mismo universo."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(sub)

	_name = LineEdit.new()
	_name.placeholder_text = "¿Cómo te llamas?"
	_name.max_length = 30
	box.add_child(_name)
	_button(box, "Nueva vida", _on_new)
	var cont := _button(box, "Continuar", _on_continue)
	var last := WorldDB.last_world_id()
	cont.disabled = last.is_empty()
	_button(box, "Ajustes de IA / Generador (dev)", func(): get_tree().change_scene_to_file(DEV))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("#f2a65a"))
	box.add_child(_status)
	if not Settings.use_mock and not Settings.has_api_key():
		_status.text = "Sin API key: los diálogos usarán respuestas de respaldo. Configúrala en Ajustes."


func _on_new() -> void:
	var player_name := _name.text.strip_edges()
	if player_name.is_empty():
		_status.text = "Escribe tu nombre para empezar."
		return
	WorldDB.create_world("Mundo de " + player_name)
	PlayerProfile.set_player_name(player_name)
	get_tree().change_scene_to_file(TOWN)


func _on_continue() -> void:
	if WorldDB.load_world(WorldDB.last_world_id()):
		get_tree().change_scene_to_file(TOWN)
	else:
		_status.text = "No se pudo cargar la última partida."


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	parent.add_child(b)
	return b

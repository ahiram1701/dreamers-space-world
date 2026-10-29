class_name PauseMenu
extends CanvasLayer
## Pausa (Esc). La partida se guarda sola en cada cambio, así que salir nunca pierde nada.

signal opened
signal closed

var _root: Control
var _info: Label


func _ready() -> void:
	layer = 35
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 360
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	box.add_child(_info)
	_button(box, "Continuar", close)
	_button(box, "Ajustes", _settings)
	_button(box, "Salir al menú principal", func(): get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn"))


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func open() -> void:
	var where := Travel.location_name(GameState.current_location())
	_info.text = "%s\n%s" % [WorldDB.get_state("profile", {}).get("name", ""), where]
	if GameState.is_awakened():
		_info.text += "\nCoordenadas %d/%d · Ramas recorridas: %d" % [GameState.fragments(), GameState.FRAGMENTS_NEEDED, TimelineManager.depth()]
	_info.text += "\n(La partida se guarda automáticamente)"
	_root.visible = true
	opened.emit()


func close() -> void:
	_root.visible = false
	closed.emit()


func _settings() -> void:
	_root.visible = false
	var s := SettingsPanel.new()
	add_child(s)
	s.closed.connect(func(): _root.visible = true)


func _button(parent: Node, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	parent.add_child(b)

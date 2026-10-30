class_name PauseMenu
extends CanvasLayer
## Pausa (Esc). La partida se guarda sola en cada cambio, así que salir nunca pierde nada.
## Aquí está la lista completa de controles (teclado y mando): en el juego no se ven.

signal opened
signal closed

## Lo que hace cada acción, para la tabla de controles (el orden es el de la tabla).
const ACTIONS := [
	["move_forward", "Moverse", "WASD", "Stick izquierdo"], ["run", "Correr", "", ""], ["jump", "Saltar", "", ""],
	["", "Mirar", "Ratón", "Stick derecho"], ["zoom_in", "Acercar / alejar la cámara (al mínimo, primera persona)", "Rueda", "Cruceta ↑ ↓"],
	["interact", "Hablar, entrar, sentarse, subir a una barca, recoger", "", ""],
	["act", "Hacer cualquier cosa: escríbela y tu personaje la hace", "", ""],
	["inventory", "Cuaderno: objetos, encargos, diario y personas", "", ""],
	["phone", "Celular: mensajes, llamadas, banco y mapa", "", ""], ["anchor", "Ancla (tras El Despertar)", "", ""],
	["choice_1", "Elegir respuesta en una conversación", "1 – 4", "Cruceta y A"], ["pause", "Pausa", "", ""],
]

var _root: Control
var _menu: VBoxContainer
var _controls: PanelContainer
var _info: Label


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var stack := HBoxContainer.new()
	stack.add_theme_constant_override("separation", 24)
	center.add_child(stack)

	var panel := PanelContainer.new()
	UIStyle.apply(panel)
	stack.add_child(panel)
	_menu = VBoxContainer.new()
	_menu.custom_minimum_size.x = 340
	_menu.add_theme_constant_override("separation", 10)
	panel.add_child(_menu)
	var title := Label.new()
	title.text = "Pausa"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_font_override("font", UITheme.font_bold)
	_menu.add_child(title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", UITheme.MUTED)
	_info.add_theme_font_size_override("font_size", 15)
	_menu.add_child(_info)
	_menu.add_child(HSeparator.new())
	_button(_menu, "Continuar", close)
	_button(_menu, "Controles", _toggle_controls)
	_button(_menu, "Ajustes", _settings)
	_button(_menu, "Salir al menú principal", func(): get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn"))

	_controls = PanelContainer.new()
	UIStyle.apply(_controls)
	_controls.visible = false
	stack.add_child(_controls)


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func open() -> void:
	var where := Travel.location_name(GameState.current_location())
	_info.text = "%s · %s\n%s, %s" % [WorldDB.get_state("profile", {}).get("name", ""), where, WorldClock.weekday().capitalize(), WorldClock.text()]
	if GameState.is_awakened():
		_info.text += "\nCoordenadas %d/%d · Ramas recorridas: %d" % [GameState.fragments(), GameState.FRAGMENTS_NEEDED, TimelineManager.depth()]
	_info.text += "\nLa partida se guarda sola."
	_controls.visible = false
	UIAnim.show(_root, Vector2.ZERO)
	_menu.get_child(3).grab_focus.call_deferred()
	opened.emit()


func close() -> void:
	UIAnim.hide(_root)
	closed.emit()


func _toggle_controls() -> void:
	if _controls.visible:
		UIAnim.hide(_controls)
		return
	for c in _controls.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_controls.add_child(box)
	var title := Label.new()
	title.text = "Controles"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", UITheme.font_bold)
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for h in ["", "Teclado y ratón", "Mando"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", UITheme.MUTED)
		l.add_theme_font_size_override("font_size", 14)
		grid.add_child(l)
	var pad := Controls.using_gamepad
	for a in ACTIONS:
		var what := Label.new()
		what.text = a[1]
		what.custom_minimum_size.x = 300
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(what)
		Controls.using_gamepad = false
		grid.add_child(_key_cell(a[2] if not a[2].is_empty() else Controls.label_for(a[0])))
		Controls.using_gamepad = true
		grid.add_child(_key_cell(a[3] if not a[3].is_empty() else Controls.label_for(a[0])))
	Controls.using_gamepad = pad
	UIAnim.show(_controls, Vector2(16, 0))


func _key_cell(text: String) -> Control:
	var c := HBoxContainer.new()
	c.add_child(UITheme.keycap(text))
	return c


func _settings() -> void:
	_root.visible = false
	var s := SettingsPanel.new()
	add_child(s)
	s.closed.connect(func(): _root.visible = true)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 42
	b.pressed.connect(action)
	parent.add_child(b)
	return b

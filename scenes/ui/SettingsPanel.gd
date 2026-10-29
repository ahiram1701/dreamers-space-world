class_name SettingsPanel
extends CanvasLayer
## Ajustes del jugador: IA, controles, sonido y actualizaciones. Se usa en el menú y en la pausa.

signal closed

var _key: LineEdit
var _model: LineEdit
var _mock: CheckBox
var _updates: CheckBox
var _sens: HSlider
var _volume: HSlider
var _status: Label


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	UIStyle.apply(panel)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Ajustes"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	_section(box, "Inteligencia artificial (Ollama Cloud)")
	_key = _line(box, "API key de Ollama Cloud", Settings.api_key, true)
	_model = _line(box, "Modelo (por defecto %s)" % Settings.DEFAULT_MODEL, Settings.model, false)
	_mock = _check(box, "Modo sin conexión (respuestas predefinidas, sin IA)", Settings.use_mock)

	_section(box, "Controles y sonido")
	_sens = _slider(box, "Sensibilidad del ratón", 0.3, 3.0, Settings.mouse_sensitivity)
	_volume = _slider(box, "Volumen", 0.0, 1.0, Settings.volume)
	_volume.value_changed.connect(func(v): AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001))))

	_section(box, "Actualizaciones")
	_updates = _check(box, "Buscar actualizaciones al iniciar", Settings.auto_check_updates)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("#9fd8ff"))
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cerrar"
	cancel.pressed.connect(_close)
	row.add_child(cancel)
	var save := Button.new()
	save.text = "Guardar"
	save.pressed.connect(_save)
	row.add_child(save)


func _save() -> void:
	Settings.api_key = _key.text.strip_edges()
	var model := _model.text.strip_edges()
	Settings.model = model if not model.is_empty() else Settings.DEFAULT_MODEL
	Settings.use_mock = _mock.button_pressed
	Settings.auto_check_updates = _updates.button_pressed
	Settings.mouse_sensitivity = _sens.value
	Settings.volume = _volume.value
	Settings.save_settings()
	_status.text = "Guardado."
	_close()


func _close() -> void:
	Settings._apply_volume()  # deshace la vista previa si no se guardó
	closed.emit()
	queue_free()


func _section(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#f2a65a"))
	parent.add_child(l)


func _line(parent: Node, placeholder: String, value: String, secret: bool) -> LineEdit:
	var l := LineEdit.new()
	l.placeholder_text = placeholder
	l.text = value
	l.secret = secret
	parent.add_child(l)
	return l


func _check(parent: Node, text: String, value: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	parent.add_child(c)
	return c


func _slider(parent: Node, text: String, min_v: float, max_v: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	return s

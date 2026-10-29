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
var _quality: OptionButton
var _figure: OptionButton
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
	var test := Button.new()
	test.text = "Probar conexión con la IA"
	test.pressed.connect(_test_connection.bind(test))
	box.add_child(test)

	_section(box, "Controles y sonido")
	_sens = _slider(box, "Sensibilidad del ratón", 0.3, 3.0, Settings.mouse_sensitivity)
	_volume = _slider(box, "Volumen", 0.0, 1.0, Settings.volume)
	_volume.value_changed.connect(func(v): AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001))))

	_section(box, "Imagen y personaje")
	_quality = _option(box, "Calidad gráfica", ["Baja (PCs modestos)", "Media", "Alta"], Settings.graphics_quality)
	_figure = _option(box, "Tu personaje", ["Lo decide el mundo", "Hombre", "Mujer"],
		["", "masculine", "feminine"].find(Settings.player_figure))

	_section(box, "Actualizaciones")
	_updates = _check(box, "Buscar actualizaciones al iniciar", Settings.auto_check_updates)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 480
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


## Prueba la key y el modelo escritos (aunque no estén guardados) con un turno de diálogo real.
func _test_connection(button: Button) -> void:
	var saved := [Settings.api_key, Settings.model, Settings.use_mock]
	Settings.api_key = _key.text.strip_edges()
	var model := _model.text.strip_edges()
	Settings.model = model if not model.is_empty() else Settings.DEFAULT_MODEL
	Settings.use_mock = false
	button.disabled = true
	_status.text = "Probando %s…" % Settings.model
	var t0 := Time.get_ticks_msec()
	var r := await ContentGenerator.request_valid("dialogue_turn", [
		{"role": "system", "content": "Eres un personaje de un videojuego de ciencia ficción."},
		{"role": "user", "content": "Saluda al jugador en una frase."}])
	var ms := Time.get_ticks_msec() - t0
	Settings.api_key = saved[0]
	Settings.model = saved[1]
	Settings.use_mock = saved[2]
	button.disabled = false
	if r.ok:
		_status.text = "Conexión correcta (%.1f s): «%s»  — pulsa Guardar para usar este modelo." % [ms / 1000.0, str(r.data.line).left(80)]
	else:
		_status.text = "No funciona: %s" % str(r.errors[0] if not r.errors.is_empty() else "sin respuesta").left(160)


func _save() -> void:
	Settings.api_key = _key.text.strip_edges()
	var model := _model.text.strip_edges()
	Settings.model = model if not model.is_empty() else Settings.DEFAULT_MODEL
	Settings.use_mock = _mock.button_pressed
	Settings.auto_check_updates = _updates.button_pressed
	Settings.mouse_sensitivity = _sens.value
	Settings.volume = _volume.value
	Settings.graphics_quality = _quality.selected
	Settings.player_figure = ["", "masculine", "feminine"][maxi(_figure.selected, 0)]
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


func _option(parent: Node, text: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.selected = maxi(selected, 0)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	return o


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

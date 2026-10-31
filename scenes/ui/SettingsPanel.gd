class_name SettingsPanel
extends CanvasLayer
## Ajustes del jugador: IA, controles, sonido y actualizaciones. Se usa en el menú y en la pausa.

signal closed

const DAY_OPTIONS := [24.0, 60.0, 120.0, 240.0, 1440.0]
const UI_SIZES := [0.0, 0.85, 1.0, 1.15, 1.3]

var _key: LineEdit
var _model: LineEdit
var _mock: CheckBox
var _updates: CheckBox
var _sens: HSlider
var _volume: HSlider
var _music: HSlider
var _quality: OptionButton
var _figure: OptionButton
var _day: OptionButton
var _fov: HSlider
var _invert: CheckBox
var _status: Label
var _text_speed: HSlider
var _ui_size: OptionButton
var _window: OptionButton
var _fps: OptionButton
var _vsync: CheckBox
var _show_fps: CheckBox
var _text_scale: HSlider


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	# Anclado a la pantalla (no un tamaño fijo): cabe en cualquier ventana
	var panel := PanelContainer.new()
	panel.anchor_left = 0.18
	panel.anchor_right = 0.82
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95
	UIStyle.apply(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Ajustes"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	var game := _page(tabs, "Juego")
	var gfx := _page(tabs, "Imagen")
	var sound := _page(tabs, "Sonido")
	var controls := _page(tabs, "Controles")
	var ai := _page(tabs, "IA")

	_figure = _option(game, "Tu personaje", ["Lo decide el mundo", "Hombre", "Mujer"],
		["", "masculine", "feminine"].find(Settings.player_figure))
	_day = _option(game, "Duración del día", ["24 minutos", "1 hora", "2 horas", "4 horas", "Tiempo real (24 h)"],
		DAY_OPTIONS.find(Settings.day_minutes) if DAY_OPTIONS.has(Settings.day_minutes) else 2)
	_text_speed = _slider(game, "Velocidad del texto", 0.5, 3.0, Settings.text_speed)
	_updates = _check(game, "Buscar actualizaciones al iniciar", Settings.auto_check_updates)

	_quality = _option(gfx, "Calidad gráfica", ["Baja (PCs modestos)", "Media", "Alta"], Settings.graphics_quality)
	_fov = _slider(gfx, "Campo de visión de la cámara", 55.0, 95.0, Settings.fov)
	_fov.step = 1.0
	_window = _option(gfx, "Pantalla (F11 alterna)", ["Ventana maximizada", "Pantalla completa", "Ventana"], maxi(Display.MODES.find(Settings.window_mode), 0))
	_fps = _option(gfx, "Límite de FPS", ["30", "60", "120", "Sin límite"], maxi(Display.FPS_OPTIONS.find(Settings.max_fps), 1))
	_vsync = _check(gfx, "Sincronización vertical (VSync)", Settings.vsync)
	_show_fps = _check(gfx, "Mostrar FPS", Settings.show_fps)
	_ui_size = _option(gfx, "Tamaño de la interfaz", ["Automático", "Pequeño", "Normal", "Grande", "Muy grande"],
		maxi(UI_SIZES.find(Settings.ui_scale), 0))
	_text_scale = _slider(gfx, "Tamaño del texto", 0.85, 1.4, Settings.text_scale)

	_volume = _slider(sound, "Volumen", 0.0, 1.0, Settings.volume)
	_volume.value_changed.connect(func(v): AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001))))
	_music = _slider(sound, "Música (0 = sin música)", 0.0, 1.0, Settings.music_volume)
	_music.value_changed.connect(func(v): Settings.music_volume = v)

	_sens = _slider(controls, "Sensibilidad del ratón y del stick", 0.3, 3.0, Settings.mouse_sensitivity)
	_invert = _check(controls, "Invertir el eje vertical de la cámara", Settings.invert_y)
	var hint := Label.new()
	hint.text = "La lista completa de controles (teclado y mando) está en la pausa → Controles."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	controls.add_child(hint)

	_section(ai, "Ollama Cloud")
	_key = _line(ai, "API key de Ollama Cloud", Settings.api_key, true)
	_model = _line(ai, "Modelo (por defecto %s)" % Settings.DEFAULT_MODEL, Settings.model, false)
	_mock = _check(ai, "Modo sin conexión (respuestas predefinidas, sin IA)", Settings.use_mock)
	var test := Button.new()
	test.text = "Probar conexión con la IA"
	test.pressed.connect(_test_connection.bind(test))
	ai.add_child(test)

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
	Settings.music_volume = _music.value
	Settings.graphics_quality = _quality.selected
	Settings.player_figure = ["", "masculine", "feminine"][maxi(_figure.selected, 0)]
	Settings.day_minutes = DAY_OPTIONS[maxi(_day.selected, 0)]
	Settings.fov = _fov.value
	Settings.text_speed = _text_speed.value
	Settings.ui_scale = UI_SIZES[maxi(_ui_size.selected, 0)]
	Settings.window_mode = Display.MODES[maxi(_window.selected, 0)]
	Settings.max_fps = Display.FPS_OPTIONS[maxi(_fps.selected, 0)]
	Settings.vsync = _vsync.button_pressed
	Settings.show_fps = _show_fps.button_pressed
	Settings.text_scale = _text_scale.value
	Settings.invert_y = _invert.button_pressed
	Settings.save_settings()
	_status.text = "Guardado."
	_close()


func _close() -> void:
	Settings._apply_volume()  # deshace la vista previa si no se guardó
	closed.emit()
	queue_free()


func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()  # si no cabe, se desplaza
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	return v


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

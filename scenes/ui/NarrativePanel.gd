class_name NarrativePanel
extends CanvasLayer
## Panel grande de narración con decisiones (El Despertar, el final).
## Uso:  panel.present(bbcode, "¿Qué haces?", ["opción A", "opción B"])  →  signal chosen(index)

signal chosen(index: int)

var _text: RichTextLabel
var _ask: Label
var _choices: VBoxContainer
var _panel: PanelContainer
var _reveal: Tween


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 0.06
	_panel.anchor_bottom = 0.94
	UIStyle.apply(_panel)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)
	_text.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_skip())
	_ask = Label.new()
	_ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ask.add_theme_color_override("font_color", Color("#f2a65a"))
	box.add_child(_ask)
	_choices = VBoxContainer.new()
	box.add_child(_choices)
	visible = false


func present(bbcode: String, ask: String, options: Array) -> void:
	_text.text = bbcode
	_ask.text = ask
	_text.visible_ratio = 0.0
	_reveal = create_tween()
	_reveal.tween_property(_text, "visible_ratio", 1.0, clampf(_text.get_total_character_count() * 0.012, 2.0, 9.0) / maxf(0.25, Settings.text_speed))
	set_options(options)
	visible = true


## Panel pequeño y centrado (una decisión tras una escena), por encima de las bandas de cine.
func set_compact() -> void:
	layer = 40
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_text.fit_content = true
	_text.size_flags_vertical = Control.SIZE_FILL


## Sustituye las opciones (p. ej. por un botón de reintentar).
func set_options(options: Array) -> void:
	for c in _choices.get_children():
		c.queue_free()
	for i in options.size():
		var b := Button.new()
		b.text = "› " + str(options[i])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(_on_pressed.bind(i))
		_choices.add_child(b)


## Un clic en el texto (o espacio) lo muestra entero de golpe.
func _skip() -> void:
	if _reveal and _reveal.is_valid():
		_reveal.kill()
	_text.visible_ratio = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept") and _text.visible_ratio < 1.0:
		_skip()
		get_viewport().set_input_as_handled()


func _on_pressed(index: int) -> void:
	for b in _choices.get_children():
		b.disabled = true
	chosen.emit(index)

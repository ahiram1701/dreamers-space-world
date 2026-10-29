class_name NarrativePanel
extends CanvasLayer
## Panel grande de narración con decisiones (El Despertar, el final).
## Uso:  panel.present(bbcode, "¿Qué haces?", ["opción A", "opción B"])  →  signal chosen(index)

signal chosen(index: int)

var _text: RichTextLabel
var _ask: Label
var _choices: VBoxContainer
var _panel: PanelContainer


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
	_ask = Label.new()
	_ask.add_theme_color_override("font_color", Color("#f2a65a"))
	box.add_child(_ask)
	_choices = VBoxContainer.new()
	box.add_child(_choices)
	visible = false


func present(bbcode: String, ask: String, options: Array) -> void:
	_text.text = bbcode
	_ask.text = ask
	_text.visible_ratio = 0.0
	create_tween().tween_property(_text, "visible_ratio", 1.0, clampf(_text.get_total_character_count() * 0.012, 2.0, 9.0))
	set_options(options)
	visible = true


## Sustituye las opciones (p. ej. por un botón de reintentar).
func set_options(options: Array) -> void:
	for c in _choices.get_children():
		c.queue_free()
	for i in options.size():
		var b := Button.new()
		b.text = "› " + str(options[i])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_pressed.bind(i))
		_choices.add_child(b)


func _on_pressed(index: int) -> void:
	for b in _choices.get_children():
		b.disabled = true
	chosen.emit(index)

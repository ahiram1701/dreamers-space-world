class_name LoadingOverlay
extends CanvasLayer
## Pantalla de espera mientras la IA trabaja (generar el Despertar, calcular un salto).

var _label: Label
var _detail: Label
var _t := 0.0
var _messages: PackedStringArray = []


func _ready() -> void:
	layer = 30
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	box.add_child(_label)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
	box.add_child(_detail)


## messages: frases que van rotando abajo ("Calculando trayectoria…", …).
func show_loading(title: String, messages: PackedStringArray = []) -> void:
	_label.text = title
	_messages = messages
	_detail.text = messages[0] if not messages.is_empty() else ""
	_t = 0.0
	visible = true


func hide_loading() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible or _messages.is_empty():
		return
	_t += delta
	_detail.text = _messages[int(_t / 2.2) % _messages.size()] + ".".repeat(int(_t * 2.0) % 4)

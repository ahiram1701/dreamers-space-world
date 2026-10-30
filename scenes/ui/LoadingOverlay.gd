class_name LoadingOverlay
extends CanvasLayer
## Pantalla de espera mientras la IA trabaja (generar el Despertar, calcular un salto).
## Con `tunnel = true` muestra el túnel del salto en lugar del fondo liso.

const TUNNEL_SHADER := preload("res://scenes/ui/tunnel.gdshader")

var _bg: ColorRect
var _tunnel: ColorRect
var _label: Label
var _detail: Label
var _t := 0.0
var _messages: PackedStringArray = []
var _tip: Label

## Consejos que se ven mientras esperas.
const TIPS := [
	"Con F puedes hacer cualquier cosa: escríbela y tu personaje la hace. El mundo reacciona.",
	"La gente recuerda lo que haces, lo cuenta a otros y te trata en consecuencia.",
	"Si alguien te cobra, paga con el botón Pagar o diciéndoselo. Sin dinero no se compra.",
	"Tienes hambre, sed, sueño e higiene: come, bebe, duerme en una cama y dúchate en casa.",
	"Lo que pidas con sentido puede aparecer y quedarse: un fontanero, una panadería…",
	"En el Cuaderno (I) están tus objetos, encargos, el diario y la gente que conoces.",
	"La rueda del ratón acerca la cámara; al máximo, ves con los ojos de tu personaje.",
	"Cada mundo es único: tus decisiones moldean el multiverso que se genera después.",
]


func _ready() -> void:
	layer = 30
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.03, 0.08, 0.92)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_tunnel = ColorRect.new()
	_tunnel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = TUNNEL_SHADER
	_tunnel.material = mat
	_tunnel.visible = false
	add_child(_tunnel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(_label)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_detail.add_theme_constant_override("outline_size", 6)
	_detail.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(_detail)
	_tip = Label.new()
	_tip.anchor_left = 0.15
	_tip.anchor_right = 0.85
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_top = -90
	_tip.offset_bottom = -40
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", UITheme.MUTED)
	_tip.add_theme_font_size_override("font_size", 16)
	add_child(_tip)


## messages: frases que van rotando abajo ("Calculando trayectoria…", …).
func show_loading(title: String, messages: PackedStringArray = [], tunnel: bool = false) -> void:
	_label.text = title
	_messages = messages
	_detail.text = messages[0] if not messages.is_empty() else ""
	_tunnel.visible = tunnel
	_bg.visible = not tunnel
	_t = 0.0
	_tip.text = "Consejo: " + TIPS[randi() % TIPS.size()]
	visible = true


func hide_loading() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible or _messages.is_empty():
		return
	_t += delta
	if int(_t) % 7 == 0 and int(_t - delta) % 7 != 0:
		_tip.text = "Consejo: " + TIPS[randi() % TIPS.size()]
	_detail.text = _messages[int(_t / 2.2) % _messages.size()] + ".".repeat(int(_t * 2.0) % 4)

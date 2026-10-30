extends Node
## Aspecto de toda la interfaz: fuente del sistema, paleta, botones con estados, campos de texto,
## barras, pestañas… Se construye una vez y se aplica a la ventana, así cualquier Control lo hereda.

const BG := Color(0.035, 0.05, 0.085, 0.93)
const BG_SOFT := Color(0.07, 0.095, 0.15, 0.92)
const LINE := Color(0.45, 0.85, 1.0, 0.35)
const ACCENT := Color("#73d9ff")
const TEXT := Color("#e8eef6")
const MUTED := Color("#93a4b8")
const GOOD := Color("#7ee08a")
const WARN := Color("#f2c14e")
const DANGER := Color("#ef6b6b")
const MONEY := Color("#ffd27a")

var theme: Theme
var font: Font
var font_bold: Font


func _ready() -> void:
	font = _system_font(400)
	font_bold = _system_font(650)
	theme = _build()
	get_tree().root.theme = theme
	apply_scale()
	Settings.changed.connect(apply_scale)


## Escala de la interfaz (ajuste del jugador, 0.85 a 1.3).
func apply_scale() -> void:
	get_tree().root.content_scale_factor = clampf(Settings.ui_scale, 0.85, 1.3)
	if theme:
		theme.default_font_size = roundi(17 * Settings.text_scale)


func _system_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Variable Text", "Segoe UI", "Inter", "Noto Sans", "Ubuntu", "Cantarell", "Helvetica", "Arial"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_LCD if OS.get_name() == "Windows" else TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


## Caja redondeada con fondo, borde y márgenes.
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, margin: float = 12.0, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 17

	# Paneles
	t.set_stylebox("panel", "PanelContainer", box(BG, LINE, 14, 20))
	t.set_stylebox("panel", "Panel", box(BG, LINE, 14, 0))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", font_bold)

	# Botones: discretos en reposo, se iluminan al pasar o al tener foco (mando/teclado)
	var normal := box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.08), 9, 10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate()
	hover.bg_color = Color(ACCENT, 0.18)
	hover.border_color = Color(ACCENT, 0.55)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(ACCENT, 0.32)
	pressed.border_color = ACCENT
	var focus := normal.duplicate()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(1, 1, 1, 0.03)
	disabled.border_color = Color(1, 1, 1, 0.04)
	for type in ["Button", "MenuButton", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.5))
		t.set_font("font", type, font_bold)

	# Campos de texto
	var field := box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.12), 9, 10)
	var field_focus := field.duplicate()
	field_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.75))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)

	# Barras
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 3, 2))
	t.set_stylebox("grabber_area", "HSlider", box(Color(ACCENT, 0.6), Color(0, 0, 0, 0), 3, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 3, 2))

	# Desplazamiento fino
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 2))
		t.set_stylebox("grabber", sb, box(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 4, 2))
		t.set_stylebox("grabber_highlight", sb, box(Color(ACCENT, 0.5), Color(0, 0, 0, 0), 4, 2))
		t.set_stylebox("grabber_pressed", sb, box(ACCENT, Color(0, 0, 0, 0), 4, 2))

	# Pestañas
	var tab := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8, 10)
	tab.content_margin_left = 16
	tab.content_margin_right = 16
	var tab_sel := tab.duplicate()
	tab_sel.bg_color = Color(ACCENT, 0.16)
	tab_sel.border_color = ACCENT
	tab_sel.border_width_bottom = 2
	t.set_stylebox("tab_unselected", "TabBar", tab)
	t.set_stylebox("tab_hovered", "TabBar", tab)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", tab)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", font_bold)

	# Menús emergentes y avisos
	t.set_stylebox("panel", "PopupMenu", box(BG, LINE, 10, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.2), Color(0, 0, 0, 0), 6, 6))
	t.set_stylebox("panel", "TooltipPanel", box(BG, LINE, 8, 8))
	t.set_stylebox("panel", "AcceptDialog", box(BG, LINE, 14, 18))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 4))
	t.set_stylebox("hover", "CheckBox", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 6, 4))
	t.set_stylebox("focus", "CheckBox", box(Color(0, 0, 0, 0), ACCENT, 6, 4))
	return t


## Etiqueta de tecla dibujada ("E" en una cajita), para avisos y consejos.
static func keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color(1, 1, 1, 0.92), Color(0, 0, 0, 0), 6, 4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#0b1220"))
	l.add_theme_font_size_override("font_size", 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

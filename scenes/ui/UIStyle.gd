class_name UIStyle
extends RefCounted
## Estilo común de los paneles (el resto lo da el tema global, autoload UITheme).


static func panel(accent: Color = UITheme.ACCENT) -> StyleBoxFlat:
	return UITheme.box(UITheme.BG, Color(accent, 0.35), 14, 20)


static func apply(panel_container: PanelContainer, accent: Color = UITheme.ACCENT) -> void:
	panel_container.add_theme_stylebox_override("panel", panel(accent))

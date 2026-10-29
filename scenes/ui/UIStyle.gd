class_name UIStyle
extends RefCounted
## Estilo común de los paneles: fondo oscuro casi opaco para que el texto no se mezcle con el 3D.


static func panel(accent: Color = Color("#73d9ff")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.1, 0.94)
	style.border_color = accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	return style


static func apply(panel_container: PanelContainer, accent: Color = Color("#73d9ff")) -> void:
	panel_container.add_theme_stylebox_override("panel", panel(accent))

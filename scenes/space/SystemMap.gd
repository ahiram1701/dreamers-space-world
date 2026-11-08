class_name SystemMap
extends Control
## El mapa del sistema solar (M en el espacio): las órbitas, los planetas, la estación, el
## cinturón, tu nave y el destino. Un clic en un planeta lo marca como destino; «Ir» activa el
## piloto automático.

signal target_chosen(index: int, go: bool)

var system: Dictionary = {}
var ship_pos := Vector3.ZERO
var target := 0
var _scale := 1.0
var _go: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport().get_visible_rect().size  # (en un CanvasLayer no hay padre que le dé tamaño)
	get_viewport().size_changed.connect(func(): size = get_viewport().get_visible_rect().size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := Label.new()
	title.text = "Mapa del sistema · clic en un planeta para marcarlo · M para cerrar"
	title.position = Vector2(24, 18)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	_go = Button.new()
	_go.text = "Ir allí (piloto automático)"
	_go.position = Vector2(24, 52)
	_go.pressed.connect(func(): target_chosen.emit(target, true))
	add_child(_go)


func _process(_delta: float) -> void:
	queue_redraw()


func _to_screen(p: Vector3) -> Vector2:
	return size / 2.0 + Vector2(p.x, p.z) * _scale


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.05, 0.92))
	var far := 1.0
	for p in system.get("planets", []):
		far = maxf(far, StarSystem.position_of(p).length())
	_scale = minf(size.x, size.y) * 0.45 / far
	draw_circle(size / 2.0, 7.0, Color("#ffd27a"))  # el sol
	var belt := float(system.get("belt", 0.0))
	if belt > 0.0:
		draw_arc(size / 2.0, belt * _scale, 0, TAU, 96, Color(0.6, 0.5, 0.4, 0.35), 6.0)
	var font := ThemeDB.fallback_font
	for i in system.get("planets", []).size():
		var p: Dictionary = system.planets[i]
		var pos := StarSystem.position_of(p)
		draw_arc(size / 2.0, Vector2(pos.x, pos.z).length() * _scale, 0, TAU, 96, Color(1, 1, 1, 0.12), 1.0)
		var sp := _to_screen(pos)
		var col := Color("#ffe066") if i == target else (Color("#9fd0ff") if p.kind != "station" else Color("#c8c8c8"))
		draw_circle(sp, 6.0 if p.kind != "gas" else 9.0, col)
		draw_string(font, sp + Vector2(10, 5), "%s%s" % [p.name, "  (tu planeta)" if p.get("home", false) else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	var ss := _to_screen(ship_pos)
	draw_circle(ss, 4.0, Color("#7cffb0"))
	draw_string(font, ss + Vector2(8, -6), "tú", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7cffb0"))
	if target >= 0 and target < system.get("planets", []).size():
		draw_dashed_line(ss, _to_screen(StarSystem.position_of(system.planets[target])), Color(1, 0.9, 0.4, 0.6), 2.0, 8.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best := -1
		var best_d := 24.0
		for i in system.get("planets", []).size():
			var d := _to_screen(StarSystem.position_of(system.planets[i])).distance_to(event.position)
			if d < best_d:
				best = i
				best_d = d
		if best >= 0:
			target = best
			target_chosen.emit(best, false)

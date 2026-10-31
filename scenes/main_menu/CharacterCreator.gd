class_name CharacterCreator
extends CanvasLayer
## Crear (o cambiar) a tu personaje: nombre, hombre o mujer, complexión, ropa y colores, con una
## vista previa en 3D que gira. Se usa al empezar una vida nueva y desde la pausa ("Tu aspecto").

signal done(look: Dictionary, player_name: String)
signal cancelled

## Pedir el nombre (al empezar una vida; desde la pausa ya lo tienes).
var ask_name := true
var look := {"figure": "", "body": "average", "outfit": "casual", "primary_color": "#3b6ea5", "secondary_color": "#2b2f3a"}

var _name: LineEdit
var _status: Label
var _figure_btns: Array = []
var _viewport: SubViewport
var _holder: Node3D
var _turn := 0.0


func _ready() -> void:
	layer = 45
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	UIStyle.apply(panel)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)

	# Vista previa
	var view := SubViewportContainer.new()
	view.stretch = true
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_stretch_ratio = 0.9
	row.add_child(view)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	view.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#b8c4d8")
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.3
	world.add_child(key)
	var cam := Camera3D.new()
	cam.fov = 32
	world.add_child(cam)
	cam.position = Vector3(0, 1.05, 4.6)
	cam.look_at(Vector3(0, 0.95, 0))
	_holder = Node3D.new()
	world.add_child(_holder)

	# Opciones (con scroll) y, debajo y siempre a la vista, el aviso y los botones
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Tu personaje" if ask_name else "Tu aspecto"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_font_override("font", UITheme.font_bold)
	box.add_child(title)
	if ask_name:
		_name = LineEdit.new()
		_name.placeholder_text = "¿Cómo te llamas?"
		_name.max_length = 30
		box.add_child(_name)
	_section(box, "Eres")
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 8)
	box.add_child(figures)
	for f in [["masculine", "Hombre"], ["feminine", "Mujer"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 40)
		b.button_pressed = look.figure == f[0]
		b.pressed.connect(func(): _choose("figure", f[0]))
		figures.add_child(b)
		_figure_btns.append([b, f[0]])
	_choice(box, "Complexión", PlayerLook.BODY_LABELS, PlayerLook.BODIES, "body")
	_choice(box, "Ropa", PlayerLook.OUTFIT_LABELS, PlayerLook.OUTFITS, "outfit")
	_swatches(box, "Color principal", "primary_color")
	_swatches(box, "Color secundario", "secondary_color")
	_status = Label.new()
	_status.add_theme_color_override("font_color", UITheme.WARN)
	side.add_child(_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	side.add_child(actions)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func(): cancelled.emit(); queue_free())
	actions.add_child(back)
	var go := Button.new()
	go.text = "Empezar" if ask_name else "Guardar"
	go.custom_minimum_size = Vector2(140, 42)
	go.pressed.connect(_finish)
	actions.add_child(go)
	_rebuild_preview()
	if _name:
		_name.grab_focus.call_deferred()


func _section(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITheme.MUTED)
	parent.add_child(l)


func _choice(parent: Node, label: String, labels: Array, values: Array, key: String) -> void:
	_section(parent, label)
	var opt := OptionButton.new()
	for l in labels:
		opt.add_item(l)
	opt.selected = maxi(values.find(look.get(key, values[0])), 0)
	opt.item_selected.connect(func(i): _choose(key, values[i]))
	parent.add_child(opt)


func _swatches(parent: Node, label: String, key: String) -> void:
	_section(parent, label)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	parent.add_child(row)
	for c in PlayerLook.COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.tooltip_text = c
		var sb := UITheme.box(Color(c), Color(1, 1, 1, 0.25), 17, 0)
		b.add_theme_stylebox_override("normal", sb)
		var sb_h := sb.duplicate()
		sb_h.border_color = Color.WHITE
		sb_h.set_border_width_all(3)
		b.add_theme_stylebox_override("hover", sb_h)
		b.add_theme_stylebox_override("pressed", sb_h)
		b.add_theme_stylebox_override("focus", sb_h)
		b.pressed.connect(func(): _choose(key, c))
		row.add_child(b)


func _choose(key: String, value: String) -> void:
	look[key] = value
	if key == "figure":
		for pair in _figure_btns:
			pair[0].button_pressed = pair[1] == value
		_status.text = ""
	_rebuild_preview()


func _rebuild_preview() -> void:
	for c in _holder.get_children():
		c.queue_free()
	var preview := look.duplicate()
	if str(preview.figure).is_empty():
		preview.figure = "masculine"
	PlayerLook.build(_holder, preview, 7)


func _process(delta: float) -> void:
	_turn += delta * 0.6
	_holder.rotation.y = sin(_turn) * 0.9


func _finish() -> void:
	if str(look.figure).is_empty():
		_status.text = "Elige si eres hombre o mujer."
		return
	var player_name := _name.text.strip_edges() if _name else ""
	if ask_name and player_name.is_empty():
		_status.text = "Escribe tu nombre."
		_name.grab_focus()
		return
	done.emit(look.duplicate(), player_name)
	queue_free()

class_name CharacterCreator
extends CanvasLayer
## Tu aspecto, con una vista previa en 3D que gira. Según `mode`:
##   "new"       al empezar una vida: nombre, hombre o mujer, piel, pelo, altura, complexión y ropa;
##   "body"      desde la pausa: solo corregir rasgos del cuerpo (lo demás se cambia en el mundo);
##   "hair"      en la peluquería: peinado y color de pelo (se paga);
##   "wardrobe"  en el armario de casa: qué ropa te pones de la que tienes;
##   "shop"      en la tienda de ropa: qué compras (y te lo pruebas antes).

signal done(look: Dictionary, player_name: String)
signal cancelled

var mode := "new"
## Pedir el nombre (al empezar una vida). Se mantiene por compatibilidad: false = modo "body".
var ask_name := true:
	set(v):
		ask_name = v
		if not v and mode == "new":
			mode = "body"
var look := {"figure": "", "body": "average", "outfit": "casual", "primary_color": "#3b6ea5", "secondary_color": "#2b2f3a"}
## "wardrobe": ids de la ropa que tienes. "shop": ofertas [{name, clothing, price}].
var choices: Array = []
## Lo que cuesta cambiar de peinado y de color en la peluquería.
const HAIRCUT := 18
const DYE := 22

var _name: LineEdit
var _status: Label
var _go: Button
var _figure_btns: Array = []
var _hair_opt: OptionButton
var _height_label: Label
var _viewport: SubViewport
var _holder: Node3D
var _turn := 0.0
var _start := {}
var _pick := 0


func _ready() -> void:
	layer = 45
	_start = look.duplicate()
	if not look.has("hair"):
		look["hair"] = AssetLibrary.HAIRSTYLES[_fig()][0][0]
	if not look.has("hair_color"):
		look["hair_color"] = AssetLibrary.HAIR_COLORS[1]
	if not look.has("skin"):
		look["skin"] = AssetLibrary.SKINS[1]
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
	cam.position = Vector3(0, 1.05, 4.6) if mode != "hair" else Vector3(0, 1.55, 1.9)
	cam.look_at(Vector3(0, 0.95, 0) if mode != "hair" else Vector3(0, 1.55, 0))
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
	title.text = {"new": "Tu personaje", "body": "Tu cuerpo", "hair": "Peluquería", "wardrobe": "Tu armario", "shop": "Tienda de ropa"}.get(mode, "Tu aspecto")
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_font_override("font", UITheme.font_bold)
	box.add_child(title)
	match mode:
		"new":
			_name = LineEdit.new()
			_name.placeholder_text = "¿Cómo te llamas?"
			_name.max_length = 30
			box.add_child(_name)
			_figures(box)
			_body_options(box)
			_hair_options(box)
			_choice(box, "Ropa", PlayerLook.OUTFIT_LABELS, PlayerLook.OUTFITS, "outfit")
			_swatches(box, "Color principal", "primary_color", PlayerLook.COLORS)
			_swatches(box, "Color secundario", "secondary_color", PlayerLook.COLORS)
		"body":
			_note(box, "La ropa te la cambias en el armario de casa y el pelo en la peluquería.")
			_figures(box)
			_body_options(box)
		"hair":
			_note(box, "Corte: $%d. Tinte: $%d más." % [HAIRCUT, DYE])
			_hair_options(box)
		"wardrobe", "shop":
			_clothes_list(box)
	_status = Label.new()
	_status.add_theme_color_override("font_color", UITheme.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	side.add_child(actions)
	var back := Button.new()
	back.text = "Volver" if mode == "new" else "Salir"
	back.pressed.connect(func(): cancelled.emit(); queue_free())
	actions.add_child(back)
	_go = Button.new()
	_go.custom_minimum_size = Vector2(160, 42)
	_go.pressed.connect(_finish)
	actions.add_child(_go)
	_refresh_go()
	_rebuild_preview()
	if _name:
		_name.grab_focus.call_deferred()
	else:
		_go.grab_focus.call_deferred()


func _fig() -> String:
	return "feminine" if look.get("figure", "") == "feminine" else "masculine"


func _section(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITheme.MUTED)
	parent.add_child(l)


func _note(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UITheme.MUTED)
	parent.add_child(l)


func _figures(box: Node) -> void:
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


func _body_options(box: Node) -> void:
	_swatches(box, "Tono de piel", "skin", AssetLibrary.SKINS)
	_section(box, "Altura")
	var line := HBoxContainer.new()
	box.add_child(line)
	var slider := HSlider.new()
	slider.min_value = PlayerLook.HEIGHT_MIN
	slider.max_value = PlayerLook.HEIGHT_MAX
	slider.step = 0.01
	slider.value = float(look.get("height", 1.75))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(slider)
	_height_label = Label.new()
	_height_label.custom_minimum_size.x = 70
	line.add_child(_height_label)
	_height_label.text = ("%.2f m" % slider.value).replace(".", ",")
	slider.value_changed.connect(func(v):
		look["height"] = snappedf(v, 0.01)
		_height_label.text = ("%.2f m" % v).replace(".", ",")
		_rebuild_preview())
	_choice(box, "Complexión", PlayerLook.BODY_LABELS, PlayerLook.BODIES, "body")


func _hair_options(box: Node) -> void:
	_section(box, "Peinado")
	_hair_opt = OptionButton.new()
	box.add_child(_hair_opt)
	_fill_hair()
	_hair_opt.item_selected.connect(func(i): _choose("hair", AssetLibrary.HAIRSTYLES[_fig()][i][0]))
	_swatches(box, "Color de pelo", "hair_color", AssetLibrary.HAIR_COLORS)


func _fill_hair() -> void:
	if _hair_opt == null:
		return
	_hair_opt.clear()
	var styles: Array = AssetLibrary.HAIRSTYLES[_fig()]
	var at := 0
	for i in styles.size():
		_hair_opt.add_item(styles[i][1])
		if styles[i][0] == look.get("hair", ""):
			at = i
	_hair_opt.selected = at
	look["hair"] = styles[at][0]


## Armario o tienda: una lista de conjuntos (te lo pruebas al elegirlo).
func _clothes_list(box: Node) -> void:
	if choices.is_empty():
		_note(box, "No tienes otra ropa aquí." if mode == "wardrobe" else "Hoy no queda nada en la tienda.")
		return
	_section(box, "Qué te pones" if mode == "wardrobe" else "Lo que hay hoy")
	var group := ButtonGroup.new()
	for i in choices.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = _choice_label(i)
		b.button_pressed = i == 0
		b.pressed.connect(func(): _pick_clothes(i))
		box.add_child(b)
	_pick_clothes(0)


func _choice_label(i: int) -> String:
	if mode == "shop":
		return "%s   —   %s" % [choices[i].name, Wallet.text(int(choices[i].price))]
	return WorldDB.get_entity("item", choices[i]).get("name", "?")


func _pick_clothes(i: int) -> void:
	_pick = i
	var c: Dictionary = choices[i].clothing if mode == "shop" else WorldDB.get_entity("item", choices[i]).get("clothing", {})
	look.merge(c, true)
	_refresh_go()
	_rebuild_preview()


func _choice(parent: Node, label: String, labels: Array, values: Array, key: String) -> void:
	_section(parent, label)
	var opt := OptionButton.new()
	for l in labels:
		opt.add_item(l)
	opt.selected = maxi(values.find(look.get(key, values[0])), 0)
	opt.item_selected.connect(func(i): _choose(key, values[i]))
	parent.add_child(opt)


func _swatches(parent: Node, label: String, key: String, colors: Array) -> void:
	_section(parent, label)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	parent.add_child(row)
	for c in colors:
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
		_fill_hair()
	_refresh_go()
	_rebuild_preview()


## Lo que cuesta en la peluquería lo que has elegido.
func hair_price() -> int:
	var p := 0
	if look.get("hair", "") != _start.get("hair", ""):
		p += HAIRCUT
	if look.get("hair_color", "") != _start.get("hair_color", ""):
		p += DYE
	return p


func _refresh_go() -> void:
	if _go == null:
		return
	match mode:
		"new":
			_go.text = "Empezar"
		"hair":
			var p := hair_price()
			_go.text = "Pagar %s" % Wallet.text(p) if p > 0 else "Así está bien"
		"wardrobe":
			_go.text = "Ponértelo"
			_go.disabled = choices.is_empty()
		"shop":
			_go.text = "Comprar (%s)" % Wallet.text(int(choices[_pick].price)) if not choices.is_empty() else "Comprar"
			_go.disabled = choices.is_empty()
		_:
			_go.text = "Guardar"


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
	if mode == "new" and player_name.is_empty():
		_status.text = "Escribe tu nombre."
		_name.grab_focus()
		return
	var out := look.duplicate()
	match mode:
		"hair":
			var p := hair_price()
			if p > 0 and not Wallet.can_pay(p):
				_status.text = "No te alcanza: cuesta %s y llevas %s." % [Wallet.text(p), Wallet.text(Wallet.amount())]
				return
			out["_price"] = p
		"wardrobe":
			out["_item"] = choices[_pick]
		"shop":
			var price := int(choices[_pick].price)
			if not Wallet.can_pay(price):
				_status.text = "No te alcanza: cuesta %s y llevas %s." % [Wallet.text(price), Wallet.text(Wallet.amount())]
				return
			out["_offer"] = choices[_pick]
	done.emit(out, player_name)
	queue_free()

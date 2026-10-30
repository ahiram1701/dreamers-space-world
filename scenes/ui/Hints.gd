class_name Hints
extends CanvasLayer
## Consejos de la primera vez: aparecen cuando algo empieza a ser posible ("E para hablar",
## "F: haz lo que quieras"), uno cada vez, y no se repiten nunca (Settings.seen_hints).
## Muestran las teclas o los botones del mando según con qué estés jugando.

const SHOW_FOR := 6.5

var player: Player

var _queue: Array = []
var _box: PanelContainer
var _row: HBoxContainer
var _showing := false
var _t := 0.0


func _ready() -> void:
	layer = 6
	_box = PanelContainer.new()
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.offset_bottom = -26
	_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.05, 0.09, 0.78), Color(1, 1, 1, 0.08), 12, 12))
	_box.visible = false
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_box.add_child(_row)

	Inventory.changed.connect(func(): show_once("inventory"))
	Wallet.changed.connect(func(_a, d): if d != 0: show_once("money"))
	Body.need_changed.connect(func(_n, v): if v < 40.0: show_once("needs"))
	GameState.stat_changed.connect(func(_s, _v): if GameState.is_awakened(): show_once("anchor"))
	get_tree().create_timer(2.0).timeout.connect(func(): show_once("move"))
	get_tree().create_timer(40.0).timeout.connect(func(): show_once("act"))


## Cada consejo: partes de texto y teclas (["key", "acción del InputMap"]).
func _parts(id: String) -> Array:
	match id:
		"move":
			return [["keys", "WASD"], "moverte  ·  ratón para mirar  ·", ["key", "zoom_in"], "acercar o alejar la cámara"]
		"interact":
			return [["key", "interact"], "habla con la gente, entra en los edificios, siéntate…"]
		"act":
			return [["key", "act"], "Haz lo que quieras: escríbelo y tu personaje lo hará"]
		"inventory":
			return [["key", "inventory"], "Cuaderno: tus objetos, encargos, diario y la gente que conoces"]
		"needs":
			return ["Tu cuerpo necesita cosas: come, bebe, descansa. Pídeselo al mundo con", ["key", "act"]]
		"money":
			return ["Llevas dinero: lo verás arriba a la derecha. Puedes pagar, cobrar y trabajar"]
		"anchor":
			return [["key", "anchor"], "Ancla: salta a otras ramas del multiverso"]
		"pause":
			return [["key", "pause"], "Pausa: ahí tienes todos los controles"]
	return []


func show_once(id: String) -> void:
	if id in Settings.seen_hints or id in _queue or _parts(id).is_empty():
		return
	_queue.append(id)


func _process(delta: float) -> void:
	if player and player.interact_target != null:
		show_once("interact")
	if _showing:
		_t += delta
		if player and not player.controls_enabled:
			_t = SHOW_FOR + 1.0  # se abre un panel o una conversación: el consejo se aparta
		if _t > SHOW_FOR:
			_showing = false
			UIAnim.hide(_box)
		return
	# Solo con las manos libres (sin paneles ni conversaciones abiertos)
	if _queue.is_empty() or (player and not player.controls_enabled):
		return
	var id: String = _queue.pop_front()
	if id in Settings.seen_hints:
		return
	Settings.seen_hints.append(id)
	Settings.save_settings()
	_build(_parts(id))
	_showing = true
	_t = 0.0
	UIAnim.show(_box, Vector2(0, 10))
	if id == "act":
		show_once("pause")


func _build(parts: Array) -> void:
	for c in _row.get_children():
		c.queue_free()
	for p in parts:
		if p is Array:
			_row.add_child(UITheme.keycap(p[1] if p[0] == "keys" else Controls.label_for(p[1])))
		else:
			var l := Label.new()
			l.text = p
			l.add_theme_font_size_override("font_size", 16)
			_row.add_child(l)

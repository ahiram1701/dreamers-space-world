class_name PhonePanel
extends CanvasLayer
## El celular en pantalla (tecla C): mensajes, contactos (llamar o escribir), banco y mapa.
## Es un celular de verdad dentro del juego: si no lo llevas encima, no hay nada que abrir.

signal opened
signal closed
## Llamar a alguien (lo gestiona la escena: abre la conversación en modo llamada).
signal call_requested(npc_id: String)
## Marcar un destino en el mapa (el HUD muestra una flecha hasta él).
signal waypoint_set(label: String, pos: Vector3)

## Lo asigna la escena: sitios con nombre {nombre: Vector3} y dónde está el jugador.
var places: Callable = func(): return {}
var player: Player

var _root: Control
var _phone: PanelContainer
var _screen: VBoxContainer
var _title: Label
var _back: Button
var _clock: Label
var _chat_with := ""
var _chat_list: VBoxContainer
var _chat_scroll: ScrollContainer
var _chat_input: LineEdit
var _app := ""


func _ready() -> void:
	layer = 16
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_phone = PanelContainer.new()
	_phone.anchor_left = 1.0
	_phone.anchor_right = 1.0
	_phone.anchor_top = 1.0
	_phone.anchor_bottom = 1.0
	_phone.offset_left = -410
	_phone.offset_right = -40
	_phone.offset_top = -660
	_phone.offset_bottom = -30
	var frame := UITheme.box(Color("#06080d"), Color(1, 1, 1, 0.16), 34, 14, 2)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 14
	_phone.add_theme_stylebox_override("panel", frame)
	_root.add_child(_phone)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_phone.add_child(col)
	# Barra de estado
	var status := HBoxContainer.new()
	col.add_child(status)
	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", 13)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_clock)
	var battery := Label.new()
	battery.text = "4G  ▮▮▮▯"
	battery.add_theme_font_size_override("font_size", 12)
	battery.add_theme_color_override("font_color", UITheme.MUTED)
	status.add_child(battery)
	var head := HBoxContainer.new()
	col.add_child(head)
	_back = Button.new()
	_back.text = "‹"
	_back.flat = true
	_back.pressed.connect(_home)
	head.add_child(_back)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_font_override("font", UITheme.font_bold)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	_screen = VBoxContainer.new()
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen.add_theme_constant_override("separation", 8)
	col.add_child(_screen)
	Phone.message_received.connect(func(id, _t): if _app == "chat" and id == _chat_with: _show_chat(id))


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if not Phone.has_phone():
		return
	_home()
	UIAnim.show(_root, Vector2.ZERO)
	if player:
		player.play_gesture("read", 600.0)  # mira la pantalla
	opened.emit()


func close() -> void:
	if not _root.visible:
		return
	UIAnim.hide(_root)
	if player:
		player.stop_gesture()
	closed.emit()


func _process(_delta: float) -> void:
	if _root.visible:
		_clock.text = "%s %s" % [WorldClock.weekday().left(3).capitalize(), WorldClock.text()]


func _clear() -> void:
	for c in _screen.get_children():
		c.queue_free()


# --- Inicio ---------------------------------------------------------------------------------

func _home() -> void:
	_app = "home"
	_chat_with = ""
	_clear()
	_title.text = "Inicio"
	_back.visible = false
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_screen.add_child(grid)
	var unread := Phone.unread()
	for app in [["Mensajes" + (" (%d)" % unread if unread > 0 else ""), _show_messages, Color("#7ee08a")],
			["Contactos", _show_contacts, UITheme.ACCENT], ["Banco", _show_bank, UITheme.MONEY], ["Mapa", _show_map, Color("#ef9a9a")]]:
		var b := Button.new()
		b.text = app[0]
		b.custom_minimum_size = Vector2(150, 92)
		var sb := UITheme.box(Color(app[2], 0.16), Color(app[2], 0.4), 18, 10)
		b.add_theme_stylebox_override("normal", sb)
		var sb_h := sb.duplicate()
		sb_h.bg_color = Color(app[2], 0.3)
		b.add_theme_stylebox_override("hover", sb_h)
		b.pressed.connect(app[1])
		grid.add_child(b)
	var hint := Label.new()
	hint.text = Jobs.describe() if Jobs.has_job() else "Sin trabajo. Puedes pedirlo hablando con la gente."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	hint.add_theme_font_size_override("font_size", 13)
	_screen.add_child(hint)


func _scroll_list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_screen.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


func _row(parent: Node, title: String, sub: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [title, sub] if not sub.is_empty() else title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size.y = 52 if not sub.is_empty() else 40
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _name(id: String) -> String:
	return WorldDB.get_entity("npc", id).get("name", "?")


# --- Mensajes y contactos -------------------------------------------------------------------

func _show_messages() -> void:
	_app = "messages"
	_clear()
	_title.text = "Mensajes"
	_back.visible = true
	var list := _scroll_list()
	var any := false
	for id in Phone.contacts():
		var m := Phone.messages(id)
		if m.is_empty():
			continue
		any = true
		var unread := Phone.unread(id)
		_row(list, _name(id) + ("  •" if unread > 0 else ""), ("Tú: " if m[-1].from == "player" else "") + str(m[-1].text), _show_chat.bind(id))
	if not any:
		_muted(list, "No tienes mensajes. Escribe a alguien desde Contactos.")


func _show_contacts() -> void:
	_app = "contacts"
	_clear()
	_title.text = "Contactos"
	_back.visible = true
	var list := _scroll_list()
	for id in Phone.contacts():
		var row := HBoxContainer.new()
		list.add_child(row)
		var name := Label.new()
		name.text = _name(id)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name)
		var call := Button.new()
		call.text = "Llamar"
		call.pressed.connect(_call.bind(id))
		row.add_child(call)
		var write := Button.new()
		write.text = "Escribir"
		write.pressed.connect(_show_chat.bind(id))
		row.add_child(write)
	if Phone.contacts().is_empty():
		_muted(list, "No tienes el número de nadie. Pídeselo a la gente al hablar.")


func _call(id: String) -> void:
	var refusal := Phone.call_refusal(id)
	close()
	if not refusal.is_empty():
		Sfx.deny(self)
		NPCMemory.add_event(id, "Viste una llamada perdida del jugador.")
		get_tree().call_group("hud", "notify", refusal, "warn")
		return
	call_requested.emit(id)


func _show_chat(id: String) -> void:
	_app = "chat"
	_chat_with = id
	_clear()
	_title.text = _name(id)
	_back.visible = true
	Phone.mark_read(id)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_screen.add_child(_chat_scroll)
	_chat_list = VBoxContainer.new()
	_chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_list.add_theme_constant_override("separation", 6)
	_chat_scroll.add_child(_chat_list)
	for m in Phone.messages(id):
		_bubble(m.text, m.from == "player")
	var row := HBoxContainer.new()
	_screen.add_child(row)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Escribe un mensaje…"
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(_t): _send())
	row.add_child(_chat_input)
	var send := Button.new()
	send.text = "Enviar"
	send.pressed.connect(_send)
	row.add_child(send)
	_chat_input.grab_focus.call_deferred()
	_scroll_down()


func _bubble(text: String, mine: bool) -> void:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	_chat_list.add_child(line)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.ACCENT, 0.28) if mine else Color(1, 1, 1, 0.09), Color(0, 0, 0, 0), 14, 10))
	line.add_child(p)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 220
	l.add_theme_font_size_override("font_size", 15)
	p.add_child(l)


func _send() -> void:
	var text := _chat_input.text.strip_edges()
	if text.is_empty():
		return
	_chat_input.clear()
	Phone.send(_chat_with, text)
	_bubble(text, true)
	_scroll_down()


func _scroll_down() -> void:
	await get_tree().process_frame
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


# --- Banco ----------------------------------------------------------------------------------

func _show_bank() -> void:
	_app = "bank"
	_clear()
	_title.text = "Banco"
	_back.visible = true
	var bal := Label.new()
	bal.text = Wallet.text()
	bal.add_theme_font_size_override("font_size", 40)
	bal.add_theme_font_override("font", UITheme.font_bold)
	bal.add_theme_color_override("font_color", UITheme.MONEY)
	_screen.add_child(bal)
	var list := _scroll_list()
	var log := Wallet.log_entries()
	for i in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		var row := HBoxContainer.new()
		list.add_child(row)
		var what := Label.new()
		what.text = str(e.get("what", "")) if not str(e.get("what", "")).is_empty() else ("Ingreso" if int(e.delta) > 0 else "Pago")
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(what)
		var amount := Label.new()
		amount.text = ("+" if int(e.delta) > 0 else "−") + Wallet.text(absi(int(e.delta)))
		amount.add_theme_color_override("font_color", UITheme.GOOD if int(e.delta) > 0 else UITheme.DANGER)
		row.add_child(amount)
	if log.is_empty():
		_muted(list, "Sin movimientos todavía.")


# --- Mapa -----------------------------------------------------------------------------------

func _show_map() -> void:
	_app = "map"
	_clear()
	_title.text = "Mapa"
	_back.visible = true
	var map := MapView.new()
	map.custom_minimum_size = Vector2(320, 300)
	map.places = places.call() if places.is_valid() else {}
	map.player = player
	_screen.add_child(map)
	var list := _scroll_list()
	var all: Dictionary = map.places
	for name in all:
		var pos: Vector3 = all[name]
		var dist := roundi(Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length()) if player else 0
		_row(list, str(name).capitalize(), "a %d m · marcar destino" % dist, func(): waypoint_set.emit(str(name).capitalize(), pos); close())
	_row(list, "Quitar destino", "", func(): waypoint_set.emit("", Vector3.INF); close())


func _muted(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.MUTED)
	parent.add_child(l)


## Vista cenital simple: los sitios como puntos con nombre y tú en el centro.
class MapView extends Control:
	var places: Dictionary = {}
	var player: Node3D

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.12), true)
		if places.is_empty():
			return
		var minp := Vector2(INF, INF)
		var maxp := Vector2(-INF, -INF)
		var pts := []
		for n in places:
			var p := Vector2(places[n].x, places[n].z)
			pts.append(p)
		if player:
			pts.append(Vector2(player.global_position.x, player.global_position.z))
		for p in pts:
			minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
			maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
		var span := maxf(maxp.x - minp.x, maxp.y - minp.y) + 20.0
		var to_map := func(p: Vector2) -> Vector2: return (p - minp + Vector2(10, 10)) / span * minf(size.x, size.y) + Vector2(0, 0)
		var font := get_theme_default_font()
		for n in places:
			var m: Vector2 = to_map.call(Vector2(places[n].x, places[n].z))
			draw_circle(m, 4.0, Color("#73d9ff"))
			draw_string(font, m + Vector2(6, 4), str(n).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
		if player:
			var me: Vector2 = to_map.call(Vector2(player.global_position.x, player.global_position.z))
			draw_circle(me, 6.0, Color("#ffd27a"))
			draw_string(font, me + Vector2(8, -6), "Tú", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffd27a"))

class_name DialoguePanel
extends CanvasLayer
## Conversación con un PNJ: el jugador puede elegir una opción generada o escribir lo que quiera.
## Escribir libremente es clave: es lo que hace que cada partida sea única.

signal closed(npc_id: String)
## Cada respuesta del PNJ (para que la escena le ponga la emoción y los gestos).
signal turn_received(npc_id: String, turn: Dictionary)

# Texto y no emojis: la fuente por defecto de Godot no los trae.
const EMOTION_LABEL := {
	"neutral": "", "happy": "· alegre", "sad": "· triste", "worried": "· preocupación",
	"angry": "· enojo", "curious": "· curiosidad", "scared": "· miedo",
	"amused": "· divertido", "mysterious": "· misterio",
}

var scene_context: String = ""
## Si la escena lo asigna, da el contexto en cada turno (dónde está el PNJ, qué hace…): así la IA
## nunca habla como si el PNJ estuviera en otro sitio. Recibe el npc_id.
var context_provider: Callable

var _npc: Dictionary = {}
var _speaker: Label
var _role: Label
var _mood: Label
var _history: RichTextLabel
var _history_scroll: ScrollContainer
var _history_lines: Array = []
var _typing: Tween
var _bars: Array = []
## Conversación por teléfono: sin bandas de cine; la persona no está contigo.
var call_mode := false
var _last_line := ""
var _line: RichTextLabel
var _choices: VBoxContainer
var _input: LineEdit
var _say_btn: Button
var _give_btn: MenuButton
var _bye_btn: Button
var _pay_btn: Button
var _busy := false
var _thinking_t := 0.0
var _leaving := false


func _ready() -> void:
	layer = 10
	visible = false
	# Bandas de cine: la conversación se separa del resto del juego
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -34.0
		bar.offset_bottom = 34.0 if top else 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -46
	UIStyle.apply(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# Placa: nombre, a qué se dedica y cómo te trata
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_font_override("font", UITheme.font_bold)
	head.add_child(_speaker)
	_role = Label.new()
	_role.add_theme_color_override("font_color", UITheme.MUTED)
	_role.add_theme_font_size_override("font_size", 15)
	_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_role)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_mood = Label.new()
	_mood.add_theme_font_size_override("font_size", 14)
	_mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_mood)

	# Lo dicho antes en esta conversación (desplazable) y la frase actual
	_history_scroll = ScrollContainer.new()
	_history_scroll.custom_minimum_size.y = 64
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_history_scroll)
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.fit_content = true
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.add_theme_color_override("default_color", UITheme.MUTED)
	_history.add_theme_font_size_override("normal_font_size", 14)
	_history_scroll.add_child(_history)
	_line = RichTextLabel.new()
	_line.bbcode_enabled = true
	_line.fit_content = true
	_line.custom_minimum_size.y = 56
	_line.add_theme_font_size_override("normal_font_size", 19)
	_line.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _skip_typing())
	box.add_child(_line)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	box.add_child(_choices)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "Di o haz lo que quieras… (p. ej. «*le doy un abrazo*», «¿me cobras el café?»)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _on_say())
	row.add_child(_input)
	_say_btn = Button.new()
	_say_btn.text = "Decir"
	_say_btn.pressed.connect(_on_say)
	row.add_child(_say_btn)
	_give_btn = MenuButton.new()  # dar de verdad un objeto, no solo decir que se lo das
	_give_btn.text = "Dar objeto"
	_give_btn.flat = false
	_give_btn.about_to_popup.connect(_fill_give_menu)
	_give_btn.get_popup().id_pressed.connect(_on_give)
	row.add_child(_give_btn)
	_pay_btn = Button.new()  # pagar de verdad lo que te cobran
	_pay_btn.visible = false
	_pay_btn.add_theme_color_override("font_color", UITheme.MONEY)
	_pay_btn.pressed.connect(_on_pay)
	row.add_child(_pay_btn)
	Actions.charged.connect(func(id, _t): if not _npc.is_empty() and id == _npc.id: _refresh_pay())
	_bye_btn = Button.new()
	_bye_btn.text = "Despedirse"
	_bye_btn.pressed.connect(close)
	row.add_child(_bye_btn)


## Cómo te trata según la relación (sin números: como se nota en la vida real).
static func treatment(relationship: int) -> Array:
	if relationship >= 40:
		return ["Trato cercano", UITheme.GOOD]
	if relationship >= 12:
		return ["Trato cordial", Color("#a8e6b0")]
	if relationship > -12:
		return ["Trato neutral", UITheme.MUTED]
	if relationship > -40:
		return ["Trato tenso", UITheme.WARN]
	return ["Trato hostil", UITheme.DANGER]


func _refresh_header() -> void:
	var met: bool = NPCMemory.get_mem(_npc.id).met
	_speaker.text = ("En llamada · " if call_mode else "") + (_npc.name if met else "Desconocido/a")
	_role.text = str(_npc.get("occupation", "")) if met else ""
	var t := treatment(int(NPCMemory.get_mem(_npc.id).relationship))
	_mood.text = t[0] if met else ""
	_mood.add_theme_color_override("font_color", t[1])


func _add_history(who: String, text: String) -> void:
	_history_lines.append("[b]%s:[/b] %s" % [who, text])
	while _history_lines.size() > 12:
		_history_lines.pop_front()
	_history.text = "\n".join(_history_lines)
	_history_scroll.visible = not _history_lines.is_empty()
	await get_tree().process_frame
	_history_scroll.scroll_vertical = int(_history_scroll.get_v_scroll_bar().max_value)


func _skip_typing() -> void:
	if _typing and _typing.is_valid():
		_typing.kill()
		_line.visible_ratio = 1.0


func open(npc_id: String, by_phone: bool = false) -> void:
	call_mode = by_phone
	for b in _bars:
		b.visible = not by_phone
	_give_btn.visible = not by_phone  # por teléfono no se dan objetos
	_npc = WorldDB.get_entity("npc", npc_id)
	_history_lines.clear()
	_history.text = ""
	_history_scroll.visible = false
	_last_line = ""
	_refresh_header()
	visible = true
	_leaving = false
	_refresh_pay()
	var left := NPCMemory.refusal_left(npc_id)
	if left > 0:  # sigue enfadado/a: ni te mira
		_clear_choices()
		_line.text = "[i]%s te da la espalda. No quiere hablar contigo ahora (unos %d min).[/i]" % [_npc.name, ceili(left / 60.0)]
		_bye_btn.grab_focus()
		return
	_send("")


func close() -> void:
	if _busy:
		return
	visible = false
	StoryDirector.end_conversation(_npc.id)
	closed.emit(_npc.id)


func _on_say() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.clear()
	# "Te pago", "aquí tienes": pagar lo que te han cobrado pasa de verdad, no solo se dice
	var low := text.to_lower()
	if Actions.owed(_npc.id) > 0 and ["te pago", "le pago", "aquí tienes", "aqui tienes", "aquí tiene", "toma el dinero", "pago yo", "cóbrame", "cobrame", "cóbreme"].any(func(w): return low.contains(w)):
		var note := Actions.settle(_npc.id)
		_refresh_pay()
		if not note.is_empty():
			text += " (%s)" % note
	_send(text)


func _on_pay() -> void:
	if _busy:
		return
	var debt := Actions.owed(_npc.id)
	var note := Actions.settle(_npc.id)
	_refresh_pay()
	if note.begins_with("Pagas"):
		_send("(Le pagas %s.)" % Wallet.text(debt))
	elif not note.is_empty():
		_line.text += "\n[color=#f2a65a]%s[/color]" % note


func _refresh_pay() -> void:
	var debt := Actions.owed(_npc.id) if not _npc.is_empty() else 0
	_pay_btn.visible = debt > 0
	_pay_btn.text = "Pagar %s" % Wallet.text(debt)


func _send(text: String) -> void:
	if _busy:
		return
	_set_busy(true)
	_clear_choices()
	if not _last_line.is_empty():
		_add_history(_npc.name.split(" ")[0], _last_line)
	if not text.is_empty():
		_add_history("Tú", text)
	_line.text = "[color=gray]…[/color]"

	var ctx := scene_context
	if context_provider.is_valid():
		ctx = context_provider.call(_npc.id)
	var turn := await StoryDirector.talk(_npc.id, text, ctx)
	_set_busy(false)
	if not turn.ok:
		_line.text = "[color=red]%s[/color]" % turn.get("error", "Error")
		return

	turn_received.emit(_npc.id, turn)
	_refresh_header()
	_role.text = ("%s  %s" % [_npc.get("occupation", ""), EMOTION_LABEL.get(turn.emotion, "")]).strip_edges()
	_last_line = turn.line
	_line.text = turn.line
	if turn.source == "fallback":
		# Que el jugador sepa que esto no es la IA (y por qué), en vez de ver frases repetidas
		_line.text += "\n[color=#f2a65a][font_size=13](Sin respuesta de la IA: %s. Revisa la API key y el modelo en Ajustes.)[/font_size][/color]" % turn.get("error", "")
	var notes: Array = turn.get("notes", [])
	if not notes.is_empty():
		_line.text += "\n[color=#7ee08a]» " + "\n» ".join(PackedStringArray(notes)) + "[/color]"
		Sfx.chime(self)
	_line.visible_ratio = 0.0
	var reading := clampf(turn.line.length() * 0.025, 0.4, 3.5) / clampf(Settings.text_speed, 0.5, 3.0)
	_typing = create_tween()
	_typing.tween_property(_line, "visible_ratio", 1.0, reading)

	if turn.get("leaving", false):
		# Se va de verdad: la conversación termina cuando acaba la frase y la escena le hace marcharse
		_leaving = true
		_line.text += "\n[color=gray][i](%s se da la vuelta y se va.)[/i][/color]" % _npc.name.split(" ")[0]
		_set_busy(true)
		await get_tree().create_timer(reading + clampf(turn.line.length() * 0.035, 1.8, 5.0)).timeout
		_set_busy(false)
		if visible:
			close()
		return
	if turn.end_conversation or NPCMemory.refusal_left(_npc.id) > 0:
		_bye_btn.grab_focus()
		return
	for c in turn.choices:
		var b := Button.new()
		b.text = "%d   %s" % [_choices.get_child_count() + 1, c.text]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_send.bind(c.text))
		_choices.add_child(b)
		UIAnim.show(b, Vector2(0, 8))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") and not _busy:  # Esc: despedirse
		get_viewport().set_input_as_handled()
		close()
		return
	if event.is_action_pressed("jump") and _typing and _typing.is_running():
		get_viewport().set_input_as_handled()
		_skip_typing()
		return
	if _busy:
		return
	for i in 4:  # 1-4 eligen una respuesta (si no se está escribiendo)
		if event.is_action_pressed("choice_%d" % (i + 1)) and i < _choices.get_child_count():
			var b: Button = _choices.get_child(i)
			if not b.is_queued_for_deletion():
				get_viewport().set_input_as_handled()
				b.pressed.emit()
				return


func _process(delta: float) -> void:
	if _busy and visible and not _leaving:  # "pensando…" mientras responde la IA
		_thinking_t += delta
		var dots := ".".repeat(1 + int(_thinking_t * 3.0) % 3)
		var base := _line.text.get_slice("[color=gray]", 0)
		_line.text = base + "[color=gray]" + dots + "[/color]"


func is_leaving() -> bool:
	return _leaving


func _fill_give_menu() -> void:
	var menu := _give_btn.get_popup()
	menu.clear()
	var ids := Inventory.items()
	for i in ids.size():
		menu.add_item(WorldDB.get_entity("item", ids[i]).get("name", "?"), i)
		menu.set_item_disabled(i, Inventory.is_anchor(ids[i]))
	if ids.is_empty():
		menu.add_item("(no llevas nada)", -1)
		menu.set_item_disabled(0, true)


## Entregar un objeto: pasa de verdad y luego el PNJ reacciona a ello.
func _on_give(index: int) -> void:
	var ids := Inventory.items()
	if _busy or index < 0 or index >= ids.size():
		return
	var item_name: String = WorldDB.get_entity("item", ids[index]).get("name", "?")
	var note := Actions.player_gives(_npc.id, ids[index])
	if note.is_empty():
		return
	_send("(Le doy «%s».)" % item_name)


func _set_busy(value: bool) -> void:
	_busy = value
	_input.editable = not value
	_say_btn.disabled = value
	_give_btn.disabled = value
	_bye_btn.disabled = value


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()

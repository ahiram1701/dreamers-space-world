class_name InventoryPanel
extends CanvasLayer
## El Cuaderno (tecla I): tus objetos, los encargos, el diario y la gente que conoces.
## Los objetos se usan, examinan, dan o sueltan; lo que no es un efecto inmediato pasa por "Hacer
## algo" (F) con el texto ya escrito, así el mundo reacciona como a cualquier otra acción.

signal opened
signal closed
signal message(text: String)
## Pide abrir "Hacer algo" con este texto ya escrito ("Examino la radio…").
signal action_requested(text: String)

## Devuelve los ids de PNJs cercanos (para objetos de secretos o confianza). Lo asigna la escena.
var nearby_npcs: Callable = func(): return []

const KIND_STYLE := {"tool": ["Herramienta", Color("#e7a35b")], "artifact": ["Artefacto", Color("#c9a7ff")],
	"technology": ["Tecnología", Color("#73d9ff")], "consumable": ["Consumible", Color("#7ee08a")],
	"key": ["Llave", Color("#f2c14e")], "relic": ["Reliquia", Color("#ef9a9a")], "data": ["Datos", Color("#90caf9")]}

var _root: Control
var _tabs: TabContainer
var _grid: GridContainer
var _detail: VBoxContainer
var _errands: VBoxContainer
var _journal: VBoxContainer
var _people: VBoxContainer
var _log: VBoxContainer
var _selected := ""


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.14
	panel.anchor_right = 0.86
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	UIStyle.apply(panel)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Cuaderno"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_font_override("font", UITheme.font_bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Cerrar"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	# Objetos: rejilla a la izquierda, detalle a la derecha
	var items := HBoxContainer.new()
	items.name = "Objetos"
	items.add_theme_constant_override("separation", 16)
	_tabs.add_child(items)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	items.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	var detail_panel := PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_SOFT, Color(1, 1, 1, 0.06), 12, 16))
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_child(detail_panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(_detail)
	_errands = _tab("Encargos")
	_journal = _tab("Diario")
	_people = _tab("Personas")
	_log = _tab("Registro")


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	return v


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func open() -> void:
	_rebuild()
	UIAnim.show(_root, Vector2.ZERO)
	_focus_first.call_deferred()
	opened.emit()


## Con mando: el foco empieza en algo que se pueda pulsar.
func _focus_first() -> void:
	await get_tree().process_frame
	if _grid.get_child_count() > 0 and _grid.get_child(0) is Button:
		_grid.get_child(0).grab_focus()
	else:
		_tabs.get_tab_bar().grab_focus()


func close() -> void:
	if not _root.visible:
		return
	UIAnim.hide(_root)
	closed.emit()


func _rebuild() -> void:
	_build_items()
	_build_errands()
	_build_journal()
	_build_people()
	_build_log()


# --- Objetos -------------------------------------------------------------------------------

func _build_items() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var ids := Inventory.items()
	if not (_selected in ids):
		_selected = ids[0] if not ids.is_empty() else ""
	if ids.is_empty():
		_grid.add_child(_muted("No llevas nada. Puedes encontrar cosas buscando (F), comprándolas o pidiéndoselas a la gente."))
	for id in ids:
		var item := WorldDB.get_entity("item", id)
		var style: Array = KIND_STYLE.get(item.get("kind", "artifact"), ["Objeto", UITheme.ACCENT])
		var card := Button.new()
		card.custom_minimum_size = Vector2(170, 92)
		card.toggle_mode = true
		card.button_pressed = id == _selected
		card.text = item.get("name", "?")
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var sb := UITheme.box(Color(style[1], 0.10), Color(style[1], 0.35), 10, 12)
		sb.border_width_left = 4
		card.add_theme_stylebox_override("normal", sb)
		var sb_on := sb.duplicate()
		sb_on.bg_color = Color(style[1], 0.28)
		sb_on.border_color = style[1]
		card.add_theme_stylebox_override("pressed", sb_on)
		card.add_theme_stylebox_override("hover", sb_on)
		card.pressed.connect(func(): _selected = id; _build_items())
		_grid.add_child(card)
	_build_detail()


func _build_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected.is_empty():
		return
	var item := WorldDB.get_entity("item", _selected)
	var style: Array = KIND_STYLE.get(item.get("kind", "artifact"), ["Objeto", UITheme.ACCENT])
	var name := Label.new()
	name.text = item.get("name", "?")
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", 22)
	name.add_theme_font_override("font", UITheme.font_bold)
	_detail.add_child(name)
	var tags := Label.new()
	var lent := Inventory.lent_label(_selected)
	var effect: String = Inventory.EFFECT_LABELS.get(item.get("effect", "none"), "")
	tags.text = " · ".join(PackedStringArray([style[0]] + ([effect] if not effect.is_empty() else []) + ([lent] if not lent.is_empty() else [])))
	tags.add_theme_color_override("font_color", style[1])
	tags.add_theme_font_size_override("font_size", 14)
	_detail.add_child(tags)
	var lore := Label.new()
	lore.text = item.get("lore", "")
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.add_theme_color_override("font_color", UITheme.TEXT)
	_detail.add_child(lore)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_detail.add_child(row)
	var id := _selected
	var n: String = item.get("name", "esto")
	if Inventory.is_usable(id):
		_action(row, "Usar", func(): message.emit(Inventory.use(id, nearby_npcs.call())); _rebuild())
	else:
		_action(row, "Usar", func(): _ask("Uso «%s» para " % n))
	_action(row, "Examinar", func(): _ask("Examino «%s» con atención" % n))
	var others: Array = Inventory.items().filter(func(o): return o != id and not Inventory.is_anchor(o))
	if not others.is_empty():  # inventar: juntar cosas para hacer otra
		var combine := MenuButton.new()
		combine.text = "Combinar con…"
		combine.flat = false
		for i in others.size():
			combine.get_popup().add_item(WorldDB.get_entity("item", others[i]).get("name", "?"), i)
		combine.get_popup().id_pressed.connect(func(i):
			_ask("Combino «%s» y «%s» para hacer " % [n, WorldDB.get_entity("item", others[i]).get("name", "?")]))
		row.add_child(combine)
	if not Inventory.is_anchor(id):
		_action(row, "Dar a…", func(): _ask("Le doy «%s» a " % n))
		_action(row, "Soltar", func(): _ask("Dejo «%s» en el suelo" % n))


func _action(row: Node, text: String, f: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	row.add_child(b)


func _ask(text: String) -> void:
	close()
	action_requested.emit(text)


# --- Encargos, diario y personas -------------------------------------------------------------

func _build_errands() -> void:
	_clear(_errands)
	var list := Quests.active_custom()
	var main := Quests.for_location(GameState.current_location())
	if not main.is_empty() and main.status == "active":
		_entry(_errands, main.title, "%s\n%s" % [main.description, Quests.objective_text(main)], UITheme.WARN)
	for q in list:
		var reward := int(q.get("reward", 0))
		_entry(_errands, q.title, "%s — te lo pidió %s%s" % [q.description, WorldDB.get_entity("npc", q.giver).get("name", "?"),
			(". Paga %s." % Wallet.text(reward)) if reward > 0 else "."], UITheme.WARN)
	if _errands.get_child_count() == 0:
		_errands.add_child(_muted("Nadie te ha pedido nada todavía."))


func _build_journal() -> void:
	_clear(_journal)
	var notes := Journal.entries()
	for i in range(notes.size() - 1, -1, -1):  # lo más reciente arriba
		var who: String = WorldDB.get_entity("npc", notes[i].by).get("name", "") if not str(notes[i].by).is_empty() else "Tú"
		_entry(_journal, who, notes[i].text, UITheme.ACCENT)
	if notes.is_empty():
		_journal.add_child(_muted("Aún no has apuntado nada. Las pistas importantes se anotan solas."))


func _build_people() -> void:
	_clear(_people)
	var all: Dictionary = WorldDB.get_state("memories", {})
	var known := []
	for id in all:
		if NPCMemory.get_mem(id).met and not WorldDB.get_entity("npc", id).is_empty():
			known.append(id)
	known.sort_custom(func(a, b): return int(NPCMemory.get_mem(a).relationship) > int(NPCMemory.get_mem(b).relationship))
	for id in known:
		var e := WorldDB.get_entity("npc", id)
		var t := DialoguePanel.treatment(int(NPCMemory.get_mem(id).relationship))
		var lines := PackedStringArray([str(e.get("occupation", ""))])
		var inside := NPCMemory.inside(id)
		if not inside.is_empty():
			lines.append("Ahora está dentro de un edificio%s." % (" (con la puerta cerrada)" if NPCMemory.is_locked_in(id) else ""))
		if Actions.owed(id) > 0:
			lines.append("Le debes %s." % Wallet.text(Actions.owed(id)))
		var recent: Array = NPCMemory.get_mem(id).recent
		if not recent.is_empty():
			lines.append("Lo último: " + str(recent[-1].text))
		var card := _entry(_people, "%s   ·   %s" % [e.get("name", "?"), t[0]], "\n".join(lines), t[1])
		card.tooltip_text = ", ".join(PackedStringArray(e.get("personality", [])))
	if known.is_empty():
		_people.add_child(_muted("Todavía no conoces a nadie. Acércate a alguien y pulsa E."))


## Lo que te pasó y te dijeron, lo más reciente arriba.
func _build_log() -> void:
	_clear(_log)
	var list := Journal.log_entries()
	var colors := {"item": UITheme.GOOD, "money": UITheme.MONEY, "quest": UITheme.WARN, "memory": Color("#c9a7ff"), "warn": UITheme.DANGER, "say": UITheme.TEXT}
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		var m := int(e.get("at", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_log.add_child(row)
		var when := Label.new()
		when.text = "%s %02d:%02d" % [WorldClock.WEEKDAYS[(m / 1440 + 3) % 7].left(3).capitalize(), (m % 1440) / 60, m % 60]
		when.add_theme_color_override("font_color", UITheme.MUTED)
		when.add_theme_font_size_override("font_size", 13)
		when.custom_minimum_size.x = 80
		row.add_child(when)
		var text := Label.new()
		text.text = str(e.get("text", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_color_override("font_color", colors.get(e.get("kind", "info"), UITheme.ACCENT))
		row.add_child(text)
	if list.is_empty():
		_log.add_child(_muted("Aquí irá quedando todo lo que te pase y te digan."))


func _entry(parent: Node, title: String, body: String, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := UITheme.box(UITheme.BG_SOFT, Color(0, 0, 0, 0), 10, 14)
	sb.border_color = accent
	sb.border_width_left = 4
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	card.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UITheme.font_bold)
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_color_override("font_color", UITheme.MUTED)
	b.add_theme_font_size_override("font_size", 15)
	v.add_child(b)
	parent.add_child(card)
	return card


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.MUTED)
	l.custom_minimum_size.x = 300
	return l


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

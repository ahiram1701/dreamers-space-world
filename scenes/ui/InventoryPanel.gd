class_name InventoryPanel
extends CanvasLayer
## Inventario (tecla I): lo que llevas encima, los encargos que te han hecho y tu diario.

signal opened
signal closed
signal message(text: String)

## Devuelve los ids de PNJs cercanos (para objetos de secretos o confianza). Lo asigna la escena.
var nearby_npcs: Callable = func(): return []

var _panel: PanelContainer
var _list: VBoxContainer


func _ready() -> void:
	layer = 15
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.25
	_panel.anchor_right = 0.75
	_panel.anchor_top = 0.12
	_panel.anchor_bottom = 0.88
	_panel.visible = false
	UIStyle.apply(_panel)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Inventario y diario"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	var close_btn := Button.new()
	close_btn.text = "Cerrar  [I]"
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if _panel.visible:
		close()
	else:
		open()


func open() -> void:
	_rebuild()
	_panel.visible = true
	opened.emit()


func close() -> void:
	_panel.visible = false
	closed.emit()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var ids := Inventory.items()
	if ids.is_empty():
		_text("No llevas nada. Puedes encontrar cosas buscando (F) o pidiéndoselas a la gente.")
	for id in ids:
		var item := WorldDB.get_entity("item", id)
		var row := HBoxContainer.new()
		_list.add_child(row)
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lent := Inventory.lent_label(id)
		info.text = "[b]%s[/b]  [color=#9fd8ff]%s[/color]%s\n[i]%s[/i]" % [
			item.get("name", "?"), Inventory.EFFECT_LABELS.get(item.get("effect", "none"), ""),
			"  [color=#f2a65a](%s)[/color]" % lent if not lent.is_empty() else "", item.get("lore", "")]
		row.add_child(info)
		if Inventory.is_usable(id):
			var use := Button.new()
			use.text = "Usar"
			use.pressed.connect(_use.bind(id))
			row.add_child(use)

	var errands := Quests.active_custom()
	if not errands.is_empty():
		_heading("Encargos")
		for q in errands:
			_text("[b]%s[/b] — %s\n[i]%s[/i]" % [q.title, WorldDB.get_entity("npc", q.giver).get("name", "?"), q.description])
	var notes := Journal.entries()
	if not notes.is_empty():
		_heading("Diario")
		for i in range(notes.size() - 1, -1, -1):  # lo más reciente arriba
			var who: String = WorldDB.get_entity("npc", notes[i].by).get("name", "") if not notes[i].by.is_empty() else ""
			_text("• %s%s" % [notes[i].text, "  [color=gray](%s)[/color]" % who if not who.is_empty() else ""])


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color("#f2a65a"))
	_list.add_child(l)


func _text(bbcode: String) -> void:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text = bbcode
	_list.add_child(t)


func _use(item_id: String) -> void:
	message.emit(Inventory.use(item_id, nearby_npcs.call()))
	_rebuild()

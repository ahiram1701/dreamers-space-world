class_name InventoryPanel
extends CanvasLayer
## Inventario (tecla I): lo que llevas encima, de dónde salió y para qué sirve.

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
	title.text = "Inventario"
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
		var empty := Label.new()
		empty.text = "No llevas nada. Los objetos brillan en los puntos de interés de cada mundo."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return
	for id in ids:
		var item := WorldDB.get_entity("item", id)
		var row := HBoxContainer.new()
		_list.add_child(row)
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "[b]%s[/b]  [color=#9fd8ff]%s[/color]\n[i]%s[/i]" % [
			item.get("name", "?"), Inventory.EFFECT_LABELS.get(item.get("effect", "none"), ""), item.get("lore", "")]
		row.add_child(info)
		if Inventory.is_usable(id):
			var use := Button.new()
			use.text = "Usar"
			use.pressed.connect(_use.bind(id))
			row.add_child(use)


func _use(item_id: String) -> void:
	message.emit(Inventory.use(item_id, nearby_npcs.call()))
	_rebuild()

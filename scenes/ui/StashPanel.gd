class_name StashPanel
extends CanvasLayer
## Guardar y sacar cosas de algo que construiste (un baúl, una caja, una estantería).
## Lo guardado se queda ahí aunque te vayas (Actions.stash_*).

signal opened
signal closed

var _root: Control
var _title: Label
var _mine: VBoxContainer
var _inside: VBoxContainer
var _key := ""


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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	UIStyle.apply(panel)
	panel.custom_minimum_size = Vector2(640, 380)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_font_override("font", UITheme.font_bold)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "Cerrar"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)
	_mine = _column(cols, "Llevas encima")
	_inside = _column(cols, "Guardado aquí")


func _column(parent: Node, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	var l := Label.new()
	l.text = title
	l.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func is_open() -> bool:
	return _root.visible


func open(key: String, title: String) -> void:
	_key = key
	_title.text = title if not title.is_empty() and not title.begins_with("@") else "Guardar cosas"
	_rebuild()
	UIAnim.show(_root, Vector2.ZERO)
	opened.emit()


func close() -> void:
	if not _root.visible:
		return
	UIAnim.hide(_root)
	closed.emit()


func _rebuild() -> void:
	for list in [_mine, _inside]:
		for c in list.get_children():
			c.queue_free()
	for id in Inventory.items():
		if Inventory.is_anchor(id):
			continue
		_item(_mine, id, "Guardar →", func(): Actions.stash_put(_key, id); _rebuild())
	for id in Actions.stash(_key):
		_item(_inside, id, "← Sacar", func(): Actions.stash_take(_key, id); _rebuild())


func _item(list: Node, id: String, verb: String, f: Callable) -> void:
	var b := Button.new()
	b.text = "%s   %s" % [WorldDB.get_entity("item", id).get("name", "?"), verb]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(f)
	list.add_child(b)

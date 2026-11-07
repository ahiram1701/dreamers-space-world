class_name ShopPanel
extends CanvasLayer
## Comprar en un local (abarrotes, farmacia, ferretería) o pedir de la carta (fonda, cafetería):
## la lista con precios, lo que llevas y un botón por cosa. Al comprar emite `bought` con lo
## elegido; quien lo abre cobra y entrega (Shops.buy) para que todo pase en un solo sitio.

signal bought(entry: Dictionary)
signal closed

var title := "Tienda"
var items: Array = []
var verb := "Comprar"
## Texto del botón de cerrar (en la carta: «Listo» = ya pediste todo).
var close_text := "Cerrar"

var _money: Label
var _status: Label
var _list: VBoxContainer


func _ready() -> void:
	layer = 15
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	UIStyle.apply(panel)
	panel.custom_minimum_size = Vector2(600, 400)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_font_override("font", UITheme.font_bold)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_money = Label.new()
	_money.add_theme_color_override("font_color", UITheme.MONEY)
	head.add_child(_money)
	var close_btn := Button.new()
	close_btn.text = close_text
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = Label.new()
	_status.add_theme_color_override("font_color", UITheme.WARN)
	box.add_child(_status)
	_rebuild()
	UIAnim.show(root, Vector2.ZERO)


func _rebuild() -> void:
	_money.text = "Llevas %s" % Wallet.text()
	for c in _list.get_children():
		c.queue_free()
	for entry in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name := Label.new()
		name.text = "%s   —   %s" % [entry.name, Wallet.text(int(entry.price))]
		info.add_child(name)
		var lore := Label.new()
		lore.text = str(entry.get("lore", ""))
		lore.add_theme_font_size_override("font_size", 13)
		lore.add_theme_color_override("font_color", UITheme.MUTED)
		lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(lore)
		var b := Button.new()
		b.text = verb
		b.custom_minimum_size.x = 110
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = not Wallet.can_pay(int(entry.price))
		b.pressed.connect(func(): _buy(entry))
		row.add_child(b)
	if _list.get_child_count() > 0:
		(func(): if is_instance_valid(_list) and _list.get_child_count() > 0: _list.get_child(0).get_child(1).grab_focus()).call_deferred()


## Una nota bajo la lista (en la carta: lo que llevas pedido).
func set_note(text: String) -> void:
	if _status:
		_status.add_theme_color_override("font_color", UITheme.MUTED)
		_status.text = text


func _buy(entry: Dictionary) -> void:
	if not Wallet.can_pay(int(entry.price)):
		_status.text = "No te alcanza: cuesta %s." % Wallet.text(int(entry.price))
		return
	bought.emit(entry)
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()

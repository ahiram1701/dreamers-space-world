class_name AnchorPanel
extends CanvasLayer
## El Ancla (tecla T): saltar a una rama nueva, volver a un lugar conocido o, con las
## coordenadas completas, seguir la señal hasta su origen. Hace el salto completo:
## túnel, Travel y cambio de escena.

signal opened
signal closed

var _panel: PanelContainer
var _title: Label
var _info: Label
var _list: VBoxContainer
var _loading: LoadingOverlay
var _busy := false


func _ready() -> void:
	layer = 15
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.3
	_panel.anchor_right = 0.7
	_panel.anchor_top = 0.15
	_panel.anchor_bottom = 0.85
	_panel.visible = false
	UIStyle.apply(_panel)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var close_btn := Button.new()
	close_btn.text = "Cerrar  [T]"
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
	_loading = LoadingOverlay.new()
	add_child(_loading)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T:
		if _panel.visible:
			close()
		elif GameState.is_awakened() and not _busy:
			open()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	_rebuild()
	_panel.visible = true
	opened.emit()


func close() -> void:
	if _busy or not _panel.visible:
		return
	_panel.visible = false
	closed.emit()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var anchor_id: String = WorldDB.get_state("awakening", {}).get("anchor_id", "")
	_title.text = WorldDB.get_entity("item", anchor_id).get("name", "El Ancla")
	_info.text = "Energía: %d · Inestabilidad: %d · Ramas recorridas: %d · Coordenadas: %d/%d" % [
		GameState.get_stat("energy"), GameState.get_stat("instability"), TimelineManager.depth(),
		GameState.fragments(), GameState.FRAGMENTS_NEEDED]
	if GameState.has_free_jump():
		_info.text += "\nCoordenadas grabadas: el próximo salto no gasta energía."
	if Travel.is_pregenerating():
		_info.text += "\nCalculando el siguiente destino en segundo plano…"
	if GameState.has_all_fragments() and GameState.ending().is_empty():
		_add_option("Seguir la señal hasta su origen", GameState.travel_cost("finale"), "finale")
	_add_option("Saltar a una rama desconocida", GameState.travel_cost("new"), "new")
	for d in Travel.known_destinations():
		_add_option("Volver a %s" % d.name, d.cost, d.location_id)


func _add_option(text: String, cost: int, target: String) -> void:
	var b := Button.new()
	b.text = "%s  (−%d energía)" % [text, cost]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not GameState.can_travel(target)
	b.pressed.connect(_travel.bind(target))
	_list.add_child(b)


func _travel(target: String) -> void:
	_busy = true
	_panel.visible = false
	match target:
		"new":
			_loading.show_loading("Saltando a lo desconocido", PackedStringArray([
				"Calculando trayectoria", "Estabilizando el Ancla", "Buscando una rama compatible", "Midiendo la decoherencia"]), true)
		"finale":
			_loading.show_loading("Siguiendo la señal", PackedStringArray([
				"Triangulando las cinco coordenadas", "Todas las ramas convergen", "La transmisión se hace más fuerte"]), true)
		_:
			_loading.show_loading("Recorriendo una ruta conocida", PackedStringArray(["Sincronizando el Ancla"]), true)
	var r: Dictionary
	if target == "new":
		r = await Travel.jump_new()
	elif target == "finale":
		r = await Travel.jump_finale()
	else:
		r = await Travel.go_to(target)
	if r.ok:
		get_tree().change_scene_to_file(Travel.scene_for(r.location_id))
		return
	_loading.hide_loading()
	_busy = false
	_rebuild()
	_panel.visible = true
	_info.text = r.error

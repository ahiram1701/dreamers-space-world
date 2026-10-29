extends Control
## Menú principal: empezar una vida nueva (= un mundo nuevo y único), continuar,
## elegir entre tus partidas, ajustes y herramientas de desarrollo.

const DEV := "res://scenes/dev/AITestScene.tscn"

var _name: LineEdit
var _status: Label
var _main_box: VBoxContainer
var _saves_box: VBoxContainer
var _saves_list: VBoxContainer
var _update_banner: PanelContainer
var _update_label: Label
var _update_btn: Button
var _notes_btn: Button
var _update_bar: ProgressBar


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color("#141a2e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)
	_main_box = VBoxContainer.new()
	_main_box.custom_minimum_size = Vector2(420, 0)
	_main_box.add_theme_constant_override("separation", 12)
	stack.add_child(_main_box)
	_saves_box = VBoxContainer.new()
	_saves_box.custom_minimum_size = Vector2(620, 0)
	_saves_box.add_theme_constant_override("separation", 12)
	_saves_box.visible = false
	stack.add_child(_saves_box)

	var title := Label.new()
	title.text = "Dreamer's Space World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	_main_box.add_child(title)
	var sub := Label.new()
	sub.text = "Todos empiezan igual. Nadie termina en el mismo universo."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_main_box.add_child(sub)

	_name = LineEdit.new()
	_name.placeholder_text = "¿Cómo te llamas?"
	_name.max_length = 30
	_main_box.add_child(_name)
	_button(_main_box, "Nueva vida", _on_new)
	var cont := _button(_main_box, "Continuar", _on_continue)
	cont.disabled = WorldDB.last_world_id().is_empty()
	var saves := _button(_main_box, "Partidas", _show_saves)
	saves.disabled = WorldDB.list_worlds().is_empty()
	_button(_main_box, "Ajustes", func(): add_child(SettingsPanel.new()))
	_button(_main_box, "Herramientas de desarrollo", func(): get_tree().change_scene_to_file(DEV))
	_button(_main_box, "Salir", func(): get_tree().quit())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("#f2a65a"))
	_main_box.add_child(_status)
	if not Settings.use_mock and not Settings.has_api_key():
		_status.text = "Sin API key: la IA usará respuestas de respaldo. Configúrala en Ajustes."

	var saves_title := Label.new()
	saves_title.text = "Tus partidas (cada una es un multiverso distinto)"
	saves_title.add_theme_font_size_override("font_size", 22)
	_saves_box.add_child(saves_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 380
	_saves_box.add_child(scroll)
	_saves_list = VBoxContainer.new()
	_saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saves_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_saves_list)
	_button(_saves_box, "Volver", _hide_saves)

	var version := Label.new()
	version.text = "v" + Updater.current_version()
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	add_child(version)

	_build_update_banner()
	Updater.state_changed.connect(_on_update_state)
	Updater.progress_changed.connect(func(p): _update_bar.value = p * 100.0)
	if Updater.state == Updater.State.IDLE and Settings.auto_check_updates:
		Updater.check()  # una vez por sesión; al volver al menú se reutiliza el resultado
	else:
		_on_update_state(Updater.state)


func _on_new() -> void:
	var player_name := _name.text.strip_edges()
	if player_name.is_empty():
		_status.text = "Escribe tu nombre para empezar."
		return
	WorldDB.create_world("Mundo de " + player_name)
	PlayerProfile.set_player_name(player_name)
	get_tree().change_scene_to_file(Travel.TOWN_SCENE)


func _on_continue() -> void:
	_load(WorldDB.last_world_id())


func _load(world_id: String) -> void:
	if WorldDB.load_world(world_id):
		get_tree().change_scene_to_file(Travel.scene_for(GameState.current_location()))
	else:
		_status.text = "No se pudo cargar la partida."


func _show_saves() -> void:
	for c in _saves_list.get_children():
		c.queue_free()
	for w in WorldDB.list_worlds():
		var row := HBoxContainer.new()
		_saves_list.add_child(row)
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var progress := "Acto 0" if not w.awakened \
			else ("Final alcanzado" if not str(w.ending).is_empty() else "Coordenadas %d/%d" % [w.fragments, GameState.FRAGMENTS_NEEDED])
		info.text = "[b]%s[/b]\n[color=#9fd8ff]%s · %s[/color]  [color=#888]%s[/color]" % [
			w.name, w.place, progress, str(w.created_at).replace("T", " ").left(16)]
		row.add_child(info)
		var load_btn := Button.new()
		load_btn.text = "Cargar"
		load_btn.pressed.connect(_load.bind(w.id))
		row.add_child(load_btn)
		var del := Button.new()
		del.text = "Borrar"
		del.pressed.connect(_confirm_delete.bind(w.id, w.name))
		row.add_child(del)
	_main_box.visible = false
	_saves_box.visible = true


func _confirm_delete(world_id: String, world_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Borrar partida"
	dialog.dialog_text = "¿Borrar «%s» para siempre? Ese multiverso no se puede recuperar." % world_name
	dialog.ok_button_text = "Borrar"
	dialog.cancel_button_text = "Cancelar"
	add_child(dialog)
	dialog.confirmed.connect(_delete.bind(world_id))
	dialog.popup_centered()


func _delete(world_id: String) -> void:
	WorldDB.delete_world(world_id)
	if WorldDB.list_worlds().is_empty():
		get_tree().reload_current_scene()  # sin partidas: refresca los botones del menú
	else:
		_show_saves()


func _hide_saves() -> void:
	_saves_box.visible = false
	_main_box.visible = true


func _build_update_banner() -> void:
	_update_banner = PanelContainer.new()
	_update_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	_update_banner.visible = false
	add_child(_update_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_update_banner.add_child(row)
	_update_label = Label.new()
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_update_label)
	_update_bar = ProgressBar.new()
	_update_bar.custom_minimum_size = Vector2(220, 0)
	_update_bar.visible = false
	row.add_child(_update_bar)
	_notes_btn = Button.new()
	_notes_btn.text = "Ver novedades"
	_notes_btn.pressed.connect(func(): OS.shell_open(Updater.release_url))
	row.add_child(_notes_btn)
	_update_btn = Button.new()
	_update_btn.pressed.connect(Updater.download_and_install)
	row.add_child(_update_btn)


func _on_update_state(s: int) -> void:
	_update_bar.visible = s == Updater.State.DOWNLOADING
	_update_btn.disabled = not (s == Updater.State.AVAILABLE or (s == Updater.State.ERROR and Updater.has_update()))
	match s:
		Updater.State.AVAILABLE:
			_update_banner.visible = true
			_update_label.text = "Nueva versión v%s disponible" % Updater.latest_version
			_update_btn.text = "Actualizar" if Updater.can_self_update() else "Descargar"
		Updater.State.DOWNLOADING:
			_update_label.text = "Descargando v%s…" % Updater.latest_version
		Updater.State.VERIFYING:
			_update_label.text = "Verificando la descarga…"
		Updater.State.INSTALLING:
			_update_label.text = "Instalando y reiniciando…"
		Updater.State.ERROR:
			# Un fallo al solo comprobar (sin red, GitHub caído) no molesta al jugador
			_update_banner.visible = Updater.has_update()
			_update_label.text = "No se pudo actualizar: %s" % Updater.error_message
			_update_btn.text = "Reintentar"
		_:
			_update_banner.visible = false


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	parent.add_child(b)
	return b

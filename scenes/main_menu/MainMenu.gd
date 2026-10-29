extends Control
## Menú principal: empezar una vida nueva (= un mundo nuevo y único) o continuar la última.

const TOWN := "res://scenes/act0_town/Act0Town.tscn"
const DEV := "res://scenes/dev/AITestScene.tscn"

var _name: LineEdit
var _status: Label
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
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Dreamer's Space World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Todos empiezan igual. Nadie termina en el mismo universo."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(sub)

	_name = LineEdit.new()
	_name.placeholder_text = "¿Cómo te llamas?"
	_name.max_length = 30
	box.add_child(_name)
	_button(box, "Nueva vida", _on_new)
	var cont := _button(box, "Continuar", _on_continue)
	var last := WorldDB.last_world_id()
	cont.disabled = last.is_empty()
	_button(box, "Ajustes de IA / Generador (dev)", func(): get_tree().change_scene_to_file(DEV))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("#f2a65a"))
	box.add_child(_status)
	if not Settings.use_mock and not Settings.has_api_key():
		_status.text = "Sin API key: los diálogos usarán respuestas de respaldo. Configúrala en Ajustes."

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
	get_tree().change_scene_to_file(TOWN)


func _on_continue() -> void:
	if WorldDB.load_world(WorldDB.last_world_id()):
		get_tree().change_scene_to_file(TOWN)
	else:
		_status.text = "No se pudo cargar la última partida."


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

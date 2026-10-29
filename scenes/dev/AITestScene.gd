extends Control
## Escena de desarrollo: configurar la API key y ver cómo la IA hace crecer un mundo.
## La UI se construye en código para no depender del editor mientras el proyecto es joven.

var _key: LineEdit
var _model: LineEdit
var _mock: CheckBox
var _type: OptionButton
var _hint: LineEdit
var _generate: Button
var _log: RichTextLabel


func _ready() -> void:
	_build_ui()
	if not WorldDB.is_loaded() and not WorldDB.load_world(WorldDB.last_world_id()):
		WorldDB.create_world("Mundo de prueba")
	_print("[b]Mundo:[/b] %s — %d PNJs, %d lugares, %d objetos" % [WorldDB.world_id,
		WorldDB.query("npc").size(), WorldDB.query("location").size(), WorldDB.query("item").size()])


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(root)

	var title := Label.new()
	title.text = "Dreamer's Space World — Generador de mundo (dev)"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var cfg := HBoxContainer.new()
	root.add_child(cfg)
	_key = _line(cfg, "API key de Ollama Cloud", Settings.api_key, true)
	_model = _line(cfg, "modelo", Settings.model, false)
	_mock = CheckBox.new()
	_mock.text = "Modo mock (sin red)"
	_mock.button_pressed = Settings.use_mock
	cfg.add_child(_mock)
	var save := Button.new()
	save.text = "Guardar ajustes"
	save.pressed.connect(_on_save)
	cfg.add_child(save)
	var back := Button.new()
	back.text = "Menú"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn"))
	cfg.add_child(back)

	var gen := HBoxContainer.new()
	root.add_child(gen)
	_type = OptionButton.new()
	for t in ContentValidator.types():
		_type.add_item(t)
	gen.add_child(_type)
	_hint = _line(gen, "¿Qué quieres que aparezca? (ej: alguien que vende café en el muelle)", "", false)
	_generate = Button.new()
	_generate.text = "Generar"
	_generate.pressed.connect(_on_generate)
	gen.add_child(_generate)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log)


func _line(parent: Node, placeholder: String, value: String, secret: bool) -> LineEdit:
	var l := LineEdit.new()
	l.placeholder_text = placeholder
	l.text = value
	l.secret = secret
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _on_save() -> void:
	Settings.api_key = _key.text.strip_edges()
	Settings.model = _model.text.strip_edges() if not _model.text.strip_edges().is_empty() else Settings.DEFAULT_MODEL
	Settings.use_mock = _mock.button_pressed
	Settings.save_settings()
	_print("[color=gray]Ajustes guardados.[/color]")


func _on_generate() -> void:
	var type := _type.get_item_text(_type.selected)
	var hint := _hint.text.strip_edges()
	if hint.is_empty():
		hint = "algo sorprendente que encaje en el pueblo costero del inicio"
	_generate.disabled = true
	_print("\n[color=cyan]Generando %s…[/color]" % type)

	var r := await ContentGenerator.generate(type, hint, "dev:test_scene", {"where": "Bahía de las Horas", "era": "present"})
	_generate.disabled = false

	if not r.ok:
		_print("[color=red]Falló: %s[/color]" % ", ".join(PackedStringArray(r.errors)))
		return
	var tag := "[color=green]IA[/color]" if r.source == "ai" else "[color=orange]respaldo[/color]"
	_print("%s → [b]%s[/b] (%s)" % [tag, r.entity.get("name", "?"), r.id])
	if not r.errors.is_empty():
		_print("[color=orange]Avisos: %s[/color]" % "; ".join(PackedStringArray(r.errors)))
	_print("[code]%s[/code]" % JSON.stringify(r.entity, "  "))


func _print(text: String) -> void:
	_log.append_text(text + "\n")

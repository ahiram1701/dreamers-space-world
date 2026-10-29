class_name ActionPanel
extends CanvasLayer
## "Hacer algo" (tecla F): el jugador escribe lo que hace en el mundo ("busco en el cajón",
## "me siento a mirar el mar") y la IA cuenta qué pasa. Si encuentra algo, se hace daño o
## descubre una pista, ocurre de verdad (StoryDirector.act → Actions).

signal opened
signal closed

## Devuelve la descripción de dónde está el jugador y qué tiene cerca. Lo asigna la escena.
var context: Callable = func(): return ""

var _panel: PanelContainer
var _text: RichTextLabel
var _input: LineEdit
var _go: Button
var _busy := false


func _ready() -> void:
	layer = 12
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 0.6
	_panel.anchor_bottom = 0.95
	_panel.visible = false
	UIStyle.apply(_panel)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "¿Qué haces?"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)
	var row := HBoxContainer.new()
	box.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "Por ejemplo: busco algo útil entre las redes del muelle"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _do())
	row.add_child(_input)
	_go = Button.new()
	_go.text = "Hacer"
	_go.pressed.connect(_do)
	row.add_child(_go)
	var close_btn := Button.new()
	close_btn.text = "Cerrar"
	close_btn.pressed.connect(close)
	row.add_child(close_btn)


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	_text.text = "[color=gray]Describe con tus palabras lo que haces. Puedes buscar, examinar, descansar, construir algo… El mundo reaccionará.[/color]"
	_panel.visible = true
	opened.emit()
	_input.grab_focus.call_deferred()


func close() -> void:
	if _busy or not _panel.visible:
		return
	_panel.visible = false
	closed.emit()


func _do() -> void:
	var what := _input.text.strip_edges()
	if what.is_empty() or _busy:
		return
	_busy = true
	_input.clear()
	_input.editable = false
	_go.disabled = true
	_text.text = "[color=#8fb3ff][i]%s[/i][/color]\n\n[color=gray]…[/color]" % what
	var r := await StoryDirector.act(what, context.call())
	_busy = false
	_input.editable = true
	_go.disabled = false
	if not r.ok:
		_text.text = "[color=#f2a65a]No pasa nada especial. (Sin respuesta de la IA: %s)[/color]" % r.error.replace("[", "(").replace("]", ")")
		return
	var out := "[color=#8fb3ff][i]%s[/i][/color]\n\n%s" % [what, r.narration]
	if not r.notes.is_empty():
		out += "\n[color=#7ee08a]» " + "\n» ".join(PackedStringArray(r.notes)) + "[/color]"
		Sfx.chime(self)
	_text.text = out
	_input.grab_focus()

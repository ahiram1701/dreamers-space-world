class_name DialoguePanel
extends CanvasLayer
## Conversación con un PNJ: el jugador puede elegir una opción generada o escribir lo que quiera.
## Escribir libremente es clave: es lo que hace que cada partida sea única.

signal closed(npc_id: String)

# Texto y no emojis: la fuente por defecto de Godot no los trae.
const EMOTION_LABEL := {
	"neutral": "", "happy": "· alegre", "sad": "· triste", "worried": "· preocupación",
	"angry": "· enfado", "curious": "· curiosidad", "scared": "· miedo",
	"amused": "· divertido", "mysterious": "· misterio",
}

var scene_context: String = ""

var _npc: Dictionary = {}
var _speaker: Label
var _line: RichTextLabel
var _choices: VBoxContainer
var _input: LineEdit
var _say_btn: Button
var _bye_btn: Button
var _busy := false


func _ready() -> void:
	layer = 10
	visible = false
	var panel := PanelContainer.new()
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.55
	panel.anchor_bottom = 0.97
	UIStyle.apply(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 20)
	box.add_child(_speaker)
	_line = RichTextLabel.new()
	_line.bbcode_enabled = true
	_line.fit_content = true
	_line.custom_minimum_size.y = 60
	box.add_child(_line)
	_choices = VBoxContainer.new()
	box.add_child(_choices)

	var row := HBoxContainer.new()
	box.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "O di lo que quieras…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _on_say())
	row.add_child(_input)
	_say_btn = Button.new()
	_say_btn.text = "Decir"
	_say_btn.pressed.connect(_on_say)
	row.add_child(_say_btn)
	_bye_btn = Button.new()
	_bye_btn.text = "Despedirse"
	_bye_btn.pressed.connect(close)
	row.add_child(_bye_btn)


func open(npc_id: String) -> void:
	_npc = WorldDB.get_entity("npc", npc_id)
	_speaker.text = _npc.name if NPCMemory.get_mem(npc_id).met else "Desconocido/a"
	visible = true
	_send("")


func close() -> void:
	if _busy:
		return
	visible = false
	StoryDirector.end_conversation(_npc.id)
	closed.emit(_npc.id)


func _on_say() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.clear()
	_send(text)


func _send(text: String) -> void:
	if _busy:
		return
	_set_busy(true)
	_clear_choices()
	if not text.is_empty():
		_line.text = "[color=#8fb3ff][i]Tú: %s[/i][/color]\n\n[color=gray]…[/color]" % text
	else:
		_line.text = "[color=gray]…[/color]"

	var turn := await StoryDirector.talk(_npc.id, text, scene_context)
	_set_busy(false)
	if not turn.ok:
		_line.text = "[color=red]%s[/color]" % turn.get("error", "Error")
		return

	_speaker.text = "%s %s" % [_npc.name, EMOTION_LABEL.get(turn.emotion, "")]
	_line.text = turn.line
	_line.visible_ratio = 0.0
	create_tween().tween_property(_line, "visible_ratio", 1.0, clampf(turn.line.length() * 0.02, 0.3, 2.5))

	if turn.end_conversation:
		_bye_btn.grab_focus()
		return
	for c in turn.choices:
		var b := Button.new()
		b.text = "› " + c.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_send.bind(c.text))
		_choices.add_child(b)


func _set_busy(value: bool) -> void:
	_busy = value
	_input.editable = not value
	_say_btn.disabled = value
	_bye_btn.disabled = value


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()

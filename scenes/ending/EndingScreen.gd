class_name EndingScreen
extends CanvasLayer
## Epílogo escrito para este jugador + créditos con el resumen de SU multiverso.

signal continue_requested

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const ENDING_NAMES := {
	"close_the_loop": "Final: El bucle cerrado",
	"return_home": "Final: Bahía de las Horas",
	"keep_traveling": "Final: Ramas sin nombre",
}

var title := ""
var epilogue := ""
var ending := ""

var _text: RichTextLabel
var _buttons: HBoxContainer


func _ready() -> void:
	layer = 50
	var bg := ColorRect.new()
	bg.color = Color("#04060d")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 160)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	_buttons.visible = false
	box.add_child(_buttons)

	_text.text = "[center][font_size=34][b]%s[/b][/font_size]\n[color=#9fd8ff]%s[/color][/center]\n\n%s\n\n\n%s" % [
		title, ENDING_NAMES.get(ending, ""), epilogue, _credits()]
	_text.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_property(_text, "visible_ratio", 1.0, clampf(_text.get_total_character_count() * 0.02, 4.0, 18.0))
	tw.tween_callback(func(): _buttons.visible = true)

	_button("Volver al menú principal", func(): get_tree().change_scene_to_file(MENU))
	if ending != "return_home":
		_button("Seguir explorando el multiverso", _continue)


func _continue() -> void:
	continue_requested.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	# Cualquier tecla o clic termina de mostrar el texto de golpe
	if not _buttons.visible and (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_text.visible_ratio = 1.0
		_buttons.visible = true


func _credits() -> String:
	var places := TimelineManager.visited_locations().size() - 1  # sin contar el pueblo
	var jumps := TimelineManager.nodes().size() - 1
	var done := Quests.all_quests().filter(func(q): return q.status == "done").size()
	var met := (WorldDB.get_state("memories", {}) as Dictionary).values().filter(func(m): return m.met).size()
	var companion: String = WorldDB.get_entity("npc", GameState.companion()).get("name", "nadie")
	return """[center][color=#f2a65a]— TU MULTIVERSO —[/color]
Mundos descubiertos: %d · Saltos: %d · Misiones: %d · Personas conocidas: %d
Compañía en el viaje: %s

Ningún otro jugador ha visto estos lugares ni conocido a estas personas.
Este universo solo existe en tu partida.


[color=#9fd8ff]DREAMER'S SPACE WORLD[/color]
Un juego de ahiram1701
Mundos, personas e historia generados por IA a partir de tus decisiones
Hecho con Godot Engine · IA: Ollama[/center]""" % [places, jumps, done, met, companion]


func _button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 44)
	b.pressed.connect(action)
	_buttons.add_child(b)

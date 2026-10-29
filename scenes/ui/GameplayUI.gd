class_name GameplayUI
extends Node
## Toda la interfaz de juego compartida por el pueblo y los mundos generados:
## stats, misión y coordenadas, Ancla (T), inventario (I), pausa (Esc), avisos,
## fallos visuales por inestabilidad y desanclaje. Bloquea al jugador mientras hay un panel abierto.

const GLITCH_SHADER := preload("res://scenes/ui/glitch.gdshader")
const DECAY_EVERY := 20.0      # segundos: la inestabilidad baja sola poco a poco
const DAMAGE_EVERY := 3.0      # segundos: con inestabilidad crítica el cuerpo sufre
const CRITICAL := 90

var player: Player
## Devuelve los ids de los PNJs de la escena (objetos de secretos/confianza).
var nearby_npcs: Callable = func(): return []

var anchor: AnchorPanel
var inventory: InventoryPanel
var pause: PauseMenu
var _hud: CanvasLayer
var _tracker: Label
var _toast: Label
var _glitch: ColorRect
var _blocks := 0
var _decay_t := 0.0
var _damage_t := 0.0
var _unanchoring := false


func _ready() -> void:
	add_child(StatsHUD.new())
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_tracker = _label(Vector2(0, 16), 18, Color("#ffd9a0"))
	_tracker.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	_tracker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = _label(Vector2.ZERO, 20, Color("#9fd8ff"))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 90)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 700
	_toast.modulate.a = 0.0

	var glitch_layer := CanvasLayer.new()
	glitch_layer.layer = 4
	add_child(glitch_layer)
	_glitch = ColorRect.new()
	_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLITCH_SHADER
	_glitch.material = mat
	glitch_layer.add_child(_glitch)

	anchor = AnchorPanel.new()
	add_child(anchor)
	inventory = InventoryPanel.new()
	inventory.nearby_npcs = func(): return nearby_npcs.call()
	add_child(inventory)
	pause = PauseMenu.new()
	add_child(pause)
	for panel in [anchor, inventory, pause]:
		panel.opened.connect(block.bind(true))
		panel.closed.connect(block.bind(false))
	inventory.message.connect(toast)

	GameState.stat_changed.connect(_on_stat_changed)
	Quests.quest_completed.connect(_on_quest_completed)
	Inventory.changed.connect(refresh_tracker)
	refresh_tracker()
	_update_glitch()


## Bloquea o libera al jugador (paneles, diálogos). Admite varios bloqueos a la vez.
func block(on: bool) -> void:
	_blocks = maxi(_blocks + (1 if on else -1), 0)
	if player:
		player.controls_enabled = _blocks == 0


func toast(text: String) -> void:
	if text.is_empty():
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(clampf(text.length() * 0.06, 3.0, 9.0))
	tw.tween_property(_toast, "modulate:a", 0.0, 1.0)


func refresh_tracker() -> void:
	var lines := PackedStringArray()
	var q := Quests.for_location(GameState.current_location())
	if not q.is_empty():
		lines.append("Misión: " + Quests.objective_text(q))
	var at_origin: bool = WorldDB.get_entity("location", GameState.current_location()).get("finale", false)
	if at_origin:
		lines.append("El origen de la señal" if GameState.ending().is_empty() else "Has cerrado esta historia. El multiverso sigue abierto.")
	elif GameState.is_awakened():
		if GameState.has_all_fragments() and GameState.ending().is_empty():
			lines.append("Coordenadas completas — usa el Ancla (T) para seguir la señal hasta su origen")
		elif GameState.ending().is_empty():
			lines.append("Coordenadas de la transmisión: %d/%d" % [GameState.fragments(), GameState.FRAGMENTS_NEEDED])
	_tracker.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if inventory.is_open():
				inventory.close()
			elif anchor.is_open():
				anchor.close()
			else:
				pause.toggle()
			get_viewport().set_input_as_handled()
		KEY_I:
			if not pause.is_open():
				inventory.toggle()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not GameState.is_awakened() or _unanchoring or _blocks > 0:
		return
	var instability := GameState.get_stat("instability")
	_decay_t += delta
	if _decay_t >= DECAY_EVERY:
		_decay_t = 0.0
		if instability > 0 and instability < CRITICAL:
			GameState.change_stat("instability", -1)
	if instability >= CRITICAL:
		_damage_t += delta
		if _damage_t >= DAMAGE_EVERY:
			_damage_t = 0.0
			GameState.change_stat("health", -2)
			toast("Tu cuerpo no soporta tanta decoherencia. Recarga el Ancla o usa algo que te estabilice.")


func _on_stat_changed(stat: String, value: int) -> void:
	if stat == "instability":
		_update_glitch()
	elif stat == "fragments":
		refresh_tracker()
	elif stat == "health" and value <= 0 and GameState.is_awakened():
		_unanchor()


func _on_quest_completed(q: Dictionary, reward: String) -> void:
	toast("%s\n%s" % [q.completion_text, reward])
	refresh_tracker()


func _update_glitch() -> void:
	var intensity := clampf(remap(GameState.get_stat("instability"), 60, 100, 0.0, 1.0), 0.0, 1.0)
	_glitch.visible = intensity > 0.0
	(_glitch.material as ShaderMaterial).set_shader_parameter("intensity", intensity)


## Salud a 0: te dispersas entre ramas. El Ancla te recompone aquí, con un coste.
func _unanchor() -> void:
	if _unanchoring:
		return
	_unanchoring = true
	block(true)
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var text := Label.new()
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 22)
	text.text = "Te has desanclado.\n\nDurante un instante estás en mil ramas a la vez.\nEl Ancla tira de ti y te recompone, pero algo se queda atrás."
	layer.add_child(text)
	await get_tree().create_timer(4.0).timeout
	var lost := GameState.recover_from_unanchor()
	if not lost.is_empty():
		text.text += "\n\nHas perdido: %s" % lost
		await get_tree().create_timer(2.5).timeout
	get_tree().reload_current_scene()


func _label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(l)
	return l

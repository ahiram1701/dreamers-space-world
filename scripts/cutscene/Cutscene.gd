class_name Cutscene
extends CanvasLayer
## Una escena de cine dentro del juego: la cámara se mueve, los personajes actúan y los
## subtítulos van de una o dos líneas que avanzan con clic, E o espacio (nunca desaparecen
## solos). Esc salta la escena entera. Al terminar, lo dicho queda en el Diario.
##
##   var cs := Cutscene.new()
##   add_child(cs)
##   await cs.begin(player)
##   await cs.shot(Vector3(0, 3, 8), Vector3.ZERO, 2.0)
##   await cs.line("El faro se apaga.")
##   await cs.finish("El Despertar")
##
## En pruebas (o sin pantalla) avanza sola: Engine.set_meta("cutscene_auto", true).

signal advanced

const BAR_H := 70.0

var skipping := false
var lines_said: PackedStringArray = []

var _player: Node3D
var _cam: Camera3D
var _prev_cam: Camera3D
var _bars: Array[ColorRect] = []
var _box: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _hint: Label
var _flash: ColorRect
var _typing: Tween
var _waiting := false
var _shake := 0.0
var _base_pos := Vector3.ZERO
var _moves: Array[Tween] = []


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else 0.0
		bar.offset_bottom = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_box = PanelContainer.new()
	_box.anchor_left = 0.14
	_box.anchor_right = 0.86
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_bottom = -BAR_H - 14.0
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.72)
	style.set_corner_radius_all(10)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 10
	_box.add_theme_stylebox_override("panel", style)
	_box.visible = false
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_box.add_child(v)
	_speaker = Label.new()
	_speaker.add_theme_color_override("font_color", Color("#f2a65a"))
	_speaker.add_theme_font_size_override("font_size", 17)
	v.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 22)
	v.add_child(_text)
	_hint = Label.new()
	_hint.text = "clic, E o espacio para seguir · Esc para saltar"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_hint.add_theme_font_size_override("font_size", 12)
	v.add_child(_hint)


func _auto() -> bool:
	return bool(Engine.get_meta("cutscene_auto", false)) or DisplayServer.get_name() == "headless"


## Empieza: quita el control al jugador, pone las bandas y una cámara propia donde está la suya.
func begin(player: Node3D) -> void:
	_player = player
	if player and "controls_enabled" in player:
		player.controls_enabled = false
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 4000.0
	var host: Node = player.get_parent() if player else get_parent()
	host.add_child(_cam)
	if _prev_cam:
		_cam.global_transform = _prev_cam.global_transform
	_cam.make_current()
	_base_pos = _cam.global_position
	var tw := create_tween().set_parallel()
	tw.tween_property(_bars[0], "offset_bottom", BAR_H, 0.6)
	tw.tween_property(_bars[1], "offset_top", -BAR_H, 0.6)
	if not _auto():
		await tw.finished


## Mueve la cámara a `pos` mirando a `look` en `dur` segundos (0: corte directo).
func shot(pos: Vector3, look: Vector3, dur: float = 0.0) -> void:
	if _cam == null:
		return
	var target := Transform3D(Basis.looking_at((look - pos).normalized() if pos.distance_to(look) > 0.01 else Vector3.FORWARD, Vector3.UP), pos)
	if dur <= 0.0 or skipping or _auto():
		_cam.global_transform = target
		_base_pos = pos
		return
	var from := _cam.global_transform
	var tw := create_tween()
	_moves.append(tw)
	tw.tween_method(func(t: float):
		if _cam and is_instance_valid(_cam):
			_cam.global_transform = from.interpolate_with(target, t)
			_base_pos = _cam.global_position, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## Un subtítulo. Espera a que el jugador lo haya leído (clic, E o espacio).
func line(text: String, speaker: String = "") -> void:
	if text.strip_edges().is_empty():
		return
	lines_said.append(("%s: %s" % [speaker, text]) if not speaker.is_empty() else text)
	if skipping:
		return
	_box.visible = true
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	_text.text = text
	_text.visible_ratio = 0.0
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, clampf(text.length() * 0.022, 0.3, 2.5) / clampf(Settings.text_speed, 0.25, 4.0))
	if _auto():
		_text.visible_ratio = 1.0
		await get_tree().process_frame
		return
	_waiting = true
	await advanced
	_waiting = false


## Una persona de la escena lo dice (bocadillo encima y subtítulo con su nombre).
func say(npc: Node, text: String) -> void:
	var who := ""
	if npc:
		if npc.has_method("say"):
			npc.say(text, Settings.read_time(text))
		if npc.has_method("play_gesture"):
			npc.play_gesture("nod", 1.2)
		var id := str(npc.get("npc_id")) if npc.get("npc_id") != null else ""
		who = str(WorldDB.get_entity("npc", id).get("name", "")).get_slice(" ", 0) if not id.is_empty() else ""
	await line(text, who)


func wait(seconds: float) -> void:
	if skipping or _auto() or seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


func hide_text() -> void:
	_box.visible = false


## Efectos: "flash" (destello blanco), "white" / "black" (fundido a blanco o negro),
## "clear" (vuelve a verse), "shake" (sacudida).
func fx(name: String, dur: float = 0.6) -> void:
	match name:
		"flash":
			_flash.color = Color(1, 1, 1, 0.95)
			create_tween().tween_property(_flash, "color:a", 0.0, dur)
		"white":
			_flash.color = Color(1, 1, 1, _flash.color.a)
			await _fade(1.0, dur)
		"black":
			_flash.color = Color(0, 0, 0, _flash.color.a)
			await _fade(1.0, dur)
		"clear":
			await _fade(0.0, dur)
		"shake":
			_shake = maxf(_shake, dur)


func _fade(a: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", a, 0.01 if skipping or _auto() else dur)
	await tw.finished


func _process(delta: float) -> void:
	if _cam and is_instance_valid(_cam) and _shake > 0.0:
		_shake -= delta
		_cam.global_position = _base_pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06 * clampf(_shake, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if _cam == null:
		return
	var esc: bool = event.is_action_pressed("ui_cancel") or (event.has_method("is_action_pressed") and InputMap.has_action("pause") and event.is_action_pressed("pause"))
	if esc:
		skipping = true
		get_viewport().set_input_as_handled()
		if _waiting:
			advanced.emit()
		return
	var go: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or event.is_action_pressed("ui_accept") or (InputMap.has_action("interact") and event.is_action_pressed("interact")) \
		or (InputMap.has_action("jump") and event.is_action_pressed("jump"))
	if go and _waiting:
		get_viewport().set_input_as_handled()
		if _text.visible_ratio < 1.0:  # primero se ve entero; el segundo clic sigue
			if _typing and _typing.is_valid():
				_typing.kill()
			_text.visible_ratio = 1.0
		else:
			advanced.emit()


## Termina: devuelve la cámara y el control, y guarda lo contado en el Diario.
func finish(title: String = "", give_control: bool = true) -> void:
	_box.visible = false
	if not lines_said.is_empty() and not title.is_empty():
		Journal.add("%s\n%s" % [title, "\n".join(lines_said)])
	var tw := create_tween().set_parallel()
	tw.tween_property(_bars[0], "offset_bottom", 0.0, 0.5)
	tw.tween_property(_bars[1], "offset_top", 0.0, 0.5)
	if not _auto():
		await tw.finished
	for mv in _moves:  # un movimiento de cámara a medias no sigue sobre una cámara que ya no está
		if mv and mv.is_valid():
			mv.kill()
	_moves.clear()
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if _cam:
		_cam.queue_free()
		_cam = null
	if give_control and _player and is_instance_valid(_player) and "controls_enabled" in _player:
		_player.controls_enabled = true
	if _flash.color.a > 0.0:
		await _fade(0.0, 0.5)

class_name AwakeningSequence
extends Node
## El Despertar dentro de Bahía de las Horas: el pulso de las 3:33, el campo de dilatación,
## la brecha, la narración generada para ESTE jugador, su decisión y el primer salto.
## Toda la física es local: el mar no se para, se mueve tan despacio que no se nota.

const BREACH_SHADER := preload("res://scenes/awakening/breach.gdshader")

var player: Player
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var beacon: OmniLight3D
var breach_position: Vector3

var _flicker := false
var _loading: LoadingOverlay
var _layer: CanvasLayer
var _text: RichTextLabel
var _choices: VBoxContainer
var _data: Dictionary = {}


func play() -> void:
	player.controls_enabled = false
	_loading = LoadingOverlay.new()
	add_child(_loading)

	# 1. El pulso: cae la noche, las luces mueren, todo tiembla
	_flicker = true
	player.shake(2.8, 0.09)
	var night := create_tween().set_parallel()
	night.tween_property(sun, "light_energy", 0.03, 2.5)
	night.tween_property(sky_mat, "sky_top_color", Color("#04060d"), 2.5)
	night.tween_property(sky_mat, "sky_horizon_color", Color("#121a30"), 2.5)
	night.tween_property(sky_mat, "ground_horizon_color", Color("#121a30"), 2.5)
	night.tween_property(env, "fog_light_color", Color("#1a2340"), 2.5)
	await night.finished
	_flicker = false
	beacon.light_energy = 0.0

	# 2. El campo de dilatación: el color se apaga y aparece la brecha
	env.adjustment_enabled = true
	var field := create_tween().set_parallel()
	field.tween_property(env, "adjustment_saturation", 0.35, 1.5)
	field.tween_property(env, "adjustment_contrast", 1.15, 1.5)
	_spawn_breach()
	await field.finished

	# 3. La IA escribe el Despertar de este jugador
	_loading.show_loading("3:33", PackedStringArray([
		"Algo curva el aire en la base del faro", "Tu móvil se apaga en tu mano",
		"El mar avanza demasiado despacio", "El pulso no termina"]))
	_data = await StoryDirector.generate_awakening()
	_loading.hide_loading()
	_show_panel()


func _process(_delta: float) -> void:
	if _flicker:
		beacon.light_energy = 12.0 if randf() < 0.5 else 0.0


func _spawn_breach() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = BREACH_SHADER
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.mesh.radius = 1.3
	sphere.mesh.height = 2.6
	sphere.material_override = mat
	sphere.position = breach_position
	sphere.scale = Vector3.ONE * 0.01
	add_child(sphere)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#73d9ff")
	glow.omni_range = 14.0
	glow.light_energy = 3.0
	glow.position = breach_position
	add_child(glow)
	create_tween().tween_property(sphere, "scale", Vector3.ONE, 1.5).set_trans(Tween.TRANS_ELASTIC)


func _show_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.1, 0.94)
	style.border_color = Color("#73d9ff")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.text = "[font_size=28][b]%s[/b][/font_size]\n\n%s\n\n[color=#9fd8ff][i]%s[/i][/color]\n\n[b]Tu Ancla — %s[/b]\n%s" % [
		_data.title, _data.narration, _data.source_description, _data.anchor.name, _data.anchor.description]
	_text.visible_ratio = 0.0
	box.add_child(_text)
	create_tween().tween_property(_text, "visible_ratio", 1.0, clampf(_text.get_total_character_count() * 0.012, 2.0, 9.0))

	var ask := Label.new()
	ask.text = "La brecha empieza a cerrarse. ¿Qué haces?"
	ask.add_theme_color_override("font_color", Color("#f2a65a"))
	box.add_child(ask)
	_choices = VBoxContainer.new()
	box.add_child(_choices)
	for i in _data.choices.size():
		var b := Button.new()
		b.text = "› " + _data.choices[i].text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_choose.bind(i))
		_choices.add_child(b)


func _choose(index: int) -> void:
	for b in _choices.get_children():
		b.disabled = true
	StoryDirector.apply_awakening(_data, index)
	await _jump()


func _jump() -> void:
	_layer.visible = false
	player.shake(1.5, 0.15)
	_loading.show_loading("Cruzando la brecha", PackedStringArray([
		"Sincronizando el Ancla", "Calculando trayectoria", "Buscando una rama compatible"]))
	var r := await Travel.jump_new()
	if r.ok:
		get_tree().change_scene_to_file(Travel.scene_for(r.location_id))
		return
	# El Despertar ya está aplicado: solo hay que reintentar el salto (o hacerlo luego con T)
	_loading.hide_loading()
	_layer.visible = true
	for c in _choices.get_children():
		c.queue_free()
	var retry := Button.new()
	retry.text = "Reintentar el salto  (%s)" % r.error
	retry.pressed.connect(_jump)
	_choices.add_child(retry)

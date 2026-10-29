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
var _panel: NarrativePanel
var _data: Dictionary = {}


func play() -> void:
	player.controls_enabled = false
	_loading = LoadingOverlay.new()
	add_child(_loading)
	_panel = NarrativePanel.new()
	add_child(_panel)

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
	spawn_breach(self, breach_position, 1.3)
	await field.finished

	# 3. La IA escribe el Despertar de este jugador
	_loading.show_loading("3:33", PackedStringArray([
		"Algo curva el aire en la base del faro", "Tu móvil se apaga en tu mano",
		"El mar avanza demasiado despacio", "El pulso no termina"]))
	_data = await StoryDirector.generate_awakening()
	_loading.hide_loading()
	_panel.present("[font_size=28][b]%s[/b][/font_size]\n\n%s\n\n[color=#9fd8ff][i]%s[/i][/color]\n\n[b]Tu Ancla — %s[/b]\n%s" % [
		_data.title, _data.narration, _data.source_description, _data.anchor.name, _data.anchor.description],
		"La brecha empieza a cerrarse. ¿Qué haces?", _data.choices.map(func(c): return c.text))
	_panel.chosen.connect(_choose, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if _flicker:
		beacon.light_energy = 12.0 if randf() < 0.5 else 0.0


## Una brecha visible: esfera con lente gravitatoria + luz. También la usa el final.
static func spawn_breach(parent: Node, pos: Vector3, radius: float) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = BREACH_SHADER
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.mesh.radius = radius
	sphere.mesh.height = radius * 2.0
	sphere.material_override = mat
	sphere.position = pos
	sphere.scale = Vector3.ONE * 0.01
	parent.add_child(sphere)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#73d9ff")
	glow.omni_range = radius * 10.0
	glow.light_energy = 3.0
	glow.position = pos
	parent.add_child(glow)
	sphere.create_tween().tween_property(sphere, "scale", Vector3.ONE, 1.5).set_trans(Tween.TRANS_ELASTIC)
	return sphere


func _choose(index: int) -> void:
	StoryDirector.apply_awakening(_data, index)
	await _jump()


func _jump() -> void:
	_panel.visible = false
	player.shake(1.5, 0.15)
	_loading.show_loading("Cruzando la brecha", PackedStringArray([
		"Sincronizando el Ancla", "Calculando trayectoria", "Buscando una rama compatible"]), true)
	var r := await Travel.jump_new()
	if r.ok:
		get_tree().change_scene_to_file(Travel.scene_for(r.location_id))
		return
	# El Despertar ya está aplicado: solo hay que reintentar el salto (o hacerlo luego con T)
	_loading.hide_loading()
	_panel.visible = true
	_panel.set_options(["Reintentar el salto  (%s)" % r.error])
	_panel.chosen.connect(func(_i): _jump(), CONNECT_ONE_SHOT)

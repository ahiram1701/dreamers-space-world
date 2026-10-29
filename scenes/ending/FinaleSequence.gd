class_name FinaleSequence
extends Node
## En el origen de la señal: la brecha original, el emisor, la revelación escrita para este
## jugador y la decisión final. Después, el epílogo y los créditos.

var player: Player
var center: Vector3

var _loading: LoadingOverlay
var _panel: NarrativePanel
var _data: Dictionary = {}


func play() -> void:
	player.controls_enabled = false
	_build_emitter()
	_loading = LoadingOverlay.new()
	add_child(_loading)
	_panel = NarrativePanel.new()
	add_child(_panel)
	await get_tree().create_timer(2.5).timeout  # un momento para ver el lugar

	_loading.show_loading("La señal", PackedStringArray([
		"Todas las ramas convergen aquí", "La transmisión suena a tu alrededor", "Reconoces una voz"]))
	_data = await StoryDirector.generate_finale()
	_loading.hide_loading()
	_panel.present("[font_size=28][b]%s[/b][/font_size]\n\n%s\n\n[color=#9fd8ff][i]«%s»[/i][/color]" % [
		_data.title, _data.revelation, _data.source_voice],
		"Es la última decisión de este viaje.", _data.choices.map(func(c): return c.text))
	_panel.chosen.connect(_choose, CONNECT_ONE_SHOT)


func _choose(index: int) -> void:
	var result := StoryDirector.apply_ending(_data, index)
	_panel.visible = false
	player.shake(2.0, 0.12)
	await get_tree().create_timer(1.5).timeout
	if result.ending == "return_home":
		GameState.set_location(GameState.HOME)  # "Continuar" te dejará en Bahía de las Horas
	var screen := EndingScreen.new()
	screen.title = result.title
	screen.epilogue = result.epilogue
	screen.ending = result.ending
	add_child(screen)
	screen.continue_requested.connect(func(): player.controls_enabled = true)


## La brecha original y un transmisor hecho con piezas de todos los mundos visitados.
func _build_emitter() -> void:
	AwakeningSequence.spawn_breach(self, center + Vector3(0, 9, -14), 7.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8a8f99")
	mat.metallic = 0.7
	mat.roughness = 0.35
	var base := MeshInstance3D.new()
	base.mesh = CylinderMesh.new()
	base.mesh.top_radius = 1.2
	base.mesh.bottom_radius = 1.6
	base.mesh.height = 1.4
	base.material_override = mat
	base.position = center + Vector3(0, 0.7, -6)
	add_child(base)
	var mast := MeshInstance3D.new()
	mast.mesh = CylinderMesh.new()
	mast.mesh.top_radius = 0.08
	mast.mesh.bottom_radius = 0.15
	mast.mesh.height = 6.0
	mast.material_override = mat
	mast.position = center + Vector3(0, 4.4, -6)
	add_child(mast)
	var light := OmniLight3D.new()
	light.light_color = Color("#f2a65a")
	light.omni_range = 8.0
	light.position = center + Vector3(0, 7.5, -6)
	add_child(light)
	var tw := light.create_tween().set_loops()
	tw.tween_property(light, "light_energy", 4.0, 0.333)
	tw.tween_property(light, "light_energy", 0.3, 0.333)
	var label := Label3D.new()
	label.text = "Emisor"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.01
	label.position = center + Vector3(0, 8.5, -6)
	add_child(label)

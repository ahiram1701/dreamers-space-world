class_name AwakeningSequence
extends Node
## El Despertar: a las 3:33 la lámpara del faro se enciende sola, el mar se queda quieto y una
## grieta junto a la puerta se abre y te arrastra lejos de casa. Se cuenta como una escena de
## cine (tomas de lo que hay de verdad: el faro, la puerta, el mar, el pueblo) con subtítulos
## cortos que avanzan con clic. Una sola decisión, concreta: agarrar o no la mano de quien llega.

const BREACH_SHADER := preload("res://scenes/awakening/breach.gdshader")

var player: Player
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var beacon: OmniLight3D
var breach_position: Vector3
var tower_position := Vector3.ZERO      # pie del faro
var town_position := Vector3.ZERO       # centro del pueblo (para las tomas de las luces)
var tower_height := 18.0
var npcs: Dictionary = {}               # id → TownNPC (para que el vecino llegue corriendo)

var _flicker := false
var _loading: LoadingOverlay
var _panel: NarrativePanel
var _cut: Cutscene
var _breach: MeshInstance3D
var _data: Dictionary = {}


func play() -> void:
	player.controls_enabled = false
	_loading = LoadingOverlay.new()
	add_child(_loading)
	_panel = NarrativePanel.new()
	add_child(_panel)
	_panel.set_compact()
	_cut = Cutscene.new()
	add_child(_cut)
	await _cut.begin(player)
	if tower_position == Vector3.ZERO:
		tower_position = breach_position + Vector3(3.5, -1.6, -3.5)

	# 1. El pulso: cae la noche, las luces mueren, la lámpara parpadea sola
	_flicker = true
	_cut.fx("shake", 2.5)
	var night := create_tween().set_parallel()
	night.tween_property(sun, "light_energy", 0.03, 2.5)
	night.tween_property(sky_mat, "sky_top_color", Color("#04060d"), 2.5)
	night.tween_property(sky_mat, "sky_horizon_color", Color("#121a30"), 2.5)
	night.tween_property(sky_mat, "ground_horizon_color", Color("#121a30"), 2.5)
	night.tween_property(env, "fog_light_color", Color("#1a2340"), 2.5)
	await _cut.shot(_cam_for("lighthouse").pos, _cam_for("lighthouse").look, 2.5)
	_flicker = false
	beacon.light_energy = 0.0

	# 2. El color se apaga y aparece la grieta, aún pequeña
	env.adjustment_enabled = true
	var field := create_tween().set_parallel()
	field.tween_property(env, "adjustment_saturation", 0.35, 1.5)
	field.tween_property(env, "adjustment_contrast", 1.15, 1.5)
	_breach = spawn_breach(self, breach_position, 0.5)

	# 3. La IA escribe la escena de ESTE jugador (mientras, la grieta late)
	_loading.show_loading("3:33 a. m.", PackedStringArray([
		"La lámpara del faro gira sola", "Tu celular se apaga en tu mano",
		"El mar se queda quieto a medio romper", "Algo dobla el aire junto a la puerta"]))
	_data = await StoryDirector.generate_awakening()
	_loading.hide_loading()

	# 4. La escena, toma a toma
	for beat in _data.get("beats", []):
		var shot := str(beat.get("shot", "breach"))
		var cam := _cam_for(shot)
		_stage(shot)
		await _cut.shot(cam.pos, cam.look, 1.4)
		await _cut.line(str(beat.get("line", "")))
		if _cut.skipping:
			break
	_cut.hide_text()

	# 5. La única decisión
	var anchor: Dictionary = _data.get("anchor", {})
	_panel.present("[font_size=24][b]%s[/b][/font_size]\n\n[color=#9fd8ff]En tu mano: [b]%s[/b][/color]\n%s" % [
		_data.get("title", "3:33"), anchor.get("name", "la brújula"), anchor.get("description", "")],
		"La brecha tira de ti. ¿Qué haces?", _data.choices.map(func(c): return c.text))
	_panel.chosen.connect(_choose, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if _flicker:
		beacon.light_energy = 12.0 if randf() < 0.5 else 0.0


## Dónde se pone la cámara y a qué mira en cada toma (todas son de cosas que existen aquí).
func _cam_for(shot: String) -> Dictionary:
	var out := breach_position - tower_position
	out.y = 0.0
	out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD
	var side := out.cross(Vector3.UP).normalized()
	var to_sea := tower_position - town_position
	to_sea.y = 0.0
	to_sea = to_sea.normalized() if to_sea.length() > 0.1 else out
	var head := player.global_position + Vector3(0, 1.6, 0)
	var facing := (breach_position - player.global_position)
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.1 else out
	match shot:
		"lighthouse":
			return {"pos": tower_position + out * 24.0 + side * 6.0 + Vector3(0, 5.0, 0), "look": tower_position + Vector3(0, tower_height * 0.55, 0)}
		"lamp":
			return {"pos": tower_position + out * 9.0 + Vector3(0, tower_height - 3.0, 0), "look": tower_position + Vector3(0, tower_height - 1.0, 0)}
		"door":
			return {"pos": breach_position + out * 4.5 + side * 1.6 + Vector3(0, 0.3, 0), "look": breach_position + Vector3(0, -0.2, 0)}
		"crack":
			return {"pos": breach_position + out * 1.8 + side * 0.6, "look": breach_position}
		"breach":
			return {"pos": breach_position + out * 7.0 - side * 3.0 + Vector3(0, 1.2, 0), "look": breach_position}
		"sea":
			return {"pos": tower_position + Vector3(0, 6.0, 0) + to_sea * 4.0, "look": tower_position + to_sea * 70.0}
		"sky":
			return {"pos": head, "look": head + Vector3(0, 10, 0) + out * 3.0}
		"town":
			return {"pos": tower_position + out * 6.0 + Vector3(0, 4.0, 0), "look": town_position + Vector3(0, 2.0, 0)}
		"player", "companion":
			return {"pos": head + facing * 1.7 + side * 0.4, "look": head}
		"watch":
			return {"pos": head + facing * 0.9 + Vector3(0, -0.4, 0), "look": player.global_position + Vector3(0, 1.0, 0)}
	return {"pos": breach_position + out * 6.0 + Vector3(0, 1.5, 0), "look": breach_position}


## Lo que pasa en cada toma: la grieta crece, el vecino llega corriendo, todo tiembla.
func _stage(shot: String) -> void:
	match shot:
		"lamp":
			_flicker = true
			get_tree().create_timer(1.5).timeout.connect(func(): _flicker = false; beacon.light_energy = 0.0)
		"crack":
			if _breach:
				create_tween().tween_property(_breach, "scale", Vector3.ONE * 1.4, 1.2)
		"breach":
			if _breach:
				create_tween().tween_property(_breach, "scale", Vector3.ONE * 3.2, 1.6).set_trans(Tween.TRANS_EXPO)
			_cut.fx("shake", 1.6)
			player.play_gesture("crouch", 1.5)
		"companion":
			var id := str(_data.get("companion", ""))
			var npc: Node3D = npcs.get(id)
			if npc and is_instance_valid(npc):
				var from := player.global_position + (town_position - player.global_position).normalized() * 9.0
				npc.global_position = Vector3(from.x, player.global_position.y + 0.2, from.z)
				if npc.has_method("walk_to"):
					npc.walk_to(player.global_position + Vector3(1.2, 0, 0.8), true)
				if npc.has_method("face"):
					npc.face(player.global_position)


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
	_panel.visible = false
	var result := StoryDirector.apply_awakening(_data, index)
	var companion := str(result.get("companion", ""))
	if not companion.is_empty():
		var cam := _cam_for("companion")
		await _cut.shot(cam.pos, cam.look, 0.8)
		await _cut.say(npcs.get(companion), str(_data.get("companion_line", "¡Agárrate!")))
	var b := _cam_for("breach")
	_cut.fx("shake", 2.0)
	await _cut.shot(b.pos.lerp(breach_position, 0.85), breach_position, 1.2)
	await _cut.fx("white", 0.8)
	await _cut.finish(str(_data.get("title", "El Despertar")), false)
	await _jump()


func _jump() -> void:
	_panel.visible = false
	_loading.show_loading("Arrastrado por la brecha", PackedStringArray([
		"La brújula gira sin parar", "Caes sin caer", "Algo te suelta lejos de casa"]), true)
	var r := await Travel.jump_new()
	if r.ok:
		get_tree().change_scene_to_file(Travel.scene_for(r.location_id))
		return
	# El Despertar ya está aplicado: solo hay que reintentar el salto (o hacerlo luego con T)
	_loading.hide_loading()
	_panel.visible = true
	_panel.set_options(["Reintentar el salto  (%s)" % r.error])
	_panel.chosen.connect(func(_i): _jump(), CONNECT_ONE_SHOT)

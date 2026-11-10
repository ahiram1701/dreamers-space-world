class_name AwakeningSequence
extends Node
## El Despertar: a las 3:33 la lámpara del faro se enciende sola, el mar se queda quieto y una
## grieta junto a la puerta se abre y te arrastra lejos de casa.
##
## Regla: el MOTOR decide qué pasa en cada toma y con quién (según lo que hay de verdad: qué
## vecino puede venir, dónde vive); la IA solo escribe la frase de cada toma ya decidida. Al
## final de cada toma se comprueba que lo que dice la frase se ve (el vecino visible, en el
## encuadre y cerca); si no, la frase se cambia por una neutra.

const BREACH_SHADER := preload("res://scenes/awakening/breach.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

var player: Player
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var beacon: OmniLight3D
var breach_position: Vector3
var tower_position := Vector3.ZERO      # pie del faro
var town_position := Vector3.ZERO       # centro del pueblo (para las tomas de las luces)
var tower_height := 18.0
var npcs: Dictionary = {}               # id → TownNPC
var door_position: Callable             # id de puerta → posición (para que el vecino salga de su casa)

var _flicker := false
var _loading: LoadingOverlay
var _panel: NarrativePanel
var _cut: Cutscene
var _breach: MeshInstance3D
var _compass: Node3D
var _data: Dictionary = {}
var _friend: TownNPC
var _friend_id := ""
var log_checks: Array = []              # comprobaciones de cada toma (para las pruebas)


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
	_friend_id = StoryDirector.awakening_friend()
	_friend = npcs.get(_friend_id)
	if _friend and not is_instance_valid(_friend):
		_friend = null

	# 1. El pulso: cae la noche y las luces mueren (la lámpara aún no)
	var night := create_tween().set_parallel()
	night.tween_property(sun, "light_energy", 0.03, 2.5)
	night.tween_property(sky_mat, "sky_top_color", Color("#04060d"), 2.5)
	night.tween_property(sky_mat, "sky_horizon_color", Color("#121a30"), 2.5)
	night.tween_property(sky_mat, "ground_horizon_color", Color("#121a30"), 2.5)
	night.tween_property(env, "fog_light_color", Color("#1a2340"), 2.5)
	var c0 := _cam_for("lighthouse")
	await _cut.shot(c0.pos, c0.look, 2.5)

	# 2. La IA escribe la frase de cada toma YA DECIDIDA
	var plan := shot_plan()
	_loading.show_loading("3:33 a. m.", PackedStringArray([
		"La lámpara del faro gira sola", "El mar se queda quieto", "Algo dobla el aire junto a la puerta"]))
	_data = await StoryDirector.generate_awakening(plan)
	_loading.hide_loading()

	# 3. La escena, toma a toma: primero ocurre, luego se dice
	for beat in _data.beats:
		var shot := str(beat.shot)
		await _stage(shot)
		var cam := _cam_for(shot)
		await _cut.shot(cam.pos, cam.look, 1.2)
		var line := str(beat.line)
		if not _visible_ok(shot):
			line = str(StoryDirector.NEUTRAL_BEATS.get(shot, ""))
		await _cut.line(line)
		if _cut.skipping:
			break
	_cut.hide_text()

	# 4. La única decisión (solo si el vecino está aquí de verdad)
	var anchor: Dictionary = _data.get("anchor", {})
	_panel.present("[font_size=24][b]%s[/b][/font_size]\n\n[color=#9fd8ff]En tu mano: [b]%s[/b][/color]\n%s" % [
		_data.get("title", "3:33"), anchor.get("name", "la brújula"), anchor.get("description", "")],
		"La brecha tira de ti. ¿Qué haces?", _data.choices.map(func(c): return c.text))
	_panel.chosen.connect(_choose, CONNECT_ONE_SHOT)


## Las tomas que se pueden escenificar ahora, en orden, con lo que pasa en cada una.
func shot_plan() -> Array:
	var who := str(WorldDB.get_entity("npc", _friend_id).get("name", "")).get_slice(" ", 0) if _friend else ""
	var plan := [
		{"shot": "lighthouse", "does": "el faro entero de noche; su lámpara, apagada desde hace años, empieza a parpadear sola"},
		{"shot": "lamp", "does": "primer plano de la lámpara de arriba encendiéndose y girando sin corriente"},
		{"shot": "sea", "does": "el mar se calma de golpe: las olas se aplanan y deja de oírse el oleaje"},
		{"shot": "crack", "does": "junto a la puerta del faro aparece una grieta brillante en el aire, del tamaño de una moneda, que crece"},
		{"shot": "breach", "does": "la grieta se abre enorme y tira de todo; el jugador se agacha para no caer"},
	]
	if _friend:
		plan.append({"shot": "companion", "does": "%s sale corriendo de su casa y llega hasta el jugador, a su lado" % who})
	plan.append({"shot": "watch", "does": "el jugador mira la brújula que tiene en la mano: la aguja gira y se queda apuntando al pueblo"})
	return plan


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
		"companion":
			# Desde detrás del jugador, mirando hacia donde llega el vecino: se le ve llegar
			if _friend:
				var mid := (_friend.global_position + player.global_position) / 2.0
				var across := (_friend.global_position - player.global_position)
				across.y = 0.0
				var perp := across.normalized().cross(Vector3.UP) if across.length() > 0.2 else side
				return {"pos": mid + perp * maxf(4.0, across.length() * 0.7) + Vector3(0, 1.8, 0), "look": mid + Vector3(0, 1.1, 0)}
		"player":
			return {"pos": head + facing * 1.7 + side * 0.4, "look": head}
		"watch":
			return {"pos": head + facing * 0.8 + side * 0.25 + Vector3(0, -0.25, 0), "look": _compass.global_position if _compass else head + Vector3(0, -0.5, 0)}
	return {"pos": breach_position + out * 6.0 + Vector3(0, 1.5, 0), "look": breach_position}


## Lo que pasa en cada toma, de verdad, antes de su frase.
func _stage(shot: String) -> void:
	match shot:
		"lighthouse", "lamp":
			_flicker = true
		"sea":
			_flicker = false
			beacon.light_energy = 6.0
			_calm_sea()
		"crack":
			_breach = spawn_breach(self, breach_position, 0.5)
			create_tween().tween_property(_breach, "scale", Vector3.ONE * 1.4, 1.2).set_delay(1.5)
		"breach":
			if _breach == null:
				_breach = spawn_breach(self, breach_position, 0.5)
			create_tween().tween_property(_breach, "scale", Vector3.ONE * 3.2, 1.6).set_trans(Tween.TRANS_EXPO)
			_cut.fx("shake", 1.6)
			player.face_towards(breach_position)
			player.play_gesture("crouch", 2.5)
		"companion":
			await _bring_friend()
		"watch":
			_show_compass()


## El vecino sale de su casa (visible, despierto) y corre hasta ti. La cámara lo sigue.
func _bring_friend() -> void:
	if _friend == null:
		return
	var home := str(WorldDB.get_entity("npc", _friend_id).get("home", ""))
	var from: Vector3 = door_position.call(home) if door_position.is_valid() and not home.is_empty() else Vector3.INF
	if from == Vector3.INF or from == Vector3.ZERO or from.distance_to(player.global_position) > 60.0:
		from = player.global_position + (town_position - player.global_position).normalized() * 14.0
	NPCMemory.come_out(_friend_id)
	_friend.set_meta("scripted", true)  # el horario del pueblo no lo mete en casa a mitad de escena
	_friend.unsettle()
	_friend.set_present(true)
	_friend.global_position = from + Vector3(0, 0.3, 0)
	_friend.walk_to(player.global_position + (from - player.global_position).normalized() * 1.3, true)
	# La cámara lo sigue mientras corre (hasta 7 s); si no llega, se le acerca a su lado
	var t := 0.0
	while t < 7.0 and _friend.global_position.distance_to(player.global_position) > 1.8 and not _cut.skipping:
		var cam := _cam_for("companion")
		_cut.shot(cam.pos, cam.look, 0.0)
		await get_tree().process_frame
		t += get_process_delta_time()
	if _friend.global_position.distance_to(player.global_position) > 1.8:
		_friend.global_position = InteriorManager.free_spot_near(player, player.global_position + (from - player.global_position).normalized() * 1.3, Vector3.ZERO, [player, _friend])
	_friend.stop()
	_friend.face(player.global_position)
	_friend.set_emotion("scared")


## La brújula en la mano: un disco de latón con su aguja, delante del pecho, y el gesto de mirarla.
func _show_compass() -> void:
	if _compass == null:
		_compass = Node3D.new()
		_compass.name = "Brujula"
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.045
		cm.height = 0.015
		disc.mesh = cm
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color("#b8913a")
		brass.metallic = 0.8
		brass.roughness = 0.3
		disc.material_override = brass
		_compass.add_child(disc)
		var needle := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.006, 0.004, 0.07)
		needle.mesh = bm
		var red := StandardMaterial3D.new()
		red.albedo_color = Color("#e5533d")
		red.emission_enabled = true
		red.emission = Color("#e5533d")
		red.emission_energy_multiplier = 0.6
		needle.material_override = red
		needle.position.y = 0.01
		needle.name = "Aguja"
		_compass.add_child(needle)
		player.add_child(_compass)
		var spin := needle.create_tween()
		spin.tween_property(needle, "rotation:y", TAU * 3.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var fwd := -player.global_basis.z
	_compass.global_position = player.global_position + Vector3(0, 1.05, 0) + fwd * 0.32
	player.play_gesture("read", 4.0)


## Las olas se aplanan y el oleaje se apaga (el mar «se queda quieto»).
func _calm_sea() -> void:
	for mi in get_tree().current_scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m and m.shader == WATER_SHADER:
			var h0: Variant = m.get_shader_parameter("wave_height")
			create_tween().tween_method(func(v: float): m.set_shader_parameter("wave_height", v), float(h0) if h0 != null else 0.22, 0.01, 1.2)
	for a in get_tree().current_scene.find_children("*", "AmbientAudio", true, false):
		create_tween().tween_property(a, "volume_db", -60.0, 1.2)


## ¿Se ve lo que dice la toma? (para el vecino: visible, en el encuadre y a menos de 3 m)
func _visible_ok(shot: String) -> bool:
	var ok := true
	if shot == "companion":
		var cam := get_viewport().get_camera_3d()
		ok = _friend != null and _friend.visible and _friend.global_position.distance_to(player.global_position) < 3.0 \
			and (cam == null or cam.is_position_in_frustum(_friend.global_position + Vector3(0, 1.2, 0)))
	elif shot == "watch":
		ok = _compass != null and _compass.visible
	var info := {"shot": shot, "ok": ok}
	if shot == "companion" and _friend:
		var cam2 := get_viewport().get_camera_3d()
		info["visible"] = _friend.visible
		info["dist"] = snappedf(_friend.global_position.distance_to(player.global_position), 0.1)
		info["in_frame"] = cam2 == null or cam2.is_position_in_frustum(_friend.global_position + Vector3(0, 1.2, 0))
	log_checks.append(info)
	if not ok:
		push_warning("[escena] la toma «%s» no se pudo mostrar como dice su frase" % shot)
	return ok


func _process(_delta: float) -> void:
	if _flicker:
		beacon.light_energy = 12.0 if randf() < 0.5 else 0.0
	if _compass and _compass.visible and player:
		var fwd := -player.global_basis.z
		_compass.global_position = player.global_position + Vector3(0, 1.05, 0) + fwd * 0.32


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
	if not companion.is_empty() and _friend:
		# Se ve: te agarra la mano y lo dice
		var cam := _cam_for("companion")
		await _cut.shot(cam.pos, cam.look, 0.6)
		_friend.play_gesture("handshake", 3.0)
		player.play_gesture("handshake", 3.0)
		await _cut.say(_friend, str(_data.get("companion_line", "¡Agárrate!")))
	elif _friend:
		# Te sueltas: se ve cómo se queda atrás
		var cam2 := _cam_for("companion")
		await _cut.shot(cam2.pos, cam2.look, 0.6)
		_friend.play_gesture("shake_head", 2.0)
		await _cut.line("Te sueltas. %s se queda en la explanada, mirándote." % str(WorldDB.get_entity("npc", _friend_id).get("name", "")).get_slice(" ", 0))
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

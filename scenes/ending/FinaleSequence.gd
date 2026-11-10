class_name FinaleSequence
extends Node
## La vuelta a casa: la brecha te deja en el muelle de Bahía de las Horas, la brújula se queda
## quieta y un vecino sale de su casa y te reconoce. Misma regla que El Despertar: el motor
## decide las tomas (lo que se verá) y la IA solo pone la frase de cada una; luego la última
## decisión (quedarte, volver a por alguien o seguir viajando), el epílogo y los créditos.

const WATER_SHADER := preload("res://shaders/water.gdshader")

var player: Player
var center: Vector3                     # donde llegas: el muelle
var tower_position := Vector3.ZERO
var town_position := Vector3.ZERO
var npcs: Dictionary = {}
var door_position: Callable

var _loading: LoadingOverlay
var _panel: NarrativePanel
var _cut: Cutscene
var _data: Dictionary = {}
var _breach: MeshInstance3D
var _neighbor: TownNPC
var _neighbor_id := ""
var _compass: Node3D
var log_checks: Array = []


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
	_pick_neighbor()
	_breach = AwakeningSequence.spawn_breach(self, center + Vector3(0, 1.6, -2.0), 1.6)
	_cut.fx("white", 0.01)
	var b := _cam_for("breach")
	await _cut.shot(b.pos, b.look)
	_cut.fx("clear", 1.2)

	var plan := shot_plan()
	_loading.show_loading("Casa", PackedStringArray([
		"La brújula deja de girar", "Huele a sal", "Reconoces el ruido del muelle"]))
	_data = await StoryDirector.generate_finale(plan)
	_loading.hide_loading()

	for beat in _data.get("beats", []):
		var shot := str(beat.get("shot", "town"))
		await _stage(shot)
		var cam := _cam_for(shot)
		await _cut.shot(cam.pos, cam.look, 1.2)
		var line := str(beat.get("line", ""))
		if not _visible_ok(shot):
			line = str(StoryDirector.NEUTRAL_BEATS.get(shot, ""))
		await _cut.line(line)
		if _cut.skipping:
			break
	_cut.hide_text()
	_panel.present("[font_size=26][b]%s[/b][/font_size]" % _data.get("title", "Casa"),
		"Estás en casa. ¿Y ahora?", _data.choices.map(func(c): return c.text))
	_panel.chosen.connect(_choose, CONNECT_ONE_SHOT)


## Las tomas que se pueden mostrar ahora, con lo que pasa en cada una.
func shot_plan() -> Array:
	var plan := [
		{"shot": "breach", "does": "la grieta te deja sobre las tablas del muelle y se cierra detrás de ti"},
		{"shot": "pier", "does": "el muelle de siempre, las barcas amarradas y el agua"},
		{"shot": "lighthouse", "does": "el faro, apagado"},
		{"shot": "watch", "does": "la brújula en tu mano: la aguja da una vuelta y se queda quieta, ya no tiene a dónde apuntar"},
		{"shot": "town", "does": "las luces del pueblo a lo lejos"},
	]
	if _neighbor:
		plan.append({"shot": "neighbor", "does": "%s sale de su casa, baja corriendo y se para delante de ti" % str(WorldDB.get_entity("npc", _neighbor_id).get("name", "")).get_slice(" ", 0)})
	plan.append({"shot": "player", "does": "tu cara, de cerca: respiras hondo"})
	return plan


func _pick_neighbor() -> void:
	var best_rel := -1000
	for id in npcs:
		if not is_instance_valid(npcs[id]):
			continue
		var rel := int(NPCMemory.get_mem(id).relationship)
		if rel > best_rel:
			_neighbor = npcs[id]
			_neighbor_id = id
			best_rel = rel


func _cam_for(shot: String) -> Dictionary:
	var head := player.global_position + Vector3(0, 1.6, 0)
	var to_town := town_position - center
	to_town.y = 0.0
	to_town = to_town.normalized() if to_town.length() > 0.1 else Vector3.BACK
	var side := to_town.cross(Vector3.UP).normalized()
	match shot:
		"breach":
			return {"pos": center + to_town * 6.0 + side * 2.0 + Vector3(0, 2.0, 0), "look": center + Vector3(0, 1.4, -2.0)}
		"pier":
			return {"pos": center + side * 6.0 + Vector3(0, 1.6, 0), "look": center + Vector3(0, 0.3, 0)}
		"lighthouse":
			return {"pos": center + to_town * 3.0 + Vector3(0, 2.0, 0), "look": tower_position + Vector3(0, 12.0, 0)}
		"town":
			return {"pos": center + Vector3(0, 3.0, 0), "look": town_position + Vector3(0, 2.0, 0)}
		"neighbor":
			if _neighbor:
				var mid := (_neighbor.global_position + player.global_position) / 2.0
				var across := _neighbor.global_position - player.global_position
				across.y = 0.0
				var perp := across.normalized().cross(Vector3.UP) if across.length() > 0.2 else side
				return {"pos": mid + perp * maxf(4.0, across.length() * 0.7) + Vector3(0, 1.8, 0), "look": mid + Vector3(0, 1.1, 0)}
		"watch":
			return {"pos": head + to_town * 0.8 + side * 0.25 + Vector3(0, -0.25, 0), "look": _compass.global_position if _compass else head}
	return {"pos": head + to_town * 1.8, "look": head}


func _stage(shot: String) -> void:
	match shot:
		"breach":
			if _breach:
				_breach.create_tween().tween_property(_breach, "scale", Vector3.ONE * 0.01, 2.0)
		"watch":
			_show_compass()
		"neighbor":
			await _bring_neighbor()
		"player":
			player.face_towards(center + (town_position - center).normalized() * 3.0)


func _bring_neighbor() -> void:
	if _neighbor == null:
		return
	var home := str(WorldDB.get_entity("npc", _neighbor_id).get("home", ""))
	var from: Vector3 = door_position.call(home) if door_position.is_valid() and not home.is_empty() else Vector3.INF
	if from == Vector3.INF or from == Vector3.ZERO or from.distance_to(player.global_position) > 70.0:
		from = player.global_position + (town_position - player.global_position).normalized() * 14.0
	NPCMemory.come_out(_neighbor_id)
	_neighbor.set_meta("scripted", true)
	_neighbor.unsettle()
	_neighbor.set_present(true)
	_neighbor.global_position = from + Vector3(0, 0.3, 0)
	_neighbor.walk_to(player.global_position + (from - player.global_position).normalized() * 1.4, true)
	var t := 0.0
	while t < 8.0 and _neighbor.global_position.distance_to(player.global_position) > 2.0 and not _cut.skipping:
		var cam := _cam_for("neighbor")
		_cut.shot(cam.pos, cam.look, 0.0)
		await get_tree().process_frame
		t += get_process_delta_time()
	if _neighbor.global_position.distance_to(player.global_position) > 2.0:
		_neighbor.global_position = InteriorManager.free_spot_near(player, player.global_position + (from - player.global_position).normalized() * 1.4, Vector3.ZERO, [player, _neighbor])
	_neighbor.stop()
	_neighbor.face(player.global_position)
	_neighbor.set_emotion("happy")
	_neighbor.play_gesture("hug", 2.5)


func _show_compass() -> void:
	if _compass == null:
		_compass = Node3D.new()
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.045
		cm.height = 0.015
		disc.mesh = cm
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color("#b8913a")
		brass.metallic = 0.8
		disc.material_override = brass
		_compass.add_child(disc)
		var needle := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.006, 0.004, 0.07)
		needle.mesh = bm
		needle.position.y = 0.01
		_compass.add_child(needle)
		player.add_child(_compass)
		needle.create_tween().tween_property(needle, "rotation:y", TAU * 1.25, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_compass.global_position = player.global_position + Vector3(0, 1.05, 0) - player.global_basis.z * 0.32
	player.play_gesture("read", 4.0)


func _visible_ok(shot: String) -> bool:
	var ok := true
	if shot == "neighbor":
		var cam := get_viewport().get_camera_3d()
		ok = _neighbor != null and _neighbor.visible and _neighbor.global_position.distance_to(player.global_position) < 3.0 \
			and (cam == null or cam.is_position_in_frustum(_neighbor.global_position + Vector3(0, 1.2, 0)))
	elif shot == "watch":
		ok = _compass != null and _compass.visible
	log_checks.append({"shot": shot, "ok": ok})
	return ok


func _choose(index: int) -> void:
	var result := StoryDirector.apply_ending(_data, index)
	_panel.visible = false
	await _cut.fx("black", 1.0)
	await _cut.finish(str(_data.get("title", "La vuelta a casa")), false)
	if _neighbor and is_instance_valid(_neighbor):
		_neighbor.remove_meta("scripted")
	if _compass:
		_compass.queue_free()
	var screen := EndingScreen.new()
	screen.title = result.title
	screen.epilogue = result.epilogue
	screen.ending = result.ending
	add_child(screen)
	screen.continue_requested.connect(func():
		var ui = get_tree().get_first_node_in_group("gameplay_ui")
		if ui:
			ui.block(false, "cutscene")
		else:
			player.controls_enabled = true)

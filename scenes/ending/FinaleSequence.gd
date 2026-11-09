class_name FinaleSequence
extends Node
## La vuelta a casa: la brecha te deja en el muelle de Bahía de las Horas, la brújula se queda
## quieta y los vecinos te reconocen. Escena de cine con tomas reales del pueblo, y después la
## última decisión (quedarte, volver a por alguien o seguir viajando), el epílogo y los créditos.

var player: Player
var center: Vector3                     # donde llegas (el muelle o la explanada del faro)
var tower_position := Vector3.ZERO
var town_position := Vector3.ZERO
var npcs: Dictionary = {}

var _loading: LoadingOverlay
var _panel: NarrativePanel
var _cut: Cutscene
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
	var breach := AwakeningSequence.spawn_breach(self, center + Vector3(0, 1.6, -2.0), 1.6)
	_cut.fx("white", 0.01)
	var b := _cam_for("breach")
	await _cut.shot(b.pos, b.look)
	_cut.fx("clear", 1.2)

	_loading.show_loading("Casa", PackedStringArray([
		"La brújula deja de girar", "Huele a sal", "Reconoces el ruido del muelle"]))
	_data = await StoryDirector.generate_finale()
	_loading.hide_loading()
	# La grieta se cierra detrás de ti
	breach.create_tween().tween_property(breach, "scale", Vector3.ONE * 0.01, 2.5).set_delay(1.0)

	for beat in _data.get("beats", []):
		var shot := str(beat.get("shot", "town"))
		_stage(shot)
		var cam := _cam_for(shot)
		await _cut.shot(cam.pos, cam.look, 1.4)
		await _cut.line(str(beat.get("line", "")))
		if _cut.skipping:
			break
	_cut.hide_text()
	_panel.present("[font_size=26][b]%s[/b][/font_size]" % _data.get("title", "Casa"),
		"Estás en casa. ¿Y ahora?", _data.choices.map(func(c): return c.text))
	_panel.chosen.connect(_choose, CONNECT_ONE_SHOT)


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
			return {"pos": center + side * 5.0 + Vector3(0, 1.2, 0), "look": center + Vector3(0, 0.3, 0)}
		"lighthouse":
			return {"pos": center + to_town * 3.0 + Vector3(0, 2.0, 0), "look": tower_position + Vector3(0, 12.0, 0)}
		"town":
			return {"pos": center + Vector3(0, 3.0, 0), "look": town_position + Vector3(0, 2.0, 0)}
		"sea":
			return {"pos": center + Vector3(0, 2.0, 0), "look": center - to_town * 60.0}
		"sky":
			return {"pos": head, "look": head + Vector3(0, 12, 0) - to_town * 3.0}
		"neighbor":
			return {"pos": head + to_town * -1.5 + side * 1.2, "look": head + to_town * 2.0}
		"watch":
			return {"pos": head + to_town * 0.9 + Vector3(0, -0.4, 0), "look": player.global_position + Vector3(0, 1.0, 0)}
	return {"pos": head + to_town * 1.8, "look": head}


func _stage(shot: String) -> void:
	if shot != "neighbor":
		return
	# El vecino que más te aprecia baja corriendo
	var best: Node3D = null
	var best_rel := -1000
	for id in npcs:
		var rel := int(NPCMemory.get_mem(id).relationship)
		if rel > best_rel and is_instance_valid(npcs[id]):
			best = npcs[id]
			best_rel = rel
	if best:
		var from := player.global_position + (town_position - player.global_position).normalized() * 10.0
		best.global_position = Vector3(from.x, player.global_position.y + 0.2, from.z)
		if best.has_method("walk_to"):
			best.walk_to(player.global_position + Vector3(1.0, 0, 1.0), true)
		if best.has_method("set_emotion"):
			best.set_emotion("happy")


func _choose(index: int) -> void:
	var result := StoryDirector.apply_ending(_data, index)
	_panel.visible = false
	await _cut.fx("black", 1.0)
	await _cut.finish(str(_data.get("title", "La vuelta a casa")), false)
	var screen := EndingScreen.new()
	screen.title = result.title
	screen.epilogue = result.epilogue
	screen.ending = result.ending
	add_child(screen)
	screen.continue_requested.connect(func(): player.controls_enabled = true)

extends SceneTree
## Los ajustes se aplican en plena partida, sin salir: calidad gráfica (efectos, hierba), tamaño
## del texto y aspecto del personaje. Y una vida nueva sale con el aspecto elegido.
##   godot --headless --path . -s tests/test_settings_live.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var settings = root.get_node("/root/Settings")
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de ajustes")
	var look = load("res://scripts/player/PlayerLook.gd")
	look.save({"figure": "masculine", "body": "sturdy", "outfit": "formal", "primary_color": "#b23a3a", "secondary_color": "#2b2f3a"})
	var quality_before: int = settings.graphics_quality
	var text_before: float = settings.text_scale
	settings.graphics_quality = 2
	var town: Node = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	for i in 5:
		await process_frame
	var player = town.get("_player")
	_expect(look.current().figure == "masculine" and look.current().body == "sturdy", "la vida nueva tiene el aspecto elegido")
	var model_before: Node = player.get("_body").get_child(0)

	# Calidad gráfica: se nota sin recargar
	var env: Environment = town.get("_fx").env
	var grass: Array = root.get_tree().get_nodes_in_group("grass")
	_expect(env.ssil_enabled and not grass.is_empty(), "con calidad alta: SSIL y hierba")
	var full: int = grass[0].multimesh.visible_instance_count
	settings.graphics_quality = 0
	settings.changed.emit()
	await process_frame
	_expect(not env.ssao_enabled and not env.ssil_enabled, "al bajar la calidad se quitan los efectos al momento")
	_expect(grass[0].multimesh.visible_instance_count < full, "y se ve menos hierba (%d → %d)" % [full, grass[0].multimesh.visible_instance_count])

	# Tamaño del texto: también los textos con tamaño propio
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	root.add_child(label)
	await process_frame
	settings.text_scale = 1.3
	settings.changed.emit()
	await process_frame
	_expect(label.get_theme_font_size("font_size") == 26, "el texto se agranda al momento (%d)" % label.get_theme_font_size("font_size"))
	settings.text_scale = 1.0
	settings.changed.emit()
	await process_frame
	_expect(label.get_theme_font_size("font_size") == 20, "y vuelve a su tamaño sin acumular")

	# Aspecto: cambia el modelo del jugador en caliente
	look.save({"figure": "feminine", "body": "slim", "outfit": "casual", "primary_color": "#2f6b4f", "secondary_color": "#e8e2d4"})
	player.rebuild_look()
	await process_frame
	await process_frame
	var model_after: Node = player.get("_body").get_child(player.get("_body").get_child_count() - 1)
	_expect(is_instance_valid(model_after) and model_after != model_before and player.get("_rig") != null, "cambiar tu aspecto cambia el personaje al momento")

	label.queue_free()
	town.queue_free()
	await process_frame
	settings.graphics_quality = quality_before
	settings.text_scale = text_before
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

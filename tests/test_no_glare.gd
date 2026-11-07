extends SceneTree
## v0.8.0: sin destellos, con música y con campo.
##  - Los «destellos» eran píxeles NaN del suelo (una normal a cero al normalizarla) que el
##    resplandor (glow) convertía en manchas blancas: el shader del suelo ya no puede dar NaN.
##  - Las estrellas van con la cámara y ninguna queda a ras del horizonte.
##  - Música de verdad que cambia según dónde estés.
##  - El campo: caminos, sitios con nombre (la granja, el lago…) que la IA conoce.
##   godot --headless --path . -s tests/test_no_glare.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 1. El shader del suelo se protege de normales a cero y colores negativos
	var src := FileAccess.get_file_as_string("res://shaders/ground.gdshader")
	_expect(src.contains("dot(NORMAL, NORMAL) < 1e-8") and src.contains("max(COLOR.rgb"), "el suelo no puede dar píxeles NaN (eran los destellos)")

	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba destellos")
	clock.set_hour(22.0)
	load("res://scripts/world/Weather.gd").forced = "clear"
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 20:
		await process_frame
	var player = town.get("_player")
	var fx = town.get("_fx")
	var stars: MultiMeshInstance3D = fx.get("_stars")
	var low := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	for i in 900:
		var o: Vector3 = fx.star_direction(rng)
		if o.y < sin(deg_to_rad(7.5)):
			low += 1
	_expect(low == 0, "ninguna estrella a ras del horizonte (%d bajas)" % low)
	player.global_position = Vector3(-150, town.ground_at(-150, -10) + 0.5, -10)
	for i in 10:
		await process_frame
	var cam := root.get_viewport().get_camera_3d()
	_expect(stars.global_position.distance_to(cam.global_position) < 1.0, "y el cielo de estrellas va con la cámara")

	# 2. Música según el sitio
	var music = root.get_node("/root/Music")
	music.set("_check", 0.0)
	for i in 5:
		await process_frame
	_expect(music.current() == "town_night", "de noche en el pueblo suena su música (%s)" % music.current())
	player.global_position = Vector3(-230, town.ground_at(-230, -40) + 0.5, -40)
	clock.set_hour(11.0)
	music.set("_check", 0.0)
	for i in 5:
		await process_frame
	_expect(music.current() == "countryside", "en el campo, de día, otra (%s)" % music.current())
	var stream: AudioStream = music.get("_a").stream
	_expect(stream != null and stream.get("loop") == true, "con su pista de verdad, en bucle (sin pantalla no suena)")

	# 3. El campo: sitios con nombre que la IA puede usar
	for place in ["la granja", "el lago", "el campamento", "las ruinas", "el mirador", "la cabaña del pescador", "el cruce de caminos"]:
		_expect(town.place_position(place) != Vector3.INF, "«%s» es un sitio del mapa" % place)
	var lake: Vector3 = town.place_position("el lago")
	_expect(town.ground_at(lake.x, lake.z) < -0.5, "el lago tiene agua (el fondo está bajo el nivel del mar)")
	var ctx: String = town.action_context()
	_expect(ctx.contains("la granja") and ctx.contains("SITIOS"), "y la tecla F conoce los sitios del mapa")
	town.queue_free()
	await process_frame
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:  # (que acabe lo pendiente: cerrar justo tras liberar la escena podía fallar)
		await process_frame
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

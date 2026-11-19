extends SceneTree
## v0.13.0: más realismo en el mundo. El sol sale y se pone según la estación (y sube menos en
## invierno); el tiempo cambia poco a poco (de despejado no se pasa a tormenta) y llueve más en
## verano; el viento sopla según el tiempo; el fin de semana se duerme más y quien trabaja fuera
## se queda en casa; se le nota a la gente el hambre y el cansancio; el ahorro da un interés
## creíble; el suelo se moja con la lluvia y las nubes cubren el cielo; los pasos suenan según lo
## que pisas; dentro de un edificio hay eco; y quien está a la vista camina a su sitio.
##   godot --headless --path . -s tests/test_realism013.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var clock = root.get_node("/root/WorldClock")
	root.get_node("/root/Settings").use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba realismo 0.13")
	var W = load("res://scripts/world/Weather.gd")
	var H = load("res://scripts/world/Households.gd")
	var Sfx = load("res://scripts/util/Sfx.gd")

	# --- El sol de verdad ------------------------------------------------------------------
	var summer: Vector2 = clock.daylight(30.0)   # solsticio de verano
	var winter: Vector2 = clock.daylight(90.0)   # solsticio de invierno
	var equinox: Vector2 = clock.daylight(0.0)
	_expect(summer.y - summer.x > 13.0 and winter.y - winter.x < 11.2, "en verano hay más horas de sol (%.1f h) que en invierno (%.1f h)" % [summer.y - summer.x, winter.y - winter.x])
	_expect(absf((equinox.y - equinox.x) - 12.0) < 0.1, "y en el equinoccio, doce (%.1f h)" % (equinox.y - equinox.x))
	_expect(summer.x < winter.x and summer.y > winter.y, "en verano amanece antes (%s) y anochece después (%s) que en invierno (%s, %s)" % [clock.fmt(summer.x), clock.fmt(summer.y), clock.fmt(winter.x), clock.fmt(winter.y)])
	var noon_s: float = clock.solar_height(13.25, 30.0)
	var noon_w: float = clock.solar_height(13.25, 90.0)
	_expect(noon_s > noon_w + 0.15, "a mediodía el sol está más alto en verano (%.2f) que en invierno (%.2f)" % [noon_s, noon_w])
	_expect(absf(clock.solar_height(summer.x, 30.0)) < 0.03, "y al amanecer está justo en el horizonte")
	var morning: Vector3 = clock.solar_direction(8.0, 0.0)
	var evening: Vector3 = clock.solar_direction(18.5, 0.0)
	_expect(morning.x < 0.0 and evening.x > 0.0 and morning.y > 0.0, "sale por un lado (el este) y se pone por el otro")

	# --- El tiempo cambia poco a poco --------------------------------------------------------
	var jumps := 0
	var wet_summer := 0
	var wet_winter := 0
	var prev: String = W.kind_at(0)
	for b in range(1, 1440):  # 120 días de juego, en franjas de 2 h
		var k: String = W.kind_at(b)
		if (prev == "clear" and k == "storm") or (prev == "storm" and k == "clear") or (prev == "clear" and k == "rain"):
			jumps += 1
		var season: String = W.SEASONS[int(b * W.BLOCK_MINUTES / (1440.0 * 30.0)) % 4]
		if k in ["rain", "storm"]:
			if season == "verano":
				wet_summer += 1
			elif season == "invierno":
				wet_winter += 1
		prev = k
	_expect(jumps == 0, "nunca pasa de despejado a lluvia o tormenta de golpe (%d saltos)" % jumps)
	_expect(wet_summer > wet_winter, "llueve más en verano (%d franjas) que en invierno (%d)" % [wet_summer, wet_winter])
	_expect(W.kind_at(500) == W.kind_at(500), "y el mismo mundo tiene el mismo tiempo a la misma hora")
	W.forced = "storm"
	var storm_wind: float = W.wind_speed()
	W.forced = "clear"
	var calm_wind: float = W.wind_speed()
	_expect(storm_wind > 10.0 and calm_wind < 5.0, "con tormenta sopla fuerte (%.0f m/s); despejado, una brisa (%.0f m/s)" % [storm_wind, calm_wind])
	_expect(W.wind().length() > 0.1, "y el viento tiene dirección")

	# --- Fin de semana y cómo está la gente --------------------------------------------------
	var adult := {"id": "npc_prueba_adulto", "household_role": "padre"}
	clock.set("_day", 6)  # miércoles
	_expect(clock.weekday() == "miércoles", "(hoy es miércoles)")
	var wed_awake: bool = not H.is_sleeping_at(adult, 7.9)
	clock.set("_day", 2)  # sábado
	_expect(clock.weekday() == "sábado", "(hoy es sábado)")
	var sat_asleep: bool = H.is_sleeping_at(adult, 7.9)
	_expect(wed_awake and sat_asleep, "el sábado a las 7:54 aún duerme; el miércoles ya está en pie")
	var worker := {"id": "npc_prueba_trabajo", "works_away": true}
	_expect(H.plan(worker, 11.0).home, "el sábado, quien trabaja fuera está en casa")
	clock.set("_day", 6)
	_expect(not H.plan(worker, 11.0).home, "entre semana, a esa hora, está trabajando")
	_expect(H.condition(adult, 13.2).contains("hambre"), "a la una se le nota el hambre: «%s»" % H.condition(adult, 13.2))
	_expect(H.condition(adult, 23.4).contains("cansancio") or H.is_sleeping_at(adult, 23.4), "y por la noche, el cansancio")
	clock.set("_day", 0)

	# --- El ahorro da un interés creíble ----------------------------------------------------
	var economy = root.get_node("/root/Economy")
	_expect(economy.SAVINGS_RATE <= 0.002, "el ahorro da como mucho un 0.2 %% semanal (%.1f %% al año)" % ((pow(1.0 + economy.SAVINGS_RATE, 52) - 1.0) * 100.0))

	# --- En el pueblo -------------------------------------------------------------------------
	W.forced = "rain"
	clock.set_hour(12.0)
	var town: Node3D = load("res://scenes/act0_town/Act0Town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	for i in 12:
		await process_frame
	var fx = town.get("_fx")
	_expect(fx.sky_mat is ShaderMaterial and fx.sky_mat.shader.resource_path.ends_with("sky.gdshader"), "el cielo es el de nubes (shaders/sky.gdshader)")
	await create_timer(3.0).timeout
	_expect(fx.wetness > 0.02, "bajo la lluvia el suelo se va mojando (%.2f)" % fx.wetness)
	var cover_rain: float = fx.sky_mat.get_shader_parameter("cloud_cover")
	W.forced = "clear"
	await create_timer(6.0).timeout
	var cover_clear: float = fx.sky_mat.get_shader_parameter("cloud_cover")
	_expect(cover_rain > 0.6 and cover_clear < cover_rain - 0.3, "las nubes cubren el cielo con lluvia (%.2f) y se abren al escampar (%.2f)" % [cover_rain, cover_clear])
	var wet_after: float = fx.wetness
	_expect(wet_after > 0.0, "y el suelo no se seca de golpe (%.2f)" % wet_after)
	_expect(fx.sun.directional_shadow_max_distance >= 120.0, "las sombras llegan lejos (%.0f m)" % fx.sun.directional_shadow_max_distance)
	# Los pasos suenan según el suelo
	_expect(town.surface_at(-5.0, 0.0) == "stone", "en la carretera, los pasos suenan a piedra (%s)" % town.surface_at(-5.0, 0.0))
	_expect(town.surface_at(30.0, 40.0) == "sand", "en la playa, a arena (%s)" % town.surface_at(30.0, 40.0))
	_expect(town.surface_at(-30.0, 30.0) == "grass", "en el césped, a hierba (%s)" % town.surface_at(-30.0, 30.0))
	var plank := StaticBody3D.new()
	var plank_mesh := MeshInstance3D.new()
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#8b6b4a")
	plank_mesh.material_override = pm
	plank_mesh.add_child(plank)
	var ps := CollisionShape3D.new()
	ps.shape = BoxShape3D.new()
	plank.add_child(ps)
	town.add_child(plank_mesh)
	_expect(Sfx.surface_sound(town, plank, Vector3(36, 0.4, 6)) == "step_wood", "en las tablas del muelle, a madera")
	pm.albedo_color = Color("#9a9a96")
	_expect(Sfx.surface_sound(town, plank, Vector3(0, 0.2, 200)) == "step_stone", "y en una acera, a piedra")
	plank_mesh.queue_free()
	# Dentro de un edificio: eco y lo de fuera amortiguado
	var interiors = town.get("_interiors")
	await interiors.enter(interiors.door_of_kind("cafe"), true)
	await create_timer(1.5).timeout
	_expect(Sfx.is_indoors(), "dentro de la cafetería hay eco de habitación")
	_expect(not fx.sun.visible and fx.env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "y la luz es la de dentro (no el sol ni el cielo)")
	interiors.leave()
	await create_timer(1.5).timeout
	_expect(not Sfx.is_indoors() and fx.env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY, "al salir, vuelve el aire libre")
	# Quien está a la vista camina a su sitio (no aparece allí de golpe)
	var npcs: Dictionary = town.get("_npcs")
	var samir = npcs["npc_samir"]
	var player = town.get("_player")
	samir.stop()
	samir.global_position = player.global_position + Vector3(4, 0.2, 0)
	await physics_frame
	var at: Vector3 = samir.global_position
	town.set("_soft_place", true)
	town.call("_follow_one", "npc_samir", true)
	town.set("_soft_place", false)
	var place_ok: bool = samir.global_position.distance_to(at) < 0.5
	_expect(place_ok, "al salir de un edificio, el vecino que tienes delante no se teletransporta (se movió %.1f m)" % samir.global_position.distance_to(at))

	# --- Moverse a pie: velocidades de persona, inercia y aliento ------------------------------
	var body = root.get_node("/root/Body")
	var P = load("res://scripts/player/Player.gd")
	_expect(P.WALK_SPEED >= 2.2 and P.WALK_SPEED <= 3.0 and P.RUN_SPEED <= 7.0 and absf(P.JUMP_VELOCITY * P.JUMP_VELOCITY / 19.6 - 1.0) < 0.2, "se anda a %.1f m/s, se corre a %.1f y se salta %.2f m" % [P.WALK_SPEED, P.RUN_SPEED, P.JUMP_VELOCITY * P.JUMP_VELOCITY / 19.6])
	samir.global_position += Vector3(30, 0, 0)
	player.global_position = Vector3(-75, town.ground_at(-75, -55) + 0.2, -55)  # campo abierto (sin agua ni muros)
	player.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame
	for n in ["hunger", "thirst", "rest"]:
		body.set_need(n, 90.0)  # (con hambre, sed o sueño no se corre: aquí se prueba el aliento)
	body.stamina = 100.0
	body.winded = false
	Input.action_press("move_forward")
	for i in 3:
		await physics_frame
	var v_start: float = Vector2(player.velocity.x, player.velocity.z).length()
	await create_timer(1.0).timeout
	var v_walk: float = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(v_start < 0.8 and v_walk > 2.2 and v_walk < 2.9, "arrancar lleva su momento (%.2f m/s al principio, %.2f al segundo)" % [v_start, v_walk])
	Input.action_press("run")
	await create_timer(3.0).timeout
	var v_run: float = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(v_run > 5.0 and body.stamina < 92.0, "corriendo se gasta el aliento (%.1f m/s, aliento %d)" % [v_run, roundi(body.stamina)])
	body.stamina = 1.0
	await create_timer(1.2).timeout  # (la inercia: de correr a andar se frena en algo menos de un segundo)
	_expect(body.winded and not body.can_run(), "sin aliento no se puede correr")
	var v_tired: float = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(v_tired < 3.0, "y vas andando (%.1f m/s)" % v_tired)
	Input.action_release("run")
	Input.action_release("move_forward")
	await create_timer(3.0).timeout
	_expect(body.stamina > 15.0, "parado, recobras el aliento (%d en 3 s)" % roundi(body.stamina))
	_expect(not body.can_run(), "aunque aún no lo bastante para volver a correr")
	await create_timer(3.0).timeout
	_expect(body.can_run(), "y al rato, sí (%d)" % roundi(body.stamina))

	# --- Coches: motor con curva de par, turbo solo en quien lo tiene, daño por zonas -----------
	var V = load("res://scripts/vehicles/Vehicle.gd")
	var Creations = load("res://scripts/agent/Creations.gd")
	_expect(V.torque_at(4000.0) > V.torque_at(900.0) and V.torque_at(4000.0) > V.torque_at(6400.0), "el motor da más fuerza a medio régimen que al ralentí o al corte")
	var sedan_e: Dictionary = V.place_factory(town, "sedan", Vector3(-40, town.ground_at(-40, 50) + 0.3, 50), 0.0, "player")
	var sedan = Creations.node_of(town, sedan_e.id)
	var sports_e: Dictionary = V.place_factory(town, "sports", Vector3(-48, town.ground_at(-48, 50) + 0.3, 50), 0.0, "player")
	var sports = Creations.node_of(town, sports_e.id)
	await create_timer(1.0).timeout
	for car in [sedan, sports]:
		player.global_position = car.global_position + Vector3(-2.5, 0.3, 0)
		await physics_frame
		car._on_use(player)
		Input.action_press("move_forward")
		Input.action_press("run")
		await create_timer(0.6).timeout
		car.set_meta("_had_boost", car.boosting)
		Input.action_release("run")
		Input.action_release("move_forward")
		car._on_use(player)
		await create_timer(0.3).timeout
	_expect(not sedan.get_meta("_had_boost") and sports.get_meta("_had_boost"), "el sedán no tiene turbo; el deportivo, sí")
	_expect(sedan.damage_desc().is_empty(), "un coche nuevo está bien")
	sedan.damage.front = 70.0
	sedan.damage.left = 65.0
	_expect(sedan.damage_desc().contains("frontal") and sedan.damage_desc().contains("reventada"), "un golpe de frente toca el motor y uno de lado revienta la rueda: «%s»" % sedan.damage_desc())
	_expect(town.vehicles_described(sedan.global_position).contains("frontal"), "y la IA lo sabe")
	sedan.repair(100.0)
	_expect(sedan.damage_desc().is_empty(), "el taller lo deja como nuevo")
	var EFX = load("res://scripts/world/EnvironmentFX.gd")
	EFX.ground_wetness = 0.0
	W.forced = "clear"
	var dry_grip: float = sedan._wet_grip()
	EFX.ground_wetness = 1.0
	var wet_grip: float = sedan._wet_grip()
	EFX.ground_wetness = 0.0
	_expect(wet_grip < dry_grip * 0.8, "con el suelo mojado los neumáticos agarran menos (%.2f → %.2f)" % [dry_grip, wet_grip])

	# --- La gravedad de los planetas en el espacio ---------------------------------------------
	var Space = load("res://scenes/space/SpaceScene.gd")
	var g2: Vector3 = Space._pull(Vector3(1000, 0, 0), Vector3.ZERO, 500.0, 1.0)
	var g4: Vector3 = Space._pull(Vector3(2000, 0, 0), Vector3.ZERO, 500.0, 1.0)
	_expect(absf(g2.length() - 9.8 / 4.0) < 0.05 and g2.x < 0.0, "a dos radios de un planeta tira con un cuarto de su gravedad, hacia él (%.2f m/s²)" % g2.length())
	_expect(g4.length() < g2.length() / 3.0, "y cuanto más lejos, menos (%.2f m/s² a cuatro radios)" % g4.length())

	town.queue_free()
	await process_frame
	W.forced = ""
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	for _settle_before_quit in 20:
		await process_frame
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1

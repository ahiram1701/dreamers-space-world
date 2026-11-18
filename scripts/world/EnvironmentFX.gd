class_name EnvironmentFX
extends Node3D
## Cielo, sol, niebla y posprocesado de cada escena, con ciclo de día y noche (WorldClock)
## y tres niveles de calidad (Settings.graphics_quality). Lo comparten el pueblo y los lugares.
##
## Uso:  var fx := EnvironmentFX.new(); fx.sky_color = …; fx.fog_color = …; add_child(fx)
##       fx.env / fx.sun / fx.sky_mat quedan disponibles para secuencias (El Despertar…).
##       sky_mat es un ShaderMaterial (shaders/sky.gdshader): sus colores se animan con
##       "shader_parameter/sky_top_color", "shader_parameter/sky_horizon_color"…
##
## Realismo (0.13): el sol sigue su camino de verdad (WorldClock.sun_direction, con estaciones),
## nubes que cubren según el tiempo y avanzan con el viento, el suelo se moja con la lluvia y
## tarda en secarse (global «wetness»), la lluvia salpica al tocar el suelo, los relámpagos
## iluminan de verdad, iluminación global y reflejos en calidad alta, sombras hasta lejos, y
## dentro de los edificios la luz es la de dentro (no la del cielo).

const SKY_SHADER := preload("res://shaders/sky.gdshader")

## Lunas o soles extra en el cielo (otros planetas): {node, alpha_day}. Siguen a la cámara.
var _sky_bodies: Array = []

## Llamada cuando cambia la noche (0..1): farolas, ventanas…
signal night_changed(amount: float)

var sky_color := Color("#7aa7d9")
var fog_color := Color("#c9d6e3")
var ground_color := Color("#3a4a2a")
var space := false           # sin ciclo de día: estrellas siempre
var day_cycle := true
var fog_density := 0.004
var sun_tint := Color.WHITE

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
## Si una secuencia controla el cielo (El Despertar), el ciclo se detiene.
var frozen := false

## Tiempo que hace (Weather): nubes, niebla y lluvia que se mezclan poco a poco.
var _overcast := 0.0
var _fogginess := 0.0
var _rain_amount := 0.0
var _lightning := 0.0
var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _rain_floor: GPUParticlesCollisionHeightField3D
var _rain_sound: AudioStreamPlayer
var _flash: DirectionalLight3D
var _stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D
var _last_night := -1.0
## Lo mojado que está el suelo (0..1): sube con la lluvia y baja despacio al escampar.
var wetness := 0.0
## El de la escena actual, para quien no tiene a mano el EnvironmentFX (los pasos chapotean).
static var ground_wetness := 0.0
var _cloud_offset := Vector2.ZERO
var _indoors := false


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL  # el reflejo del cielo se rehace repartido en varios fotogramas
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.fog_enabled = not space
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.12
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.55   # el sol mide medio grado: sombras nítidas cerca, suaves lejos
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color("#8fa8ff")
	moon.light_energy = 0.0
	moon.rotation_degrees = Vector3(-50, 150, 0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	# El destello de un relámpago: una luz fría, breve, desde lo alto de la tormenta
	_flash = DirectionalLight3D.new()
	_flash.light_color = Color("#dfe6ff")
	_flash.light_energy = 0.0
	_flash.visible = false
	_flash.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_flash)
	_apply_quality()
	_build_stars()
	if not space:
		_build_rain()
	Settings.changed.connect(_on_settings_changed)
	Sfx.ensure_buses()
	Sfx.set_indoors(false)
	_update(true)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	# Dentro de un edificio (los interiores están a -400): la luz es la de dentro
	var inside := cam != null and cam.global_position.y < -100.0 and not space
	if inside != _indoors:
		_set_indoors(inside)
	_update_weather(delta)
	_update(false)
	# El cielo de estrellas va con la cámara: así está siempre «en el infinito» y nunca queda
	# metido en una colina lejana (antes era una esfera fija en el centro del pueblo).
	if cam:
		if _stars and _stars.visible:
			_stars.global_position = cam.global_position
		for b in _sky_bodies:
			(b as Node3D).global_position = cam.global_position


## Una luna (o un sol lejano) en el cielo: color, tamaño aparente, altura y rumbo en grados.
func add_sky_body(color: Color, size: float, elevation_deg: float, yaw_deg: float) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.disable_fog = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.emission_enabled = true
	m.emission = color.darkened(0.6)
	m.emission_energy_multiplier = 0.4
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var el := deg_to_rad(elevation_deg)
	var yw := deg_to_rad(yaw_deg)
	mi.position = Vector3(cos(el) * cos(yw), sin(el), cos(el) * sin(yw)) * 430.0
	mi.extra_cull_margin = 1000.0
	holder.add_child(mi)
	_sky_bodies.append(holder)


func _sky(param: String, value: Variant) -> void:
	sky_mat.set_shader_parameter(param, value)


## Mezcla suave hacia el tiempo que toca (cambia en un par de segundos reales, no de golpe).
func _update_weather(delta: float) -> void:
	if space or frozen:
		RenderingServer.global_shader_parameter_set("rain", 0.0)
		RenderingServer.global_shader_parameter_set("wind", Vector2.ZERO)
		return
	var w := Weather.current() if day_cycle else "clear"
	var raining := w in ["rain", "storm"]
	var strength := (1.0 if w == "storm" else clampf(Weather.intensity(), 0.25, 1.0)) if raining else 0.0
	var k := 1.0 - exp(-0.6 * delta)
	_overcast = lerpf(_overcast, {"clear": 0.0, "cloudy": 0.6, "rain": 0.75 + 0.15 * strength, "fog": 0.55, "wind": 0.3, "storm": 1.0}.get(w, 0.0), k)
	_fogginess = lerpf(_fogginess, (0.4 + 0.6 * Weather.intensity()) if w == "fog" else (0.2 + 0.15 * strength if raining else 0.0), k)
	_rain_amount = lerpf(_rain_amount, strength, k)
	# El suelo se moja en un minuto de lluvia y tarda varios en secarse (antes con sol y viento)
	if raining:
		wetness = minf(wetness + delta / 50.0 * (0.3 + _rain_amount), 1.0)
	else:
		var sun_dry := clampf(WorldClock.sun_height() * 2.0, 0.0, 1.0) if day_cycle else 0.5
		wetness = maxf(wetness - delta / 420.0 * (0.4 + sun_dry + Weather.wind_speed() / 10.0), 0.0)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	ground_wetness = wetness
	RenderingServer.global_shader_parameter_set("rain", _rain_amount if not _indoors else 0.0)
	var wind := Weather.wind() if day_cycle else Vector2(1.5, 0.5)
	RenderingServer.global_shader_parameter_set("wind", wind)
	# Las nubes avanzan con el viento (a la altura de las nubes sopla más)
	_cloud_offset += wind * delta * 0.0018
	_cloud_offset = Vector2(fposmod(_cloud_offset.x, 1000.0), fposmod(_cloud_offset.y, 1000.0))
	# Tormenta: rayos (un destello que ilumina el pueblo y, poco después, el trueno)
	if w == "storm" and randf() < delta * 0.12:
		_lightning = 1.0
		_flash.rotation = Vector3(deg_to_rad(randf_range(-80.0, -45.0)), randf() * TAU, 0.0)
		var far := randf_range(0.6, 2.5)  # segundos que tarda el trueno: lo lejos que cayó
		get_tree().create_timer(far).timeout.connect(func():
			if is_inside_tree():
				Sfx.at(self, "crash", (get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else Vector3.ZERO) + Vector3(randf_range(-80, 80), 30, randf_range(-80, 80))))
	if _lightning > 0.0:
		_lightning = maxf(_lightning - delta * 4.0, 0.0)
		# Parpadea dos veces, como los rayos de verdad
		var flicker := 1.0 if _lightning > 0.7 or (_lightning > 0.3 and _lightning < 0.5) else 0.25
		_flash.visible = not _indoors
		_flash.light_energy = _lightning * flicker * 2.2
		env.ambient_light_energy = 1.0 + _lightning * flicker * 2.0
	elif _flash.visible:
		_flash.visible = false
	env.fog_density = fog_density * (1.0 + _fogginess * 9.0)
	if _rain:
		_rain.emitting = _rain_amount > 0.15
		_rain.amount_ratio = clampf(_rain_amount, 0.0, 1.0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			# La lluvia cae inclinada con el viento
			_rain.global_position = cam.global_position + Vector3(-wind.x * 0.35, 10, -wind.y * 0.35)
			var pm := _rain.process_material as ParticleProcessMaterial
			pm.direction = Vector3(wind.x / 25.0, -1.0, wind.y / 25.0).normalized()
			# Bajo techo (los interiores están a -400) no llueve
			_rain.visible = not _indoors
			_splash.visible = _rain.visible
		_rain_sound.volume_db = linear_to_db(maxf(_rain_amount * 0.55, 0.0001)) if not _indoors else linear_to_db(maxf(_rain_amount * 0.12, 0.0001))
		if _rain_amount > 0.05 and not _rain_sound.playing:
			_rain_sound.play()
		elif _rain_amount <= 0.05 and _rain_sound.playing:
			_rain_sound.stop()


## Noche actual (0..1), para quien se conecta a night_changed después de crearse la escena.
func night_amount() -> float:
	return maxf(_last_night, 0.0)


func _update(force: bool) -> void:
	if frozen:
		return
	var h := WorldClock.sun_height() if day_cycle and not space else 0.55
	var n := WorldClock.night() if day_cycle and not space else (1.0 if space else 0.0)
	# El sol sigue su camino de verdad: sale por el este, más alto en verano que en invierno
	var dir := WorldClock.sun_direction() if day_cycle and not space else Vector3(0.4, 0.55, 0.73).normalized()
	if dir.y < 0.02:
		dir = Vector3(dir.x, 0.02, dir.z).normalized()  # bajo el horizonte se apaga (ver más abajo)
	sun.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.999 else Vector3.FORWARD)
	var low := 1.0 - clampf(h * 2.5, 0.0, 1.0)   # 1 cerca del horizonte
	var warm := Color("#ff9d5c")
	sun.light_color = Color("#fff4e0").lerp(warm, low * 0.85) * sun_tint
	sun.light_energy = clampf(h * 4.0, 0.0, 1.0) * 1.35 if not space else 1.1
	moon.light_energy = n * 0.4 if not space else 0.0

	if not space:
		var day_top := sky_color.darkened(0.45)
		var dusk_top := Color("#33416e")
		var night_top := Color("#03050c")
		var top := day_top.lerp(dusk_top, low).lerp(night_top, n)
		var horizon := sky_color.lightened(0.15).lerp(Color("#f6a066"), low * (1.0 - n)).lerp(Color("#1a2747"), n)
		# Nublado: el cielo se vuelve gris y la luz del sol se apaga
		var gray := Color(0.5, 0.53, 0.57).lerp(Color("#0a0d14"), n)
		top = top.lerp(gray.darkened(0.15), _overcast * 0.8)
		horizon = horizon.lerp(gray, _overcast * 0.75)
		# Cubierto: el sol apenas pasa, la luz llega de todo el cielo y las sombras se difuminan
		sun.light_energy *= 1.0 - _overcast * 0.85
		sun.light_angular_distance = lerpf(0.55, 6.0, smoothstep(0.3, 0.9, _overcast))
		_sky("sky_top_color", top)
		_sky("sky_horizon_color", horizon)
		_sky("ground_horizon_color", horizon.darkened(0.1))
		_sky("ground_bottom_color", ground_color.darkened(0.6).lerp(Color.BLACK, n))
		_sky("sun_angle_max", 12.0 + low * 8.0)
		_sky("sunset_color", warm.lerp(Color("#ff7040"), low * 0.5))
		_sky("halo_strength", 0.35 * (1.0 - _overcast * 0.8))
		# Nubes: cubren según el tiempo; blancas al sol, grises si está cerrado, doradas al
		# ocaso, oscuras de noche (y un instante blancas con el rayo)
		_sky("cloud_cover", lerpf(0.24, 1.0, _overcast))  # despejado: algún cúmulo de buen tiempo
		var lit := Color(1, 1, 1).lerp(sun.light_color, 0.55) * clampf(h * 3.0 + 0.55, 0.25, 1.0)
		var cloud := lit.lerp(Color(0.6, 0.63, 0.68) * clampf(h * 2.0 + 0.45, 0.2, 1.0), _overcast * 0.75)
		# Al alba y al anochecer la nube no es más oscura que el cielo: la toca la luz rasante del sol
		# (por debajo) y, de noche, solo la aclara un poco la luz del pueblo
		cloud = cloud.lerp(horizon.lerp(Color("#ffb08a"), (1.0 - _overcast) * 0.4), low * (1.0 - n) * 0.5)
		cloud = cloud.lerp(horizon.lerp(top, 0.5) * 1.08, n * 0.92)
		cloud = cloud.lerp(Color("#cfd8ff"), _lightning * 0.8)
		_sky("cloud_color", cloud)
		_sky("cloud_shadow_color", cloud.darkened(0.45).lerp(horizon, 0.3))
		_sky("cloud_offset", _cloud_offset)
		env.fog_light_color = fog_color.lerp(Color("#f0b080"), low * 0.5 * (1.0 - n)).lerp(Color("#0c1222"), n)
		env.fog_light_color = env.fog_light_color.lerp(Color(0.55, 0.58, 0.62).lerp(Color("#0c1222"), n), _overcast * 0.5)
		if _lightning <= 0.0:
			env.ambient_light_energy = lerpf(1.0 + _overcast * 0.25, 0.6, n)
	else:
		_sky("sky_top_color", Color("#010207"))
		_sky("sky_horizon_color", Color("#070b1a").lerp(sky_color, 0.15))
		_sky("ground_horizon_color", Color("#070b1a").lerp(sky_color, 0.15))
		_sky("ground_bottom_color", Color("#010207"))
		_sky("cloud_cover", 0.0)
		_sky("halo_strength", 0.0)
		# En el espacio el cielo es negro: la luz ambiente sale de las luces de la propia estación
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#46507a")
		env.ambient_light_energy = 1.2
	sun.visible = sun.light_energy > 0.01 and not _indoors
	if _indoors:
		# Dentro: luz de lámparas y la que entra por las ventanas (más de día que de noche)
		moon.light_energy = 0.0
		env.ambient_light_energy = lerpf(0.75, 0.32, n)
		env.ambient_light_color = Color("#e6d2b4").lerp(Color("#b8b0c8"), n * 0.4)
	if _star_mat:
		_star_mat.albedo_color.a = clampf(n * 1.3 - 0.2, 0.0, 1.0) * (1.0 - _overcast * 0.9) if not space else 1.0
		_stars.visible = _star_mat.albedo_color.a > 0.01 and not _indoors
	if force or absf(n - _last_night) > 0.02:
		_last_night = n
		night_changed.emit(n)


## Entrar o salir de un edificio: dentro no hay cielo que ilumine ni niebla del exterior.
func _set_indoors(on: bool) -> void:
	_indoors = on
	Sfx.set_indoors(on)  # eco de habitación; la lluvia y el mar, amortiguados
	if on:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.sdfgi_enabled = false
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_enabled = not space
		_apply_quality()
	_update(true)


## Cambiar la calidad en Ajustes (también en plena partida) se aplica al momento.
func _on_settings_changed() -> void:
	_apply_quality()
	if _rain:
		_rain.amount = [600, 1400, 2600][clampi(Settings.graphics_quality, 0, 2)]
		_splash.amount = [200, 500, 900][clampi(Settings.graphics_quality, 0, 2)]
		_rain_floor.visible = Settings.graphics_quality >= 1
	for g in get_tree().get_nodes_in_group("grass"):
		Decor.apply_grass_quality(g)
	for l in get_tree().get_nodes_in_group("quality_shadows"):
		l.shadow_enabled = Settings.graphics_quality >= 2
	for p in get_tree().get_nodes_in_group("player"):
		if p._lamp:
			p._lamp.shadow_enabled = Settings.graphics_quality >= 1


func _apply_quality() -> void:
	var q := Settings.graphics_quality
	env.glow_enabled = q >= 1  # (en calidad baja, sin resplandor: las gráficas antiguas sufrían)
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0  # solo brilla lo que emite luz (no los textos blancos de noche)
	env.glow_hdr_threshold = 1.35  # (más alto: de día, la espuma y los faros no hacen manchas blancas)
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	# Luz que rebota: en media, la de la pantalla (SSIL); en alta, iluminación global de verdad
	# (SDFGI: el sol que entra en un callejón aclara las paredes, el césped tiñe de verde) y
	# reflejos en lo mojado y en el agua (SSR)
	env.ssil_enabled = q >= 1
	env.ssil_intensity = 0.8
	env.sdfgi_enabled = q >= 2 and not space and not _indoors
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 0.8
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.volumetric_fog_enabled = q >= 2 and not space and not _indoors
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = fog_color
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_sky_affect = 0.0
	if sun:
		# Sombras hasta lejos (antes acababan a 90 m y los edificios lejanos «flotaban»)
		sun.directional_shadow_max_distance = [120.0, 200.0, 300.0][clampi(q, 0, 2)]
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if q >= 1 else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.scaling_3d_scale = 1.0 if q >= 1 else 0.8
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = [600, 1400, 2600][Settings.graphics_quality]
	_rain.lifetime = 0.9
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 40, 50))
	_rain.collision_base_size = 0.02
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.08, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	# La gota desaparece al tocar el suelo (o un tejado) y salpica ahí
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 1
	_rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.012, 0.45)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.84, 0.92, 0.22)
	m.proximity_fade_enabled = true  # sin gotas gruesas pegadas a la cámara
	m.proximity_fade_distance = 1.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	drop.material = m
	_rain.draw_pass_1 = drop
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	# Salpicaduras: unas gotitas que saltan donde cae cada gota
	_splash = GPUParticles3D.new()
	_splash.amount = [200, 500, 900][Settings.graphics_quality]
	_splash.lifetime = 0.22
	_splash.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 55.0
	sm.initial_velocity_min = 0.8
	sm.initial_velocity_max = 1.8
	sm.gravity = Vector3(0, -9.8, 0)
	sm.scale_min = 0.6
	sm.scale_max = 1.2
	_splash.process_material = sm
	var dot := QuadMesh.new()
	dot.size = Vector2(0.03, 0.03)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.8, 0.86, 0.95, 0.35)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	_splash.draw_pass_1 = dot
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)
	_rain.sub_emitter = _rain.get_path_to(_splash)
	# El «suelo» que ven las gotas: un mapa de alturas alrededor de la cámara
	_rain_floor = GPUParticlesCollisionHeightField3D.new()
	_rain_floor.size = Vector3(50, 40, 50)
	_rain_floor.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_rain_floor.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_rain_floor.follow_camera_enabled = true
	_rain_floor.visible = Settings.graphics_quality >= 1
	add_child(_rain_floor)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = _rain_loop()
	_rain_sound.volume_db = -80.0
	_rain_sound.bus = Sfx.BUS_OUTSIDE
	add_child(_rain_sound)


## Rumor de lluvia: ruido suave en bucle (sin archivos de audio).
static func _rain_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var crackle := rng.randf_range(-1.0, 1.0) * (0.6 if rng.randf() < 0.004 else 0.0)
		data.encode_s16(i * 2, int(clampf(lp * 0.35 + crackle, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav


## Dirección de una estrella: al menos 8° sobre el horizonte (antes alguna quedaba a ras de suelo).
static func star_direction(rng: RandomNumberGenerator) -> Vector3:
	var yaw := rng.randf() * TAU
	var elev := asin(rng.randf_range(sin(deg_to_rad(8.0)), 1.0))
	return Vector3(cos(elev) * cos(yaw), sin(elev), cos(elev) * sin(yaw))


func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var star := QuadMesh.new()
	star.size = Vector2(1.6, 1.6)
	mm.mesh = star
	mm.instance_count = 900
	for i in mm.instance_count:
		var dir := star_direction(rng)
		var basis := Basis.looking_at(-dir).scaled(Vector3.ONE * rng.randf_range(0.4, 1.4))
		mm.set_instance_transform(i, Transform3D(basis, dir * 450.0))
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = mm
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.albedo_color = Color(1, 1, 1, 0)
	_star_mat.disable_fog = true
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_stars.material_override = _star_mat
	_stars.extra_cull_margin = 1000.0
	add_child(_stars)

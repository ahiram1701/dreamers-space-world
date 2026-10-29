class_name EnvironmentFX
extends Node3D
## Cielo, sol, niebla y posprocesado de cada escena, con ciclo de día y noche (WorldClock)
## y tres niveles de calidad (Settings.graphics_quality). Lo comparten el pueblo y los lugares.
##
## Uso:  var fx := EnvironmentFX.new(); fx.sky_color = …; fx.fog_color = …; add_child(fx)
##       fx.env / fx.sun / fx.sky_mat quedan disponibles para secuencias (El Despertar…).

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
var sky_mat: ProceduralSkyMaterial
## Si una secuencia controla el cielo (El Despertar), el ciclo se detiene.
var frozen := false

var _stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D
var _last_night := -1.0


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
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
	_apply_quality()
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.6   # sombras suaves
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color("#8fa8ff")
	moon.light_energy = 0.0
	moon.rotation_degrees = Vector3(-50, 150, 0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_build_stars()
	_update(true)


func _process(_delta: float) -> void:
	_update(false)


## Noche actual (0..1), para quien se conecta a night_changed después de crearse la escena.
func night_amount() -> float:
	return maxf(_last_night, 0.0)


func _update(force: bool) -> void:
	if frozen:
		return
	var h := WorldClock.sun_height() if day_cycle and not space else 0.55
	var n := WorldClock.night() if day_cycle and not space else (1.0 if space else 0.0)
	# El sol gira de este a oeste; por debajo del horizonte se apaga
	var t := WorldClock.hour() if day_cycle else 15.0
	sun.rotation = Vector3(-asin(clampf(h, -1.0, 1.0)) if h > 0.0 else 0.15, deg_to_rad(-90.0 + (t - 6.0) * 15.0), 0)
	var low := 1.0 - clampf(h * 2.5, 0.0, 1.0)   # 1 cerca del horizonte
	var warm := Color("#ff9d5c")
	sun.light_color = Color("#fff4e0").lerp(warm, low * 0.85) * sun_tint
	sun.light_energy = clampf(h * 4.0, 0.0, 1.0) * 1.35 if not space else 1.1
	sun.visible = sun.light_energy > 0.01
	moon.light_energy = n * 0.4 if not space else 0.0

	if not space:
		var day_top := sky_color.darkened(0.45)
		var dusk_top := Color("#33416e")
		var night_top := Color("#03050c")
		var top := day_top.lerp(dusk_top, low).lerp(night_top, n)
		var horizon := sky_color.lightened(0.15).lerp(Color("#f6a066"), low * (1.0 - n)).lerp(Color("#1a2747"), n)
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = horizon
		sky_mat.ground_horizon_color = horizon.darkened(0.1)
		sky_mat.ground_bottom_color = ground_color.darkened(0.6).lerp(Color.BLACK, n)
		sky_mat.sun_angle_max = 12.0 + low * 8.0
		env.fog_light_color = fog_color.lerp(Color("#f0b080"), low * 0.5 * (1.0 - n)).lerp(Color("#0c1222"), n)
		env.ambient_light_energy = lerpf(1.0, 0.6, n)
	else:
		sky_mat.sky_top_color = Color("#010207")
		sky_mat.sky_horizon_color = Color("#070b1a").lerp(sky_color, 0.15)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
		sky_mat.ground_bottom_color = Color("#010207")
		# En el espacio el cielo es negro: la luz ambiente sale de las luces de la propia estación
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#46507a")
		env.ambient_light_energy = 1.2
	if _star_mat:
		_star_mat.albedo_color.a = clampf(n * 1.3 - 0.2, 0.0, 1.0) if not space else 1.0
		_stars.visible = _star_mat.albedo_color.a > 0.01
	if force or absf(n - _last_night) > 0.02:
		_last_night = n
		night_changed.emit(n)


func _apply_quality() -> void:
	var q := Settings.graphics_quality
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = q >= 2
	env.volumetric_fog_enabled = q >= 2 and not space
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = fog_color
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_sky_affect = 0.0
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if q >= 1 else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.scaling_3d_scale = 1.0 if q >= 1 else 0.8
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)


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
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.05, 1), rng.randf_range(-1, 1)).normalized()
		var basis := Basis.looking_at(-dir).scaled(Vector3.ONE * rng.randf_range(0.4, 1.4))
		mm.set_instance_transform(i, Transform3D(basis, dir * 450.0))
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = mm
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.albedo_color = Color(1, 1, 1, 0)
	_star_mat.disable_fog = true
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_stars.material_override = _star_mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.extra_cull_margin = 1000.0
	add_child(_stars)

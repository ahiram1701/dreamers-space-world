extends Node3D
## Acto 0 — Bahía de las Horas. Igual para todos los jugadores; lo que cambia es
## cómo hablas con la gente, y eso ya empieza a moldear tu mundo (NPCMemory, PlayerProfile).
## Se construye en código con modelos CC0 (AssetLibrary), terreno y agua procedurales.

const NPCS_PATH := "res://data/act0/npcs.json"
const TOWN_SEED := 3330333
const SPAWN := Vector3(-6, 0.5, -4)
const LIGHTHOUSE_POS := Vector3(44, 0, -30)
const WATER_Y := -0.45
## Sitios con nombre: a dónde pueden ir los vecinos (rutinas, "acompáñame al muelle") y qué
## tiene cerca el jugador cuando hace algo (F).
const PLACES := {
	"faro": Vector3(40, 0, -25), "muelle": Vector3(36, 0, 6), "cafetería": Vector3(20, 0, 9),
	"estación": Vector3(-36, 0, 25), "vías del tren": Vector3(-20, 0, 35), "tu casa": Vector3(-11, 0, -4),
	"calle principal": Vector3(-5, 0, 10), "playa": Vector3(30, 0, -10), "plaza": Vector3(-5, 0, -20),
}
const SCENE_CONTEXT := """Acto 0. Bahía de las Horas: pueblo costero tranquilo en el presente.
El jugador es un/a vecino/a corriente del pueblo con una vida normal. Aún no sabe nada de multiversos.
Últimamente pasan cosas pequeñas y raras con explicación física aún desconocida: un pulso electromagnético a las 3:33 que enciende el faro desconectado y para relojes, vecinos con flashes de recuerdos que no son suyos, una transmisión de radio estructurada."""

var _player: Player
var _dialogue: DialoguePanel
var _objective: Label
var _beacon: OmniLight3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _awakening: AwakeningSequence
var _ui: GameplayUI
var _npcs: Dictionary = {}  # npc_id -> TownNPC
var _fx: EnvironmentFX
var _noise: FastNoiseLite
var _boats: Array = []
var _schedules: Dictionary = {}  # npc_id -> [[hora, sitio], ...]


func _ready() -> void:
	if not WorldDB.is_loaded() and not WorldDB.load_world(WorldDB.last_world_id()):
		WorldDB.create_world("Mundo sin nombre")  # escena abierta directamente desde el editor
	_seed_base_npcs()

	_build_environment()
	_build_terrain()
	_build_town()
	_build_landmarks()

	_player = Player.new()
	_player.position = SPAWN
	add_child(_player)
	_player.interact_requested.connect(_on_interact)

	for entry in _load_npc_entries():
		_schedules[entry.id] = entry.get("schedule", [])
		var npc := TownNPC.new()
		add_child(npc)
		npc.position = Vector3(entry.position[0], _ground_height(entry.position[0], entry.position[2]) + 0.1, entry.position[2])
		npc.setup(WorldDB.get_entity("npc", entry.id))
		npc.face(SPAWN)
		_npcs[entry.id] = npc

	_build_hud()
	_dialogue = DialoguePanel.new()
	_dialogue.scene_context = SCENE_CONTEXT
	add_child(_dialogue)
	_dialogue.closed.connect(_on_dialogue_closed)
	_ui = GameplayUI.new()
	_ui.player = _player
	_ui.nearby_npcs = func(): return _npcs.keys()
	_ui.scene_context = _context
	add_child(_ui)
	Actions.npc_action.connect(_on_npc_action)
	WorldClock.hour_changed.connect(func(_h): _follow_schedules(false))
	_follow_schedules(true)
	var waves := AmbientAudio.new()
	waves.kind = AmbientAudio.Kind.WAVES
	add_child(waves)
	_update_objective()


func _process(_delta: float) -> void:
	if _player.position.y < -10.0:  # cayó al mar o fuera del mapa
		_player.position = SPAWN
		_player.velocity = Vector3.ZERO
	if _awakening != null:
		return  # la secuencia controla el faro
	# El faro "respira"; cuando el Despertar está cerca, parpadea nervioso.
	var t := Time.get_ticks_msec() / 1000.0
	if _progress().get("awakening_ready", false):
		_beacon.light_energy = 6.0 + 5.0 * sin(t * 9.0) * sin(t * 2.3)
	else:
		_beacon.light_energy = 3.0 + 1.5 * sin(t * 1.2)


# --- Contenido base -------------------------------------------------------------------

## Los 3 vecinos se escriben a mano y entran en el mundo del jugador al empezar.
## A partir de ahí son suyos: sus recuerdos y su relación evolucionan distinto en cada partida.
func _seed_base_npcs() -> void:
	for entry in _load_npc_entries():
		var existing := WorldDB.get_entity("npc", entry.id)
		if existing.is_empty():
			WorldDB.add_entity("npc", entry.entity, "act0:base", entry.id)
		elif not existing.get("appearance", {}).has("figure"):  # partidas de antes de los modelos 3D
			var look: Dictionary = existing.get("appearance", {}).duplicate()
			look["figure"] = entry.entity.appearance.figure
			WorldDB.update_entity("npc", entry.id, {"appearance": look})


func _load_npc_entries() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(NPCS_PATH))
	return parsed if parsed is Array else []


# --- Progreso del Acto 0 --------------------------------------------------------------

func _progress() -> Dictionary:
	return WorldDB.get_state("act0", {"talked": [], "awakening_ready": false})


func _on_interact(target: Node) -> void:
	if target is TownNPC:
		_ui.block(true)
		target.face(_player.global_position)
		target.talking = true
		_dialogue.scene_context = _context()
		_dialogue.open(target.npc_id)


func _on_dialogue_closed(npc_id: String) -> void:
	_ui.block(false)
	_npcs[npc_id].talking = false
	_npcs[npc_id].refresh_name(WorldDB.get_entity("npc", npc_id))
	var p := _progress()
	if not (npc_id in p.talked):
		p.talked.append(npc_id)
	p.awakening_ready = p.talked.size() >= _npcs.size()
	WorldDB.set_state("act0", p)
	_update_objective()


func _update_objective() -> void:
	var p := _progress()
	if GameState.is_awakened():
		_objective.text = "Bahía de las Horas · Pulsa T para usar el Ancla"
	elif p.awakening_ready:
		_objective.text = "Son casi las 3:33. Ve al faro."
	else:
		_objective.text = "Habla con tus vecinos (%d/%d)" % [p.talked.size(), _npcs.size()]


func _on_lighthouse_entered(body: Node3D) -> void:
	if not (body is Player) or _awakening != null or GameState.is_awakened():
		return
	if not _progress().get("awakening_ready", false):
		return
	_objective.text = "3:33"
	_fx.frozen = true  # la secuencia controla el cielo
	WorldClock.set_hour(3.55)
	_awakening = AwakeningSequence.new()
	_awakening.player = _player
	_awakening.sun = _sun
	_awakening.env = _env
	_awakening.sky_mat = _sky_mat
	_awakening.beacon = _beacon
	_awakening.breach_position = LIGHTHOUSE_POS + Vector3(-3.5, 1.6, 3.5)  # junto a la puerta del faro
	add_child(_awakening)
	_awakening.play()


# --- Vida en el pueblo ---------------------------------------------------------------

## Escena para la IA: el pueblo, la hora y lo que el jugador tiene cerca.
func _context() -> String:
	var near := _nearest_place(_player.global_position)
	var people := PackedStringArray()
	for id in _npcs:
		if _npcs[id].global_position.distance_to(_player.global_position) < 12.0:
			people.append(WorldDB.get_entity("npc", id).get("name", "?"))
	return "%s\n%s El jugador está cerca de: %s.%s" % [SCENE_CONTEXT, WorldClock.describe(), near,
		(" Cerca hay: %s." % ", ".join(people)) if not people.is_empty() else ""]


func _nearest_place(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for name in PLACES:
		var d := Vector2(pos.x - PLACES[name].x, pos.z - PLACES[name].z).length()
		if d < best_d:
			best = name
			best_d = d
	return best


## Lo que un vecino decide hacer en una conversación (Actions) se ve en el mundo.
func _on_npc_action(npc_id: String, action: Dictionary) -> void:
	if not _npcs.has(npc_id):
		return
	var npc: TownNPC = _npcs[npc_id]
	match action.get("type", ""):
		"follow_player":
			npc.follow(_player)
		"stop_following":
			npc.stop()
		"go_to":
			if not NPCMemory.is_following(npc_id):
				npc.walk_to(_place_position(str(action.get("target", ""))))


## Posición de un sitio por su nombre aproximado ("el faro", "la cafetería del muelle"…).
func _place_position(text: String) -> Vector3:
	var t := text.to_lower()
	for name in PLACES:
		if t.contains(name) or name.contains(t):
			return _on_ground(PLACES[name])
	for name in PLACES:  # "cafe" → "cafetería"
		if t.length() >= 4 and name.begins_with(t.left(4)):
			return _on_ground(PLACES[name])
	return _on_ground(PLACES["calle principal"])


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground_height(p.x, p.z), p.z)


## Rutinas: cada vecino va a su sitio según la hora (salvo si te acompaña o está hablando).
func _follow_schedules(teleport: bool) -> void:
	var h := WorldClock.hour()
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		if NPCMemory.is_following(id):
			if teleport:
				npc.global_position = _player.global_position + Vector3(2, 0.5, 2)
			npc.follow(_player)
			continue
		var plan: Array = _schedules.get(id, [])
		if plan.is_empty() or npc.talking:
			continue
		var place: String = plan[plan.size() - 1][1]  # antes de la primera hora: donde acabó ayer
		for slot in plan:
			if h >= float(slot[0]):
				place = slot[1]
		var target := _place_position(place) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		if teleport:
			npc.global_position = target + Vector3(0, 0.2, 0)
		elif npc.global_position.distance_to(target) > 4.0:
			npc.walk_to(target)


# --- Construcción del mundo -----------------------------------------------------------

func _build_environment() -> void:
	_fx = EnvironmentFX.new()
	_fx.sky_color = Color("#86aee0")
	_fx.fog_color = Color("#cfd9e2")
	_fx.ground_color = Color("#4f6b3a")
	_fx.fog_density = 0.0035
	add_child(_fx)
	_env = _fx.env
	_sun = _fx.sun
	_sky_mat = _fx.sky_mat
	Decor.bind_windows(_fx)


## Altura del suelo: el pueblo es llano, la playa baja hacia el mar, el faro está sobre un
## pequeño promontorio y hay colinas suaves lejos de las calles.
func _ground_height(x: float, z: float) -> float:
	var h := 0.0
	if x > 28.0:
		h = -smoothstep(28.0, 58.0, x) * 1.7 - smoothstep(58.0, 95.0, x) * 4.0
	var hills := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	h += hills * 2.4 * maxf(smoothstep(62.0, 95.0, absf(z)), smoothstep(-48.0, -85.0, x)) * (1.0 - smoothstep(10.0, 28.0, x))
	var d := Vector2(x - LIGHTHOUSE_POS.x, z - LIGHTHOUSE_POS.z).length()
	if d < 12.0:
		h = lerpf(0.55, h, smoothstep(6.5, 12.0, d))
	return h


func _ground_color(x: float, z: float, h: float) -> Color:
	var grass := Color("#5d7f3c").lerp(Color("#77923f"), _noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5)
	var sand := Color("#dcc79a")
	var wet := Color("#a89670")
	var road := Color("#6f6a62")
	var c := grass.lerp(sand, smoothstep(22.0, 29.0, x))
	c = c.lerp(wet, smoothstep(-0.15, -0.45, h) * smoothstep(28.0, 32.0, x))
	if absf(x + 5.0) < 3.2 and absf(z) < 62.0:
		c = road
	elif x > -5.0 and x < 37.0 and absf(z - 4.0) < 2.4:
		c = road.lerp(sand, smoothstep(26.0, 34.0, x) * 0.6)
	var dl := Vector2(x - LIGHTHOUSE_POS.x, z - LIGHTHOUSE_POS.z).length()
	if dl < 9.0 and h > 0.2:
		c = Color("#7a7468").lerp(grass, smoothstep(5.0, 9.0, dl) * 0.5)
	return c


func _build_terrain() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = TOWN_SEED
	_noise.frequency = 0.02
	var x0 := -110.0
	var z0 := -130.0
	var step := 2.0
	var nx := 150  # hasta x = 190
	var nz := 130
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var xa := x0 + i * step
			var za := z0 + j * step
			var quad := [Vector2(xa, za), Vector2(xa + step, za), Vector2(xa, za + step), Vector2(xa + step, za + step)]
			for k in [0, 1, 2, 2, 1, 3]:
				var p: Vector2 = quad[k]
				var h := _ground_height(p.x, p.y)
				st.set_color(_ground_color(p.x, p.y, h))
				st.add_vertex(Vector3(p.x, h, p.y))
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Decor.ground_material()
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	Decor.water(self, Vector3(165, WATER_Y, 0), Vector2(270, 300))  # empieza en x = 30, más allá de la arena seca

	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED + 7
	Decor.grass(self, Vector2(-30, 0), Vector2(56, 70), 4.0, rng, _ground_height, _grass_allowed, Color("#86a347"), Color("#3d5a24"))


func _grass_allowed(x: float, z: float) -> bool:
	return x < 19.0 and absf(x + 5.0) > 3.6 and not (absf(z - 4.0) < 2.8 and x > -5.0)


func _build_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED  # mismo pueblo para todos: el Acto 0 es el punto de partida común
	var wall_colors := [Color("#f4f1de"), Color("#e9d8b4"), Color("#f2c9a0"), Color("#c9dbe2"), Color("#e7b8a8"), Color("#d8e2c4")]
	for row in range(-4, 5):
		for side in [-1, 1]:
			if rng.randf() < 0.2 or (row == 0 and side == -1):  # ese hueco es tu casa
				continue
			var pos := Vector3(-5 + side * rng.randf_range(10, 12), 0, row * 12 + rng.randf_range(-2, 2))
			_house(pos, side, "town" if absi(row) <= 1 else "small", wall_colors[rng.randi() % wall_colors.size()], rng)
	# Tu casa, junto al punto de inicio
	_house(Vector3(-16, 0, -4), -1, "small", Color("#9fc4e0"), rng)
	_label3d(Vector3(-16, 8.5, -4), "Tu casa")

	# Farolas a lo largo de la calle y hacia el muelle
	for z in range(-56, 60, 16):
		Decor.streetlight(self, Vector3(-8.8, 0, z), PI / 2, _fx)
		Decor.streetlight(self, Vector3(-1.2, 0, z + 8), -PI / 2, _fx)
	for x in [6.0, 18.0, 30.0]:
		Decor.streetlight(self, Vector3(x, _ground_height(x, 7.2), 7.2), PI, _fx)

	# Árboles y rocas fuera de las calles
	for i in 140:
		var x := rng.randf_range(-105, 24)
		var z := rng.randf_range(-125, 125)
		if absf(x + 5.0) < 17.0 and absf(z) < 60.0:
			continue  # la calle y sus casas
		if x > -48 and x < -22 and z > 24 and z < 42:
			continue  # la estación y las vías
		if absf(z - 37.0) < 3.0 or (x > -6 and absf(z - 4.0) < 5.0) or Vector2(x - SPAWN.x, z - SPAWN.z).length() < 8.0:
			continue
		var kind := 0 if rng.randf() < 0.75 else 2
		var biome := "pine" if absf(z) > 75.0 or x < -60.0 else "temperate"
		var model := AssetLibrary.nature(biome, kind, rng)
		if model:
			AssetLibrary.place(self, model, Vector3(x, _ground_height(x, z) - 0.1, z),
				rng.randf_range(5.0, 9.0) if kind == 0 else rng.randf_range(0.8, 2.2), rng.randf() * TAU, kind == 0 or rng.randf() < 0.5)
	for i in 40:  # arbustos y flores junto a las casas
		var z := rng.randf_range(-55, 55)
		var x := -5.0 + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(4.2, 6.0)
		var bush := AssetLibrary.nature("temperate", 1, rng)
		if bush:
			AssetLibrary.place(self, bush, Vector3(x, 0, z), rng.randf_range(0.5, 1.1), rng.randf() * TAU, false)


func _build_landmarks() -> void:
	# Faro: torre blanca con franjas, balcón, linterna acristalada y cúpula
	var base_y := _ground_height(LIGHTHOUSE_POS.x, LIGHTHOUSE_POS.z)
	var lp := LIGHTHOUSE_POS + Vector3(0, base_y, 0)
	_cylinder(lp + Vector3(0, 0.6, 0), 3.4, 3.6, 1.2, Color("#8a8478"))
	var tower := _cylinder(lp + Vector3(0, 10.2, 0), 1.55, 2.3, 18, Color("#f2efe6"))
	tower.add_child(_stripe(-2.5, 2.05))
	tower.add_child(_stripe(3.5, 1.8))
	_cylinder(lp + Vector3(0, 19.35, 0), 2.4, 2.4, 0.3, Color("#2d3238"))
	var glass := _cylinder(lp + Vector3(0, 20.6, 0), 1.25, 1.25, 2.2, Color("#fff3b0"))
	glass.material_override.emission_enabled = true
	glass.material_override.emission = Color("#ffe9a0")
	glass.material_override.emission_energy_multiplier = 1.5
	var dome := MeshInstance3D.new()
	dome.mesh = SphereMesh.new()
	dome.mesh.radius = 1.45
	dome.mesh.height = 1.6
	dome.mesh.is_hemisphere = true
	dome.material_override = _mat(Color("#b23a3a"))
	dome.position = lp + Vector3(0, 21.7, 0)
	add_child(dome)
	var door := _box(lp + Vector3(-1.75, 1.3, 1.75), Vector3(0.2, 2.2, 1.2), Color("#4a3426"), false)
	door.rotation.y = PI / 4
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color("#fff3b0")
	_beacon.omni_range = 34.0
	_beacon.position = lp + Vector3(0, 20.6, 0)
	add_child(_beacon)
	var zone := Area3D.new()
	var zs := CollisionShape3D.new()
	zs.shape = SphereShape3D.new()
	zs.shape.radius = 5.5
	zone.add_child(zs)
	zone.position = lp + Vector3(0, 1, 0)
	zone.body_entered.connect(_on_lighthouse_entered)
	add_child(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED + 11
	for i in 14:  # rocas al pie del faro y en la orilla
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 14.0)
		var rock := AssetLibrary.nature("barren", 2, rng)
		if rock:
			var rp := Vector3(LIGHTHOUSE_POS.x + cos(a) * r, 0, LIGHTHOUSE_POS.z + sin(a) * r)
			AssetLibrary.place(self, rock, rp + Vector3(0, _ground_height(rp.x, rp.z) - 0.3, 0), rng.randf_range(0.8, 2.4), rng.randf() * TAU, true)

	# Muelle de madera con postes y barcas
	var dock_y := 0.35
	for i in 14:
		var plank := _box(Vector3(37.5 + i * 2.0, dock_y, 6), Vector3(1.9, 0.18, 3.6), Color("#8b6b4a").darkened(rng.randf() * 0.15))
		plank.material_override.roughness = 0.9
	for i in 8:
		for side in [-1, 1]:
			_cylinder(Vector3(38 + i * 3.6, dock_y - 1.2, 6 + side * 1.9), 0.14, 0.16, 3.0, Color("#5a4632"))
	for b in [["Boat", Vector3(48, WATER_Y + 0.05, 11.5), 8.0, 0.3], ["Lifeboat", Vector3(57, WATER_Y + 0.05, 0.5), 4.0, -0.4], ["BoatWSail", Vector3(70, WATER_Y, 16), 9.0, 1.2]]:
		var boat := AssetLibrary.instance("ships_pack", b[0])
		if boat:
			var bb := AssetLibrary.bounds(boat)
			_boats.append(AssetLibrary.place(self, boat, b[1], bb.size.y * b[2], b[3], false))

	# Cafetería del muelle
	_building(Vector3(20, 0, 14), "1Story_Sign_Mat", 3.4, PI, Color("#c97b5a"))
	_label3d(Vector3(20, 7.5, 14), "Cafetería del Muelle")

	# Estación de tren abandonada
	_building(Vector3(-36, 0, 30), "2Story_Wide_Mat", 3.0, PI, Color("#8c8279"))
	_label3d(Vector3(-36, 10.5, 30), "Estación (cerrada)")
	for z in [-0.75, 0.75]:
		_box(Vector3(-36, 0.12, 37 + z), Vector3(130, 0.12, 0.12), Color("#7a7a80"), false).material_override.metallic = 0.8
	for i in 64:
		_box(Vector3(-100 + i * 2.0, 0.04, 37), Vector3(0.35, 0.08, 2.3), Color("#4a3a2c"), false)


## Casa de la calle principal mirando a la calle (side: -1 a la izquierda, 1 a la derecha).
func _house(base: Vector3, side: int, size_class: String, wall: Color, rng: RandomNumberGenerator) -> void:
	var model := AssetLibrary.building(size_class, rng, wall)
	if model == null:
		_box(base + Vector3(0, 2, 0), Vector3(6, 4, 6), wall)
		return
	var b := AssetLibrary.bounds(model)
	AssetLibrary.place(self, model, base, b.size.y * 2.7, PI / 2 if side < 0 else -PI / 2, true)


## Edificio concreto (cafetería, estación) con su color de fachada.
func _building(base: Vector3, model_name: String, scale: float, yaw: float, wall: Color) -> void:
	var model := AssetLibrary.building_named(model_name, wall)
	if model == null:
		_box(base + Vector3(0, 2, 0), Vector3(8, 4, 6), wall)
		return
	var b := AssetLibrary.bounds(model)
	AssetLibrary.place(self, model, base, b.size.y * scale, yaw, true)


# --- Helpers de primitivas ------------------------------------------------------------

func _box(pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.material_override = _mat(color)
	mesh.position = pos
	add_child(mesh)
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = size
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


func _cylinder(pos: Vector3, top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	mesh.mesh.top_radius = top
	mesh.mesh.bottom_radius = bottom
	mesh.mesh.height = height
	mesh.material_override = _mat(color)
	mesh.position = pos
	add_child(mesh)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CylinderShape3D.new()
	shape.shape.radius = bottom
	shape.shape.height = height
	body.add_child(shape)
	mesh.add_child(body)
	return mesh


func _stripe(y: float, radius: float) -> MeshInstance3D:
	var s := MeshInstance3D.new()
	s.mesh = CylinderMesh.new()
	s.mesh.top_radius = radius - 0.04
	s.mesh.bottom_radius = radius + 0.02
	s.mesh.height = 1.6
	s.material_override = _mat(Color("#b23a3a"))
	s.position.y = y
	return s


func _label3d(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.outline_size = 10
	l.pixel_size = 0.01
	l.position = pos
	add_child(l)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_objective = Label.new()
	_objective.position = Vector2(20, 16)
	_objective.add_theme_font_size_override("font_size", 22)
	_objective.add_theme_constant_override("outline_size", 6)
	_objective.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(_objective)
	var help := Label.new()
	help.text = "WASD moverse · Shift correr · Espacio saltar · E hablar · F hacer algo · I inventario y diario · Esc pausa"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -34
	help.offset_left = 20
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hud.add_child(help)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

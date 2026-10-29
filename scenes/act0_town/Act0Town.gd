extends Node3D
## Acto 0 — Bahía de las Horas. Igual para todos los jugadores; lo que cambia es
## cómo hablas con la gente, y eso ya empieza a moldear tu mundo (NPCMemory, PlayerProfile).
## Todo se construye en código con primitivas; se sustituirá por piezas modulares.

const NPCS_PATH := "res://data/act0/npcs.json"
const TOWN_SEED := 3330333
const SPAWN := Vector3(-6, 0.5, -4)
const LIGHTHOUSE_POS := Vector3(44, 0, -30)
const SCENE_CONTEXT := """Acto 0. Bahía de las Horas: pueblo costero tranquilo en el presente, al atardecer.
El jugador es un/a vecino/a corriente del pueblo con una vida normal. Aún no sabe nada de multiversos.
Últimamente pasan cosas pequeñas y raras (el faro se enciende solo a las 3:33, sueños compartidos, una señal de radio)."""

var _player: Player
var _dialogue: DialoguePanel
var _objective: Label
var _beacon: OmniLight3D
var _npcs: Dictionary = {}  # npc_id -> TownNPC


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
		var npc := TownNPC.new()
		add_child(npc)
		npc.position = Vector3(entry.position[0], entry.position[1], entry.position[2])
		npc.setup(WorldDB.get_entity("npc", entry.id))
		npc.face(SPAWN)
		_npcs[entry.id] = npc

	_build_hud()
	_dialogue = DialoguePanel.new()
	_dialogue.scene_context = SCENE_CONTEXT
	add_child(_dialogue)
	_dialogue.closed.connect(_on_dialogue_closed)
	_update_objective()


func _process(_delta: float) -> void:
	if _player.position.y < -10.0:  # cayó al mar o fuera del mapa
		_player.position = SPAWN
		_player.velocity = Vector3.ZERO
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
		if WorldDB.get_entity("npc", entry.id).is_empty():
			WorldDB.add_entity("npc", entry.entity, "act0:base", entry.id)


func _load_npc_entries() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(NPCS_PATH))
	return parsed if parsed is Array else []


# --- Progreso del Acto 0 --------------------------------------------------------------

func _progress() -> Dictionary:
	return WorldDB.get_state("act0", {"talked": [], "awakening_ready": false})


func _on_interact(target: Node) -> void:
	if target is TownNPC:
		_player.controls_enabled = false
		target.face(_player.global_position)
		_dialogue.open(target.npc_id)


func _on_dialogue_closed(npc_id: String) -> void:
	_player.controls_enabled = true
	_npcs[npc_id].refresh_name(WorldDB.get_entity("npc", npc_id))
	var p := _progress()
	if not (npc_id in p.talked):
		p.talked.append(npc_id)
	p.awakening_ready = p.talked.size() >= _npcs.size()
	WorldDB.set_state("act0", p)
	_update_objective()


func _update_objective() -> void:
	var p := _progress()
	if p.awakening_ready:
		_objective.text = "Son casi las 3:33. El faro te llama."
	else:
		_objective.text = "Habla con tus vecinos (%d/%d)" % [p.talked.size(), _npcs.size()]


func _on_lighthouse_entered(body: Node3D) -> void:
	if body is Player and _progress().get("awakening_ready", false):
		_objective.text = "La luz del faro se dobla sobre sí misma… (El Despertar llegará en la próxima versión.)"


# --- Construcción del mundo -----------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3a4a7a")
	sky_mat.sky_horizon_color = Color("#f2a65a")
	sky_mat.ground_horizon_color = Color("#f2a65a")
	sky_mat.ground_bottom_color = Color("#1d2a3a")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#e9b384")
	env.fog_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffd2a1")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-18, -60, 0)  # sol bajo de atardecer
	add_child(sun)


func _build_terrain() -> void:
	_box(Vector3(-32, -0.5, 0), Vector3(116, 1, 160), Color("#6b8f4e"))         # tierra (x -90..26)
	_box(Vector3(36, -0.55, 0), Vector3(20, 1, 160), Color("#e3cf9c"))           # playa
	var sea := _box(Vector3(110, -0.8, 0), Vector3(130, 1, 400), Color("#2b6c8f"), false)
	sea.material_override.metallic = 0.3
	sea.material_override.roughness = 0.1
	_box(Vector3(-5, 0.01, 0), Vector3(6, 0.02, 120), Color("#7a7468"), false)   # calle principal
	_box(Vector3(10, 0.01, 4), Vector3(40, 0.02, 5), Color("#7a7468"), false)    # calle al muelle


func _build_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED  # mismo pueblo para todos: el Acto 0 es el punto de partida común
	var wall_colors := [Color("#f4f1de"), Color("#e9e4d4"), Color("#f7e6c4"), Color("#dfe7e2")]
	for row in range(-4, 5):
		for side in [-1, 1]:
			if rng.randf() < 0.2 or (row == 0 and side == -1):  # ese hueco es tu casa
				continue
			var pos := Vector3(-5 + side * rng.randf_range(8, 11), 0, row * 12 + rng.randf_range(-2, 2))
			_house(pos, Vector3(rng.randf_range(5, 7), rng.randf_range(3, 5), rng.randf_range(5, 7)),
				wall_colors[rng.randi() % wall_colors.size()])
	# Tu casa, junto al punto de inicio
	_house(Vector3(-14, 0, -4), Vector3(6, 3.5, 6), Color("#bcd4e6"))
	_label3d(Vector3(-14, 5.5, -4), "Tu casa")


func _build_landmarks() -> void:
	# Faro
	var tower := _cylinder(LIGHTHOUSE_POS + Vector3(0, 9, 0), 1.6, 2.2, 18, Color("#f4f1de"))
	tower.add_child(_stripe(0.0))
	tower.add_child(_stripe(-5.0))
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color("#fff3b0")
	_beacon.omni_range = 30.0
	_beacon.position = LIGHTHOUSE_POS + Vector3(0, 18.5, 0)
	add_child(_beacon)
	var zone := Area3D.new()
	var zs := CollisionShape3D.new()
	zs.shape = SphereShape3D.new()
	zs.shape.radius = 5.0
	zone.add_child(zs)
	zone.position = LIGHTHOUSE_POS + Vector3(0, 1, 0)
	zone.body_entered.connect(_on_lighthouse_entered)
	add_child(zone)

	# Muelle y cafetería
	_box(Vector3(50, 0.3, 6), Vector3(26, 0.4, 3.5), Color("#8b6b4a"))
	_house(Vector3(22, 0, 12), Vector3(8, 3.5, 6), Color("#c97b5a"))
	_label3d(Vector3(22, 5.5, 12), "Cafetería del Muelle")

	# Estación de tren abandonada
	_house(Vector3(-36, 0, 30), Vector3(14, 4.5, 7), Color("#8c8279"))
	_label3d(Vector3(-36, 6.5, 30), "Estación (cerrada)")
	for z in [-0.8, 0.8]:
		_box(Vector3(-36, 0.1, 37 + z), Vector3(120, 0.2, 0.15), Color("#5a5a5a"), false)


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


func _house(base: Vector3, size: Vector3, wall: Color) -> void:
	_box(base + Vector3(0, size.y / 2, 0), size, wall)
	var roof := MeshInstance3D.new()
	roof.mesh = PrismMesh.new()
	roof.mesh.size = Vector3(size.x + 0.6, 1.8, size.z + 0.6)
	roof.material_override = _mat(Color("#a64b3c"))
	roof.position = base + Vector3(0, size.y + 0.9, 0)
	add_child(roof)


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


func _stripe(y: float) -> MeshInstance3D:
	var s := MeshInstance3D.new()
	s.mesh = CylinderMesh.new()
	s.mesh.top_radius = 2.0
	s.mesh.bottom_radius = 2.05
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
	help.text = "WASD moverse · Shift correr · Espacio saltar · Ratón cámara · E hablar · Esc soltar ratón"
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

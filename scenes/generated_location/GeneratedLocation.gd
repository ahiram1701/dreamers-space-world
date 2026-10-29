extends Node3D
## Un lugar que la IA creó para ESTE jugador. Se reconstruye desde su definición en WorldDB
## (tipo, bioma, época, semilla, gravedad, cielo, puntos de interés, PNJs, objetos y misión):
## es el mismo lugar cada vez que vuelves.

const SPAWN := Vector3(0, 3, 0)
const POI_MIN := 18.0

var _def: Dictionary = {}
var _location_id := ""
var _height_at: Callable
var _limit := 70.0
var _player: Player
var _dialogue: DialoguePanel
var _ui: GameplayUI
var _env: Environment
var _fx: EnvironmentFX
var _npcs: Dictionary = {}
var _places: Dictionary = {}  # nombre del punto de interés -> posición
var _placed: Array = []  # posiciones ocupadas (balizas, objetos) para que la decoración no las tape


func _ready() -> void:
	if not WorldDB.is_loaded() and not WorldDB.load_world(WorldDB.last_world_id()):
		WorldDB.create_world("Mundo sin nombre")  # escena abierta directamente desde el editor
	_location_id = GameState.current_location()
	_def = WorldDB.get_entity("location", _location_id)
	if _def.is_empty():
		_def = ContentGenerator.load_fallback("location")  # vista previa sin partida (editor / smoke test)
		_location_id = ""

	var space := StationBuilder.is_space(_def)
	var ground := StationBuilder.build(_def, _rng(0)) if space else TerrainBuilder.build(_def)
	_height_at = ground.height_at
	_limit = ground.get("limit", TerrainBuilder.SIZE / 2.0 - 4.0)
	add_child(ground.node)
	_build_environment(space)
	_build_points_of_interest()
	_spawn_pickups()
	if not space:
		PropsBuilder.build(self, _def, _height_at, _rng(4), _placed)
	elif _def.get("kind", "") == "anomaly_zone" or _def.get("finale", false):
		PropsBuilder._floating_rocks(self, _rng(4), "void")

	_player = Player.new()
	_player.gravity_scale = float(_def.get("gravity", 1.0))
	_player.position = SPAWN + Vector3(0, _height_at.call(0.0, 0.0), 0)
	add_child(_player)
	_player.interact_requested.connect(_on_interact)

	_spawn_npcs()
	_build_hud()
	_ui = GameplayUI.new()
	_ui.player = _player
	_ui.nearby_npcs = func(): return _npcs.keys()
	_ui.scene_context = _action_context
	add_child(_ui)
	Actions.npc_action.connect(_on_npc_action)
	for id in _npcs:  # quien aceptó acompañarte sigue contigo
		if NPCMemory.is_following(id):
			_npcs[id].follow(_player)
	_dialogue = DialoguePanel.new()
	_dialogue.scene_context = _scene_context()
	add_child(_dialogue)
	_dialogue.closed.connect(_on_dialogue_closed)
	add_child(AmbientAudio.for_location(_def))
	GameState.stat_changed.connect(func(_s, _v): _apply_instability())
	_apply_instability()

	if _def.get("finale", false) and GameState.ending().is_empty():
		var finale := FinaleSequence.new()
		finale.player = _player
		finale.center = Vector3(0, _height_at.call(0.0, 0.0), 0)
		add_child(finale)
		finale.play()
	else:
		_ui.toast("Llegada: %s" % _def.get("name", "?"))
		Travel.pregenerate()  # el siguiente destino se prepara mientras exploras


func _process(_delta: float) -> void:
	var p := _player.position
	if p.y < -30.0:
		_player.position = SPAWN + Vector3(0, _height_at.call(0.0, 0.0), 0)
		_player.velocity = Vector3.ZERO
	elif absf(p.x) > _limit or absf(p.z) > _limit:  # borde del mapa generado
		_player.position.x = clampf(p.x, -_limit, _limit)
		_player.position.z = clampf(p.z, -_limit, _limit)


# --- Construcción ---------------------------------------------------------------------

func _build_environment(space: bool) -> void:
	var pal := TerrainBuilder.palette(_def.get("biome", "barren"))
	var rng := _rng(1)
	_fx = EnvironmentFX.new()
	_fx.sky_color = Color(_def.get("sky_color", "#7090c0"))
	_fx.fog_color = Color(pal.fog)
	_fx.ground_color = Color(pal.low)
	_fx.space = space
	_fx.fog_density = 0.003
	_fx.sun_tint = Color.WHITE.lerp(_fx.sky_color, 0.25)
	add_child(_fx)
	_env = _fx.env
	Decor.bind_windows(_fx)
	if space:
		StationBuilder.add_starfield(self, _rng(5), _fx.sky_color)
	elif _def.get("biome", "") in ["temperate", "jungle", "ocean", "urban"]:
		var tip := Color(pal.high).lightened(0.15)
		Decor.grass(self, Vector2.ZERO, Vector2(60, 60), 1.4 if _def.get("biome", "") != "urban" else 0.4, rng, _height_at,
			func(x: float, z: float) -> bool: return _height_at.call(x, z) > -0.2, tip, Color(pal.low).darkened(0.3))


## Cada punto de interés es una baliza con nombre (llegar a ella cuenta para las misiones).
## La última recarga el Ancla.
func _build_points_of_interest() -> void:
	var rng := _rng(2)
	var names: Array = _def.get("points_of_interest", []).duplicate()
	names.append("Punto de recarga del Ancla")
	var max_r := minf(55.0, _limit - 6.0)
	for i in names.size():
		var angle := TAU * i / names.size() + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(POI_MIN, max_r)
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		pos.y = _height_at.call(pos.x, pos.z)
		var is_recharge := i == names.size() - 1
		_beacon(pos, names[i], Color("#4fc3f7") if is_recharge else Color("#f2a65a"), -1 if is_recharge else i)
		_places[str(names[i])] = pos
		_placed.append(pos)


func _beacon(pos: Vector3, label: String, color: Color, poi_index: int) -> void:
	var pillar := MeshInstance3D.new()
	pillar.mesh = CylinderMesh.new()
	pillar.mesh.top_radius = 0.25
	pillar.mesh.bottom_radius = 0.6
	pillar.mesh.height = 6.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	pillar.material_override = mat
	pillar.position = pos + Vector3(0, 3, 0)
	add_child(pillar)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 9.0
	light.position = pos + Vector3(0, 6.5, 0)
	add_child(light)
	var l := Label3D.new()
	l.text = label
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 56
	l.outline_size = 10
	l.pixel_size = 0.01
	l.position = pos + Vector3(0, 7.6, 0)
	add_child(l)
	var area := Area3D.new()
	var zone := CollisionShape3D.new()
	zone.shape = SphereShape3D.new()
	zone.shape.radius = 4.0
	area.add_child(zone)
	area.position = pos + Vector3(0, 1, 0)
	area.body_entered.connect(_on_beacon_entered.bind(poi_index))
	add_child(area)


## Los objetos del lugar que aún no has recogido, junto a los puntos de interés.
func _spawn_pickups() -> void:
	var rng := _rng(6)
	var picked: Array = _def.get("picked", [])
	var items: Array = _def.get("item_ids", [])
	for i in items.size():
		if items[i] in picked or Inventory.has(items[i]):
			continue
		var entity := WorldDB.get_entity("item", items[i])
		if entity.is_empty():
			continue
		var anchor: Vector3 = _placed[i % maxi(_placed.size() - 1, 1)] if not _placed.is_empty() else Vector3.ZERO
		var p := anchor + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
		p.y = _height_at.call(p.x, p.z)
		var pickup := Pickup.new()
		add_child(pickup)
		pickup.position = p
		pickup.setup(entity)
		_placed.append(p)


## Habitantes del lugar + el compañero del Despertar, si lo hay.
func _spawn_npcs() -> void:
	var rng := _rng(3)
	var ids: Array = _def.get("npc_ids", []).duplicate()
	var companion := GameState.companion()
	if not companion.is_empty() and GameState.is_awakened():
		ids.append(companion)
	for i in ids.size():
		var entity := WorldDB.get_entity("npc", ids[i])
		if entity.is_empty():
			continue
		var npc := TownNPC.new()
		add_child(npc)
		var is_companion: bool = ids[i] == companion
		var offset := Vector3(2.5, 0, 2.0) if is_companion \
			else Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(6, 12)).rotated(Vector3.UP, rng.randf() * TAU)
		npc.position = offset + Vector3(0, _height_at.call(offset.x, offset.z), 0)
		npc.setup(entity)
		npc.face(Vector3.ZERO)
		_npcs[ids[i]] = npc


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var box := VBoxContainer.new()
	box.position = Vector2(20, 16)
	hud.add_child(box)
	var title := Label.new()
	title.text = _def.get("name", "?")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "%s · gravedad %.1f g" % [_era_label(_def.get("era", "")), float(_def.get("gravity", 1.0))]
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	sub.add_theme_constant_override("outline_size", 4)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(sub)
	var help := Label.new()
	help.text = "WASD moverse · Shift correr · Espacio saltar · E interactuar · F hacer algo · T Ancla · I inventario · Esc pausa"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -34
	help.offset_left = 20
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hud.add_child(help)


# --- Interacción ----------------------------------------------------------------------

func _on_interact(target: Node) -> void:
	if target is TownNPC:
		_ui.block(true)
		target.face(_player.global_position)
		target.talking = true
		_dialogue.scene_context = _scene_context() + "\n" + WorldClock.describe() if not StationBuilder.is_space(_def) else _scene_context()
		_dialogue.open(target.npc_id)
	elif target is Pickup:
		Inventory.add(target.item_id)
		if not _location_id.is_empty():
			var picked: Array = _def.get("picked", []).duplicate()
			picked.append(target.item_id)
			_def["picked"] = picked
			WorldDB.update_entity("location", _location_id, {"picked": picked})
		var item := WorldDB.get_entity("item", target.item_id)
		_ui.toast("Recogido: %s  (I para ver el inventario)" % item.get("name", "?"))
		_player.interact_target = null
		target.queue_free()
		_ui.refresh_tracker()


func _on_dialogue_closed(npc_id: String) -> void:
	_ui.block(false)
	if _npcs.has(npc_id):
		_npcs[npc_id].talking = false
		_npcs[npc_id].refresh_name(WorldDB.get_entity("npc", npc_id))
	Quests.notify("talk_npc", npc_id)


func _on_beacon_entered(body: Node3D, poi_index: int) -> void:
	if not (body is Player) or not GameState.is_awakened():
		return
	if poi_index >= 0:
		Quests.notify("visit_poi", str(poi_index))
		return
	if _def.get("recharged", false):
		_ui.toast("Este punto de recarga ya está agotado.")
		return
	GameState.recharge()
	if not _location_id.is_empty():
		WorldDB.update_entity("location", _location_id, {"recharged": true})
	_def["recharged"] = true
	_ui.toast("Ancla recargada. La inestabilidad baja un poco.")


## Con mucha inestabilidad el mundo se desatura (el GameplayUI añade los fallos de imagen).
func _apply_instability() -> void:
	var instability := GameState.get_stat("instability")
	_env.adjustment_saturation = remap(clampf(instability, 50, 100), 50, 100, 1.12, 0.3)


func _scene_context() -> String:
	var ctx := "%s (%s, %s). %s El jugador llegó a través de una brecha con su Ancla; aquí es un forastero de otra rama del multiverso." % [
		_def.get("name", ""), _def.get("kind", ""), _era_label(_def.get("era", "")), _def.get("description", "")]
	var q := Quests.for_location(_location_id)
	if not q.is_empty():
		var giver: String = WorldDB.get_entity("npc", q.giver).get("name", "?")
		ctx += "\nMisión de este lugar (%s): «%s» — %s. La pidió %s. Objetivo: %s." % [
			"completada" if q.status == "done" else "en curso", q.title, q.description, giver, Quests.objective_text(q)]
	return ctx


## Contexto para "Hacer algo": el lugar, la hora y qué tiene cerca el jugador.
func _action_context() -> String:
	var near := "campo abierto"
	var best := 25.0
	for name in _places:
		var d: float = _places[name].distance_to(_player.global_position)
		if d < best:
			near = name
			best = d
	var ctx := _scene_context() + "\nEl jugador está cerca de: %s." % near
	if not StationBuilder.is_space(_def):
		ctx += " " + WorldClock.describe()
	return ctx


## Lo que un PNJ decide en una conversación se ve en el mundo: te sigue o va a un sitio.
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
			var t := str(action.get("target", "")).to_lower()
			var dest := Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
			for name in _places:
				if name.to_lower().contains(t) or t.contains(name.to_lower()):
					dest = _places[name]
			if not NPCMemory.is_following(npc_id):
				npc.walk_to(dest)


func _era_label(era: String) -> String:
	return {
		"prehistory": "prehistoria", "ancient": "antigüedad", "medieval": "época medieval",
		"industrial": "era industrial", "present": "presente", "near_future": "futuro cercano",
		"far_future": "futuro lejano", "deep_future": "futuro profundo",
	}.get(era, era)


## RNG determinista por lugar: mismo lugar → mismas balizas, PNJs y decoración al volver.
func _rng(salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_def.get("seed", 1)) * 31 + salt
	return rng

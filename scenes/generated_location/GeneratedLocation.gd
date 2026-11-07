extends LocationScene
## Un lugar que la IA creó para ESTE jugador. Se reconstruye desde su definición en WorldDB
## (tipo, bioma, época, semilla, gravedad, cielo, puntos de interés, PNJs, objetos y misión):
## es el mismo lugar cada vez que vuelves.

const SPAWN := Vector3(0, 3, 0)
const POI_MIN := 18.0

var _def: Dictionary = {}
var _location_id := ""
var _height_at: Callable
var _limit := 70.0
var _env: Environment
var _fx: EnvironmentFX
var _placed: Array = []  # posiciones ocupadas (balizas, objetos) para que la decoración no las tape
var _extras := {"features": [], "buildings": [], "removed": []}  # lo que decora PropsBuilder


func _ready() -> void:
	if not WorldDB.is_loaded() and not WorldDB.load_world(WorldDB.last_world_id()):
		WorldDB.create_world("Mundo sin nombre")  # escena abierta directamente desde el editor
	_location_id = GameState.current_location()
	_def = WorldDB.get_entity("location", _location_id)
	if _def.is_empty():
		_def = ContentGenerator.load_fallback("location")  # vista previa sin partida (editor / smoke test)
		_location_id = ""

	_extras.removed = Actions.removed_here(GameState.current_location())
	_interiors = InteriorManager.new()
	add_child(_interiors)
	var space := StationBuilder.is_space(_def)
	if _def.get("biome", "") == "ocean" and not space:
		_water_level = -0.45
	var ground := StationBuilder.build(_def, _rng(0)) if space else TerrainBuilder.build(_def)
	_height_at = ground.height_at
	_limit = ground.get("limit", TerrainBuilder.SIZE / 2.0 - 4.0)
	add_child(ground.node)
	if ground.node is ChunkTerrain:
		(ground.node as ChunkTerrain).build_now(Vector3.ZERO)  # suelo bajo tus pies desde el primer frame
	_build_environment(space)
	_build_points_of_interest()
	_spawn_pickups()
	if not space:
		PropsBuilder.build(self, _def, _height_at, _rng(4), _placed, _extras)
		_features = _extras.features
		_add_doors()
		_planet_finds()
	elif _def.get("kind", "") == "anomaly_zone" or _def.get("finale", false):
		PropsBuilder._floating_rocks(self, _rng(4), "void")

	_player = Player.new()
	_player.gravity_scale = float(_def.get("gravity", 1.0))
	_player.position = SPAWN + Vector3(0, _height_at.call(0.0, 0.0), 0)
	_player.water_level = _water_level
	add_child(_player)
	_interiors.player = _player

	_spawn_npcs()
	_ui = GameplayUI.new()
	_ui.player = _player
	_ui.nearby_npcs = func(): return _npcs.keys()
	add_child(_ui)
	_show_place()
	_interiors.entered.connect(func(_k, _id): _bring_followers())
	_interiors.exited.connect(func(_k, _id): _bring_followers())
	for id in _npcs:  # quien aceptó acompañarte sigue contigo
		if NPCMemory.is_following(id):
			_npcs[id].follow(_player)
	_dialogue = DialoguePanel.new()
	_dialogue.scene_context = _scene_context()
	add_child(_dialogue)
	_setup_common()
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
	if _interiors.is_inside():
		return
	if p.y < -30.0:  # (no debería pasar: el terreno no tiene fin) vuelves a donde pisabas firme
		var safe := _player.last_safe_position()
		_player.position = safe + Vector3(0, 0.5, 0) if safe != Vector3.INF and safe.y > -20.0 else SPAWN + Vector3(0, _height_at.call(0.0, 0.0), 0)
		_player.velocity = Vector3.ZERO
	elif absf(p.x) > _limit or absf(p.z) > _limit:  # borde de una estación espacial
		_player.position.x = clampf(p.x, -_limit, _limit)
		_player.position.z = clampf(p.z, -_limit, _limit)
	_process_common()


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
	if not space and str(_def.get("kind", "")) == "planet_surface":
		# Otro planeta: en su cielo se ven sus lunas (o un segundo sol), de día y de noche
		var seed := hash(str(_def.get("planet", _def.get("name", ""))))
		var n := seed % 3
		for i in n:
			_fx.add_sky_body(Color.from_hsv(fposmod(seed * 0.13 + i * 0.37, 1.0), 0.25, 0.95), 18.0 + (seed >> (i * 4)) % 30, 20.0 + i * 25.0, float(seed % 360) + i * 110.0)
	if space:
		pass
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


## Cada punto de interés es algo de verdad según lo que es (una antena, unos restos, un
## campamento, una roca…), con un letrero pequeño que se lee de cerca. Llegar a él cuenta para las
## misiones; el último es el punto de recarga del Ancla (una terminal).
func _beacon(pos: Vector3, label: String, _color: Color, poi_index: int) -> void:
	var root := Node3D.new()
	root.name = "PuntoDeInteres_%d" % (poi_index + 1)
	add_child(root)
	root.global_position = pos
	root.rotation.y = float(hash(label) % 628) / 100.0
	var low := label.to_lower()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label)
	var kind := "cairn"
	if poi_index < 0:
		kind = "terminal"
	elif ["baliza", "antena", "señal", "senal", "transmis", "radio", "faro", "emisor"].any(func(w): return low.contains(w)):
		kind = "antenna"
	elif ["restos", "naufrag", "nave", "chatarra", "pecio", "estrell", "accidente", "expedición", "expedicion"].any(func(w): return low.contains(w)):
		kind = "wreck"
	elif ["cráter", "crater", "impacto", "pozo", "fuente", "charco", "lago", "manantial", "géiser", "geiser"].any(func(w): return low.contains(w)):
		kind = "crater"
	elif ["campamento", "refugio", "tienda", "hoguera", "puesto"].any(func(w): return low.contains(w)):
		kind = "camp"
	elif ["ruina", "templo", "columna", "estatua", "altar", "torre"].any(func(w): return low.contains(w)):
		kind = "ruins"
	elif ["roca", "piedra", "monolito", "obelisco", "cristal", "megalito"].any(func(w): return low.contains(w)):
		kind = "monolith"
	var stone := Color(TerrainBuilder.palette(_def.get("biome", "barren")).high).darkened(0.35)
	match kind:
		"terminal":  # una consola con pantalla: aquí se recarga el Ancla
			PropsBuilder._box(root, Vector3(0, 0.55, 0), Vector3(0.9, 1.1, 0.6), Color("#3a3f46"), true)
			var screen := PropsBuilder._box(root, Vector3(0, 1.25, 0.05), Vector3(0.8, 0.5, 0.06), Color("#0b2a3a"), false)
			screen.rotation_degrees.x = -25.0
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color("#0b2a3a")
			sm.emission_enabled = true
			sm.emission = Color("#4fc3f7")
			sm.emission_energy_multiplier = 0.9
			(screen as MeshInstance3D).material_override = sm
			var l := OmniLight3D.new()
			l.light_color = Color("#4fc3f7")
			l.light_energy = 0.6
			l.omni_range = 3.0
			l.position = Vector3(0, 1.4, 0.5)
			root.add_child(l)
		"antenna":  # un mástil con una luz roja pequeña que parpadea
			_cylinder_at(root, Vector3(0, 2.5, 0), 0.06, 5.0, Color("#9aa3ad"))
			for k in 3:
				var a := k * TAU / 3.0
				var guy := _cylinder_at(root, Vector3(cos(a) * 0.9, 1.2, sin(a) * 0.9), 0.015, 2.8, Color("#6b7078"))
				guy.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
			var tip := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.09
			sp.height = 0.18
			tip.mesh = sp
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color("#ff3a2a")
			tm.emission_enabled = true
			tm.emission = Color("#ff3a2a")
			tip.material_override = tm
			tip.position = Vector3(0, 5.05, 0)
			root.add_child(tip)
			var tw := create_tween().set_loops()
			tw.tween_property(tm, "emission_energy_multiplier", 1.2, 0.15)
			tw.tween_property(tm, "emission_energy_multiplier", 0.0, 1.2)
			_static_cylinder(root, 0.15, 5.0)
		"wreck":  # restos de una nave medio enterrada
			var ship := AssetLibrary.instance(Ship.MODEL_DIR, ["Striker", "Bob", "Dispatcher"][rng.randi() % 3])
			if ship:
				var placed := AssetLibrary.place(root, ship, Vector3(0, -0.6, 0), 2.6, rng.randf() * TAU, true)
				placed.rotation_degrees.z = rng.randf_range(12.0, 28.0)
				placed.rotation_degrees.x = rng.randf_range(-10.0, 10.0)
			for k in 6:
				var chunk := PropsBuilder._box(root, Vector3(rng.randf_range(-5, 5), 0.1, rng.randf_range(-5, 5)), Vector3(rng.randf_range(0.3, 1.0), 0.12, rng.randf_range(0.3, 0.8)), Color("#5c6168"), false)
				chunk.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
		"crater":  # un hoyo oscuro rodeado de piedras
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 3.2
			cm.bottom_radius = 2.4
			cm.height = 0.05
			disc.mesh = cm
			var dm := StandardMaterial3D.new()
			dm.albedo_color = stone.darkened(0.5)
			disc.material_override = dm
			disc.position.y = 0.03
			root.add_child(disc)
			for k in 10:
				var a := k * TAU / 10.0 + rng.randf() * 0.3
				var rock := AssetLibrary.nature("barren", 2, rng)
				if rock:
					AssetLibrary.place(root, rock, Vector3(cos(a), 0, sin(a)) * 3.6, rng.randf_range(0.4, 1.1), rng.randf() * TAU, true)
		"camp":
			var tent := AssetLibrary.instance("survival_pack", "Tent")
			if tent:
				AssetLibrary.place(root, tent, Vector3(-1.5, 0, 0), 2.0, 0.4, true)
			var fire := AssetLibrary.instance("survival_pack", "Bonfire")
			if fire:
				AssetLibrary.place(root, fire, Vector3(1.6, 0, 0.5), 0.5, 0.0, false)
		"ruins":  # columnas rotas
			for k in 5:
				var a := k * TAU / 5.0
				var h := rng.randf_range(0.8, 3.4)
				_cylinder_at(root, Vector3(cos(a) * 2.6, h / 2.0, sin(a) * 2.6), 0.32, h, stone)
				_static_cylinder(root, 0.35, h, Vector3(cos(a) * 2.6, 0, sin(a) * 2.6))
		"monolith":
			PropsBuilder._box(root, Vector3(0, 1.9, 0), Vector3(1.0, 3.8, 0.45), stone.darkened(0.3), true)
		_:  # un mojón de piedras apiladas
			for k in 4:
				PropsBuilder._box(root, Vector3(rng.randf_range(-0.05, 0.05), 0.2 + k * 0.33, 0), Vector3(0.8 - k * 0.15, 0.32, 0.7 - k * 0.12), stone.lightened(k * 0.05), k == 0)
	# Letrero de madera a un lado, con el nombre (solo se lee de cerca)
	var post := _cylinder_at(root, Vector3(2.4, 0.6, 2.4), 0.05, 1.2, Color("#6b4a2b"))
	post.rotation.y = 0.0
	var sign := PropsBuilder._box(root, Vector3(2.4, 1.25, 2.4), Vector3(1.4, 0.4, 0.05), Color("#8a6a44"), false)
	sign.look_at(root.global_position + Vector3(0, 1.25, 0), Vector3.UP)
	var l := Label3D.new()
	l.text = label
	l.font_size = 40
	l.outline_size = 6
	l.pixel_size = 0.004
	l.width = 320.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color("#fff6d8")
	l.position = Vector3(2.4, 1.85, 2.4)
	l.visibility_range_end = 14.0
	l.visibility_range_end_margin = 2.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(l)
	Decor.landmark(self, pos, {"terminal": "una terminal (punto de recarga del Ancla)", "antenna": "una antena con una luz roja: %s" % label,
		"wreck": "restos de una nave: %s" % label, "crater": "un cráter: %s" % label, "camp": "un campamento: %s" % label,
		"ruins": "unas ruinas: %s" % label, "monolith": "una piedra alta: %s" % label}.get(kind, "un mojón de piedras: %s" % label), "poi")
	var area := Area3D.new()
	Layers.zone(area)
	var zone := CollisionShape3D.new()
	zone.shape = SphereShape3D.new()
	zone.shape.radius = 4.5
	area.add_child(zone)
	area.position = pos + Vector3(0, 1, 0)
	area.body_entered.connect(_on_beacon_entered.bind(poi_index))
	add_child(area)


func _cylinder_at(parent: Node3D, at: Vector3, r: float, h: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.1
	cm.height = h
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi


func _static_cylinder(parent: Node3D, r: float, h: float, at: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = at + Vector3(0, h / 2.0, 0)
	body.add_child(cs)
	parent.add_child(body)


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


## Cosas que se encuentran por el suelo según el planeta (vuelven a salir al día siguiente).
func _planet_finds() -> void:
	var biome := str(_def.get("biome", "barren"))
	var finds: Array = {
		"crystal": ["Cristal resonante", "Un cristal que vibra un poco al tocarlo.", "none"],
		"volcanic": ["Obsidiana", "Vidrio volcánico, negro y afilado.", "none"],
		"desert": ["Cuarzo del desierto", "Un trozo de cuarzo pulido por el viento.", "none"],
		"ice": ["Hielo antiguo", "Hielo limpísimo de hace miles de años. Se puede derretir y beber.", "hydrate"],
		"temperate": ["Fruta extraña", "Una fruta de este planeta. Huele bien.", "nourish"],
		"jungle": ["Fruta extraña", "Una fruta de este planeta. Huele dulce.", "nourish"],
		"ocean": ["Concha iridiscente", "Una concha que cambia de color con la luz.", "none"],
	}.get(biome, ["Mineral metálico", "Un mineral pesado y brillante. Alguien pagaría por él.", "none"])
	var rng := _rng(9)
	for i in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 70.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _height_at.call(p.x, p.z)
		if _water_level > -INF and p.y < _water_level + 0.2:
			continue
		Countryside.make_forage(self, self, p, "Recoger: %s" % str(finds[0]).to_lower(), str(finds[0]), str(finds[1]), str(finds[2]), "")


## Nombre del lugar, época y gravedad arriba a la izquierda (HUD).
func _show_place() -> void:
	_ui.hud.set_place("%s · gravedad %.1f g" % [_era_label(_def.get("era", "")), float(_def.get("gravity", 1.0))])
	_ui.hud.set_objective(_def.get("name", "?"))


# --- Interacción ----------------------------------------------------------------------

func navigation_area() -> AABB:
	return AABB(Vector3(-_limit, -40, -_limit), Vector3(_limit * 2.0, 140, _limit * 2.0))


func ground_at(x: float, z: float) -> float:
	return _height_at.call(x, z)


func scene_context() -> String:
	return _scene_context()


func _pick_up(target: Pickup) -> void:
	Inventory.add(target.item_id)
	if not _location_id.is_empty():
		var picked: Array = _def.get("picked", []).duplicate()
		picked.append(target.item_id)
		_def["picked"] = picked
		WorldDB.update_entity("location", _location_id, {"picked": picked})
	var item := WorldDB.get_entity("item", target.item_id)
	_ui.toast("Recogido: %s  (I para ver el inventario)" % item.get("name", "?"))
	Sfx.chime(self)
	target.queue_free()
	_ui.refresh_tracker()


func _after_dialogue(npc_id: String) -> void:
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


## Quien te acompaña entra y sale contigo de los edificios.
func _bring_followers() -> void:
	for id in _npcs:
		if NPCMemory.is_following(id):
			_npcs[id].global_position = _player.global_position + Vector3(1.5, 0.3, 1.0)


## Cada edificio de un asentamiento tiene puerta; el interior depende de la época.
func _add_doors() -> void:
	var era: String = _def.get("era", "present")
	var futuristic := era in ["near_future", "far_future", "deep_future"]
	var i := 0
	var count: int = _extras.buildings.filter(func(b): return is_instance_valid(b)).size()
	# Los negocios propios de su época (una taberna y un mercado en la Antigüedad…), si el
	# asentamiento es lo bastante grande: el resto son casas.
	var businesses: Array = Shops.for_era(era).slice(0, clampi(count - 2, 0, 3))
	for b in _extras.buildings:
		if not is_instance_valid(b):
			continue
		var size: Vector3 = b.get_meta("size", Vector3(6, 4, 6))
		var front: Vector3 = b.global_transform.basis.z.normalized()
		var pos: Vector3 = b.position + front * (size.z / 2.0 + 0.6)
		pos.y = _height_at.call(pos.x, pos.z)
		i += 1
		if not businesses.is_empty():
			var kind: String = businesses.pop_front()
			var label := Shops.label(kind, era)
			_interiors.add_door("edificio_%d" % i, pos, b.rotation.y, kind, int(_def.get("seed", 1)) * 100 + i, label)
			_interiors.set_building("edificio_%d" % i, b.global_position, size, b.rotation.y)
			_interiors.set_door_option("edificio_%d" % i, "floors", 2 if size.y > 7.0 else 1)
			var sign := Label3D.new()
			sign.text = label.split(" ", false, 1)[-1].capitalize()
			sign.font_size = 56
			sign.outline_size = 10
			sign.pixel_size = 0.008
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.position = pos + Vector3(0, minf(size.y * 0.6, 4.0), 0)
			Decor.fade_label(sign)
			add_child(sign)
			continue
		_interiors.add_door("edificio_%d" % i, pos, b.rotation.y, "scifi" if futuristic else "house", int(_def.get("seed", 1)) * 100 + i,
			"un edificio" if futuristic else "una casa")
		_interiors.set_building("edificio_%d" % i, b.global_position, size, b.rotation.y)
		_interiors.set_door_option("edificio_%d" % i, "floors", 2 if size.y > 7.0 else 1)


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

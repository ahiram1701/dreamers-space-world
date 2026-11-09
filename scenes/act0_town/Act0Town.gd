extends LocationScene
## Acto 0 — Bahía de las Horas. Igual para todos los jugadores; lo que cambia es
## cómo hablas con la gente, y eso ya empieza a moldear tu mundo (NPCMemory, PlayerProfile).
## Se construye en código con modelos CC0 (AssetLibrary), terreno y agua procedurales.

const NPCS_PATH := "res://data/act0/npcs.json"
const TOWN_SEED := 3330333
const SPAWN := Vector3(-6, 0.5, -4)
const LIGHTHOUSE_POS := Vector3(44, 0, -30)
const AWAKE_FROM := 3.25  # 3:15 a. m.
const AWAKE_TO := 3.75  # 3:45 a. m.
const TRACKS_Z := 37.0
const WATER_Y := -0.45
## Sitios con nombre: a dónde pueden ir los vecinos (rutinas, "acompáñame al muelle") y qué
## tiene cerca el jugador cuando hace algo (F).
const PLACES := {
	"faro": Vector3(40, 0, -25), "muelle": Vector3(36, 0, 6), "cafetería": Vector3(20, 0, 9),
	"estación": Vector3(-36, 0, 25), "vías del tren": Vector3(-20, 0, 35), "tu casa": Vector3(-11, 0, -4),
	"calle principal": Vector3(-5, 0, 10), "playa": Vector3(30, 0, -10), "plaza": Vector3(-5, 0, -20),
}
## Sitios que están dentro de un edificio: los vecinos que van ahí están en su interior.
const INDOOR := {"cafetería": "cafe", "estación": "station", "faro": "lighthouse", "tu casa": "home"}
const SCENE_CONTEXT := """Acto 0. Bahía de las Horas: pueblo costero tranquilo en el presente.
El jugador es un/a vecino/a corriente del pueblo con una vida normal. Aún no sabe nada de multiversos.
Últimamente pasan cosas pequeñas y raras con explicación física aún desconocida: un pulso electromagnético a las 3:33 que enciende el faro desconectado y para relojes, vecinos con flashes de recuerdos que no son suyos, una transmisión de radio estructurada."""

var _beacon: OmniLight3D
var _beacon_glass: StandardMaterial3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _awakening: AwakeningSequence
var _hour_hint := false
var _was_awake_hour := false
var _fx: EnvironmentFX
var _noise: FastNoiseLite
var _boats: Array = []
var _schedules: Dictionary = {}  # npc_id -> [[hora, sitio], ...]
var _activities: Dictionary = {}  # npc_id -> {sitio: [qué hace, gesto]}
var _homes: Dictionary = {}       # npc_id -> id de la puerta de su casa
var _removed: Array = []         # los que ya talaste (no vuelven)
var _house_count := 0
var _going_home := {}
var _windows := {}   # id de puerta -> material de sus ventanas
var _shops_to_open := [["clothes", "la tienda de ropa", "Ropa"], ["salon", "la peluquería", "Peluquería"]]  # en casas de la calle
var _locals_to_open := ["grocery", "restaurant", "pharmacy", "hardware"]  # abarrotes, fonda, farmacia, ferretería   # npc_id -> true mientras camina a su casa para dormir


func _ready() -> void:
	if not WorldDB.is_loaded() and not WorldDB.load_world(WorldDB.last_world_id()):
		WorldDB.create_world("Mundo sin nombre")  # escena abierta directamente desde el editor
	_seed_base_npcs()
	_places = PLACES.duplicate()
	_water_level = WATER_Y
	_removed = Actions.removed_here(GameState.current_location())
	_interiors = InteriorManager.new()
	add_child(_interiors)

	_build_environment()
	_build_terrain()
	_build_town()
	_build_landmarks()
	var countryside := Countryside.new()
	add_child(countryside)
	countryside.build(self, _ground_height, _places)

	_player = Player.new()
	_player.position = SPAWN
	_player.water_level = WATER_Y
	add_child(_player)
	_interiors.player = _player
	_interiors.entered.connect(func(_k, _id): _follow_schedules(true))
	_interiors.exited.connect(func(_k, _id): _follow_schedules(true))

	for entry in _load_npc_entries():
		_schedules[entry.id] = entry.get("schedule", [])
		_activities[entry.id] = entry.get("activities", {})
		_homes[entry.id] = entry.get("home", "")
		var npc := TownNPC.new()
		add_child(npc)
		npc.position = Vector3(entry.position[0], _ground_height(entry.position[0], entry.position[2]) + 0.1, entry.position[2])
		npc.setup(WorldDB.get_entity("npc", entry.id))
		npc.face(SPAWN)
		_npcs[entry.id] = npc

	_dialogue = DialoguePanel.new()
	_dialogue.scene_context = SCENE_CONTEXT
	add_child(_dialogue)
	_ui = GameplayUI.new()
	_ui.player = _player
	_ui.nearby_npcs = func(): return _npcs.keys()
	add_child(_ui)
	_launch_pad()
	_setup_common()
	_place_vehicles()
	var traffic := Traffic.new()
	traffic.scene = self
	add_child(traffic)
	WorldClock.hour_changed.connect(func(_h): _follow_schedules(false); _shop_hours(); _update_windows())
	_interiors.entered.connect(func(_k, _id): _update_windows())
	_interiors.exited.connect(func(_k, _id): _update_windows())
	_follow_schedules(true)
	_shop_hours()
	_update_windows.call_deferred()
	if GameState.is_awakened() and WorldDB.get_state("homecoming", false) and GameState.ending().is_empty():
		_homecoming.call_deferred()
	var waves := AmbientAudio.new()
	waves.kind = AmbientAudio.Kind.WAVES
	add_child(waves)
	_update_objective()


func _process(_delta: float) -> void:
	if _player.position.y < -30.0 and not _interiors.is_inside():  # (no debería: el mundo no tiene borde)
		var safe := _player.last_safe_position()
		_player.position = safe + Vector3(0, 0.5, 0) if safe != Vector3.INF and safe.y > -20.0 else SPAWN
		_player.velocity = Vector3.ZERO
	_process_common()
	if _awakening != null:
		_beacon_glass.emission_energy_multiplier = _beacon.light_energy * 0.4
		return  # la secuencia controla el faro
	if not GameState.is_awakened() and Engine.get_process_frames() % 30 == 0 and _progress().get("awakening_ready", false):
		_watch_awakening_hour()
	# Si ya estabas junto al faro cuando llegó la hora, empieza igual
	if not GameState.is_awakened() and not _interiors.is_inside() and Engine.get_process_frames() % 30 == 0 			and Vector2(_player.global_position.x - LIGHTHOUSE_POS.x, _player.global_position.z - LIGHTHOUSE_POS.z).length() < 5.5 			and _progress().get("awakening_ready", false):
		_on_lighthouse_entered(_player)
		return
	# El faro "respira"; cuando el Despertar está cerca, parpadea nervioso.
	_beacon.light_energy = beacon_energy(WorldClock.hour(), Time.get_ticks_msec() / 1000.0, _progress().get("awakening_ready", false))
	_beacon_glass.emission_energy_multiplier = _beacon.light_energy * 0.4


## El faro está desconectado: apagado. Solo a las 3:33 un pulso lo enciende unos segundos, y
## cuando el Despertar está cerca el pulso empieza antes y es más fuerte.
static func beacon_energy(hour: float, t: float, ready: bool) -> float:
	var start := 3.0 + 33.0 / 60.0
	var lead := 18.0 / 60.0 if ready else 0.0  # listo para el Despertar: parpadea desde las 3:15
	if hour < start - lead or hour > start + (12.0 if ready else 2.0) / 60.0:
		return 0.0
	var flick := absf(sin(t * 9.0) * sin(t * 2.3))
	return (6.0 + 6.0 * flick) if ready else (4.0 * flick if flick > 0.3 else 0.0)


# --- Contenido base -------------------------------------------------------------------

## Los 3 vecinos se escriben a mano y entran en el mundo del jugador al empezar.
## A partir de ahí son suyos: sus recuerdos y su relación evolucionan distinto en cada partida.
func _seed_base_npcs() -> void:
	if not WorldDB.get_state("contacts_seeded", false):  # tus vecinos de siempre: tienes su número
		WorldDB.set_state("contacts_seeded", true)
		for entry in _load_npc_entries():
			NPCMemory.set_fields(entry.id, {"phone": true})
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


## La cafetería abre de 7:00 a 22:00 (de noche, la puerta está cerrada).
func _shop_hours() -> void:
	var h := WorldClock.hour()
	var open := h >= 7.0 and h < 22.0
	if not NPCMemory.is_locked_in("npc_teo"):
		_interiors.set_locked("cafe", "" if open else "La cafetería está cerrada. Abre a las 7:00 a. m.")
	var shop_open := h >= 9.0 and h < 20.0
	for id in _interiors.doors():
		var kind: String = _interiors.doors()[id].kind
		if kind in ["clothes", "salon"] or Shops.KINDS.has(kind):
			var label := _interiors.door_label(id)
			label = label.left(1).to_upper() + label.substr(1)
			var is_open := Shops.is_open(kind, h) if Shops.is_shop(kind) else shop_open
			var hours := Shops.hours_text(kind) if Shops.is_shop(kind) else WorldClock.span(9, 20)
			_interiors.set_locked(id, "" if is_open else "%s: cerrado. Abre %s." % [label, hours])


## De quién es cada casa (para reaccionar si entras sin permiso).
func owner_of_door(door: String) -> String:
	for id in _homes:
		var home: String = _homes[id]
		if home == door or (not home.is_empty() and _interiors.door_of_kind(home) == door):
			return id
	return super(door)  # la familia que vive en esa casa


func home_door_of(npc_id: String) -> String:
	var home: String = _homes.get(npc_id, "")
	if home.is_empty():
		return super(npc_id)
	return home if _interiors.doors().has(home) else _interiors.door_of_kind(home)


func navigation_area() -> AABB:
	return AABB(Vector3(-100, -6, -90), Vector3(150, 40, 290))  # el pueblo, la playa, el muelle y la cabaña del pescador


func ground_at(x: float, z: float) -> float:
	return _ground_height(x, z)


func scene_context() -> String:
	return SCENE_CONTEXT


## Si un vecino se mete "dentro" sin decir dónde, va a su casa (o, si no tiene, a su trabajo).
func _npc_home_door(npc_id: String) -> String:
	var home := home_door_of(npc_id)
	if not home.is_empty():
		return home
	for slot in _schedules.get(npc_id, []):
		var kind: String = INDOOR.get(slot[1], "")
		if not kind.is_empty() and kind != "home":
			return _interiors.door_of_kind(kind)
	return super(npc_id)


func _after_dialogue(npc_id: String) -> void:
	var p := _progress()
	if not (npc_id in p.talked):
		p.talked.append(npc_id)
	p.awakening_ready = _base_talked(p) >= _schedules.size()
	WorldDB.set_state("act0", p)
	_update_objective()


func _update_objective() -> void:
	var p := _progress()
	if GameState.is_awakened():
		_set_objective("Bahía de las Horas · Pulsa T para usar el Ancla")
	elif p.awakening_ready:
		if is_awakening_hour(WorldClock.hour()):
			_set_objective("Son las %s: ve a la puerta del faro, ya." % WorldClock.text())
		else:
			_set_objective("Ve a la puerta del faro a las 3:33 a. m. (puedes dormir o esperar hasta esa hora)")
	else:
		var left := PackedStringArray()
		for id in _schedules:
			if not (id in p.talked):
				left.append(str(WorldDB.get_entity("npc", id).get("name", "?")).split(" ")[0])
		_set_objective("Habla con Marina, Teo y Samir (%d/%d) · falta: %s" % [_base_talked(p), _schedules.size(), ", ".join(left)])


## Cuántos de tus vecinos de siempre (los del Acto 0) te conocen ya.
func _base_talked(p: Dictionary) -> int:
	return p.talked.filter(func(id): return _schedules.has(id)).size()


## La vuelta a casa: la brecha te deja delante del faro y se juega el final.
func _homecoming() -> void:
	await get_tree().create_timer(0.5).timeout
	var door: Vector3 = _interiors.door_position("faro")
	var out := (door - LIGHTHOUSE_POS)
	out.y = 0.0
	out = out.normalized() if out.length() > 0.1 else Vector3.BACK
	var spot := door + out * 5.0
	spot.y = maxf(door.y, 0.0)
	_player.global_position = spot + Vector3(0, 0.3, 0)
	var finale := FinaleSequence.new()
	finale.player = _player
	finale.center = spot
	finale.tower_position = LIGHTHOUSE_POS
	finale.town_position = SPAWN
	finale.npcs = _npcs
	add_child(finale)
	finale.play()


## El Despertar solo ocurre de verdad a las 3:33 de la madrugada (con un margen para llegar).
static func is_awakening_hour(h: float) -> bool:
	return h >= AWAKE_FROM and h <= AWAKE_TO


## Lleva el objetivo al día con la hora y, si te pilla dentro del faro, te saca a la puerta.
func _watch_awakening_hour() -> void:
	var now := is_awakening_hour(WorldClock.hour())
	if now != _was_awake_hour:
		_was_awake_hour = now
		_update_objective()
		if now and _ui:
			_ui.toast("Son las %s. El faro parpadea solo, sin corriente." % WorldClock.text())
	var near := Vector2(_player.global_position.x - LIGHTHOUSE_POS.x, _player.global_position.z - LIGHTHOUSE_POS.z).length()
	if near > 14.0:
		_hour_hint = false  # al volver otra vez se avisa de nuevo
	if now and _interiors.is_inside() and _interiors.current_door() == "faro" and _awakening == null:
		_interiors.leave()


func _on_lighthouse_entered(body: Node3D) -> void:
	if not (body is Player) or _awakening != null or GameState.is_awakened():
		return
	if not _progress().get("awakening_ready", false):
		return
	if not is_awakening_hour(WorldClock.hour()):
		if not _hour_hint:
			_hour_hint = true
			if _ui:
				_ui.toast("El faro está apagado y en silencio. Marina dijo que el pulso llega a las 3:33 de la madrugada; ahora son las %s. Vuelve a esa hora." % WorldClock.text())
		return
	_set_objective("3:33 a. m.")
	_fx.frozen = true  # la secuencia controla el cielo
	_awakening = AwakeningSequence.new()
	_awakening.player = _player
	_awakening.sun = _sun
	_awakening.env = _env
	_awakening.sky_mat = _sky_mat
	_awakening.beacon = _beacon
	var door: Vector3 = _interiors.door_position("faro")
	_awakening.breach_position = door + (door - LIGHTHOUSE_POS).normalized() * 1.5 + Vector3(0, 1.4, 0) if door != Vector3.ZERO 		else LIGHTHOUSE_POS + Vector3(-3.5, 1.6, 3.5)  # junto a la puerta del faro
	_awakening.tower_position = LIGHTHOUSE_POS
	_awakening.town_position = SPAWN
	_awakening.npcs = _npcs
	add_child(_awakening)
	_awakening.play()


# --- Vida en el pueblo ---------------------------------------------------------------

## Rutinas: cada vecino va a su sitio según la hora (salvo si te acompaña o está hablando).
func _follow_schedules(teleport: bool) -> void:
	for id in _npcs.keys():
		_follow_one(id, teleport)


func _follow_one(id: String, teleport: bool) -> void:
	var h := WorldClock.hour()
	var npc: TownNPC = _npcs[id]
	if npc_busy(id):
		return  # se fue o se encerró: no sigue su rutina hasta que salga
	if _going_home.has(id):
		if not teleport:
			return  # sigue caminando a casa
		_going_home.erase(id)
		npc.stop()
	if NPCMemory.is_following(id):
		if teleport:
			npc.global_position = _player.global_position + Vector3(1.5, 0.3, 1.0)
		npc.follow(_player)
		return
	var plan: Array = _schedules.get(id, [])
	if plan.is_empty() or npc.talking:
		return
	var place: String = plan[plan.size() - 1][1]  # antes de la primera hora: donde acabó ayer
	for slot in plan:
		if h >= float(slot[0]):
			place = slot[1]
	var act: Array = _activities.get(id, {}).get(place, ["", ""])
	npc.set_activity(act[0], act[1])
	var night := h >= 23.0 or h < 7.0
	# Dentro de un edificio: su casa ("casa") o un sitio cubierto (la cafetería, la estación…)
	var door_id := ""
	if place == "casa":
		door_id = _homes.get(id, "")
	elif INDOOR.has(place):
		door_id = _interiors.door_of_kind(INDOOR[place])
	var target := place_position(place) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)) if place != "casa" else Vector3.INF
	if not door_id.is_empty():
		if _interiors.current_door() == door_id:  # estás dentro: está ahí, en su sitio
			npc.set_present(true)
			var home := door_id == home_door_of(id)
			var spot := _interiors.activity_spot("bed", 0) if night and home else {}
			if not spot.is_empty():  # de noche, en su casa: dormido
				npc.settle(spot.pos, spot.face, "sleep", "durmiendo")
			elif npc.activity != act[0] or not npc.is_settled():
				npc.stop()
				if _interiors.current_kind() == "cafe" and id != "npc_teo":  # de cliente: en una mesa
					var seat := _interiors.activity_spot("table", 2 + _npcs.keys().find(id))
					if not seat.is_empty():
						npc.settle(seat.pos, seat.face, "sit_eat" if act[1] in ["drink", "eat"] else "sit", act[0])
						return
				var p := _interiors.npc_spot(0 if _interiors.current_kind() == "cafe" else _npcs.keys().find(id))  # Teo, tras la barra
				npc.settle(p + Vector3(0, 0.1, 0), p + Vector3(0, 0, 1), act[1], act[0])
			return
		if night:  # de noche se va a dormir: camina hasta su puerta y entra
			if npc.is_present() and not teleport and not InteriorManager.is_interior_pos(npc.global_position):
				var door_at := _interiors.door_position(door_id)
				_going_home[id] = true
				npc_go(id, door_at, func():
					_going_home.erase(id)
					Sfx.at(self, "door", door_at + Vector3(0, 1, 0))
					if _interiors.current_door() == door_id:  # llegas tú antes: entra y se acuesta
						npc.global_position = _interiors.entry_position() + Vector3(0, 0.3, 0)
						_follow_one(id, true)
					else:
						npc.set_present(false))
			else:
				npc.set_present(false)
			return
		npc.unsettle()
		npc.set_present(true)
		var door := _interiors.door_position(door_id)
		if door != Vector3.INF:  # de día y estás fuera: lo ves junto a la puerta
			target = door + Vector3(randf_range(-2, 2), 0, randf_range(1.5, 3))
			target.y = _ground_height(target.x, target.z)
	elif not npc.is_present():
		npc.set_present(true)
	if target == Vector3.INF:
		return
	# Llueve y su sitio está a la intemperie: se resguarda bajo el alero de la puerta más cercana
	if door_id.is_empty() and Weather.is_raining():
		var best := Vector3.INF
		for d in _interiors.doors():
			var p: Vector3 = _interiors.doors()[d].pos
			if best == Vector3.INF or p.distance_to(npc.global_position) < best.distance_to(npc.global_position):
				best = p
		if best != Vector3.INF:
			target = best + Vector3(randf_range(-1.2, 1.2), 0, randf_range(0.6, 1.4))
			target.y = _ground_height(target.x, target.z)
			npc.set_activity("resguardándose de la lluvia", "cross_arms")
			if not teleport and npc.global_position.distance_to(target) > 2.0:
				npc.walk_to(target, true)  # deprisa, que se moja
				return
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
## El terreno hecho a mano (el pueblo y su costa). Fuera de él sigue el mundo sin fin (ChunkTerrain).
const CORE := Rect2(-110, -130, 300, 260)
var _wild: FastNoiseLite


func _ground_height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	return h if CORE.has_point(Vector2(x, z)) else Countryside.shape(x, z, h)


## El terreno sin los retoques del campo (allanar la granja, cavar el lago).
func _raw_height(x: float, z: float) -> float:
	var h := _town_height(x, z)
	var out := Vector2(maxf(maxf(CORE.position.x - x, x - CORE.end.x), 0.0), maxf(maxf(CORE.position.y - z, z - CORE.end.y), 0.0)).length()
	if out <= 0.0:
		return h
	return lerpf(h, _wild_height(x, z), smoothstep(0.0, 60.0, out))


## Más allá del pueblo: colinas y, lejos, montañas tierra adentro (oeste); al este, mar abierto
## con alguna isla.
func _wild_height(x: float, z: float) -> float:
	if _wild == null:
		_wild = FastNoiseLite.new()
		_wild.seed = TOWN_SEED + 99
		_wild.frequency = 0.003
		_wild.fractal_octaves = 4
	var m := _wild.get_noise_2d(x, z)
	var d := Vector2(x - 40.0, z).length()
	var land := 0.8 + (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 3.0 + maxf(m, -0.2) * 40.0 * smoothstep(180.0, 700.0, d)
	var sea := -5.7 + maxf(m - 0.3, 0.0) * 45.0   # islas donde el ruido sube
	return lerpf(land, sea, smoothstep(30.0, 110.0, x))


func _town_height(x: float, z: float) -> float:
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
	if x < 24.0 and (x < -45.0 or absf(z) > 66.0):  # el campo: caminos de tierra y flores
		c = Countryside.tint(x, z, h, c)
	if x > 100.0 and h > 1.5:  # islas: verdes por arriba
		c = c.lerp(grass, smoothstep(1.5, 3.5, h))
	if h > 6.0:  # montañas: roca y, arriba, nieve
		c = c.lerp(Color("#7c7466"), smoothstep(6.0, 14.0, h)).lerp(Color("#eef2f4"), smoothstep(22.0, 30.0, h))
	return c


func _build_terrain() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = TOWN_SEED
	_noise.frequency = 0.02
	_wild_height(0.0, 0.0)  # (crea su ruido aquí: los trozos se hacen en hilos)
	Countryside.prepare(_raw_height)
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
	body.add_to_group("terrain")
	add_child(body)
	# Fuera del pueblo, el mundo sigue: terreno por trozos y el mar sin fin (va contigo)
	var world := ChunkTerrain.new()
	world.name = "MundoSinFin"
	world.height_fn = _ground_height
	world.color_fn = _ground_color
	world.material = Decor.ground_material()
	world.core = CORE
	world.water_level = WATER_Y
	world.prop_fn = func(x: float, z: float, h: float, rng: RandomNumberGenerator) -> String:
		if h < 0.4:
			return ""
		var r := rng.randf()
		if x < 20.0:
			if Countryside.keep_clear(x, z):
				return ""
			if Countryside.flowery(x, z):
				return "flower" if r < 0.8 else ("tree" if r < 0.84 else "")
			return "tree" if r < 0.2 else ("plant" if r < 0.3 else ("rock" if r < 0.35 else ""))
		return "tree" if r < 0.1 else ("rock" if r < 0.2 else "")  # islas: palmeras y rocas
	var pine := ChunkTerrain.nature_placer("pine")
	var palm := ChunkTerrain.nature_placer("ocean")
	world.prop_tries = 46
	# Hierba alta por todo el campo (no en los caminos, la arena ni la roca de la montaña)
	world.grass_density = 0.55
	world.grass_accept = func(x: float, z: float, h: float) -> bool:
		return x < 20.0 and h > 0.3 and h < 9.0 and Countryside._path_dist(x, z) > Countryside.PATH_W + 0.4
	world.prop_builder = func(parent: Node3D, kind: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
		if kind in ["grass", "flower"]:  # matas de hierba alta y de flores (sin colisión)
			var names: Array = ["Flowers", "Flowers", "Grass"] if kind == "flower" else ["Grass", "Grass_2", "Grass"]
			var m := AssetLibrary.instance("nature_pack", str(names[rng.randi() % names.size()]))
			if m:
				AssetLibrary.place(parent, m, pos, rng.randf_range(0.35, 0.7), rng.randf() * TAU, false)
			return
		(pine if pos.x < 20.0 else palm).call(parent, kind, pos, rng)
	add_child(world)

	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED + 7
	Decor.grass(self, Vector2(-30, 0), Vector2(56, 70), 4.0, rng, _ground_height, _grass_allowed, Color("#86a347"), Color("#3d5a24"))


func _grass_allowed(x: float, z: float) -> bool:
	if absf(x - PAD.x) < 9.6 and absf(z - PAD.z) < 9.6:
		return false  # la plataforma de despegue es de cemento
	return x < 19.0 and absf(x + 5.0) > 3.6 and not (absf(z - 4.0) < 2.8 and x > -5.0)


func _build_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED  # mismo pueblo para todos: el Acto 0 es el punto de partida común
	var wall_colors := [Color("#f4f1de"), Color("#e9d8b4"), Color("#f2c9a0"), Color("#c9dbe2"), Color("#e7b8a8"), Color("#d8e2c4")]
	for row in range(-4, 5):
		for side in [-1, 1]:
			var empty := rng.randf() < 0.2  # (en este orden: el pueblo sale igual que siempre)
			if row == 0 and side == -1:  # ese hueco es tu casa
				continue
			if empty:  # solar vacío: ahí puede abrirse un sitio nuevo (lo crea la IA)
				if absf(row * 12 - TRACKS_Z) >= 9.0:
					_free_lots.append({"pos": Vector3(-5 + side * 11.0, 0, row * 12), "yaw": PI / 2 if side < 0 else -PI / 2})
				continue
			var pos := Vector3(-5 + side * rng.randf_range(10, 12), 0, row * 12 + rng.randf_range(-2, 2))
			if absf(pos.z - TRACKS_Z) < 9.0:  # encima de las vías no: se deja libre (gastando los mismos números
				rng.randi()                   # del RNG, para que el resto del pueblo salga igual que antes)
				rng.randi()
				_house_count += 1            # y sin mover los números de las demás casas (casa_N)
				continue
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
		var height := rng.randf_range(5.0, 9.0) if kind == 0 else rng.randf_range(0.8, 2.2)
		var yaw := rng.randf() * TAU
		var solid: Variant = "trunk" if kind == 0 else (true if kind == 2 else "bush")
		var fid := "%s_%d_%d" % [["tree", "bush", "rock"][kind], roundi(x), roundi(z)]
		if model and not (fid in _removed):
			_features.append({"id": fid, "kind": ["tree", "bush", "rock"][kind], "pos": Vector3(x, 0, z),
				"node": AssetLibrary.place(self, model, Vector3(x, _ground_height(x, z) - 0.1, z), height, yaw, solid)})
		elif model:
			model.free()
	for i in 40:  # arbustos y flores junto a las casas
		var z := rng.randf_range(-55, 55)
		var x := -5.0 + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(4.2, 6.0)
		var bush := AssetLibrary.nature("temperate", 1, rng)
		var h := rng.randf_range(0.5, 1.1)
		var yaw := rng.randf() * TAU
		var fid := "bush_%d_%d" % [roundi(x), roundi(z)]
		if _near_door(Vector3(x, 0, z), 3.5):  # delante de una puerta no: se sale por ahí
			if bush:
				bush.free()
			continue
		if bush and not (fid in _removed):
			_features.append({"id": fid, "kind": "bush", "pos": Vector3(x, 0, z), "node": AssetLibrary.place(self, bush, Vector3(x, 0, z), h, yaw, "bush")})
		elif bush:
			bush.free()


## ¿Hay una puerta (o el sitio donde se sale de ella) a menos de `dist`?
func _near_door(p: Vector3, dist: float) -> bool:
	var doors: Dictionary = _interiors.doors()
	for id in doors:
		var d: Dictionary = doors[id]
		var out := Vector3(sin(d.yaw), 0, cos(d.yaw))
		for q in [d.pos, d.pos + out * 1.2, d.pos + out * 2.4]:
			if Vector2(p.x - q.x, p.z - q.z).length() < dist:
				return true
	return false


func _build_landmarks() -> void:
	# Faro: torre blanca con franjas, balcón, linterna acristalada y cúpula
	var base_y := _ground_height(LIGHTHOUSE_POS.x, LIGHTHOUSE_POS.z)
	var lp := LIGHTHOUSE_POS + Vector3(0, base_y, 0)
	_cylinder(lp + Vector3(0, 0.6, 0), 3.4, 3.6, 1.2, Color("#8a8478"))
	# Torre más ancha abajo: dentro vive Marina (sala redonda con la escalera de caracol en medio)
	var tower := _cylinder(lp + Vector3(0, 10.2, 0), 2.1, 3.2, 18, Color("#f2efe6"))
	tower.add_child(_stripe(-2.5, 2.83))
	tower.add_child(_stripe(3.5, 2.47))
	_cylinder(lp + Vector3(0, 19.35, 0), 2.4, 2.4, 0.3, Color("#2d3238"))
	var glass := _cylinder(lp + Vector3(0, 20.6, 0), 1.25, 1.25, 2.2, Color("#fff3b0"))
	glass.material_override.emission_enabled = true
	glass.material_override.emission = Color("#ffe9a0")
	glass.material_override.emission_energy_multiplier = 0.0
	glass.material_override.albedo_color = Color("#9a9478")  # cristal apagado
	_beacon_glass = glass.material_override
	var dome := MeshInstance3D.new()
	dome.mesh = SphereMesh.new()
	dome.mesh.radius = 1.45
	dome.mesh.height = 1.6
	dome.mesh.is_hemisphere = true
	dome.material_override = _mat(Color("#b23a3a"))
	dome.position = lp + Vector3(0, 21.7, 0)
	add_child(dome)
	_lighthouse_door(lp)
	_lighthouse_gallery(lp)
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
	Layers.zone(zone)  # (sin esto la zona no «veía» al jugador y a las 3:33 no pasaba nada)
	zone.body_entered.connect(_on_lighthouse_entered)
	add_child(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED + 11
	for i in 14:  # rocas al pie del faro y en la orilla
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 14.0)
		var rock := AssetLibrary.nature("barren", 2, rng)
		var rh := rng.randf_range(0.8, 2.4)
		var ryaw := rng.randf() * TAU
		if rock:
			var rp := Vector3(LIGHTHOUSE_POS.x + cos(a) * r, 0, LIGHTHOUSE_POS.z + sin(a) * r)
			var fid := "rock_%d_%d" % [roundi(rp.x), roundi(rp.z)]
			if fid in _removed:
				rock.free()
			else:
				_features.append({"id": fid, "kind": "rock", "pos": rp,
					"node": AssetLibrary.place(self, rock, rp + Vector3(0, _ground_height(rp.x, rp.z) - 0.3, 0), rh, ryaw, true)})

	# Muelle de madera con postes y barcas
	var dock_y := 0.35
	for i in 14:
		var plank := _box(Vector3(37.5 + i * 2.0, dock_y, 6), Vector3(1.9, 0.18, 3.6), Color("#8b6b4a").darkened(rng.randf() * 0.15))
		plank.material_override.roughness = 0.9
	for i in 8:
		for side in [-1, 1]:
			_cylinder(Vector3(38 + i * 3.6, dock_y - 1.2, 6 + side * 1.9), 0.14, 0.16, 3.0, Color("#5a4632"))
	for b in [["Boat", Vector3(46, 0, 10.5), 4.8, 0.3], ["Lifeboat", Vector3(57, 0, 1.0), 4.0, -0.4], ["BoatWSail", Vector3(70, 0, 16), 6.5, 1.2]]:
		var boat := Boat.new()
		boat.water_level = WATER_Y
		boat.ground_at = _ground_height
		add_child(boat)
		boat.position = b[1]
		boat.rotation.y = b[3]
		boat.setup("ships_pack", b[0], b[2])
		_boats.append(boat)

	# Cafetería del muelle
	_building(Vector3(20, 0, 14), "1Story_Sign_Mat", 3.4, PI, Color("#c97b5a"), "cafe", "la cafetería")
	_label3d(Vector3(20, 7.5, 14), "Cafetería del Muelle")

	# Estación de tren abandonada
	_building(Vector3(-36, 0, 30), "2Story_Wide_Mat", 3.0, PI, Color("#8c8279"), "station", "la estación")
	_label3d(Vector3(-36, 10.5, 30), "Estación (cerrada)")
	for z in [-0.75, 0.75]:
		_box(Vector3(-36, 0.12, 37 + z), Vector3(130, 0.12, 0.12), Color("#7a7a80"), false).material_override.metallic = 0.8
	for i in 64:
		_box(Vector3(-100 + i * 2.0, 0.04, 37), Vector3(0.35, 0.08, 2.3), Color("#4a3a2c"), false)
	_level_crossing(Vector3(-5, 0, TRACKS_Z))


## Paso a nivel donde la calle cruza las vías: tablones entre los rieles, cruces de San Andrés y
## una señal de peligro a cada lado.
func _level_crossing(at: Vector3) -> void:
	_box(at + Vector3(0, 0.13, 0), Vector3(8.0, 0.06, 2.6), Color("#5b4a3a"), false)
	for side in [-1, 1]:
		var post := at + Vector3(side * 4.6, 0, side * 2.6)
		_box(post + Vector3(0, 1.4, 0), Vector3(0.12, 2.8, 0.12), Color("#e8e2d4"))
		for a in [PI / 5, -PI / 5]:  # la cruz (blanca y roja)
			var arm := _box(post + Vector3(0, 2.5, 0.08 * side), Vector3(1.3, 0.2, 0.04), Color("#e8e2d4"), false)
			arm.rotation.z = a
			var stripe := _box(post + Vector3(0, 2.5, 0.1 * side), Vector3(0.3, 0.21, 0.02), Color("#b23a3a"), false)
			stripe.rotation.z = a
		var sign := AssetLibrary.instance("street_pack", "Sign_Triangle")
		if sign:
			AssetLibrary.place(self, sign, at + Vector3(side * 5.6, 0, side * 6.0), 2.4, 0.0 if side < 0 else PI, true)


## Plataforma de despegue al oeste del pueblo (donde está la lanzadera vieja).
const PAD := Vector3(-42, 0, -40)


func _launch_pad() -> void:
	for f in _features:  # despejar la explanada
		if is_instance_valid(f.node) and Vector3(f.pos.x, 0, f.pos.z).distance_to(PAD) < 16.0:
			f.node.queue_free()
	_features = _features.filter(func(f): return Vector3(f.pos.x, 0, f.pos.z).distance_to(PAD) >= 16.0)
	var slab := PropsBuilder._box(self, PAD + Vector3(0, 0.08, 0), Vector3(18, 0.16, 18), Color("#7a7d80"), true)
	slab.name = "LaunchPad"
	for k in 4:  # franjas amarillas
		var a := k * PI / 2.0
		PropsBuilder._box(self, PAD + Vector3(cos(a) * 7.5, 0.17, sin(a) * 7.5), Vector3(1.2 if k % 2 else 14.0, 0.02, 14.0 if k % 2 else 1.2), Color("#d4a017"), false)
	Decor.landmark(self, PAD, "plataforma de despegue (al oeste del pueblo)", "pad")
	_label3d(PAD + Vector3(0, 6, -9), "Plataforma de despegue")
	_upgrade_vehicles()


## Mundos de antes de la v0.7.1: los coches y la lanzadera eran de piezas; ahora llevan modelo.
func _upgrade_vehicles() -> void:
	if WorldDB.get_state("vehicles_v2", false):
		return
	WorldDB.set_state("vehicles_v2", true)
	for e in Creations.all_here():
		if str(e.get("by", "")) != "world" or not str(e.get("model", "")).is_empty():
			continue
		if Vehicle.KIT.has(str(e.get("factory", ""))):
			var f := Vehicle.factory(str(e.factory))
			Creations.update(str(e.id), {"model": f.model, "parts": []})
		elif str(e.get("name", "")) == "Lanzadera vieja":
			var s := Ship.factory()
			Creations.update(str(e.id), {"model": s.get("model", ""), "height": s.get("height", 3.0), "parts": s.parts})


## Si llegas en nave, aterrizas en la plataforma (si está libre).
func arrival_pad() -> Vector3:
	for e in Creations.all_here():
		if Vector3(float(e.pos[0]), 0, float(e.pos[2])).distance_to(PAD) < 9.0:
			return Vector3.INF
	return PAD + Vector3(0, 0.17, 0)


## Vehículos del pueblo (una vez por mundo): los de los vecinos, tu bici, la lancha del muelle y
## una lanzadera vieja en la plataforma. Si te llevas uno que no es tuyo, es robo.
func _place_vehicles() -> void:
	_places["plataforma de despegue"] = PAD
	if WorldDB.get_state("town_vehicles", false):
		return
	WorldDB.set_state("town_vehicles", true)
	# Junto a la acera, entre farolas y fuera de los carriles del tráfico (Traffic.LANES)
	WorldDB.set_state("vehicles_v2", true)
	var cars := [["sedan", Vector3(-7.6, 0, -32), PI, "npc_teo"], ["pickup", Vector3(-31, 0, 18), PI / 2, "npc_samir"],
		["van", Vector3(-2.4, 0, -14), 0.0, "vecino"], ["moto", Vector3(-2.6, 0, 18), 0.0, "vecino"],
		["taxi", Vector3(-7.6, 0, 32), PI, "vecino"], ["suv", Vector3(-2.4, 0, -46), 0.0, "vecino"],
		["hatchback", Vector3(-7.6, 0, 50), PI, "vecino"], ["bike", Vector3(-12.5, 0, -1), PI / 2, "player"]]
	for c in cars:
		var at: Vector3 = c[1]
		at.y = _ground_height(at.x, at.z) + 0.1
		Vehicle.place_factory(self, c[0], at, c[2], c[3])
	Vehicle.place_factory(self, "speedboat", Vector3(42, WATER_Y, 12), PI / 2, "npc_marina", "#2c5d8f")
	var ship := Ship.factory()
	var e := Creations.add({"name": "Lanzadera vieja", "parts": ship.parts, "behaviors": ship.behaviors, "model": ship.get("model", ""),
		"height": ship.get("height", 3.0), "pos": [PAD.x, 0.17, PAD.z], "yaw": PI / 4, "fuel": 0.6, "owner": "", "by": "world"})
	if not e.is_empty():
		Creations.build(self, e)


## Casa de la calle principal mirando a la calle (side: -1 a la izquierda, 1 a la derecha).
func _house(base: Vector3, side: int, size_class: String, wall: Color, rng: RandomNumberGenerator) -> void:
	var model := AssetLibrary.building(size_class, rng, wall, true)
	if model == null:
		_box(base + Vector3(0, 2, 0), Vector3(6, 4, 6), wall)
		return
	var b := AssetLibrary.bounds(model)
	var root := AssetLibrary.place(self, model, base, b.size.y * 2.7, PI / 2 if side < 0 else -PI / 2, true)
	_house_count += 1
	var home := base.is_equal_approx(Vector3(-16, 0, -4))
	if not home and side > 0 and absf(base.z) <= 14.0 and not _shops_to_open.is_empty():
		var shop: Array = _shops_to_open.pop_front()  # en el centro del pueblo: la tienda de ropa y la peluquería
		_add_door(root, shop[0], "casa_%d" % _house_count, shop[1])
		var door := _interiors.door_position("casa_%d" % _house_count)
		_label3d(door + _out_of(root) * 1.4 + Vector3(0, 3.6, 0), shop[2])
		return
	# Los locales, en el centro (sin tocar casas donde ya vive una familia en esta partida)
	var central := absf(base.z) <= 26.0 and (side < 0 or absf(base.z) > 14.0)
	var id := "casa_%d" % _house_count
	var someones_home := _load_npc_entries().any(func(e): return e.get("home", "") == id)  # (la casa de Teo no)
	if not home and central and not someones_home and not _locals_to_open.is_empty() and Households.members(id).is_empty():
		var kind: String = _locals_to_open.pop_front()
		_add_door(root, kind, id, Shops.label(kind))
		_label3d(_interiors.door_position(id) + _out_of(root) * 1.4 + Vector3(0, 3.6, 0), str(Shops.info(kind).sign))
		return
	_add_door(root, "home" if home else "house", "casa_%d" % _house_count, "tu casa" if home else "una casa")


## Edificio concreto (cafetería, estación) con su color de fachada.
func _building(base: Vector3, model_name: String, scale: float, yaw: float, wall: Color, kind: String, label: String) -> void:
	var model := AssetLibrary.building_named(model_name, wall, true)  # ventanas propias: la estación cerrada, a oscuras
	if model == null:
		_box(base + Vector3(0, 2, 0), Vector3(8, 4, 6), wall)
		return
	var b := AssetLibrary.bounds(model)
	_add_door(AssetLibrary.place(self, model, base, b.size.y * scale, yaw, true), kind, kind, label)


## Puerta en la fachada (los modelos miran hacia +Z): se entra con E.
func _add_door(root: Node3D, kind: String, id: String, label: String) -> void:
	var size: Vector3 = root.get_meta("size", Vector3(6, 4, 6))
	var front := root.global_transform.basis.z.normalized()
	var pos := root.position + front * (size.z / 2.0 + 0.6)
	var model: Node3D = root.get_child(0) if root.get_child_count() > 0 else null
	if model and model.has_meta("model_name"):  # la puerta, donde el modelo tiene la suya
		var right := front.cross(Vector3.UP).normalized()
		var off := AssetLibrary.find_door(root, front, right)
		if not is_nan(off) and absf(off) < size.x / 2.0 - 0.5:
			pos += right * off
	pos.y = _ground_height(pos.x, pos.z)
	_interiors.add_door(id, pos, root.rotation.y, kind, hash(id), label)
	_interiors.set_building(id, root.global_position, size, root.rotation.y)
	if model and model.has_meta("windows"):
		_windows[id] = model.get_meta("windows")
	if kind == "station":
		_interiors.set_door_option(id, "floors", 2)  # dos plantas por fuera: también por dentro
	if model == null or not model.has_meta("model_name") or kind in ["cafe", "station"]:
		return  # la cafetería y la estación ya traen su fachada
	# Casas y negocios de la calle: plantas, fachada y ventanas que se encienden con vida dentro
	# Tantas plantas como tiene el modelo («3Story_Balcony» = 3, con balcón), no a ojo por su altura
	var mname := str(model.get_meta("model_name"))
	_interiors.set_door_option(id, "floors", AssetLibrary.floors_of(mname, size.y))
	_interiors.set_door_option(id, "balcony", mname.contains("Balcony"))
	if mname.contains("Balcony"):
		# El balcón de verdad del modelo: ahí se sale (antes, una losa invisible por delante). Y la
		# caja de choque de la casa acaba en la fachada, para poder pisarlo.
		var bal := AssetLibrary.balcony_of(root)
		if not bal.is_empty():
			_interiors.set_door_option(id, "balcony_spot", root.global_transform * (bal.local as Vector3))
			_interiors.set_door_option(id, "balcony_size", Vector2(float(bal.width), float(bal.depth)))
			for body in root.get_children():
				if body is StaticBody3D:
					for cs in body.get_children():
						if cs is CollisionShape3D and cs.shape is BoxShape3D:
							var bx: BoxShape3D = cs.shape
							bx.size.z -= float(bal.depth) + 0.1
							cs.position.z -= (float(bal.depth) + 0.1) / 2.0
	var sign: String = {"clothes": "Ropa", "salon": "Peluquería"}.get(kind, str(Shops.info(kind).get("sign", "")) if Shops.is_shop(kind) else "")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	Decor.facade(self, pos, root.rotation.y, sign, rng)


## Ventanas encendidas de noche solo si hay alguien despierto dentro (o el negocio está abierto).
func _update_windows() -> void:
	var h := WorldClock.hour()
	for id in _windows:
		var kind: String = _interiors.doors().get(id, {}).get("kind", "")
		var lit := false
		if kind == "home":
			lit = _interiors.current_door() == id
		elif kind == "house":
			for m in _households.ensure(id, owner_of_door(id)):
				var p := Households.plan(WorldDB.get_entity("npc", m), h)
				if p.home and p.get("gesture", "") != "sleep":
					lit = true
					break
		elif Shops.is_shop(kind):
			lit = Shops.is_open(kind, h)
		elif kind == "station":
			lit = false  # cerrada desde hace años
		else:
			lit = h >= 9.0 and h < 20.0
		Decor.set_windows_lit(_windows[id], lit)


# --- Lo que el jugador cambia en el mundo ------------------------------------------------

# --- Helpers de primitivas ------------------------------------------------------------

## La puerta del faro: una puerta de verdad (hoja de madera con su pomo) en un marco de piedra,
## arriba del zócalo, y unos escalones para llegar a ella.
func _lighthouse_door(lp: Vector3) -> void:
	var out := Vector3(-1, 0, 1).normalized()
	var yaw := atan2(out.x, out.z)
	var plinth_top := 1.2
	var door_at := lp + out * 3.18 + Vector3(0, plinth_top, 0)
	var model := AssetLibrary.instance("house_interior_pack", "Door_4")
	if model:
		AssetLibrary.place(self, model, door_at, 2.25, yaw, true)
	else:
		_box(door_at + Vector3(0, 1.1, 0), Vector3(1.1, 2.2, 0.12), Color("#4a3426"), false).rotation.y = yaw
	var stone := Color("#b9b2a4")
	for side in [-1.0, 1.0]:  # jambas y dintel de piedra
		var jamb := _box(door_at + out.cross(Vector3.UP) * side * 0.72 + Vector3(0, 1.2, 0) + out * 0.08, Vector3(0.28, 2.5, 0.3), stone, false)
		jamb.rotation.y = yaw
	var lintel := _box(door_at + Vector3(0, 2.55, 0) + out * 0.08, Vector3(1.75, 0.3, 0.32), stone, false)
	lintel.rotation.y = yaw
	for k in 4:  # escalones hasta el zócalo
		var step := _box(lp + out * (3.75 + k * 0.38) + Vector3(0, (plinth_top - k * 0.3) / 2.0, 0), Vector3(1.8, plinth_top - k * 0.3, 0.38), Color("#8a8478"))
		step.rotation.y = yaw
	_interiors.add_door("faro", lp + out * 3.45 + Vector3(0, plinth_top, 0), yaw, "lighthouse", 33, "el faro")
	_interiors.set_building("faro", lp, Vector3(6.4, 18.0, 6.4), yaw)
	_interiors.set_door_option("faro", "shape", "round")


## El balcón de la linterna (a 19 m): se puede salir a él por la escalera de dentro. Barandilla
## alrededor y una trampilla para bajar.
var _gallery_spot := Vector3.INF


func _lighthouse_gallery(lp: Vector3) -> void:
	var floor_y := lp.y + 19.5
	for k in 16:  # barandilla
		var a := TAU * k / 16.0
		var post := _box(Vector3(lp.x + cos(a) * 2.32, floor_y + 0.5, lp.z + sin(a) * 2.32), Vector3(0.06, 1.0, 0.95), Color("#2d3238"))
		post.rotation.y = -a
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.28
	tm.outer_radius = 2.36
	ring.mesh = tm
	ring.material_override = _mat(Color("#2d3238"))
	ring.position = Vector3(lp.x, floor_y + 1.0, lp.z)
	add_child(ring)
	var out := Vector3(-1, 0, 1).normalized()
	_gallery_spot = Vector3(lp.x, floor_y + 0.1, lp.z) + out * 1.8
	PropsBuilder._box(self, _gallery_spot + Vector3(0, -0.07, 0) - out * 0.15, Vector3(0.7, 0.04, 0.7), Color("#5a4632"), false)
	Interactable.create(self, _gallery_spot - out * 0.15 + Vector3(0, 0.9, 0), 1.2, "Bajar por la escalera", func(_p): _climb_down())
	Decor.landmark(self, _gallery_spot, "el balcón de la linterna del faro, a 19 m sobre el mar", "gallery")
	_interiors.climb.connect(func(dir, door):
		if dir == "up" and door == "faro":
			_interiors.leave_to(_gallery_spot + out * 0.1 + Vector3(0, 0.2, 0), out))


func _climb_down() -> void:
	await _interiors.enter_at("faro", "hatch")


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


## Hacia la calle desde la fachada de un edificio (para que la esquina no tape su letrero).
func _out_of(root: Node3D) -> Vector3:
	var f := root.global_transform.basis.z
	return Vector3(f.x, 0, f.z).normalized()


func _label3d(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.outline_size = 10
	l.pixel_size = 0.01
	l.position = pos
	Decor.fade_label(l)
	# De muy cerca no se ve (si no, al pasar la cámara por él tapaba media pantalla)
	l.visibility_range_begin = 7.0
	l.visibility_range_begin_margin = 1.5
	add_child(l)


## El objetivo del Acto 0 arriba a la izquierda (HUD).
func _set_objective(text: String) -> void:
	if _ui:
		_ui.hud.set_place("Bahía de las Horas")
		_ui.hud.set_objective(text)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

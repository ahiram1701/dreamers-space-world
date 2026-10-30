class_name LocationScene
extends Node3D
## Lo común a todos los lugares jugables (el pueblo del Acto 0 y los lugares que crea la IA):
## interactuar con E, conversar, lo que hacen los PNJs (acompañar, irse, encerrarse, reaccionar),
## lo que el jugador cambia en el mundo (talar, construir) y las acciones con F paso a paso.
## Cada escena construye su mundo y llama a `_setup_common()` al final de su _ready.

## Palabras con las que se nombra cada tipo de interior ("me voy a la cafetería").
const KIND_WORDS := {
	"cafe": ["cafe", "cafetería", "cafeteria", "bar", "barra"], "station": ["estación", "estacion", "taller", "andén"],
	"lighthouse": ["faro"], "home": ["tu casa"], "house": ["casa", "hogar", "vivienda"], "scifi": ["módulo", "modulo", "edificio", "base"],
}
const CONTACT_GESTURES := ["punch", "push", "kick", "hug", "handshake", "pat", "give"]

var _player: Player
var _npcs: Dictionary = {}          # npc_id -> TownNPC
var _interiors: InteriorManager
var _ui: GameplayUI
var _dialogue: DialoguePanel
var _features: Array = []           # árboles, rocas y arbustos: {id, kind, pos, node}
var _water_level := -INF
var _performer: ActionPerformer
var _places: Dictionary = {}        # sitios con nombre -> posición
var _errands: Dictionary = {}       # npc_id -> true mientras se va o se mete en un edificio
var _targets: Dictionary = {}       # ids de "cosas cercanas" que se le dieron a la IA (F) -> entrada
## Solares libres donde la IA puede abrir un sitio nuevo ({pos, yaw}); si no hay, se busca hueco.
var _free_lots: Array = []
var _added_places := 0
var _life: TownLife
var _passersby: Passersby
var _yawn_t := 0.0


# --- Lo que define cada escena -----------------------------------------------------------

func ground_at(_x: float, _z: float) -> float:
	return 0.0


## Descripción fija del lugar para la IA.
func scene_context() -> String:
	return ""


## Nombre del sitio con nombre más cercano a una posición (o "").
func place_near(pos: Vector3) -> String:
	var best := ""
	var best_d := 30.0
	for name in _places:
		var d := Vector2(pos.x - _places[name].x, pos.z - _places[name].z).length()
		if d < best_d:
			best = name
			best_d = d
	return best


## Posición de un sitio por su nombre aproximado ("el faro", "la cafetería del muelle"…), o INF.
func place_position(text: String) -> Vector3:
	var t := text.to_lower().strip_edges()
	if t.is_empty():
		return Vector3.INF
	for name in _places:
		var n: String = name.to_lower()
		if t.contains(n) or n.contains(t):
			return _on_ground(_places[name])
	for name in _places:  # "cafe" → "cafetería"
		if t.length() >= 4 and name.to_lower().begins_with(t.left(4)):
			return _on_ground(_places[name])
	return Vector3.INF


## Puerta "de casa" de un PNJ, a la que va si se mete en un edificio sin decir cuál.
func _npc_home_door(npc_id: String) -> String:
	var npc: TownNPC = _npcs[npc_id]
	var best := ""
	var best_d := 80.0
	for id in _interiors.doors():
		var d := npc.global_position.distance_to(_interiors.doors()[id].pos)
		if d < best_d:
			best = id
			best_d = d
	return best


func _after_dialogue(_npc_id: String) -> void:
	pass


func _pick_up(_p: Pickup) -> void:
	pass


# --- Montaje común ----------------------------------------------------------------------

func _setup_common() -> void:
	_player.interact_requested.connect(_on_interact)
	_interiors.player = _player
	for entry in Actions.placed_here(GameState.current_location()):
		Decor.build_placed(self, entry, ground_at, _water_level, _on_placed_use)
	Actions.player_pose = _player_pose
	Actions.feature_finder = _find_feature
	Actions.object_placed.connect(func(e): Decor.build_placed(self, e, ground_at, _water_level, _on_placed_use))
	Actions.feature_removed.connect(_remove_feature)
	Actions.npc_action.connect(_on_npc_action)
	Actions.lot_finder = _find_lot
	Actions.workplace_finder = func(id: String) -> Dictionary:
		var door := _door_for(id, "")
		return {"place": door, "label": _interiors.door_label(door) if not door.is_empty() else "su negocio"}
	Phone.scene_context = scene_context
	Phone.ensure_phone()
	_ui.start_call = start_call
	_ui.places = func(): return _places
	Actions.arrival_spot = _arrival_spot
	Actions.resident_added.connect(func(e): _add_resident(e, true))
	Actions.place_added.connect(func(e): _build_place(e))
	for e in Actions.places_added_here(GameState.current_location()):
		_build_place(e)
	for e in Actions.residents_here(GameState.current_location()):
		_add_resident(e, false)
	_dialogue.context_provider = dialogue_context
	_dialogue.closed.connect(_on_dialogue_closed)
	_dialogue.turn_received.connect(_on_turn)
	_life = TownLife.new()
	_life.scene = self
	add_child(_life)
	var ambience := Ambience.new()
	ambience.scene = self
	add_child(ambience)
	if not StationBuilder.is_space(WorldDB.get_entity("location", GameState.current_location())) and _places.size() >= 2:
		_passersby = Passersby.new()
		_passersby.scene = self
		add_child(_passersby)
	_performer = ActionPerformer.new()
	_performer.scene = self
	_performer.player = _player
	add_child(_performer)
	_ui.actions.performer = _performer
	_ui.actions.suggestions = suggestions
	_ui.scene_context = action_context
	_interiors.message.connect(_ui.toast)
	_interiors.entered.connect(func(_k, _id): _refresh_presence(); _add_work_spot(); _check_trespass())
	_interiors.exited.connect(func(_k, _id): _refresh_presence())
	WorldClock.hour_changed.connect(func(_h): _refresh_presence())
	_refresh_presence()


func _process_common() -> void:
	_process_work()
	# Te caes de sueño: de vez en cuando, un bostezo
	_yawn_t += get_process_delta_time()
	if _yawn_t > 35.0:
		_yawn_t = 0.0
		if Body.get_need("rest") < 15.0 and _player.controls_enabled and _player.current_gesture().is_empty():
			_player.play_gesture("think", 1.8)
	var head := _player.global_position + Vector3(0, 1.6, 0)
	for id in _npcs:  # te miran al pasar cerca
		var npc: TownNPC = _npcs[id]
		if npc.is_present():
			npc.look_at_target(head if npc.global_position.distance_to(head) < 7.0 else Vector3.INF)


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, ground_at(p.x, p.z), p.z)


# --- Interacción (E) y conversación -------------------------------------------------------

func _on_interact(target: Node) -> void:
	if _performer.is_busy():
		return
	if target is TownNPC and target.has_meta("passerby"):
		# Alguien de paso: al hablarle pasa a existir de verdad
		var id := _passersby.promote(target) if _passersby else ""
		if not id.is_empty():
			_npcs[id] = target
			_start_dialogue(target)
	elif target is TownNPC:
		_start_dialogue(target)
	elif target is Interactable:
		target.use(_player)
	elif target is Boat:
		target._on_use(_player)
	elif target is Pickup:
		_pick_up(target)


# --- Casa ajena ----------------------------------------------------------------------------

## ¿De quién es esta casa? (cada escena lo sabe por sus rutinas; "" si de nadie en concreto)
func owner_of_door(_door: String) -> String:
	return ""


## Entras en una casa con su dueño dentro: de día y si os lleváis bien, te recibe; de noche o
## si te tiene manía, te echa (y luego lo cuenta).
func _check_trespass() -> void:
	await get_tree().create_timer(1.0).timeout
	var door := _interiors.current_door()
	var owner := owner_of_door(door)
	if owner.is_empty() or not _npcs.has(owner) or not _npcs[owner].is_present():
		return
	var npc: TownNPC = _npcs[owner]
	var rel := int(NPCMemory.get_mem(owner).relationship)
	var h := WorldClock.hour()
	var night := h >= 23.0 or h < 7.0
	npc.face(_player.global_position)
	if night or rel < 0:
		npc.set_emotion("angry")
		npc.play_gesture("point", 2.5)
		npc.say("¿Qué haces en mi casa? ¡Sal de aquí ahora mismo!" if night else "¿Quién te dio permiso para entrar? Fuera.", 5.0)
		NPCMemory.add_event(owner, "El jugador se metió en tu casa sin permiso%s." % (" de madrugada" if night else ""), -10)
		_life.witness("el jugador se metió sin permiso en casa de %s" % WorldDB.get_entity("npc", owner).get("name", "alguien"), npc.global_position, [owner])
	else:
		npc.play_gesture("wave", 2.0)
		npc.say("¡Ah, eres tú! Pasa, pasa.", 4.0)
		NPCMemory.add_event(owner, "El jugador vino a verte a tu casa.", 1)


# --- Trabajo -------------------------------------------------------------------------------

## En tu sitio de trabajo aparece "Trabajar" (solo en tu turno).
func _add_work_spot() -> void:
	var j := Jobs.job()
	if j.is_empty() or j.place != _interiors.current_door() or j.get("location", "") != GameState.current_location():
		return
	var spot: Vector3 = _interiors.npc_spot(1) if _interiors.npc_spot(1) != Vector3.INF else _player.global_position + Vector3(0, 0, -2)
	var root: Node3D = _interiors.get("_interior").root
	var it := Interactable.create(root, spot - root.global_position + Vector3(0, 1.0, 0), 1.8,
		"Trabajar: %s (%02d:00–%02d:00)" % [j.title, j.start_hour, j.end_hour], func(_p): _work())
	_work_spot = it


var _work_spot: Interactable


func _process_work() -> void:
	if _work_spot and is_instance_valid(_work_spot):
		_work_spot.enabled = Jobs.can_work_now()


## Trabajar el turno: fundido, pasan las horas, cobras y la IA cuenta cómo fue.
func _work() -> void:
	var j := Jobs.job()
	if j.is_empty() or not Jobs.can_work_now():
		return
	_ui.block(true)
	_player.play_gesture("wipe" if "caf" in str(j.place_label) else "hammer", 999.0)
	await _interiors._fade_to(1.0)
	var r := Jobs.work_shift()
	var summary := await StoryDirector.shift_summary(j, r, perception(true))
	await get_tree().create_timer(0.5).timeout
	_player.stop_gesture()
	await _interiors._fade_to(0.0)
	_ui.block(false)
	var late := "  (llegaste %d min tarde)" % r.late_minutes if int(r.get("late_minutes", 0)) > 30 else ""
	_ui.toast("%s\nCobras %s por el turno.%s" % [summary, Wallet.text(int(r.get("paid", 0))), late], "money")


## Llamar a alguien por el celular: la misma conversación, pero a distancia.
func start_call(npc_id: String) -> void:
	_ui.block(true)
	_player.play_gesture("call", 600.0)
	Sfx.chime(self)
	_dialogue.open(npc_id, true)


func _start_dialogue(npc: TownNPC) -> void:
	_ui.block(true)
	npc.stop()
	npc.face(_player.global_position)
	npc.talking = true
	_player.face_towards(npc.global_position)
	_player.focus_on(npc.global_position + Vector3(0, 1.5, 0))
	_dialogue.open(npc.npc_id)


func _on_dialogue_closed(npc_id: String) -> void:
	_ui.block(false)
	if _dialogue.call_mode:
		_player.stop_gesture()
	_player.clear_look()
	_player.end_focus()
	if _npcs.has(npc_id):
		_npcs[npc_id].talking = false
		_npcs[npc_id].refresh_name(WorldDB.get_entity("npc", npc_id))
	_after_dialogue(npc_id)


## El PNJ gesticula según cómo se siente en cada respuesta.
func _on_turn(npc_id: String, turn: Dictionary) -> void:
	if _npcs.has(npc_id):
		_npcs[npc_id].set_emotion(turn.get("emotion", "neutral"))


## Contexto de cada turno de conversación: el lugar, la hora y la situación física real del PNJ.
## Lo que se nota del jugador a simple vista (para los PNJs): cansancio, hambre, suciedad, la lluvia…
func player_appearance() -> String:
	var signs := PackedStringArray()
	if Body.get_need("rest") < 25.0:
		signs.append("tiene ojeras y cara de no haber dormido")
	if Body.get_need("hunger") < 15.0:
		signs.append("está pálido/a, como si no hubiera comido")
	if Body.get_need("thirst") < 15.0:
		signs.append("tiene los labios secos")
	if Body.get_need("hygiene") < 25.0:
		signs.append("va desaliñado/a y huele mal" if Body.get_need("hygiene") < 12.0 else "va algo desaliñado/a")
	if Weather.is_raining() and not _interiors.is_inside():
		signs.append("está empapado/a por la lluvia")
	return ("Se nota que el jugador " + ", ".join(signs) + ".") if not signs.is_empty() else ""


## Qué está haciendo la gente cercana (su actividad), para que la IA lo tenga en cuenta.
func people_doing(exclude: String = "", radius: float = 25.0) -> String:
	var out := PackedStringArray()
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		if id == exclude or not npc.is_present() or npc.global_position.distance_to(_player.global_position) > radius:
			continue
		var who: String = WorldDB.get_entity("npc", id).get("name", "?") if NPCMemory.get_mem(id).met else "alguien (%s)" % WorldDB.get_entity("npc", id).get("occupation", "?")
		out.append("%s %s" % [who, npc.doing()])
	return "; ".join(out)


## Percepción común (F y diálogos): día, hora, tiempo y, si es el jugador quien actúa, su cuerpo y su dinero.
func perception(for_player: bool) -> PackedStringArray:
	var lines := PackedStringArray([scene_context(), WorldClock.describe()])
	if not StationBuilder.is_space(WorldDB.get_entity("location", GameState.current_location())):
		lines.append(Weather.describe() if not _interiors.is_inside() else "Fuera: " + Weather.describe().to_lower())
	if for_player:
		lines.append("TU CUERPO: " + Body.describe())
		lines.append("TRABAJO: " + Jobs.describe())
		lines.append("CELULAR: " + ("lo llevas encima (puedes llamar o escribir a tus contactos)." if Phone.has_phone() else "no lo llevas."))
		lines.append("DINERO: llevas %s. Precios orientativos (dólares): café 3, comida 12–18, una reparación 25–80, una noche de hotel 90, un turno de trabajo 60–120. En otras épocas o mundos tu dinero puede no valer." % Wallet.text())
	return lines


func dialogue_context(npc_id: String) -> String:
	if _dialogue.call_mode:
		return Phone.remote_context(npc_id, true)
	var lines := perception(false)
	var npc: TownNPC = _npcs.get(npc_id)
	var where := ""
	if _interiors.is_inside():
		where = "dentro de %s" % _interiors.current_label()
	else:
		var near := place_near(_player.global_position)
		where = ("fuera, cerca de: %s" % near) if not near.is_empty() else "fuera, al aire libre"
	var state := "TU SITUACIÓN FÍSICA AHORA MISMO: estás %s, de pie, cara a cara con el jugador (a %.0f m), hablando con él/ella." % [
		where, npc.global_position.distance_to(_player.global_position) if npc else 1.5]
	if NPCMemory.is_following(npc_id):
		state += " Le estás acompañando."
	state += " No te has ido a ningún sitio: si quieres irte o meterte en algún edificio, usa la acción leave o go_inside y entonces ocurrirá."
	lines.append(state)
	var people := PackedStringArray()
	for id in _npcs:
		if id != npc_id and _npcs[id].is_present() and _npcs[id].global_position.distance_to(_player.global_position) < 12.0:
			people.append(WorldDB.get_entity("npc", id).get("name", "?"))
	if not people.is_empty():
		lines.append("También hay cerca: %s." % ", ".join(people))
	var look := player_appearance()
	if not look.is_empty():
		lines.append(look)
	if Actions.owed(npc_id) > 0:
		lines.append("El jugador te debe %s (si paga, lo verás en la conversación)." % Wallet.text(Actions.owed(npc_id)))
	if Jobs.has_job() and Jobs.job().employer == npc_id:
		lines.append("EL JUGADOR TRABAJA PARA TI: " + Jobs.describe().replace("Trabajas", "Trabaja").replace("Llevas", "Lleva").replace("Tu turno", "Su turno"))
	elif not Jobs.has_job():
		lines.append("El jugador no tiene trabajo.")
	lines.append("Tienes su número de celular." if bool(NPCMemory.get_mem(npc_id).get("phone", false)) else "No tienes su número de celular (ni él/ella el tuyo).")
	return "\n".join(lines)


# --- Lo que hacen los PNJs ----------------------------------------------------------------

## Lo que un PNJ decide (en una conversación o al reaccionar a lo que haces con F) se ve en el mundo.
func _on_npc_action(npc_id: String, a: Dictionary) -> void:
	if not _npcs.has(npc_id):
		return
	var npc: TownNPC = _npcs[npc_id]
	match a.get("type", ""):
		"follow_player":
			npc.follow(_player)
		"stop_following":
			npc.stop()
		"go_to":
			if not NPCMemory.is_following(npc_id):
				var dest := place_position(str(a.get("target", "")))
				if dest != Vector3.INF:
					npc.walk_to(dest)
		"approach":
			if not npc.is_present() and not NPCMemory.is_locked_in(npc_id):  # sale de donde estaba para venir
				var door := _interiors.door_position(NPCMemory.inside(npc_id))
				NPCMemory.come_out(npc_id)
				npc.set_present(true)
				if door != Vector3.INF:
					npc.global_position = door + Vector3(0, 0.3, 0)
			npc.walk_to(_near_player(npc, 1.4))
		"give_item", "take_item":
			npc.play_gesture("give", 2.5)
		"update_item":
			npc.play_gesture("hammer", 3.0)
		"refuse_contact":
			npc.play_gesture("cross_arms", 6.0)
		"play":
			npc.play_gesture(_gesture(a.get("target", "")), 4.0)
		"leave":
			_npc_leave(npc_id, str(a.get("target", "")))
		"go_inside":
			_npc_go_inside(npc_id, str(a.get("target", "")), bool(a.get("locked", false)), int(a.get("amount", 0)))
		"npc_react":
			_npc_react(npc_id, a)


func _gesture(text: Variant) -> String:
	return ContentValidator._match_enum(str(text), ContentValidator.archetypes().gesture)


## Un punto junto al jugador, en el lado del PNJ.
func _near_player(npc: Node3D, dist: float) -> Vector3:
	var away := npc.global_position - _player.global_position
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	return _player.global_position + away * dist


## Reacción inmediata a lo que hace el jugador (un golpe, un abrazo, que le des algo…).
func _npc_react(npc_id: String, a: Dictionary) -> void:
	var npc: TownNPC = _npcs[npc_id]
	if not npc.is_present():
		return
	npc.stop()
	npc.face(_player.global_position)
	var emotion: String = a.get("emotion", "")
	if not emotion.is_empty():
		npc.set_emotion(emotion)
	var gesture := _gesture(a.get("gesture", ""))
	if gesture.is_empty():
		gesture = {"angry": "cross_arms", "scared": "crouch", "happy": "wave", "sad": "shake_head", "amused": "shrug"}.get(emotion, "")
	if not gesture.is_empty():
		npc.play_gesture(gesture, 3.0)
	var line := str(a.get("line", "")).strip_edges()
	if not line.is_empty():
		npc.say(line)
	# Quien está cerca lo ve (y luego lo cuenta)
	var seen := str(a.get("narration", "")).strip_edges()
	if seen.is_empty():
		seen = "algo pasó entre el jugador y %s" % WorldDB.get_entity("npc", npc_id).get("name", "alguien")
	_life.witness("%s (con %s)" % [seen, WorldDB.get_entity("npc", npc_id).get("name", "alguien")], npc.global_position, [npc_id])
	match a.get("behavior", "stay"):
		"flee":
			var away := (npc.global_position - _player.global_position)
			away.y = 0
			var dest := npc.global_position + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 18.0
			npc.walk_to(_on_ground(dest), true)
			NPCMemory.add_event(npc_id, "Saliste corriendo para alejarte del jugador.")
		"approach":
			npc.walk_to(_near_player(npc, 1.2))
		"follow":
			NPCMemory.set_fields(npc_id, {"following": true})
			npc.follow(_player)
		"go_inside":
			_npc_go_inside(npc_id, "", emotion in ["angry", "scared"], 0)
		"leave":
			_npc_leave(npc_id, "")
		"fight_back":
			await get_tree().create_timer(0.6).timeout
			if is_instance_valid(npc) and npc.global_position.distance_to(_player.global_position) < 2.5:
				npc.play_gesture("push", 1.5)
				await get_tree().create_timer(0.35).timeout
				Sfx.at(self, "hit", _player.global_position + Vector3(0, 1.2, 0))
				_player.shake(0.25, 0.05)
				if GameState.is_awakened():
					GameState.change_stat("health", -6)
				NPCMemory.add_event(npc_id, "Le devolviste el golpe al jugador.")


## Se va (de la conversación o de la escena): camina hasta el sitio que dijo o se aleja.
func _npc_leave(npc_id: String, target: String) -> void:
	var door := _door_for(npc_id, target) if not target.is_empty() else ""
	if not door.is_empty():
		_npc_go_inside(npc_id, target, false, 0)
		return
	var npc: TownNPC = _npcs[npc_id]
	NPCMemory.set_fields(npc_id, {"following": false})
	var dest := place_position(target)
	if dest == Vector3.INF or dest.distance_to(npc.global_position) < 6.0:
		var away := npc.global_position - _player.global_position
		away.y = 0
		dest = _on_ground(npc.global_position + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 22.0)
	_errands[npc_id] = true
	npc.walk_to(dest)
	NPCMemory.add_event(npc_id, "Te marchaste y dejaste al jugador ahí.")
	var on_arrive := func(): _errands.erase(npc_id)
	npc.arrived.connect(on_arrive, CONNECT_ONE_SHOT)


## Camina hasta la puerta de un edificio y entra. Se queda dentro un rato (con pestillo si no
## quiere ver a nadie); si entras, lo encuentras ahí.
func _npc_go_inside(npc_id: String, target: String, locked: bool, minutes: int) -> void:
	var door := _door_for(npc_id, target)
	if door.is_empty():
		_npc_leave(npc_id, "")
		return
	var npc: TownNPC = _npcs[npc_id]
	NPCMemory.set_fields(npc_id, {"following": false})
	_errands[npc_id] = true
	var stay := float(minutes) * 6.0 if minutes > 0 else (45.0 if locked else 60.0)
	if _interiors.current_door() == door:  # ya estás dentro de ese sitio: entra contigo
		_enter_building(npc_id, door, locked, stay)
		return
	npc.walk_to(_interiors.door_position(door))
	npc.arrived.connect(func(): _enter_building(npc_id, door, locked, stay), CONNECT_ONE_SHOT)


func _enter_building(npc_id: String, door: String, locked: bool, minutes: float) -> void:
	_errands.erase(npc_id)
	var label := _interiors.door_label(door)
	NPCMemory.go_inside(npc_id, door, label, minutes, locked)
	NPCMemory.add_event(npc_id, "Entraste en %s%s." % [label, " y cerraste por dentro para no ver al jugador" if locked else ""])
	Sfx.at(self, "door", _interiors.door_position(door) + Vector3(0, 1, 0))
	_refresh_presence()


## Puerta a la que se refiere un texto ("la cafetería", "casa"…), o la de casa del PNJ.
func _door_for(npc_id: String, target: String) -> String:
	var t := target.to_lower()
	var doors := _interiors.doors()
	if not t.is_empty():
		for id in doors:
			if t.contains(str(id).to_lower()) or t.contains(str(doors[id].label).to_lower().trim_prefix("la ").trim_prefix("el ").trim_prefix("una ").trim_prefix("un ")):
				return id
		for kind in KIND_WORDS:
			if KIND_WORDS[kind].any(func(w): return t.contains(w)):
				var best := ""
				var best_d := INF
				for id in doors:
					if doors[id].kind == kind or (kind == "house" and doors[id].kind == "home" and t.contains("tu ")):
						var d: float = doors[id].pos.distance_to(_npcs[npc_id].global_position)
						if d < best_d:
							best = id
							best_d = d
				if not best.is_empty():
					return best
	return _npc_home_door(npc_id)


## Quién está dónde: el que se metió en un edificio no se ve fuera; si entras, está dentro.
## Al acabar su rato dentro, sale (y abre la puerta).
func _refresh_presence() -> void:
	var i := 0
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		var w: Dictionary = NPCMemory.get_mem(id).whereabouts
		var door := NPCMemory.inside(id)
		if door.is_empty():
			if not w.is_empty():  # se le pasó el rato: sale
				_interiors.set_locked(str(w.get("door", "")), "")
				NPCMemory.come_out(id)
				if not npc.is_present():
					var p := _interiors.door_position(str(w.get("door", "")))
					npc.set_present(true)
					if p != Vector3.INF and not _interiors.is_inside():
						npc.global_position = p + Vector3(0, 0.3, 0)
		else:
			if NPCMemory.is_locked_in(id):
				_interiors.set_locked(door, "%s no abre. Se oye a alguien dentro." % WorldDB.get_entity("npc", id).get("name", "Alguien").split(" ")[0])
			if _interiors.current_door() == door:
				npc.set_present(true)
				npc.stop()
				npc.global_position = _interiors.npc_spot(i) + Vector3(0, 0.2, 0)
			else:
				npc.set_present(false)
		i += 1


## El PNJ está ocupado (yéndose, encerrado): las rutinas no lo mueven.
func npc_busy(npc_id: String) -> bool:
	return _errands.has(npc_id) or not NPCMemory.inside(npc_id).is_empty()


# --- Lo que el jugador cambia en el mundo ------------------------------------------------

func _player_pose() -> Dictionary:
	return {"pos": _player.global_position, "yaw": _player.facing_yaw(), "water": _water_spot()}


## Punto de agua navegable más cercano (a menos de 25 m), o INF.
func _water_spot() -> Vector3:
	if _water_level == -INF or _interiors.is_inside():
		return Vector3.INF
	var p := _player.global_position
	for dist in [3.0, 6.0, 10.0, 15.0, 20.0, 25.0]:
		for i in 12:
			var a := TAU * i / 12.0
			var q: Vector3 = p + Vector3(cos(a), 0, sin(a)) * dist
			if ground_at(q.x, q.z) < _water_level - 0.5:
				return Vector3(q.x, _water_level, q.z)
	return Vector3.INF


## Id del árbol/roca/arbusto: el que se pide por id, o el más cercano de ese tipo (a menos de 6 m).
func _find_feature(kind_or_id: String) -> String:
	for f in _features:
		if f.id == kind_or_id and is_instance_valid(f.node):
			return f.id
	var best := ""
	var best_d := 6.0
	for f in _features:
		if f.kind == kind_or_id and is_instance_valid(f.node):
			var d: float = Vector2(f.pos.x - _player.global_position.x, f.pos.z - _player.global_position.z).length()
			if d < best_d:
				best = f.id
				best_d = d
	return best


## Talado o roto: cae (o se hunde) y desaparece.
func _remove_feature(id: String) -> void:
	for f in _features:
		if f.id == id and is_instance_valid(f.node):
			var node: Node3D = f.node
			for c in node.get_children():
				if c is StaticBody3D:
					c.queue_free()
			var tw := node.create_tween()
			if f.kind == "tree":
				var away := (node.global_position - _player.global_position).normalized()
				tw.tween_property(node, "rotation", Vector3(away.z * 1.5, node.rotation.y, -away.x * 1.5), 1.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				tw.tween_callback(func(): Sfx.at(self, "hit", node.global_position))
				tw.tween_interval(1.5)
			tw.tween_property(node, "scale", Vector3(1, 0.01, 1), 0.6)
			tw.tween_callback(node.queue_free)
			_features.erase(f)
			return


## Usar algo que construiste (sentarse, dormir, guardar cosas en el baúl, escuchar la radio).
func _on_placed_use(kind: String, node: Node3D, _p: Player) -> void:
	match kind:
		"bed":
			_interiors.sleep(node)
		"storage":
			_ui.stash.open(str(node.get_meta("placed_id", "")), str(node.name))
		"signal":
			_ui.actions.open("Enciendo el aparato y busco alguna señal")
		_:
			_interiors.sit(node)


## Ideas para "Hacer algo" según lo que hay cerca y cómo estás (sin IA; el jugador las edita).
func suggestions() -> Array:
	var out := []
	var targets := nearby_targets()
	var urgent := Body.most_urgent()
	var inside := _interiors.is_inside()
	match urgent:
		"hunger":
			out.append("Me preparo algo de comer" if inside else "Busco algo de comer por aquí")
		"thirst":
			out.append("Bebo un vaso de agua" if inside else "Busco agua para beber")
		"rest":
			out.append("Me echo una siesta")
		"hygiene":
			out.append("Me doy una ducha" if inside else "Me lavo la cara y las manos")
	for id in targets:
		var e: Dictionary = targets[id]
		if e.kind == "npc" and e.pos.distance_to(_player.global_position) < 10.0 and out.size() < 4:
			var first: String = str(e.label).get_slice(",", 0).get_slice(" ", 0)
			if NPCMemory.get_mem(id.trim_prefix("npc:")).met:
				out.append("Le doy la mano a %s" % first)
				if urgent == "hunger" or urgent == "thirst":
					out.append("Le pido a %s algo de %s y se lo pago" % [first, "comer" if urgent == "hunger" else "beber"])
			else:
				out.append("Me presento a la persona de al lado")
			break
	if Weather.is_raining() and not inside:
		out.append("Busco dónde resguardarme de la lluvia")
	if targets.has("water"):
		out.append("Me siento en la orilla a mirar el mar")
	if targets.keys().any(func(k): return k.begins_with("tree_")):
		out.append("Recojo leña del suelo")
	out.append("Miro a mi alrededor con atención")
	return out


# --- Lo que crea la IA: gente y sitios que se quedan --------------------------------------

## Dónde aparece alguien nuevo: llega andando desde detrás de la cámara hasta delante del jugador.
func _arrival_spot() -> Dictionary:
	var p := _player.global_position
	var fwd := _player.view_forward()
	var to := p + fwd * 2.2
	if _interiors.is_inside():  # llega por la puerta del edificio en el que estás
		var door := _interiors.door_position(_interiors.current_door())
		return {"from": p - fwd * 4.0, "to": to, "home": door if door != Vector3.INF else to}
	var from := p - fwd * 22.0
	for i in 8:  # que no salga del agua ni de dentro de un muro
		if ground_at(from.x, from.z) > _water_level + 0.2:
			break
		from = p + (-fwd).rotated(Vector3.UP, (i + 1) * 0.7) * 22.0
	from.y = ground_at(from.x, from.z) + 0.3
	to.y = ground_at(to.x, to.z) + 0.3
	return {"from": from, "to": to, "home": to}


## Alguien que la IA creó: llega andando (si es nuevo) o ya está en su sitio (al volver).
func _add_resident(e: Dictionary, arriving: bool) -> void:
	var entity := WorldDB.get_entity("npc", str(e.id))
	if entity.is_empty() or _npcs.has(e.id):
		return
	var npc := TownNPC.new()
	add_child(npc)
	npc.setup(entity)
	var home := Vector3(e.home[0], e.home[1], e.home[2])
	_npcs[e.id] = npc
	if arriving:
		npc.global_position = e.get("arrive_from", home)
		npc.walk_to(e.get("arrive_to", home))
		var line := str(e.get("line", ""))
		var greet := func():
			npc.face(_player.global_position)
			npc.play_gesture("wave", 2.0)
			if not line.is_empty():
				npc.say(line, 5.0)
		npc.arrived.connect(greet, CONNECT_ONE_SHOT)
	else:
		npc.global_position = home + Vector3(0, 0.3, 0)


## Un solar libre cerca del jugador: los de la escena primero; si no, un hueco llano y despejado.
func _find_lot() -> Dictionary:
	var here := _player.global_position
	if _interiors.is_inside():
		here = _interiors.door_position(_interiors.current_door())
	var best := {}
	var best_d := INF
	for lot in _free_lots:
		var d: float = lot.pos.distance_to(here)
		if d < best_d and not lot.get("used", false):
			best = lot
			best_d = d
	if not best.is_empty():
		best["used"] = true
		return {"pos": _on_ground(best.pos), "yaw": best.yaw}
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(10, 5, 10)
	for ring in [16.0, 22.0, 30.0, 40.0]:
		for i in 12:
			var a := TAU * i / 12.0
			var p: Vector3 = here + Vector3(cos(a), 0, sin(a)) * ring
			p.y = ground_at(p.x, p.z)
			if p.y < _water_level + 0.3 or absf(ground_at(p.x + 4, p.z) - p.y) > 1.0 or absf(ground_at(p.x, p.z + 4) - p.y) > 1.0:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = Transform3D(Basis(), p + Vector3(0, 3.3, 0))
			q.collision_mask = Layers.WORLD | Layers.CHARACTERS
			if space.intersect_shape(q, 1).is_empty():
				return {"pos": p, "yaw": atan2(here.x - p.x, here.z - p.z)}  # la fachada mira hacia ti
	return {}


## Un edificio nuevo con letrero, puerta e interior (se reconstruye igual al volver).
func _build_place(e: Dictionary) -> void:
	var pos := Vector3(e.pos[0], e.pos[1], e.pos[2])
	var yaw := float(e.get("yaw", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.get("seed", 1))
	var tint := Color.from_hsv(rng.randf(), 0.25, 0.92)
	var model := AssetLibrary.building("small", rng, tint)
	var root: Node3D
	if model:
		var b := AssetLibrary.bounds(model)
		root = AssetLibrary.place(self, model, pos, b.size.y * 2.6, yaw, true)
	else:
		root = Node3D.new()
		root.position = pos
		root.rotation.y = yaw
		add_child(root)
		PropsBuilder._box(root, Vector3(0, 2, 0), Vector3(7, 4, 6), tint, true)
		root.set_meta("size", Vector3(7, 4, 6))
	var size: Vector3 = root.get_meta("size", Vector3(7, 4, 6))
	var front := root.global_transform.basis.z.normalized()
	var door := root.position + front * (size.z / 2.0 + 0.6)
	door.y = ground_at(door.x, door.z)
	_added_places += 1
	var id := "nuevo_%d_%s" % [_added_places, str(e.name).to_lower().validate_node_name()]
	_interiors.add_door(id, door, yaw, str(e.get("interior", "house")), int(e.get("seed", 1)), str(e.name))
	var sign := Label3D.new()  # letrero sobre la puerta
	sign.text = str(e.name)
	sign.font_size = 72
	sign.outline_size = 12
	sign.pixel_size = 0.008
	sign.modulate = Color("#fff3d6")
	sign.position = root.position + front * (size.z / 2.0 + 0.15) + Vector3(0, minf(size.y * 0.55, 3.6), 0)
	sign.rotation.y = yaw
	add_child(sign)
	_places[str(e.name)] = door


# --- Acciones con F: lo que hay cerca, con ids para la IA ---------------------------------

## Contexto para "Hacer algo": el lugar, la hora y la lista de cosas cercanas con su id.
func action_context() -> String:
	var lines := perception(true)
	if _interiors.is_inside():
		lines.append("El jugador está DENTRO de %s (una habitación con muebles)." % _interiors.current_label())
	else:
		var near := place_near(_player.global_position)
		lines.append("El jugador está fuera%s." % ((", cerca de: " + near) if not near.is_empty() else ""))
	_targets = nearby_targets()
	var items := PackedStringArray()
	for id in _targets:
		items.append("- %s: %s, a %d m" % [id, _targets[id].label, roundi(_targets[id].pos.distance_to(_player.global_position))])
	lines.append("COSAS Y PERSONAS CERCA (usa estos ids exactos en \"target\"):\n" + ("\n".join(items) if not items.is_empty() else "- nada especial"))
	var doing := people_doing()
	if not doing.is_empty():
		lines.append("LO QUE HACE LA GENTE: " + doing + ".")
	return "\n".join(lines)


## Lo que el jugador tiene a mano, con ids estables para este momento.
func nearby_targets() -> Dictionary:
	var out := {}
	var here := _player.global_position
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		if npc.is_present() and npc.global_position.distance_to(here) < 25.0:
			var e := WorldDB.get_entity("npc", id)
			var met: bool = NPCMemory.get_mem(id).met
			out["npc:" + id] = {"kind": "npc", "label": (e.get("name", "?") if met else "una persona (%s)" % e.get("occupation", "desconocida")) \
				+ (", relación %d" % int(NPCMemory.get_mem(id).relationship) if met else ""), "pos": npc.global_position, "node": npc}
	var feats := _features.filter(func(f): return is_instance_valid(f.node) and f.pos.distance_to(Vector3(here.x, f.pos.y, here.z)) < 18.0)
	feats.sort_custom(func(a, b): return a.pos.distance_to(here) < b.pos.distance_to(here))
	var names := {"tree": "árbol", "rock": "roca", "bush": "arbusto", "crop": "cultivo"}
	for f in feats.slice(0, 6):
		out[f.id] = {"kind": f.kind, "label": names.get(f.kind, f.kind), "pos": _on_ground(f.pos), "node": f.node}
	for id in _interiors.doors():
		var d: Dictionary = _interiors.doors()[id]
		if not _interiors.is_inside() and d.pos.distance_to(here) < 25.0:
			out["door:" + id] = {"kind": "door", "label": "puerta de " + d.label, "pos": d.pos, "node": d.node}
	var n := 0
	for it in get_tree().get_nodes_in_group("interactables"):
		if n >= 8 or not (it is Interactable) or it.prompt.begins_with("Entrar") or it.prompt.begins_with("Llamar"):
			continue
		if it.global_position.distance_to(here) < 14.0:
			n += 1
			var kind := "seat" if it.prompt.begins_with("Sentarse") else "bed" if it.prompt.begins_with("Dormir") \
				else "boat" if it.owner_node is Boat else "exit" if it.prompt == "Salir" else "object"
			out["%s:%d" % [kind, n]] = {"kind": kind, "label": it.prompt.to_lower(), "pos": it.global_position, "node": it}
	var water := _water_spot()
	if water != Vector3.INF:
		out["water"] = {"kind": "water", "label": "el agua (orilla)", "pos": water, "node": null}
	for id in out:
		out[id]["id"] = id
	return out


## Resuelve el target de un paso: un id de la lista, un nombre de persona, un tipo ("tree")…
func resolve_target(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return {}
	if _targets.has(t) and (_targets[t].node == null or is_instance_valid(_targets[t].node)):
		return _targets[t]
	var fresh := nearby_targets()
	if fresh.has(t):
		return fresh[t]
	var npc_id := Actions.npc_from(t)
	if fresh.has("npc:" + npc_id):
		return fresh["npc:" + npc_id]
	var low := t.to_lower()
	var best := {}
	var best_d := INF
	for id in fresh:  # por tipo: "tree", "árbol", "silla", "puerta de la cafetería"…
		var e: Dictionary = fresh[id]
		if low == e.kind or low.contains(e.kind) or e.label.contains(low) or low.contains(e.label) \
				or ContentValidator._match_enum(low, [e.kind]) == e.kind:
			var d: float = e.pos.distance_to(_player.global_position)
			if d < best_d:
				best = e
				best_d = d
	return best

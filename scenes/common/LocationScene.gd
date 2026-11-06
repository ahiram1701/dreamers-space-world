class_name LocationScene
extends Node3D
## Lo común a todos los lugares jugables (el pueblo del Acto 0 y los lugares que crea la IA):
## interactuar con E, conversar, lo que hacen los PNJs (acompañar, irse, encerrarse, reaccionar),
## lo que el jugador cambia en el mundo (talar, construir) y las acciones con F paso a paso.
## Cada escena construye su mundo y llama a `_setup_common()` al final de su _ready.

## Palabras con las que se nombra cada tipo de interior ("me voy a la cafetería").
const KIND_WORDS := {
	"cafe": ["cafe", "cafetería", "cafeteria", "bar", "barra"], "station": ["estación", "estacion", "taller", "andén"],
	"lighthouse": ["faro"], "home": ["tu casa"], "clothes": ["tienda de ropa", "ropa"], "salon": ["peluquería", "peluqueria", "barbería", "barberia"],
	"grocery": ["abarrotes", "tienda", "súper", "super", "mercado", "colmado"], "restaurant": ["fonda", "restaurante", "comida", "taberna", "posada", "comedor"],
	"pharmacy": ["farmacia", "botica", "medicina"], "hardware": ["ferretería", "ferreteria", "herrería", "herramientas"],
	"house": ["casa", "hogar", "vivienda"], "scifi": ["módulo", "modulo", "edificio", "base"],
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
var _door_rules: Doors
var _passersby: Passersby
var _households: Households
## Quien te está llevando a un sitio: npc_id -> {label, lost_t, said_t}
var _guiding: Dictionary = {}
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
	Phone.is_near = is_with_player
	Phone.contacted_in_person.connect(func(id):
		if _npcs.has(id) and _npcs[id].is_present():
			_npcs[id].face(_player.global_position)
			_npcs[id].say(["¡Estoy aquí mismo!", "Oye, que estoy aquí al lado.", "¿Me escribes? Si estoy aquí."][randi() % 3], 4.0))
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
	_households = Households.new()
	_households.scene = self
	add_child(_households)
	# Malla de navegación del exterior: los PNJ rodean lo que hay en medio (se hornea en un hilo)
	var area := navigation_area()
	if area.size != Vector3.ZERO:
		NavBaker.bake.call_deferred(self, area, "Navegacion", true)  # (en un hilo, al cerrar la escena a medio hornear, Godot podía caerse)
	_interiors.entered.connect(func(_k, _id):
		var r: Node3D = _interiors.get("_interior").get("root")
		if r == null or not r.is_inside_tree():
			return
		NavBaker.bake(r, AABB(InteriorManager.ORIGIN - Vector3(14, 1, 14), Vector3(28, 9, 28)), "NavegacionInterior", true))
	_door_rules = Doors.new()
	_door_rules.scene = self
	_door_rules.interiors = _interiors
	add_child(_door_rules)
	_interiors.entering.connect(func(k, id): _households.prepare(id, k))
	_interiors.wants.connect(_open_look_panel)
	_interiors.entered.connect(func(k, id): _households.populate(id, k); _refresh_presence(); _add_work_spot(); _check_trespass())
	_interiors.exited.connect(func(_k, _id): _households.clear(); _refresh_presence())
	WorldClock.hour_changed.connect(func(_h):
		_refresh_presence()
		if _interiors.is_inside():
			_households.refresh(_interiors.current_door()))
	_refresh_presence()


func _process_common() -> void:
	_process_work()
	_process_guides(get_process_delta_time())
	# Te caes de sueño: de vez en cuando, un bostezo
	_yawn_t += get_process_delta_time()
	if _yawn_t > 75.0:  # (se estira y bosteza: la cabeza hacia atrás, nunca agachada)
		_yawn_t = randf_range(0.0, 30.0)
		if Body.get_need("rest") < 15.0 and _player.controls_enabled and _player.current_gesture().is_empty():
			_player.play_gesture("yawn", 1.6)
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
		if target.is_asleep():
			_wake(target)
		_start_dialogue(target)
	elif target is Interactable:
		target.use(_player)
	elif target is Boat:
		target._on_use(_player)
	elif target is Pickup:
		_pick_up(target)


# --- Casa ajena ----------------------------------------------------------------------------

## La zona exterior por la que caminan los PNJ (cada escena da la suya; vacía: sin malla).
func navigation_area() -> AABB:
	return AABB()


## ¿De quién es esta casa? Quien vive en ella y está dentro ahora ("" si nadie). Cada escena
## añade los suyos (los vecinos con rutina).
func owner_of_door(door: String) -> String:
	if _households and door == _interiors.current_door() and _interiors.current_kind() == "house":
		return _households.owner_here()
	return ""


## Puerta de la casa de alguien ("" si no tiene o no se sabe).
func home_door_of(npc_id: String) -> String:
	return Households.home_of(npc_id)


# --- Locales: comprar y pedir de comer -------------------------------------------------------

## Comprar en el local donde estás (o pedir de la carta en la fonda y la cafetería).
func _open_shop() -> void:
	var kind := _interiors.current_kind()
	var info := Shops.info(kind)
	if info.is_empty():
		return
	var staff := _households.staff_here()
	if Households.has_staff(kind) and staff == null:
		_ui.toast("No hay nadie atendiendo.")
		return
	var panel := ShopPanel.new()
	var label := _interiors.current_label()
	panel.title = label.left(1).to_upper() + label.substr(1)
	panel.items = info.items
	panel.verb = "Pedir" if info.get("menu", false) else "Comprar"
	_ui.block(true)
	add_child(panel)
	panel.closed.connect(func(): _ui.block(false))
	panel.bought.connect(func(entry: Dictionary):
		if info.get("menu", false):  # se pide y se come aquí: te lo sirven en la mesa
			if Wallet.pay(int(entry.price)):
				panel.close()
				_serve(entry, staff)
			return
		var id := Shops.buy(entry)
		if id.is_empty():
			return
		_ui.toast("Compras %s por %s." % [str(entry.name).to_lower(), Wallet.text(int(entry.price))])
		Sfx.chime(self)
		if staff:
			staff.say(["Aquí tiene.", "¿Algo más?", "Que le vaya bien.", "Gracias, vuelva pronto."][randi() % 4], 3.0)
			NPCMemory.add_event(staff.npc_id, "El jugador te compró %s." % str(entry.name).to_lower(), 1))


## Te sirven lo que pediste: si te sientas a una mesa, te lo traen ahí; si no, a la barra. Comes,
## se nota en el cuerpo y pasa el rato que se tarda en comer.
func _serve(entry: Dictionary, staff: TownNPC) -> void:
	if staff:
		staff.say("Enseguida se lo traigo. Siéntese donde guste.", 3.5)
	_ui.toast("Pediste %s (%s). Siéntate a una mesa mientras te lo traen." % [str(entry.name).to_lower(), Wallet.text(int(entry.price))])
	var door := _interiors.current_door()
	var waited := 0.0
	while waited < 20.0 and not (_player.hold_position and _player.current_gesture() == "sit"):
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if _interiors.current_door() != door:
			return  # se fue sin esperar (ya pagó: allá él)
	await get_tree().create_timer(2.5).timeout
	if _interiors.current_door() != door:
		return
	var seated: bool = _player.hold_position and _player.current_gesture() == "sit"
	var plate := AssetLibrary.instance("house_interior_pack", "Plate_%d" % (1 + randi() % 3))
	var front := _player.view_forward() if not seated else _player.facing_dir()
	var plate_at := _player.global_position + front * (0.55 if seated else 0.45) + Vector3(0, 0.8 if seated else 1.0, 0)
	var placed: Node3D = AssetLibrary.place(self, plate, plate_at, 0.04, 0.0, false) if plate else null
	if staff:
		staff.say("Aquí tiene. ¡Buen provecho!", 3.0)
	_player.play_gesture("sit_eat" if seated else "eat", 7.0)
	await get_tree().create_timer(7.0).timeout
	var power := int(entry.get("power", 20))
	if entry.effect == "nourish":
		Body.change("hunger", clampf(power * 1.5, 20.0, 70.0))
	else:
		Body.change("thirst", clampf(power * 2.0, 25.0, 70.0))
	WorldClock.advance(20 if entry.effect == "nourish" else 8)
	if is_instance_valid(placed):
		placed.queue_free()
	if seated and _player.hold_position:
		_player.play_gesture("sit")
	_ui.toast("Te terminas %s. %s" % [str(entry.name).to_lower(), ["Estaba buenísimo.", "Te sienta de maravilla.", "Justo lo que necesitabas."][randi() % 3]])
	if staff:
		NPCMemory.add_event(staff.npc_id, "Le serviste %s al jugador." % str(entry.name).to_lower(), 1)


# --- Tu aspecto en el mundo: armario, tienda de ropa, peluquería ---------------------------

func _open_look_panel(what: String) -> void:
	if what in ["shop_buy", "order"]:
		_open_shop()
		return
	var creator := CharacterCreator.new()
	creator.mode = {"wardrobe": "wardrobe", "clothes_shop": "shop", "haircut": "hair"}[what]
	creator.look = PlayerLook.current()
	match what:
		"wardrobe":
			creator.choices = PlayerLook.owned_clothes()
		"clothes_shop":
			creator.choices = PlayerLook.shop_offers(_interiors.current_door())
	_ui.block(true)
	add_child(creator)
	creator.cancelled.connect(func(): _ui.block(false))
	creator.done.connect(func(look: Dictionary, _n: String):
		_ui.block(false)
		_apply_look_panel(what, look))


func _apply_look_panel(what: String, look: Dictionary) -> void:
	var staff := _households.staff_here()
	match what:
		"wardrobe":
			PlayerLook.wear(str(look._item), PlayerLook.WARDROBE)
			_player.play_gesture("crouch", 1.2)
			_ui.toast("Te cambias de ropa. La de antes queda en el armario.")
		"clothes_shop":
			var offer: Dictionary = look._offer
			if not Wallet.pay(int(offer.price)):
				return
			var id := PlayerLook.make_clothing(offer.clothing)
			Inventory.add(id)
			PlayerLook.wear(id)
			_ui.toast("Compras %s por %s y te la pones. Lo que llevabas va en la mochila." % [offer.name.to_lower(), Wallet.text(int(offer.price))])
			if staff:
				staff.say(["¡Te queda muy bien!", "Buena elección.", "Ese color te favorece."][randi() % 3], 3.5)
				NPCMemory.add_event(staff.npc_id, "El jugador te compró %s." % offer.name.to_lower(), 1)
		"haircut":
			var price := int(look.get("_price", 0))
			if price <= 0:
				return
			if not Wallet.pay(price):
				return
			var now := PlayerLook.current()
			var dyed: bool = look.hair_color != now.get("hair_color", "")
			now["hair"] = look.hair
			now["hair_color"] = look.hair_color
			PlayerLook.save(now)
			_ui.toast("Te cortan el pelo%s. Pagas %s." % [" y te lo tiñen" if dyed else "", Wallet.text(price)])
			if staff:
				staff.say(["Listo. ¿Qué te parece?", "Te ha quedado genial.", "Mírate en el espejo."][randi() % 3], 3.5)
				NPCMemory.add_event(staff.npc_id, "Le cortaste el pelo al jugador.", 1)
	_player.rebuild_look()


## Despiertas a alguien que dormía en su casa: se levanta de un salto y no le hace gracia.
func _wake(npc: TownNPC) -> void:
	npc.unsettle()
	npc.set_emotion("angry")
	npc.face(_player.global_position)
	var met: bool = NPCMemory.get_mem(npc.npc_id).met
	npc.say("¡¿Qué...?! ¿Quién anda ahí?" if not met else "¿Qué haces aquí a estas horas? ¡Me has dado un susto!", 4.0)
	NPCMemory.add_event(npc.npc_id, "El jugador entró en tu casa mientras dormías y te despertó.", -8)


## Entras en una casa con su dueño dentro: de día y si os lleváis bien, te recibe; de noche o
## si te tiene manía, te echa (y luego lo cuenta).
func _check_trespass() -> void:
	await get_tree().create_timer(1.0).timeout
	var door := _interiors.current_door()
	var owner := owner_of_door(door)
	if owner.is_empty() or not _npcs.has(owner) or not _npcs[owner].is_present():
		return
	var npc: TownNPC = _npcs[owner]
	var forced: bool = _door_rules != null and _door_rules.forced_door == door
	if _door_rules:
		_door_rules.forced_door = ""
	if npc.is_asleep():
		return  # duermen: si no haces ruido, ni se enteran
	var mem := NPCMemory.get_mem(owner)
	var rel := int(mem.relationship)
	var h := WorldClock.hour()
	var night := h >= 23.0 or h < 7.0
	npc.face(_player.global_position)
	if _interiors.invited.has(door) and not forced:  # te abrió y te invitó: ya lo sabe
		NPCMemory.add_event(owner, "El jugador tocó a tu puerta y le invitaste a pasar.", 0)
		return
	if forced:
		npc.set_emotion("angry")
		npc.play_gesture("point", 2.5)
		npc.say("¡¿Me has roto la puerta?! ¡Fuera de mi casa ahora mismo!", 5.0)
		_door_rules.caught_inside(owner)
		_life.witness("el jugador forzó la puerta de casa de %s" % WorldDB.get_entity("npc", owner).get("name", "alguien"), npc.global_position, [owner])
		return
	if not night and rel >= 0 and not bool(mem.get("met", false)):  # alguien que no conoce, en su casa
		npc.set_emotion("worried")
		npc.say("¿Hola? ¿Quién eres? ¿Qué haces en mi casa?", 5.0)
		NPCMemory.add_event(owner, "El jugador (aún no le conocías) entró en tu casa sin llamar.", -3)
		return
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
	_player.play_gesture("wipe" if "caf" in str(j.place_label) else "hammer", 999.0, true)  # las herramientas del trabajo
	await _interiors._fade_to(1.0)
	var r := Jobs.work_shift()
	var summary := await StoryDirector.shift_summary(j, r, perception(true))
	await get_tree().create_timer(0.5).timeout
	_player.stop_gesture()
	await _interiors._fade_to(0.0)
	_ui.block(false)
	var late := "  (llegaste %d min tarde)" % r.late_minutes if int(r.get("late_minutes", 0)) > 30 else ""
	_ui.toast("%s\nCobras %s por el turno.%s" % [summary, Wallet.text(int(r.get("paid", 0))), late], "money")


## ¿Está esa persona aquí contigo? (en tu mismo interior, o fuera a menos de 30 m)
func is_with_player(npc_id: String) -> bool:
	if not _npcs.has(npc_id) or not _npcs[npc_id].is_present():
		return false
	var npc: TownNPC = _npcs[npc_id]
	var inside_npc := npc.global_position.y < InteriorManager.ORIGIN.y + 100.0
	if inside_npc != _interiors.is_inside():
		return false
	return npc.global_position.distance_to(_player.global_position) < (40.0 if inside_npc else 30.0)


## Llamar a alguien por el celular: la misma conversación, pero a distancia.
func start_call(npc_id: String) -> void:
	_ui.block(true)
	_player.play_gesture("call", 600.0)
	if _npcs.has(npc_id) and _npcs[npc_id].is_present():
		_npcs[npc_id].play_gesture("call", 600.0)  # se le ve con el celular en la oreja
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
	# Queda constancia de que acabáis de hablar (y de qué), para que nada después lo contradiga
	NPCMemory.set_fields(npc_id, {"last_talk": WorldClock.absolute_minutes()})
	var said := _dialogue.last_player_text.left(120)
	if _dialogue.call_mode:
		NPCMemory.add_event(npc_id, "Hablaste por teléfono con el jugador%s." % ((". Lo último que te dijo: «%s»" % said) if not said.is_empty() else ""))
	else:
		var where := _interiors.current_label() if _interiors.is_inside() else place_near(_player.global_position)
		NPCMemory.add_event(npc_id, "Acabas de hablar con el jugador en persona%s%s." % [
			(" (en %s)" % where) if not where.is_empty() else "", (". Lo último que te dijo: «%s»" % said) if not said.is_empty() else ""])
	if _dialogue.call_mode:
		_player.stop_gesture()
		if _npcs.has(npc_id):
			_npcs[npc_id].stop_gesture()  # cuelga él también
	elif _door_rules:
		_door_rules.on_dialogue_closed(npc_id)  # en el umbral: vuelve dentro (y si te invitó, pasas)
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


## Qué prendas son cada estilo de ropa (para que nadie te pida que dejes un abrigo que no llevas).
const OUTFIT_WORDS := {"casual": "camiseta y pantalón", "street": "sudadera y pantalón de calle",
	"formal": "camisa, saco y pantalón de vestir", "work_uniform": "ropa de trabajo"}


## Lo que se ve del jugador: su ropa y si va mojado o sucio (los demás lo notan y lo comentan).
func _player_looks() -> String:
	var worn := PlayerLook.wearing()
	var look := PlayerLook.current()
	if not worn.is_empty() and WorldDB.get_entity("item", worn).has("clothing"):
		look = WorldDB.get_entity("item", worn).clothing
	var outfit := str(look.get("outfit", "casual"))
	var c1: String = PlayerLook.COLOR_NAMES.get(str(look.get("primary_color", "")), "")
	var c2: String = PlayerLook.COLOR_NAMES.get(str(look.get("secondary_color", "")), "")
	var colors := c1 if c2.is_empty() or c2 == c1 else "%s y %s" % [c1, c2]
	var clothes: String = OUTFIT_WORDS.get(outfit, "ropa normal") + ((" (%s)" % colors) if not colors.is_empty() else "")
	var parts := PackedStringArray(["lleva %s%s; NADA más: ni abrigo, ni chamarra, ni sombrero, ni mochila" % [
		clothes, "" if outfit == "formal" else ", sin saco"]])
	if _player and _player.get("_lamp") and _player.get("_lamp").visible:
		parts.append("lleva una linterna encendida en la mano")
	if Body.wet > 0.6:
		parts.append("está empapado/a")
	elif Body.wet > 0.25:
		parts.append("va algo mojado/a")
	if Body.dirt > 0.5:
		parts.append("lleva la ropa manchada de tierra")
	elif Body.dirt > 0.2:
		parts.append("va algo sucio/a")
	if Body.get_need("hygiene") < 15.0:
		parts.append("huele mal")
	return ", ".join(parts) + "."


## Cómo es cada edificio de aquí (una línea por tipo), para que nadie invente una puerta trasera.
func places_described() -> String:
	var seen := {}
	var out := PackedStringArray()
	for id in _interiors.doors():
		var d: Dictionary = _interiors.doors()[id]
		var kind: String = d.kind
		if seen.has(kind) or not InteriorBuilder.DESCRIPTIONS.has(kind):
			continue
		seen[kind] = true
		var who := "las casas del pueblo" if kind == "house" else str(d.label)
		out.append("%s: %s" % [who, InteriorBuilder.DESCRIPTIONS[kind]])
	return "; ".join(out) + "."


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
	if _interiors.is_inside() and home_door_of(npc_id) == _interiors.current_door():
		state += " Estás en TU casa%s." % ((" (estabas %s)" % npc.activity) if npc and not npc.activity.is_empty() else "")
	lines.append(state)
	lines.append("CÓMO VES AL JUGADOR: " + _player_looks())
	if _door_rules and not _door_rules.context_for(npc_id).is_empty():
		lines.append(_door_rules.context_for(npc_id))
	var people := PackedStringArray()
	for id in _npcs:
		if id != npc_id and _npcs[id].is_present() and _npcs[id].global_position.distance_to(_player.global_position) < 12.0:
			people.append(WorldDB.get_entity("npc", id).get("name", "?"))
	if not people.is_empty():
		lines.append("También hay cerca: %s." % ", ".join(people))
	var look := player_appearance()
	if not look.is_empty():
		lines.append(look)
	var spots := PackedStringArray(_places.keys())
	for id in _interiors.doors():
		var label: String = _interiors.doors()[id].label
		if not (label in spots) and not label.begins_with("una ") and not label.begins_with("un "):
			spots.append(label)
	lines.append("SITIOS DE ESTE LUGAR (a los que puedes ir o llevarle): " + ", ".join(spots) + ".")
	lines.append("CÓMO SON (no inventes puertas, cuartos ni pasadizos que no estén aquí): " + places_described())
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
					npc_go(npc_id, dest)
		"approach":
			if not npc.is_present() and not NPCMemory.is_locked_in(npc_id):  # sale de donde estaba para venir
				var door := _interiors.door_position(NPCMemory.inside(npc_id))
				NPCMemory.come_out(npc_id)
				npc.set_present(true)
				if door != Vector3.INF:
					npc.global_position = InteriorManager.free_spot_near(self, door, Vector3.ZERO, [npc]) + Vector3(0, 0.3, 0)
			npc_go(npc_id, _near_player(npc, 1.4) if InteriorManager.is_interior_pos(npc.global_position) == _interiors.is_inside() else _player.global_position)
		"guide_player":
			guide(npc_id, str(a.get("target", a.get("item_name", ""))))
		"invite_in":
			if _door_rules:
				_door_rules.invite(npc_id)
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
		"guide":
			guide(npc_id, str(a.get("item_name", a.get("text", ""))))
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
	if InteriorManager.is_interior_pos(npc.global_position) and _interiors.is_inside():
		dest = _interiors.door_position(_interiors.current_door()) + Vector3(randf_range(-6, 6), 0, randf_range(8, 14))  # sale y se aleja
	_errands[npc_id] = true
	NPCMemory.add_event(npc_id, "Te marchaste y dejaste al jugador ahí.")
	npc_go(npc_id, dest, func(): _errands.erase(npc_id))


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
	var stay := float(minutes) * 6.0 if minutes > 0 else (90.0 if locked else 150.0)
	if _interiors.current_door() == door:  # ya estás dentro de ese sitio: entra contigo
		_enter_building(npc_id, door, locked, stay)
		return
	npc_go(npc_id, _interiors.door_position(door), func(): _enter_building(npc_id, door, locked, stay))


func _enter_building(npc_id: String, door: String, locked: bool, minutes: float) -> void:
	_errands.erase(npc_id)
	var label := _interiors.door_label(door)
	NPCMemory.go_inside(npc_id, door, label, minutes, locked)
	NPCMemory.add_event(npc_id, "Entraste en %s%s." % [label, " y cerraste por dentro para no ver al jugador" if locked else ""])
	Sfx.at(self, "door", _interiors.door_position(door) + Vector3(0, 1, 0))
	_refresh_presence()


# --- Moverse de verdad: cruzando puertas ----------------------------------------------------

## Lleva a un PNJ a `dest` caminando, aunque haya que salir o entrar por una puerta: los
## interiores están lejos del mundo, así que se camina hasta la salida, se aparece fuera junto a
## la puerta y se sigue (y al revés para entrar donde estás tú).
func npc_go(npc_id: String, dest: Vector3, on_arrive: Callable = Callable(), run: bool = false, pace: float = 0.0) -> void:
	if not _npcs.has(npc_id):
		return
	var npc: TownNPC = _npcs[npc_id]
	var npc_in := InteriorManager.is_interior_pos(npc.global_position)
	var dest_in := InteriorManager.is_interior_pos(dest)
	var door := _interiors.current_door()
	if npc_in and not dest_in and _interiors.is_inside():
		# Salir: hasta la puerta de dentro y aparecer fuera
		var go_out := func():
			if not is_instance_valid(npc):
				return
			var outside := _interiors.door_position(door)
			var yaw: float = _interiors.doors().get(door, {}).get("yaw", 0.0)
			var out_dir := Vector3(sin(yaw), 0, cos(yaw))
			npc.global_position = InteriorManager.free_spot_near(self, (outside if outside != Vector3.INF else dest) + out_dir * 1.5, out_dir, [npc, _player]) + Vector3(0, 0.3, 0)
			Sfx.at(self, "door", npc.global_position)
			_walk(npc, dest, on_arrive, run, pace)
		npc.walk_to(_interiors.exit_position(), run, pace)
		npc.arrived.connect(go_out, CONNECT_ONE_SHOT)
		# Si sales tú antes de que llegue a la puerta, sale contigo (el interior desaparece)
		var on_exit := func(_k, _id):
			if is_instance_valid(npc) and InteriorManager.is_interior_pos(npc.global_position):
				if npc.arrived.is_connected(go_out):
					npc.arrived.disconnect(go_out)
				go_out.call()
		_interiors.exited.connect(on_exit, CONNECT_ONE_SHOT)
	elif not npc_in and dest_in and _interiors.is_inside():
		# Entrar donde estás tú: hasta la puerta de fuera y aparecer por la entrada
		npc.walk_to(_interiors.door_position(door), run, pace)
		npc.arrived.connect(func():
			if is_instance_valid(npc) and _interiors.current_door() == door:
				npc.global_position = _interiors.entry_position() + Vector3(0, 0.3, 0.8)
				_walk(npc, dest, on_arrive, run, pace), CONNECT_ONE_SHOT)
	else:
		_walk(npc, dest, on_arrive, run, pace)


func _walk(npc: TownNPC, dest: Vector3, on_arrive: Callable, run: bool, pace: float = 0.0) -> void:
	npc.walk_to(dest, run, pace)
	if on_arrive.is_valid():
		npc.arrived.connect(on_arrive, CONNECT_ONE_SHOT)


# --- Llevarte a un sitio ------------------------------------------------------------------

## Un PNJ te lleva a un sitio: "Sígueme", camina (te espera si te quedas atrás) y al llegar te lo señala.
func guide(npc_id: String, target: String) -> void:
	if not _npcs.has(npc_id):
		return
	var npc: TownNPC = _npcs[npc_id]
	var dest := place_position(target)
	var label := target
	if dest == Vector3.INF:
		var door := _door_for_text(target)
		if not door.is_empty():
			dest = _interiors.door_position(door)
			label = _interiors.door_label(door)
	if dest == Vector3.INF or target.strip_edges().is_empty():
		npc.say("Uy, no sé dónde queda eso, la verdad.", 4.0)
		NPCMemory.add_event(npc_id, "El jugador te pidió que le llevaras a «%s», pero no sabes dónde está." % target)
		return
	NPCMemory.set_fields(npc_id, {"following": false})
	_errands[npc_id] = true
	_guiding[npc_id] = {"label": label, "lost_t": 0.0, "said_t": 0.0}
	npc.say("Sígueme, es por aquí.", 3.5)
	npc.play_gesture("point", 1.5)
	# A paso de quien acompaña a alguien (más ágil que un paseo)
	npc_go(npc_id, _on_ground(dest) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), func(): _guide_arrived(npc_id), false, 2.6)


## Puerta que nombra un texto, sin caer en la casa del PNJ si no coincide nada.
func _door_for_text(target: String) -> String:
	var t := target.to_lower()
	for id in _interiors.doors():
		var label: String = str(_interiors.doors()[id].label).to_lower()
		if not t.is_empty() and (t.contains(str(id).to_lower()) or t.contains(label.trim_prefix("la ").trim_prefix("el ")) or label.contains(t)):
			return id
	return ""


func _guide_arrived(npc_id: String) -> void:
	if not _guiding.has(npc_id):
		return
	var g: Dictionary = _guiding[npc_id]
	_guiding.erase(npc_id)
	_errands.erase(npc_id)
	var npc: TownNPC = _npcs[npc_id]
	npc.face(_player.global_position)
	npc.play_gesture("point", 2.5)
	npc.say("Aquí es: %s." % g.label, 4.5)
	NPCMemory.add_event(npc_id, "Llevaste al jugador hasta %s." % g.label, 2)


## Mientras te lleva: si te quedas atrás, te espera; si te pierde mucho rato, lo deja.
func _process_guides(delta: float) -> void:
	for id in _guiding.keys():
		var npc: TownNPC = _npcs.get(id)
		if npc == null or not is_instance_valid(npc):
			_guiding.erase(id)
			continue
		var g: Dictionary = _guiding[id]
		var same_side := InteriorManager.is_interior_pos(npc.global_position) == _interiors.is_inside()
		var d := npc.global_position.distance_to(_player.global_position) if same_side else 999.0
		g.said_t = float(g.said_t) + delta
		if d > 9.0 and not npc.is_paused():
			npc.pause_walk()
			npc.face(_player.global_position)
		elif d < 5.0 and npc.is_paused():
			npc.resume_walk()
		if npc.is_paused() and float(g.said_t) > 7.0 and same_side and d < 30.0:
			g.said_t = 0.0
			npc.say(["¿Vienes?", "Por aquí.", "¡Eh, que es por aquí!"][randi() % 3], 3.0)
		g.lost_t = float(g.lost_t) + delta if d > 45.0 else 0.0
		if float(g.lost_t) > 60.0:  # te perdió: lo deja
			_guiding.erase(id)
			_errands.erase(id)
			npc.resume_walk()
			npc.stop()
			NPCMemory.add_event(id, "Ibas a llevar al jugador a %s, pero se quedó atrás y lo perdiste." % g.label, -1)
			if bool(NPCMemory.get_mem(id).get("phone", false)):
				Phone.deliver(id, "Oye, te perdí de vista. ¿Sigues queriendo ir a %s?" % g.label)


## Puerta a la que se refiere un texto ("la cafetería", "casa"…), o la de casa del PNJ.
func _door_for(npc_id: String, target: String) -> String:
	var t := target.to_lower()
	var doors := _interiors.doors()
	if not t.is_empty():
		for id in doors:
			var label: String = str(doors[id].label).to_lower()
			if label.begins_with("una ") or label.begins_with("un "):
				continue  # "una casa" no nombra ninguna en concreto
			if t.contains(str(id).to_lower()) or t.contains(label.trim_prefix("la ").trim_prefix("el ")):
				return id
		var own := home_door_of(npc_id)
		if not own.is_empty() and KIND_WORDS.house.any(func(w): return t.contains(w)) and not t.contains("tu "):
			return own  # "me voy a casa", "a mi casa": la suya
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
				var was: String = str(w.get("door", ""))
				_interiors.set_locked(was, "")
				NPCMemory.come_out(id)
				if npc.is_present() and _interiors.current_door() == was and InteriorManager.is_interior_pos(npc.global_position):
					# Estás dentro con él: no desaparece, se despide y sale por la puerta
					npc.say(["Bueno, me voy.", "Me tengo que ir.", "Hasta luego."][randi() % 3], 3.0)
					_errands[id] = true
					npc_go(id, _interiors.door_position(was) + Vector3(randf_range(-4, 4), 0, randf_range(5, 9)), func(): _errands.erase(id))
				elif not npc.is_present():
					var p := _interiors.door_position(str(w.get("door", "")))
					npc.set_present(true)
					if p != Vector3.INF and not _interiors.is_inside():
						npc.global_position = InteriorManager.free_spot_near(self, p, Vector3.ZERO, [npc]) + Vector3(0, 0.3, 0)
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
	Decor.fade_label(sign)
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

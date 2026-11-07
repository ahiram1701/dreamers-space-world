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
	Creations.vehicle_builder = Vehicle.build
	for entry in Creations.all_here():  # lo creado con el agente creador
		Creations.build(self, entry)
	_park_arrival_ship.call_deferred()
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
	StoryDirector.people_facts = people_facts
	StoryDirector.place_names = place_names
	_interiors.message.connect(_ui.toast)
	_interiors.fixture_used.connect(_on_fixture_used)
	_interiors.sat_down.connect(_on_sat)
	_interiors.slept.connect(_on_slept)
	_interiors.sleep_check = _sleep_check
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
	elif target.has_method("_on_use"):  # vehículos, naves
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


## Te sirven lo que pediste: el mesero va a la barra, lo prepara, te lo trae en una bandeja a tu
## mesa y te lo deja delante (si no te sientas, en la barra). Comes, se nota en el cuerpo y pasa
## el rato que se tarda en comer.
func _serve(entry: Dictionary, staff: TownNPC) -> void:
	_serving = true
	if staff:
		staff.say("Enseguida se lo traigo." + ("" if _player.hold_position else " Siéntese donde guste."), 3.5)
	_ui.toast("Pediste %s (%s).%s" % [str(entry.name).to_lower(), Wallet.text(int(entry.price)), "" if _player.hold_position else " Siéntate a una mesa mientras te lo traen."])
	var door := _interiors.current_door()
	var bar: Vector3 = _interiors.npc_spot(0)
	if staff and bar != Vector3.INF:  # a la barra a prepararlo
		staff.walk_to(bar)
		await _await_arrival(staff, 8.0)
	var waited := 0.0
	while waited < 20.0 and not (_player.hold_position and _player.current_gesture() == "sit"):
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if _interiors.current_door() != door:
			_serving = false
			return  # se fue sin esperar (ya pagó: allá él)
	if staff and is_instance_valid(staff):
		staff.set_activity("preparando el pedido", "cook")
		staff.play_gesture("cook", 4.0)
	await get_tree().create_timer(4.5).timeout
	if _interiors.current_door() != door:
		_serving = false
		return
	var seated: bool = _player.hold_position and _player.current_gesture() == "sit"
	if staff and is_instance_valid(staff):  # te lo trae en la bandeja
		staff.hold("proc:tray", "una bandeja", 0.4, 0.5)
		staff.set_activity("llevando un pedido", "")
		staff.walk_to(_near_player(staff, 0.9))
		await _await_arrival(staff, 12.0)
		if is_instance_valid(staff):
			staff.face(_player.global_position)
			staff.play_gesture("give", 1.6)
	if _interiors.current_door() != door:
		_serving = false
		return
	var plate := AssetLibrary.instance("house_interior_pack", "Plate_%d" % (1 + randi() % 3))
	var front := _player.view_forward() if not seated else _player.facing_dir()
	var plate_at := _player.global_position + front * (0.55 if seated else 0.45) + Vector3(0, 0.8 if seated else 1.0, 0)
	var placed: Node3D = AssetLibrary.place(self, plate, plate_at, 0.04, 0.0, false) if plate else null
	if staff and is_instance_valid(staff):
		staff.say("Aquí tiene. ¡Buen provecho!", 3.0)
		staff.hold("", "")
		var back := _waiter_spot()
		var waiter := staff
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(waiter) and back != Vector3.INF:
				waiter.walk_to(back)
				await waiter.arrived
				if is_instance_valid(waiter):
					waiter.settle(back + Vector3(0, 0.1, 0), back + Vector3(0, 0, 2), "", "atendiendo"))
	_serving = false
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
	if staff and is_instance_valid(staff):
		NPCMemory.add_event(staff.npc_id, "Le serviste %s al jugador." % str(entry.name).to_lower(), 1)


var _serving := false


## Dónde espera quien atiende (en la cafetería, en la sala: la barra es de Teo).
func _waiter_spot() -> Vector3:
	return _interiors.npc_spot(1 if _interiors.current_kind() == "cafe" else 0)


## Espera a que alguien llegue a donde iba (o se acabe el tiempo).
func _await_arrival(npc: TownNPC, limit: float) -> void:
	var t := 0.0
	while t < limit and is_instance_valid(npc) and npc.is_walking():
		await get_tree().create_timer(0.25).timeout
		t += 0.25


## Te sientas a una mesa de la cafetería o la fonda: el mesero viene a tomarte nota.
func _on_sat(seat: Node3D) -> void:
	var kind := _interiors.current_kind()
	if not Shops.info(kind).get("menu", false) or _serving:
		return
	var waiter := _households.staff_here()
	if waiter == null or waiter.talking:
		return
	_serving = true
	var door := _interiors.current_door()
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(waiter) or _interiors.current_door() != door or not _player.hold_position:
		_serving = false
		return
	waiter.walk_to(_near_player(waiter, 1.0))
	await _await_arrival(waiter, 12.0)
	if not is_instance_valid(waiter) or not _player.hold_position or _interiors.current_door() != door:
		_serving = false
		return
	waiter.face(_player.global_position)
	waiter.say(["¡Buenas! ¿Qué le traigo?", "Hola, ¿ya sabe qué va a tomar?", "Buenas tardes. Aquí tiene la carta."][randi() % 3], 3.5)
	_serving = false
	_open_shop()
	var panel: Node = get_children().filter(func(c): return c is ShopPanel).back() if get_children().any(func(c): return c is ShopPanel) else null
	if panel:
		await panel.closed
	if is_instance_valid(waiter) and not _serving:  # no pidió nada: vuelve a su sitio
		waiter.say("Cuando quiera, me llama.", 2.5)
		var bar: Vector3 = _waiter_spot()
		if bar != Vector3.INF:
			waiter.walk_to(bar)
			await waiter.arrived
			if is_instance_valid(waiter) and not _serving:
				waiter.settle(bar + Vector3(0, 0.1, 0), bar + Vector3(0, 0, 2), "", "atendiendo")


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


## Entras en una casa con su dueño DENTRO (no basta con que esté por el pueblo): de día y si os
## lleváis bien, te recibe; de noche o si te tiene manía, te echa (y luego lo cuenta). Si forzaste
## la puerta y no había nadie, al volver solo encuentra la puerta forzada: no sabe que fuiste tú.
func _check_trespass() -> void:
	await get_tree().create_timer(1.0).timeout
	var door := _interiors.current_door()
	var owner := owner_of_door(door)
	var forced: bool = _door_rules != null and _door_rules.forced_door == door
	if _door_rules:
		_door_rules.forced_door = ""
	var home_inside: bool = not owner.is_empty() and _npcs.has(owner) and _npcs[owner].is_present() \
		and InteriorManager.is_interior_pos(_npcs[owner].global_position) and _npcs[owner].global_position.distance_to(_player.global_position) < 30.0
	if not home_inside:
		if forced:
			for id in residents_of(door):
				NPCMemory.add_event(id, "Al volver a casa encontraste la puerta forzada. No sabes quién fue.", 0, true)
		return
	var npc: TownNPC = _npcs[owner]
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


## Quién vive en una casa (la familia, o el dueño de un sitio como el faro).
func residents_of(door: String) -> Array:
	var out: Array = Households.members(door).duplicate()
	var owner := owner_of_door(door)
	if not owner.is_empty() and not owner in out:
		out.push_front(owner)
	return out.filter(func(id): return not str(id).is_empty() and WorldDB.get_entity("npc", str(id)).size() > 0)


## Quien está ahora mismo en este interior contigo (despierto o no).
func people_inside() -> Array:
	var out := []
	for npc in _npcs.values():
		if is_instance_valid(npc) and npc.is_present() and InteriorManager.is_interior_pos(npc.global_position) \
				and npc.global_position.distance_to(_player.global_position) < 30.0:
			out.append(npc)
	return out


func _first_name(id: String) -> String:
	return str(WorldDB.get_entity("npc", id).get("name", "alguien")).split(" ")[0]


## Comes de la nevera, bebes o te duchas en una casa que no es la tuya.
func _on_fixture_used(what: String, door: String) -> void:
	if _interiors.current_kind() == "home":
		return
	var residents := residents_of(door)
	if residents.is_empty():
		return
	var verb: String = {"eat": "comió de tu nevera", "drink": "bebió agua en tu cocina", "shower": "se duchó en tu baño"}.get(what, "usó tus cosas")
	if _interiors.invited.has(door):
		NPCMemory.add_event(residents[0], "El jugador %s (le habías invitado a pasar)." % verb, 0 if what == "drink" else 1)
		return
	var watchers := people_inside().filter(func(n): return not n.is_asleep() and not n.has_meta("passerby"))
	if not watchers.is_empty():
		var w: TownNPC = watchers[0]
		w.face(_player.global_position)
		w.set_emotion("angry" if what != "drink" else "worried")
		w.say({"eat": "¡Oye! ¿Te estás comiendo nuestra comida?", "drink": "¿Y tú qué haces en mi cocina?", "shower": "¡¿Te estás duchando en MI baño?!"}.get(what, "¡Oye!"), 4.0)
		for n in watchers:
			NPCMemory.add_event(n.npc_id, "Viste al jugador: %s, sin pedir permiso." % verb.replace("tu ", "la ").replace("tus ", "las "), -3 if what == "drink" else -10)
		for id in residents:
			if not watchers.any(func(n): return n.npc_id == id):
				NPCMemory.add_event(id, "Te contaron que el jugador %s sin permiso." % verb, -6 if what != "drink" else -2, true)
		return
	if what == "eat":  # nadie le vio: al volver, falta comida (sin saber quién fue)
		NPCMemory.add_event(residents[0], "Al volver notaste que faltaba comida de tu nevera. No sabes quién fue.", 0, true)


## Antes de dormir en una cama: ¿es de alguien que está durmiendo ahí? ¿llegará a acostarse?
func _sleep_check(door: String, bed: Node3D, minutes: float) -> Dictionary:
	if _interiors.current_kind() == "home":
		return {}
	var owner := _bed_owner(door, bed)
	if owner.is_empty():
		return {}
	for n in people_inside():
		if n.npc_id == owner and n.is_asleep() and n.global_position.distance_to(bed.global_position) < 2.0:
			return {"refuse": "Ahí está durmiendo %s." % _first_name(owner)}
	if not NPCMemory.inside(owner).is_empty() and NPCMemory.inside(owner) != door:
		return {}  # está fuera (en la clínica, de viaje): esta noche no viene
	var bedtime := 22.5 + float(hash(owner) % 3) * 0.5
	var until := fposmod(bedtime - WorldClock.hour(), 24.0) * 60.0
	if until < minutes:
		return {"minutes": maxf(until, 20.0), "by": owner}
	return {}


## La cama es de quien vive en la casa (la primera, del dueño; las demás, del resto de la familia).
func _bed_owner(door: String, bed: Node3D) -> String:
	var residents := residents_of(door)
	if residents.is_empty():
		return ""
	var beds: Array = _interiors.get("_interior").get("beds") if _interiors.get("_interior") else []
	var i := 0
	for k in beds.size():
		if beds[k].node == bed:
			i = k
	return str(residents[i % residents.size()])


## Dormiste en una cama ajena: si llega su dueño, te despierta (y reacciona según os llevéis); si
## alguien de la casa te vio, se lo cuenta; si nadie, al volver encuentra la cama deshecha.
func _on_slept(door: String, bed: Node3D, _minutes: float, by: String) -> void:
	if _interiors.current_kind() == "home" or not _interiors.is_inside():
		return
	var owner := by if not by.is_empty() else _bed_owner(door, bed)
	if owner.is_empty():
		return
	if not by.is_empty():
		var npc: TownNPC = _npcs.get(by)
		if npc == null or not is_instance_valid(npc):
			var entity := WorldDB.get_entity("npc", by)
			if entity.is_empty():
				return
			npc = TownNPC.new()
			add_child(npc)
			npc.setup(entity)
			npc.redress(false)
			_npcs[by] = npc
			_households.spawned()[by] = npc
		npc.set_present(true)
		npc.unsettle()
		npc.global_position = InteriorManager.free_spot_near(self, bed.global_position + bed.global_basis.z * 1.6, Vector3.ZERO, [npc, _player]) + Vector3(0, 0.1, 0)
		npc.face(_player.global_position)
		var rel := int(NPCMemory.get_mem(by).relationship)
		if rel >= 40:
			npc.set_emotion("surprised")
			npc.say("¿Te quedaste dormido/a en mi cama? Bueno… venga, levántate, que me toca a mí.", 5.0)
			NPCMemory.add_event(by, "Al ir a acostarte encontraste al jugador dormido en tu cama. Te sorprendió, pero no te molestó mucho.", -2)
		elif rel >= 0:
			npc.set_emotion("angry")
			npc.play_gesture("point", 2.0)
			npc.say("¡¿Qué haces en mi cama?! ¡Levántate ahora mismo!", 5.0)
			NPCMemory.add_event(by, "Al ir a acostarte encontraste al jugador dormido en TU cama, sin permiso.", -15)
		else:
			npc.set_emotion("angry")
			npc.play_gesture("point", 2.5)
			npc.say("¡Fuera de mi cama y de mi casa! ¡Voy a contárselo a todo el mundo!", 5.0)
			NPCMemory.add_event(by, "Encontraste al jugador dormido en tu cama, sin permiso. Ya te caía mal.", -25)
		_ui.toast("%s te despierta: es su cama." % _first_name(by))
		return
	var watchers := people_inside().filter(func(n): return not n.is_asleep() and not n.has_meta("passerby"))
	if not watchers.is_empty():
		for n in watchers:
			NPCMemory.add_event(n.npc_id, "Viste al jugador dormir en la cama de %s, sin permiso." % _first_name(owner), -5)
		if not watchers.any(func(n): return n.npc_id == owner):
			NPCMemory.add_event(owner, "Te contaron que el jugador durmió en tu cama sin permiso.", -10, true)
		return
	NPCMemory.add_event(owner, "Al volver encontraste tu cama deshecha, como si alguien hubiera dormido en ella. No sabes quién.", 0, true)


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
	if not _npcs.has(npc_id):
		return
	_npcs[npc_id].set_emotion(turn.get("emotion", "neutral"))
	# Lo que narra que hace, lo hace; lo que no se puede hacer, no se muestra
	var action := str(turn.get("action", ""))
	if action.is_empty():
		return
	var mapped := ActionMapper.map(action, known_names())
	if str(mapped.shown).is_empty():
		turn.erase("action")
		return
	turn["action"] = mapped.shown
	var already: Array = turn.get("actions", []).filter(func(a): return a.get("type", "") == "play").map(func(a): return _gesture(a.get("target", "")))
	perform_steps(npc_id, mapped.steps.filter(func(s): return s.type != "gesture" or not (s.gesture in already)))


## Nombres de lo que hay aquí (sitios, puertas, cosas a la vista, gente): a qué puede mirar o
## hacia dónde puede caminar alguien.
func known_names() -> Array:
	var out := []
	for p in _places:
		out.append(str(p))
	for id in _interiors.doors():
		out.append(str(_interiors.doors()[id].label))
	for m in get_tree().get_nodes_in_group("landmark"):
		var l := str(m.get_meta("label", ""))
		out.append(l.get_slice(" ", 0) if l.split(" ").size() > 3 else l)
	for id in _npcs:
		out.append(str(WorldDB.get_entity("npc", id).get("name", "")).get_slice(" ", 0))
	out.append_array(["ventana", "puerta", "barra", "mar", "cielo", "faro", "calle"])
	return out


## Dónde está algo por su nombre (sitio, puerta, cosa, persona): Vector3.INF si no se sabe.
func position_of_name(name: String, near: Vector3) -> Vector3:
	var low := name.to_lower()
	var p := place_position(name)
	if p != Vector3.INF:
		return p
	for id in _interiors.doors():
		if str(_interiors.doors()[id].label).to_lower().contains(low):
			return _interiors.door_position(id)
	var best := Vector3.INF
	for m in get_tree().get_nodes_in_group("landmark"):
		if str(m.get_meta("label", "")).to_lower().contains(low):
			var q: Vector3 = (m as Node3D).global_position
			if best == Vector3.INF or q.distance_to(near) < best.distance_to(near):
				best = q
	if best != Vector3.INF:
		return best
	for id in _npcs:
		if str(WorldDB.get_entity("npc", id).get("name", "")).to_lower().begins_with(low):
			return _npcs[id].global_position
	return Vector3.INF


## Un PNJ hace, uno tras otro, los pasos de su acotación (ActionMapper).
func perform_steps(npc_id: String, steps: Array) -> void:
	for s in steps:
		var npc: TownNPC = _npcs.get(npc_id)
		if npc == null or not is_instance_valid(npc) or not npc.is_present():
			return
		match str(s.type):
			"ride":
				npc_board(npc_id)
				await get_tree().create_timer(1.5).timeout
			"get_out":
				var v: Node3D = npc.riding_vehicle()
				if v:
					npc.get_off(v.global_position + v.global_basis.x * 2.0 + Vector3(0, 0.3, 0))
			"gesture":
				npc.play_gesture(str(s.gesture), 2.6)
				await get_tree().create_timer(2.2).timeout
			"face":
				var t := str(s.target)
				var at := _player.global_position if t == "player" else position_of_name(t, npc.global_position)
				if t == "away":
					at = npc.global_position + (npc.global_position - _player.global_position).normalized() * 5.0
				if at != Vector3.INF:
					npc.face(at)
					await get_tree().create_timer(1.4).timeout
					if is_instance_valid(npc):
						npc.face(_player.global_position)
			"walk":
				var at := position_of_name(str(s.target), npc.global_position)
				if at != Vector3.INF:
					# Solo unos pasos: no se va de la conversación
					var to := npc.global_position + (at - npc.global_position).limit_length(4.0)
					npc.walk_to(_on_ground(to))
					await get_tree().create_timer(2.5).timeout
					if is_instance_valid(npc):
						npc.face(_player.global_position)
			"emotion":
				npc.set_emotion(str(s.emotion))
			"wear", "remove":
				var layers: Array = npc.layers.duplicate()
				var id := str(s.garment)
				if s.type == "remove":
					layers = layers.filter(func(l): return str(l.id) != id)
				elif not Wardrobe.wears(layers, id):
					var rng := RandomNumberGenerator.new()
					rng.seed = hash(npc_id + id)
					layers.append(Wardrobe._layer(id, rng))
				npc.play_gesture("pat", 1.5)
				npc.set_layers(layers)
				await get_tree().create_timer(1.2).timeout


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


## Qué está haciendo la gente cercana, dónde está de verdad, qué lleva en las manos y qué ropa
## lleva: la IA no puede ponerle a nadie una escoba que no tiene ni situarle donde no está.
func people_doing(exclude: String = "", radius: float = 25.0) -> String:
	var out := PackedStringArray()
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		if id == exclude or not npc.is_present() or npc.global_position.distance_to(_player.global_position) > radius:
			continue
		var who: String = WorldDB.get_entity("npc", id).get("name", "?") if NPCMemory.get_mem(id).met else "alguien (%s)" % WorldDB.get_entity("npc", id).get("occupation", "?")
		out.append("%s: %s" % [who, npc_described(npc)])
	return "\n- ".join(out)


## Una persona tal y como está ahora: dónde, qué hace, qué lleva en la mano y qué viste.
func npc_described(npc: TownNPC) -> String:
	var where := where_is(npc.global_position)
	var vehicle: Node3D = npc.riding_vehicle()
	if vehicle:
		where = "dentro de %s" % vehicle.call("the_name")
	return "%s; %s; %s; viste %s" % [where, npc.doing(), npc.held_desc(), Wardrobe.describe(WorldDB.get_entity("npc", npc.npc_id).get("appearance", {}), npc.layers).split(";")[0]]


## Dónde está un punto, en palabras: «dentro de la cafetería», «fuera, junto al muelle».
func where_is(pos: Vector3) -> String:
	if InteriorManager.is_interior_pos(pos):
		return "dentro de %s" % _interiors.current_label() if _interiors.is_inside() else "dentro de un edificio"
	var near := place_near(pos)
	return ("fuera, junto a: %s" % near) if not near.is_empty() else "fuera, al aire libre"


## Lo que el validador necesita saber de la gente cercana (nombre, qué lleva, dónde está).
func people_facts() -> Array:
	var out := []
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		if not npc.is_present() or npc.global_position.distance_to(_player.global_position) > 40.0:
			continue
		var nm := str(WorldDB.get_entity("npc", id).get("name", ""))
		if nm.is_empty():
			continue
		out.append({"name": nm.split(" ")[0].to_lower(), "held": npc.held.to_lower(), "place": where_is(npc.global_position).to_lower()})
	return out


## Nombres de los sitios de aquí (para saber cuándo la IA sitúa a alguien en otro).
func place_names() -> Array:
	var out: Array = _places.keys().map(func(k): return str(k).to_lower())
	for id in _interiors.doors():
		out.append(str(_interiors.doors()[id].label).to_lower().trim_prefix("la ").trim_prefix("el "))
	return out


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
const OUTFIT_WORDS := Wardrobe.BASE_WORDS


## Lo que se ve del jugador: su ropa y si va mojado o sucio (los demás lo notan y lo comentan).
func _player_looks() -> String:
	var worn := PlayerLook.wearing()
	var look := PlayerLook.current()
	if not worn.is_empty() and WorldDB.get_entity("item", worn).has("clothing"):
		look = WorldDB.get_entity("item", worn).clothing
	var parts := PackedStringArray(["lleva " + Wardrobe.describe(look, PlayerLook.layers())])
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
	if npc:
		lines.append("TÚ, AHORA MISMO: %s. (Lo que no llevas en la mano no lo tienes: no digas que agarras, sostienes o usas algo que no está aquí.)" % npc_described(npc))
	var people := PackedStringArray()
	for id in _npcs:
		if id != npc_id and _npcs[id].is_present() and _npcs[id].global_position.distance_to(_player.global_position) < 12.0:
			people.append("%s (%s)" % [WorldDB.get_entity("npc", id).get("name", "?"), npc_described(_npcs[id])])
	if not people.is_empty():
		lines.append("También hay cerca: %s." % "; ".join(people))
	var cars := vehicles_described(npc.global_position if npc else _player.global_position)
	lines.append("VEHÍCULOS CERCA: " + (cars + "." if not cars.is_empty() else "ninguno (si te piden subir a un coche, aquí no hay)."))
	var around := surroundings_described(npc.global_position if npc else _player.global_position)
	if not around.is_empty():
		lines.append(around)
	var folk := Townsfolk.context_for(self, npc_id, _dialogue.last_player_text if _dialogue else "")
	if not folk.is_empty():
		lines.append(folk)
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
		"ride_with_player":
			npc_board(npc_id)
		"get_out":
			var v: Node3D = npc.riding_vehicle()
			if v:
				npc.get_off(v.global_position + v.global_basis.x * 2.0 + Vector3(0, 0.3, 0))
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
			# Si ya vas en un vehículo, «sígueme» es subirse
			if _player.riding != null and _player.riding.has_method("board"):
				npc_board(npc_id)
		"ride":
			npc_board(npc_id)
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
		lines.append("LA GENTE DE CERCA, TAL Y COMO ESTÁ (dónde, qué hace, qué lleva en la mano: no inventes nada de esto):\n- " + doing)
	var cars := vehicles_described(_player.global_position)
	lines.append("VEHÍCULOS CERCA: " + (cars + "." if not cars.is_empty() else "ninguno."))
	var spots := PackedStringArray()
	for name in _places:
		spots.append(name)
	if not spots.is_empty():
		lines.append("SITIOS DE ESTE LUGAR (para go_to, aunque estén lejos): " + ", ".join(spots) + ".")
	var dests := PackedStringArray()
	var seen := {}
	for nm in travel_destinations():
		var id: String = travel_destinations()[nm]
		if not seen.has(id):
			seen[id] = true
			dests.append("%s (location:%s)" % [nm, id])
	if not dests.is_empty():
		lines.append("OTROS LUGARES A LOS QUE PUEDE VIAJAR (paso travel): " + ", ".join(dests) + ".")
	var around := surroundings_described(_player.global_position)
	if not around.is_empty():
		lines.append(around)
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


## Te llevas un vehículo que no es tuyo: si alguien lo ve, es un robo (y el dueño se entera).
func on_vehicle_taken(v: Node3D) -> void:
	var owner_id := str(v.get("owner_id"))
	var what: String = v.call("the_name") if v.has_method("the_name") else str(v.get("display_name"))
	var saw: Array = _life.witness("el jugador se llevó %s, que no es suyo" % what, v.global_position, [owner_id]) if _life else []
	if owner_id.begins_with("npc_") or WorldDB.get_entity("npc", owner_id).size() > 0:
		var seen_by_owner: bool = _npcs.has(owner_id) and _npcs[owner_id].is_present() and _npcs[owner_id].global_position.distance_to(v.global_position) < 25.0
		if seen_by_owner or not saw.is_empty():
			NPCMemory.add_event(owner_id, ("Viste cómo el jugador se llevaba %s (es tuyo/a) sin permiso." if seen_by_owner else "Te contaron que el jugador se llevó %s (tuyo/a) sin permiso.") % what, -20, not seen_by_owner)
	if not saw.is_empty() and _ui and _ui.has_method("toast"):
		_ui.toast("Alguien te ha visto llevarte %s." % what)


## Atropellas a alguien: cae, se hace daño y lo recuerda (y quien lo vea, también). Un golpe muy
## fuerte le manda unos días a la clínica.
func on_npc_hit(v: Node3D, npc: TownNPC, impact: float) -> void:
	var driving: bool = v.get("_rider") != null
	var what: String = v.call("the_name") if v.has_method("the_name") else "un coche"
	npc.say(["¡Ay! ¡¿Estás loco?!", "¡Aaah!", "¡Cuidado!"][randi() % 3] if impact < 8.0 else "¡Aaagh…!", 3.5)
	if npc.has_meta("passerby") or npc.npc_id.is_empty():
		if driving and _ui:
			_ui.toast("Atropellaste a alguien.")
		return
	var id := npc.npc_id
	var nm: String = str(WorldDB.get_entity("npc", id).get("name", "alguien")).split(" ")[0]
	if not driving:
		NPCMemory.add_event(id, "Te golpeó %s que iba sin nadie al volante." % what, 0)
		return
	var grave := impact >= 14.0
	var how := "te dio un golpe leve" if impact < 6.0 else ("te hizo mucho daño" if not grave else "casi te mata: acabaste en la clínica")
	NPCMemory.add_event(id, "El jugador te atropelló con %s y %s." % [what, how], -15 if impact < 6.0 else (-35 if not grave else -60))
	if _life:
		_life.witness("el jugador atropelló a %s con %s" % [nm, what], npc.global_position, [id])
	if _ui:
		_ui.toast(("Atropellaste a %s." % nm) + (" Está muy mal herido/a." if grave else ""))
	if grave:  # al levantarse no puede seguir: se lo llevan a la clínica unos días
		_errands[id] = true
		await get_tree().create_timer(6.0).timeout
		if is_instance_valid(npc):
			NPCMemory.go_inside(id, "clinica", "la clínica", 60.0 * 24.0 * 2.0, true)
			_errands.erase(id)
			npc.set_present(false)


## Te subes a un vehículo: quien te acompaña sube contigo (si cabe y está cerca).
func on_player_boarded(v: Node3D) -> void:
	for id in _npcs:
		var npc: TownNPC = _npcs[id]
		if not npc.is_present() or not NPCMemory.is_following(id) or npc.global_position.distance_to(v.global_position) > 25.0:
			continue
		_board_when_near(npc, v)


## El PNJ camina hasta el vehículo (aunque se mueva un poco, o aunque ya estés dentro) y sube.
## Si al acabar la conversación sigue hablando contigo, espera a que termine. Devuelve si subió.
func _board_when_near(npc: TownNPC, v: Node3D) -> bool:
	var waited := 0.0
	var last_goal := Vector3.INF
	# Cuánto mide: a una nave de 10 m no se llega a 3 m de su centro
	var half: float = clampf(float(v.get("length")) * 0.5 if v.get("length") != null else 1.5, 1.2, 8.0)
	while waited < 25.0 and is_instance_valid(npc) and is_instance_valid(v):
		var d := npc.global_position.distance_to(v.global_position)
		if d < half + 2.2 and not npc.talking:
			break
		if not npc.talking and (last_goal == Vector3.INF or last_goal.distance_to(v.global_position) > 1.5 or waited > 0.0 and fmod(waited, 2.0) < 0.25):
			var side: Vector3 = (npc.global_position - v.global_position)
			side.y = 0.0
			last_goal = v.global_position + (side.normalized() if side.length() > 0.1 else Vector3.RIGHT) * (half + 1.0)
			npc.walk_to(last_goal, true)
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if not is_instance_valid(npc) or not is_instance_valid(v):
		return false
	if npc.global_position.distance_to(v.global_position) > half + 4.5:
		npc.say("No llego hasta allá.", 3.0)
		return false
	if not v.call("board", npc):
		npc.say("No quepo. Te veo allá.", 3.0)
		return false
	return true


## Te bajas: los que iban contigo bajan también y, si te acompañaban, te siguen.
func on_player_alighted(_v: Node3D, left: Array) -> void:
	for npc in left:
		if is_instance_valid(npc) and NPCMemory.is_following(npc.npc_id):
			npc.follow(_player)


## Tocas el claxon: quien está delante se aparta (y alguno protesta).
func on_horn(v: Node3D) -> void:
	var fwd: Vector3 = v.global_basis.z.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var people: Array = _npcs.values()
	people.append_array(get_children().filter(func(c): return c is TownNPC and c.has_meta("passerby")))
	for npc in people:
		if not (npc is TownNPC) or not npc.is_present() or npc.talking or npc.is_riding() or npc.is_settled():
			continue
		var to: Vector3 = npc.global_position - v.global_position
		if to.length() > 16.0 or to.normalized().dot(fwd) < 0.5:
			continue
		var side: Vector3 = right * (1.0 if to.dot(right) > 0.0 else -1.0)
		npc.face(v.global_position)
		npc.walk_to(npc.global_position + side * 3.0, true)
		if randf() < 0.5:
			npc.say(["¡Ya voy, ya voy!", "¡Qué prisa!", "¡Eh, tranquilo!"][randi() % 3], 2.5)


## «Súbete al coche»: el PNJ va al vehículo en el que estás (o al más cercano) y se sube.
func npc_board(npc_id: String) -> String:
	if not _npcs.has(npc_id):
		return ""
	var npc: TownNPC = _npcs[npc_id]
	if npc.is_riding():
		return "ya va a bordo"
	var v: Node3D = _player.riding if _player.riding != null and _player.riding.has_method("board") else nearest_vehicle(_player.global_position, 30.0)
	if v == null:
		npc.say("¿Qué coche? Aquí no veo ninguno.", 3.0)
		return "no hay ningún vehículo cerca"
	if npc.global_position.distance_to(v.global_position) > 40.0:
		return "está demasiado lejos del vehículo"
	if int(v.call("free_seats")) <= 0:
		npc.say("No queda sitio.", 3.0)
		return "no queda sitio en %s" % _vehicle_name(v)
	NPCMemory.set_fields(npc_id, {"following": true})
	_board_when_near(npc, v)
	return "va hacia %s para subirse" % _vehicle_name(v)


func _vehicle_name(v: Node3D) -> String:
	return str(v.call("the_name")) if v.has_method("the_name") else str(v.get("display_name"))


## El vehículo más cercano (a menos de radius), o null.
func nearest_vehicle(pos: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for c in get_children():
		if c is Node3D and c.has_method("board") and c.has_method("free_seats") and c.global_position.distance_to(pos) < best_d:
			best = c
			best_d = c.global_position.distance_to(pos)
	return best


## Vehículos cerca (para la IA): «el sedán de Teo, a 8 m, vacío».
func vehicles_described(pos: Vector3, radius: float = 30.0) -> String:
	var out := PackedStringArray()
	for c in get_children():
		if not (c is Vehicle or c is Ship or c is Boat) or c.global_position.distance_to(pos) > radius:
			continue
		var nm: String = c.call("the_name") if c.has_method("the_name") else str(c.get("display_name"))
		var owner := str(c.get("owner_id")) if c.get("owner_id") != null else ""
		var whose := ""
		if owner == "player":
			whose = " (tuyo)"
		elif not owner.is_empty() and WorldDB.get_entity("npc", owner).size() > 0:
			whose = " de %s" % str(WorldDB.get_entity("npc", owner).get("name", "un vecino")).split(" ")[0]
		var who := []
		if c.get("_rider") != null:
			who.append("el jugador al volante")
		if c.has_method("passengers"):
			for p in c.call("passengers"):
				who.append(str(WorldDB.get_entity("npc", p.npc_id).get("name", "alguien")).split(" ")[0])
		out.append("%s%s, a %d m, %s" % [nm, whose, int(c.global_position.distance_to(pos)), ("con " + ", ".join(PackedStringArray(who))) if not who.is_empty() else "vacío"])
	return "; ".join(out)


## Llegas en tu nave (desde el espacio): se posa en un claro (en casa, en la plataforma de
## despegue) y apareces junto a ella, nunca lejos ni metido dentro de algo.
func _park_arrival_ship() -> void:
	var arrival: Dictionary = WorldDB.get_state("arrival_ship", {})
	if arrival.is_empty() or str(arrival.get("to", "")) != GameState.current_location() or arrival.get("ship", {}).is_empty():
		return
	WorldDB.set_state("arrival_ship", {})
	var e: Dictionary = arrival.ship.duplicate(true)
	e.erase("id")
	var at := landing_spot(_player.global_position, Vector3(11, 4, 12))
	e["pos"] = [at.x, at.y, at.z]
	var saved := Creations.add(e)
	if saved.is_empty():
		return
	var ship := Creations.build(self, saved)
	# Bajas por el costado de la nave
	var side: Vector3 = (ship.global_basis.x if ship else Vector3.RIGHT).normalized()
	var out := at - side * 7.0
	out.y = ground_at(out.x, out.z)
	_player.global_position = InteriorManager.free_spot_near(self, out, -side, [_player]) + Vector3(0, 0.2, 0)
	_player.velocity = Vector3.ZERO
	_bring_passengers(arrival.get("passengers", []), _player.global_position, -side)


## Los que viajaban contigo en la nave bajan a tu lado y te siguen (en un planeta aparecen
## aunque no vivan allí; en el pueblo, son los vecinos de siempre que vuelven contigo).
func _bring_passengers(ids: Array, near: Vector3, away: Vector3) -> void:
	var k := 0
	for id in ids:
		var entity := WorldDB.get_entity("npc", str(id))
		if entity.is_empty():
			continue
		var npc: TownNPC = _npcs.get(id)
		if npc == null:
			npc = TownNPC.new()
			add_child(npc)
			npc.setup(entity)
			_npcs[id] = npc
		k += 1
		var spot: Vector3 = near + away.rotated(Vector3.UP, 0.6 * k) * (1.6 + 0.4 * k)
		spot.y = ground_at(spot.x, spot.z)
		npc.global_position = InteriorManager.free_spot_near(self, spot, away, [_player]) + Vector3(0, 0.1, 0)
		npc.face(near)
		NPCMemory.set_fields(str(id), {"following": true})
		npc.follow(_player)


## Adónde puede ir el jugador con F («vuelvo al pueblo», «vamos a Kepra»): nombre -> location_id
## de los lugares ya conocidos (más «el pueblo»/«casa» para Bahía de las Horas).
func travel_destinations() -> Dictionary:
	var out := {}
	var here := GameState.current_location()
	if here != GameState.HOME:
		for w in ["pueblo", "casa", "bahía", "bahia", "hogar", "bahía de las horas", "la tierra", "mi planeta"]:
			out[w] = GameState.HOME
	for n in TimelineManager.visited_locations():
		var id: String = n.location_id
		if id == here or id == Travel.SPACE:
			continue
		var nm := str(WorldDB.get_entity("location", id).get("name", "")) if id != GameState.HOME else "Bahía de las Horas"
		if not nm.is_empty():
			out[nm.to_lower()] = id
	return out


## Lo que dice el jugador → location_id ("" si no es un lugar al que se viaja).
func travel_destination_for(text: String) -> String:
	var t := text.to_lower().strip_edges().trim_prefix("location:")
	if t.is_empty():
		return ""
	var dests := travel_destinations()
	if dests.values().has(t):
		return t
	for nm in dests:
		if t == nm or t.contains(nm) or (nm.length() > 5 and nm.contains(t) and t.length() > 3):
			return dests[nm]
	return ""


## Viajar con F a otro lugar: en tu nave (vas hasta ella, subes y el piloto automático te lleva)
## o con el Ancla, si tiene energía. Devuelve lo que pasó, para la narración.
func travel_to(location_id: String) -> String:
	if location_id == GameState.current_location():
		return "Ya estás aquí."
	var nm := "Bahía de las Horas" if location_id == GameState.HOME else str(WorldDB.get_entity("location", location_id).get("name", "allí"))
	var ship: Node3D = null
	var best := 400.0
	for c in get_children():
		if c is Ship and (c.get("owner_id") == null or str(c.get("owner_id")) in ["player", ""]) and c.global_position.distance_to(_player.global_position) < best:
			ship = c
			best = c.global_position.distance_to(_player.global_position)
	if ship:
		if _player.riding != ship:
			if _player.riding != null:
				_player.riding.call("_leave")
			await _player.auto_walk_to(ship.global_position, 4.0)
			if not is_instance_valid(ship):
				return ""
			ship.call("_on_use", _player)
			await get_tree().create_timer(1.5).timeout
		var e := Creations.get_entry(str(ship.get("entry_id")))
		if e.is_empty():
			e = ship.get("entry")
		e = e.duplicate(true)
		e["fuel"] = ship.get("fuel")
		var aboard := []
		if ship.has_method("passengers"):
			for p in ship.call("passengers"):
				aboard.append(p.npc_id)
		var r := Travel.fly_direct(e, location_id, aboard)
		if not r.ok:
			return str(r.error)
		_player.riding = null
		WorldDB.flush()
		get_tree().change_scene_to_file(Travel.scene_for(location_id))
		return "Despegas y el piloto automático te lleva a %s." % nm
	if GameState.is_awakened() and GameState.can_travel(location_id):
		var r := Travel.go_to(location_id)
		if r.ok:
			WorldDB.flush()
			get_tree().change_scene_to_file(Travel.scene_for(location_id))
			return "El Ancla vibra y el mundo se pliega: llegas a %s." % nm
		return str(r.error)
	return "No tienes cómo ir a %s desde aquí: ni nave cerca ni energía en el Ancla." % nm


## Sitio donde cabe algo de tamaño size (ancho, alto, largo) cerca de near: plano y sin nada
## encima. Una escena puede dar el suyo con arrival_pad() (la plataforma de despegue).
func landing_spot(near: Vector3, size: Vector3) -> Vector3:
	if has_method("arrival_pad"):
		var pad: Vector3 = call("arrival_pad")
		if pad != Vector3.INF:
			return pad
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.WORLD | Layers.CHARACTERS
	q.exclude = [_player.get_rid()]
	for ring in range(0, 8):
		var r := 12.0 + ring * 6.0
		for k in 12:
			var a := TAU * k / 12.0 + ring * 0.37
			var p := near + Vector3(sin(a), 0, cos(a)) * r
			var g := ground_at(p.x, p.z)
			var flat := true  # plano: las esquinas a la misma altura (±1 m)
			for c in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
				if absf(ground_at(p.x + c.x * size.x / 2.0, p.z + c.z * size.z / 2.0) - g) > 1.0:
					flat = false
			if not flat or (_water_level > -INF and g < _water_level + 0.3):
				continue
			q.transform = Transform3D(Basis(), Vector3(p.x, g + size.y / 2.0 + 0.8, p.z))
			if space.intersect_shape(q, 1).is_empty():
				return Vector3(p.x, g + 0.1, p.z)
	return Vector3(near.x + 14.0, ground_at(near.x + 14.0, near.z) + 0.1, near.z)


## La nave sale de la atmósfera: al espacio (SpaceScene), contigo dentro.
func launch_ship(ship: Node3D) -> void:
	var e := Creations.get_entry(str(ship.get("entry_id")))
	if e.is_empty():
		e = ship.get("entry")
	e = e.duplicate(true)
	e["fuel"] = ship.get("fuel")
	var aboard := []
	if ship.has_method("passengers"):
		for p in ship.call("passengers"):
			aboard.append(p.npc_id)
	if _player.riding == ship:
		_player.riding = null
	Travel.launch(e, aboard)
	WorldDB.flush()
	get_tree().change_scene_to_file(Travel.SPACE_SCENE)


## Lo que hay a la vista alrededor de `pos` (para la IA: solo puede mencionar lo que está aquí).
## Cosas marcadas con Decor.landmark, puertas, asientos, árboles y el agua; y lo que NO hay
## donde se podría suponer (un negocio sin toldo).
func surroundings_described(pos: Vector3, radius: float = 25.0) -> String:
	if _interiors.is_inside():
		return ""
	var items := []
	var seen := {}
	for m in get_tree().get_nodes_in_group("landmark"):
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var d: float = (m as Node3D).global_position.distance_to(pos)
		var label := str(m.get_meta("label", ""))
		if d > radius or label.is_empty():
			continue
		if seen.has(label):
			seen[label].n += 1
			seen[label].d = minf(seen[label].d, d)
			continue
		seen[label] = {"label": label, "d": d, "n": 1}
		items.append(seen[label])
	for id in _interiors.doors():
		var door: Dictionary = _interiors.doors()[id]
		var d: float = door.pos.distance_to(pos)
		if d <= radius:
			items.append({"label": "la puerta de " + str(door.label), "d": d, "n": 1})
	for it in get_tree().get_nodes_in_group("interactables"):
		if it is Interactable and it.prompt.begins_with("Sentarse") and it.global_position.distance_to(pos) <= radius:
			var k := "un asiento (banca o silla)"
			if not seen.has(k):
				seen[k] = {"label": k, "d": it.global_position.distance_to(pos), "n": 1}
				items.append(seen[k])
	for place in _places:
		var d: float = (_places[place] as Vector3).distance_to(pos)
		if d <= radius and not seen.has(place):
			seen[place] = true
			items.append({"label": str(place), "d": d, "n": 1})
	var trees := _features.filter(func(f): return is_instance_valid(f.node) and f.kind == "tree" and f.pos.distance_to(pos) <= radius).size()
	if trees > 0:
		items.append({"label": "árboles" if trees > 1 else "un árbol", "d": radius, "n": 1})
	if _water_spot() != Vector3.INF and _water_spot().distance_to(pos) <= radius:
		items.append({"label": "el mar (la orilla)", "d": _water_spot().distance_to(pos), "n": 1})
	items.sort_custom(func(a, b): return a.d < b.d)
	var parts := PackedStringArray()
	for it in items.slice(0, 14):
		parts.append("%s%s a %d m" % [it.label, (" (%d)" % it.n) if it.n > 1 else "", int(it.d)])
	# Lo que no hay: negocios cercanos sin toldo (la cafetería no tiene)
	var without := PackedStringArray()
	for id in _interiors.doors():
		var door: Dictionary = _interiors.doors()[id]
		if door.kind in ["house", "home"] or door.pos.distance_to(pos) > radius:
			continue
		var has_awning := false
		for m in get_tree().get_nodes_in_group("landmark"):
			if is_instance_valid(m) and str(m.get_meta("kind", "")) == "awning" and (m as Node3D).global_position.distance_to(door.pos + Vector3(0, 2.9, 0)) < 2.5:
				has_awning = true
		if not has_awning:
			without.append(str(door.label))
	var out := "A TU ALREDEDOR (lo único que hay a la vista; no menciones toldos, bancas, fuentes, puestos ni nada que no esté aquí): " + (", ".join(parts) if not parts.is_empty() else "nada en especial") + "."
	if not without.is_empty():
		out += " Sin toldo: %s." % ", ".join(without)
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

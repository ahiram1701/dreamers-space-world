class_name GameplayUI
extends Node
## Toda la interfaz de juego compartida por el pueblo y los mundos generados:
## stats, misión y coordenadas, Ancla (T), inventario (I), hacer algo (F), pausa (Esc), hora, avisos,
## fallos visuales por inestabilidad y desanclaje. Bloquea al jugador mientras hay un panel abierto.

const GLITCH_SHADER := preload("res://scenes/ui/glitch.gdshader")
const DECAY_EVERY := 20.0      # segundos: la inestabilidad baja sola poco a poco
const DAMAGE_EVERY := 3.0      # segundos: con inestabilidad crítica el cuerpo sufre
const CRITICAL := 90

var player: Player
## Devuelve los ids de los PNJs de la escena (objetos de secretos/confianza).
var nearby_npcs: Callable = func(): return []
## Dónde está el jugador y qué tiene cerca (para "Hacer algo"). Lo asigna la escena.
var scene_context: Callable = func(): return ""

var anchor: AnchorPanel
var inventory: InventoryPanel
var pause: PauseMenu
var actions: ActionPanel
var hud: HUD
var hints: Hints
var phone: PhonePanel
var stash: StashPanel
## Lo asigna la escena: llamar a alguien (abre la conversación en modo llamada).
var start_call: Callable
## Lo asigna la escena: sitios con nombre para el mapa del celular.
var places: Callable = func(): return {}
var _glitch: ColorRect
var _blocks := 0
var _owners := {}   # quién bloquea el control (un panel, el diálogo, una escena): abrir dos veces no suma dos
var _decay_t := 0.0
var _damage_t := 0.0
var _unanchoring := false


func _ready() -> void:
	add_to_group("gameplay_ui")
	hud = HUD.new()
	add_child(hud)
	hud.player = player
	hints = Hints.new()
	hints.player = player
	add_child(hints)
	stash = StashPanel.new()
	add_child(stash)
	phone = PhonePanel.new()
	phone.player = player
	phone.places = func(): return places.call()
	add_child(phone)
	phone.call_requested.connect(func(id): if start_call.is_valid(): start_call.call(id))
	phone.waypoint_set.connect(hud.set_waypoint)
	Phone.message_received.connect(func(id, text):
		Sfx.chime(self)
		toast("%s: %s" % [WorldDB.get_entity("npc", id).get("name", "?").split(" ")[0], text], "memory"))
	Inventory.phone_requested.connect(func(): if not _talking() and (_blocks == 0 or inventory.is_open()): inventory.close(); phone.open())
	Inventory.action_requested.connect(func(text): if not actions.is_busy() and not _talking(): inventory.close(); actions.open(text))
	Inventory.light_toggled.connect(func(on): if player: player.set_light(on))
	Inventory.look_changed.connect(func(): if player: player.rebuild_look())
	Jobs.fired.connect(func(_r): toast("Te han despedido del trabajo.", "warn"))
	Jobs.hired.connect(func(j): toast("Trabajo nuevo: %s (%s)" % [j.title, WorldClock.span(j.start_hour, j.end_hour)], "quest"))

	var glitch_layer := CanvasLayer.new()
	glitch_layer.layer = 4
	add_child(glitch_layer)
	_glitch = ColorRect.new()
	_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLITCH_SHADER
	_glitch.material = mat
	glitch_layer.add_child(_glitch)

	anchor = AnchorPanel.new()
	add_child(anchor)
	inventory = InventoryPanel.new()
	inventory.nearby_npcs = func(): return nearby_npcs.call()
	add_child(inventory)
	pause = PauseMenu.new()
	add_child(pause)
	actions = ActionPanel.new()
	actions.context = func(): return scene_context.call()
	actions.player = player
	add_child(actions)
	for panel in [anchor, inventory, pause, actions, phone, stash]:
		panel.opened.connect(block.bind(true, str(panel.get_script().resource_path.get_file())))
		panel.closed.connect(block.bind(false, str(panel.get_script().resource_path.get_file())))
	pause.opened.connect(func(): WorldClock.paused = true)   # la pausa pausa el mundo (reloj, necesidades, encargos)
	pause.closed.connect(func(): WorldClock.paused = false)
	inventory.message.connect(toast)
	inventory.action_requested.connect(func(text): if not actions.is_busy() and not _talking(): actions.open(text))

	GameState.stat_changed.connect(_on_stat_changed)
	Quests.quest_completed.connect(_on_quest_completed)
	Economy.bill_paid.connect(func(t): toast(t, "money"))
	Economy.bill_unpaid.connect(func(t): toast(t, "warn"))
	Economy.evicted.connect(func(t): toast(t, "warn"))
	Society.event_started.connect(func(_id, t): toast("Hoy: %s." % t, "info"))
	Quests.quest_failed.connect(func(_q, text): toast(text, "warn"); refresh_tracker())
	Quests.quest_accepted.connect(func(q): toast("Nuevo encargo de %s: %s" % [WorldDB.get_entity("npc", q.giver).get("name", "?"), q.title], "quest"); refresh_tracker())
	# Los encargos que llegan por mensaje (o fuera de una conversación) también se avisan
	Quests.quest_added.connect(func(q):
		var talking = get_tree().current_scene.get("_dialogue") if get_tree().current_scene else null
		if q.get("objective", "") == "custom" and not (talking and talking.visible):
			toast("Apuntado en el Cuaderno: %s" % q.title, "quest")
		refresh_tracker())
	Inventory.changed.connect(refresh_tracker)
	refresh_tracker()
	_update_glitch()


## Bloquea o libera al jugador (paneles, diálogos). Admite varios bloqueos a la vez.
## Quita o devuelve el control. Con `who` (un panel, "dialogue", "cutscene"…), cada dueño cuenta
## una sola vez: abrir dos veces o cerrar de más no desfasa nada (antes podía quedar bloqueado
## para siempre). Sin dueño, cuenta como antes.
func block(on: bool, who: String = "") -> void:
	if who.is_empty():
		_owners["_anon"] = maxi(int(_owners.get("_anon", 0)) + (1 if on else -1), 0)
	elif on:
		_owners[who] = 1
	else:
		_owners.erase(who)
	_blocks = 0
	for k in _owners:
		_blocks += int(_owners[k])
	if player:
		player.controls_enabled = _blocks == 0


## ¿Hay una conversación abierta (en persona o por teléfono)?
func _talking() -> bool:
	return _owners.has("dialogue")


## ¿Hay una escena de cine en marcha? Mientras, no se abre ningún panel.
func in_cutscene() -> bool:
	return _owners.has("cutscene")


## Aviso en una tarjeta (ver HUD.notify): "item", "money", "quest", "memory", "warn" o "info".
func toast(text: String, kind: String = "info") -> void:
	hud.notify(text, kind)


func refresh_tracker() -> void:
	var lines := PackedStringArray()
	var q := Quests.for_location(GameState.current_location())
	if not q.is_empty() and q.status != "offered":
		lines.append("Misión: " + Quests.objective_text(q))
	# El encargo con hora más próximo (lo demás, en el Cuaderno)
	var soon := Quests.next_timed()
	if not soon.is_empty():
		lines.append("Encargo: %s — %s" % [soon.title, Quests.when_text(soon)])
	var at_home: bool = GameState.current_location() == GameState.HOME and WorldDB.get_state("homecoming", false)
	if at_home:
		lines.append("De vuelta en casa" if GameState.ending().is_empty() else "Has vuelto a casa. Puedes seguir viajando cuando quieras.")
	elif GameState.is_awakened() and GameState.ending().is_empty():
		if GameState.has_all_fragments():
			lines.append("La brújula apunta firme a casa — usa el Ancla (T) para el último salto")
		else:
			var left := GameState.FRAGMENTS_NEEDED - GameState.fragments()
			var hint := " · habla con la gente del lugar" if not q.is_empty() and q.status == "offered" else ""
			lines.append("Rumbo a casa: faltan %d %s%s" % [left, "salto" if left == 1 else "saltos", hint])
	hud.set_tracker("\n".join(lines))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or in_cutscene():
		return
	if event.is_action_pressed("pause"):
		if phone.is_open():
			phone.close()
		elif actions.is_open():
			actions.close()
		elif inventory.is_open():
			inventory.close()
		elif anchor.is_open():
			anchor.close()
		elif _blocks == 0 or pause.is_open():
			pause.toggle()
		else:
			return  # una conversación abierta: Esc es despedirse (lo gestiona el diálogo)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):  # B del mando: cerrar lo que esté abierto
		for panel in [phone, stash, actions, inventory, anchor, pause]:
			if panel.is_open():
				panel.close()
				get_viewport().set_input_as_handled()
				return
	elif event.is_action_pressed("inventory"):
		if not pause.is_open() and (not _talking() or inventory.is_open()):
			inventory.toggle()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("phone"):
		if phone.is_open():
			phone.close()
			get_viewport().set_input_as_handled()
		elif _blocks == 0 and not _talking():
			if Phone.has_phone():
				phone.open()
			else:
				toast("No llevas el celular encima.", "warn")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("act"):
		if _blocks == 0 and not actions.is_busy():
			actions.open()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not GameState.is_awakened() or _unanchoring or _blocks > 0:
		return
	var instability := GameState.get_stat("instability")
	_decay_t += delta
	if _decay_t >= DECAY_EVERY:
		_decay_t = 0.0
		if instability > 0 and instability < CRITICAL:
			GameState.change_stat("instability", -1)
	if instability >= CRITICAL:
		_damage_t += delta
		if _damage_t >= DAMAGE_EVERY:
			_damage_t = 0.0
			GameState.change_stat("health", -2)
			toast("Tu cuerpo no soporta tanta decoherencia. Recarga el Ancla o usa algo que te estabilice.")


func _on_stat_changed(stat: String, value: int) -> void:
	if stat == "instability":
		_update_glitch()
	elif stat == "fragments":
		refresh_tracker()
	elif stat == "health" and value <= 0 and GameState.is_awakened():
		_unanchor()


func _on_quest_completed(q: Dictionary, reward: String) -> void:
	var text := str(q.get("completion_text", "")).strip_edges()
	toast(("%s\n%s" % [text, reward]) if not text.is_empty() else "Cumpliste «%s». %s" % [q.title, reward], "quest")
	refresh_tracker()


func _update_glitch() -> void:
	var intensity := clampf(remap(GameState.get_stat("instability"), 60, 100, 0.0, 1.0), 0.0, 1.0)
	_glitch.visible = intensity > 0.0
	(_glitch.material as ShaderMaterial).set_shader_parameter("intensity", intensity)


## Salud a 0: te dispersas entre ramas. El Ancla te recompone aquí, con un coste.
func _unanchor() -> void:
	if _unanchoring:
		return
	_unanchoring = true
	block(true)
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var text := Label.new()
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 22)
	text.text = "Te has desanclado.\n\nDurante un instante estás en mil ramas a la vez.\nEl Ancla tira de ti y te recompone, pero algo se queda atrás."
	layer.add_child(text)
	await get_tree().create_timer(4.0).timeout
	var lost := GameState.recover_from_unanchor()
	if not lost.is_empty():
		text.text += "\n\nHas perdido: %s" % lost
		await get_tree().create_timer(2.5).timeout
	get_tree().reload_current_scene()

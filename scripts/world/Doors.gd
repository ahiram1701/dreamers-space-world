class_name Doors
extends Node
## Puertas de verdad: en casa ajena se toca y alguien abre (o no); te invitan a pasar o te
## atienden en el umbral; un negocio cerrado está cerrado; y una puerta que nadie abre se puede
## forzar o colarse por una ventana, con el riesgo de que te oigan y luego todos lo sepan.

const NIGHT_FROM := 23.0
const NIGHT_TO := 7.0
const BAN_DAYS := 3.0
const TOOL_WORDS := ["palanca", "barreta", "hacha", "martillo", "destornillador", "desarmador"]

var scene: LocationScene
var interiors: InteriorManager
## Quien salió a abrir: {npc, door, temp (lo creó la puerta), invited}
var doorstep := {}
## La última puerta que forzaste (para que quien esté dentro reaccione como debe).
var forced_door := ""


func _ready() -> void:
	interiors.gate = may_enter
	interiors.knocked.connect(knock)
	interiors.force_requested.connect(func(id): force(id, false))
	WorldClock.hour_changed.connect(func(_h): interiors.refresh_prompts())
	interiors.refresh_prompts.call_deferred()


## ¿Se entra sin llamar? Tu casa y los sitios públicos abiertos, sí; la casa de otro, no.
func may_enter(id: String) -> bool:
	var kind: String = interiors.doors().get(id, {}).get("kind", "")
	if kind == "home":
		return true
	if kind == "house":
		return false
	return scene.owner_of_door(id).is_empty() or Jobs.has_job() and Jobs.job().get("place", "") == id


static func is_night(h: float) -> bool:
	return h >= NIGHT_FROM or h < NIGHT_TO


## Quién vive tras esa puerta y está en casa: [{id, awake, named}].
func residents_home(id: String) -> Array:
	var out := []
	var h := WorldClock.hour()
	var kind: String = interiors.doors().get(id, {}).get("kind", "")
	var owner := scene.owner_of_door(id)
	if not owner.is_empty() and scene._npcs.has(owner):
		# Un vecino con nombre: si no se le ve fuera, está dentro (de noche, dormido)
		var npc: TownNPC = scene._npcs[owner]
		var inside := NPCMemory.inside(owner)
		if (not npc.is_present() and (inside.is_empty() or inside == id)) or inside == id:
			out.append({"id": owner, "awake": not is_night(h), "named": true})
		return out
	if kind == "house":
		for m in scene._households.ensure(id, owner):
			var e := WorldDB.get_entity("npc", m)
			if e.is_empty():
				continue
			var p := Households.plan(e, h)
			if p.home:
				out.append({"id": m, "awake": p.get("gesture", "") != "sleep", "named": scene._npcs.has(m),
					"kid": e.get("household_role", "") == "niño"})
	return out


## Tocas: suena, esperas, y abre alguien (o nadie).
func knock(id: String) -> void:
	if not doorstep.is_empty():
		return
	var d: Dictionary = interiors.doors().get(id, {})
	var kind: String = d.get("kind", "")
	Sfx.knock(interiors)
	scene._player.play_gesture("knock", 1.2)
	scene._ui.toast("Tocas a la puerta de %s…" % d.get("label", "la casa"))
	await get_tree().create_timer(1.8).timeout
	if Shops.is_shop(kind) or kind in ["clothes", "salon", "cafe"]:
		_closed_shop(id)
		return
	if interiors.locked.has(id):  # alguien encerrado que no quiere ver a nadie
		scene._ui.toast(interiors.locked[id])
		interiors.allow_force(id)
		return
	var home := residents_home(id)
	var awake := home.filter(func(r): return r.awake and not r.get("kid", false))
	if awake.is_empty():
		awake = home.filter(func(r): return r.awake)
	var who: Dictionary = awake[0] if not awake.is_empty() else {}
	if who.is_empty() and not home.is_empty() and randf() < 0.45:  # dormían: alguien se despierta (de mal humor)
		who = home[0]
		NPCMemory.add_event(who.id, "El jugador tocó a tu puerta mientras dormías y te despertó.", -2)
		await get_tree().create_timer(2.5).timeout
	if who.is_empty():
		scene._ui.toast("No abre nadie." if home.is_empty() else "No abre nadie. Dentro todo está a oscuras.")
		interiors.allow_force(id)
		return
	_answer(id, str(who.id), not bool(who.awake))


## Sale a abrir y habla contigo en el umbral.
func _answer(id: String, npc_id: String, woken: bool) -> void:
	var npc: TownNPC = scene._npcs.get(npc_id)
	var temp := false
	if npc == null:
		npc = TownNPC.new()
		scene.add_child(npc)
		npc.setup(WorldDB.get_entity("npc", npc_id))
		scene._npcs[npc_id] = npc
		temp = true
	NPCMemory.come_out(npc_id)
	npc.set_present(true)
	npc.unsettle()
	npc.stop()
	var door := interiors.door_position(id)
	var yaw: float = interiors.doors()[id].yaw
	var out := Vector3(sin(yaw), 0, cos(yaw))
	npc.global_position = InteriorManager.free_spot_near(scene, door + out * 0.4, out, [npc, scene._player]) + Vector3(0, 0.2, 0)
	npc.face(scene._player.global_position)
	Sfx.door(interiors)
	doorstep = {"npc": npc, "id": npc_id, "door": id, "temp": temp, "invited": false}
	var mem := NPCMemory.get_mem(npc_id)
	var first: String = WorldDB.get_entity("npc", npc_id).get("name", "Alguien").split(" ")[0]
	if banned(npc_id):
		npc.set_emotion("angry")
		npc.say("¿Tú otra vez? Después de lo que hiciste, aquí no entras. Vete.", 4.5)
		NPCMemory.add_event(npc_id, "El jugador tocó a tu puerta y no le dejaste pasar (no olvidas lo que hizo).")
		await get_tree().create_timer(3.0).timeout
		_close_door()
		return
	if woken:
		npc.set_emotion("angry")
		npc.say("¿Sabes qué hora es? ¿Qué quieres?", 4.0)
	elif not bool(mem.get("met", false)):
		npc.say("¿Sí? ¿Qué se le ofrece?", 3.5)
	else:
		npc.say("¡Ah, eres tú! ¿Qué pasó?", 3.5)
	NPCMemory.add_event(npc_id, "El jugador tocó a tu puerta y saliste a abrirle. Estás en el umbral de %s, hablando con él/ella." % interiors.door_label(id))
	scene._ui.toast("%s abre la puerta." % first)
	await get_tree().create_timer(0.6).timeout
	if Settings.use_mock or not Settings.has_api_key():
		# Sin IA: de día y si no le caes mal, te invita a pasar
		var h := WorldClock.hour()
		if int(mem.relationship) >= 0 and not woken and h >= 8.0 and h < 21.0:
			npc.say("Pasa, pasa.", 3.0)
			invite(npc_id)
			await get_tree().create_timer(1.2).timeout
			_close_door()
			return
	scene._start_dialogue(npc)


## Lo que sabe quien te abre (va al contexto de la conversación).
func context_for(npc_id: String) -> String:
	if doorstep.is_empty() or doorstep.id != npc_id:
		return ""
	return "ESTÁS EN LA PUERTA DE TU CASA (%s): el jugador tocó y saliste a abrir. Él/ella está fuera. Decide si le invitas a pasar (acción invite_in) según cómo te cae, la hora y lo que te diga; si no, le atiendes aquí en el umbral. Si pasa sin tu permiso, es allanamiento." % interiors.door_label(doorstep.door)


## Te invita a pasar: la puerta te deja entrar durante esa visita.
func invite(npc_id: String) -> bool:
	if doorstep.is_empty() or doorstep.id != npc_id:
		return false
	doorstep.invited = true
	interiors.invited[doorstep.door] = true
	interiors.refresh_prompt(doorstep.door)
	NPCMemory.add_event(npc_id, "Invitaste al jugador a pasar a tu casa.", 1)
	return true


## Se acaba la plática en el umbral: vuelve dentro (y si te invitó, entras con él/ella).
func on_dialogue_closed(npc_id: String) -> void:
	if doorstep.is_empty() or doorstep.id != npc_id:
		return
	await get_tree().create_timer(0.8).timeout
	_close_door()


func _close_door() -> void:
	if doorstep.is_empty():
		return
	var d := doorstep
	doorstep = {}
	var npc: TownNPC = d.npc
	if is_instance_valid(npc):
		if d.temp:
			scene._npcs.erase(d.id)
			npc.queue_free()
		else:
			NPCMemory.go_inside(d.id, d.door, interiors.door_label(d.door), 240.0, false)
			npc.set_present(false)
	Sfx.door(interiors)
	if d.invited:
		interiors.enter(d.door, true)


## Negocio cerrado: a veces el dueño, que aún anda dentro, te deja pasar un momento.
func _closed_shop(id: String) -> void:
	var h := WorldClock.hour()
	var text: String = interiors.locked.get(id, "Está cerrado.")
	if Households.has_staff(interiors.doors()[id].kind) and h >= 6.0 and h < 23.0 and randf() < 0.35:
		scene._ui.toast("Se oyen pasos. «Ya cerramos… bueno, pásale rápido, que ya me iba.»")
		interiors.invited[id] = true
		await get_tree().create_timer(1.0).timeout
		interiors.enter(id, true)
		return
	scene._ui.toast(text)
	interiors.allow_force(id)


# --- Forzar o colarse ---------------------------------------------------------------------

func has_tool() -> bool:
	for w in TOOL_WORDS:
		if not Inventory.find_by_name(w).is_empty():
			return true
	return false


## No te dejan pasar de forma decente: fuerzas la puerta (o, de noche, te cuelas por una ventana).
## Puede que te oigan los de dentro o quien pase cerca; si es así, lo sabrá todo el mundo.
func force(id: String, window: bool) -> String:
	if not interiors.doors().has(id) or interiors.is_inside():
		return ""
	var h := WorldClock.hour()
	if window and not is_night(h):
		var msg := "De día te vería cualquiera colándote por una ventana."
		scene._ui.toast(msg)
		return msg
	var tool := has_tool()
	var player := scene._player
	player.face_towards(interiors.door_position(id))
	player.play_gesture("hammer" if tool and not window else "push", 2.0 if tool else 3.5)
	scene._ui.toast("Te cuelas por una ventana…" if window else ("Haces palanca en la cerradura…" if tool else "Empujas la puerta con el hombro…"))
	for i in (2 if tool or window else 4):
		if not window:
			Sfx.knock(interiors)
		await get_tree().create_timer(0.8).timeout
	# ¿Quién lo oye?
	var noise := 0.35 if window else (0.6 if tool else 0.9)
	var heard_inside := false
	for r in residents_home(id):
		if randf() < noise * (1.0 if r.awake else 0.45):
			heard_inside = true
	var label := interiors.door_label(id)
	var seen := []
	if scene._life:
		for w in scene._life.witness("el jugador %s %s" % ["se coló por una ventana de" if window else "forzó la puerta de", label],
				interiors.door_position(id), []):
			if randf() < noise + 0.2:
				seen.append(w)
	var owners := residents_home(id).map(func(r): return r.id)
	if owners.is_empty() and not scene.owner_of_door(id).is_empty():
		owners = [scene.owner_of_door(id)]
	if not seen.is_empty():
		scene._ui.toast("¡Te han visto!")
		for o in owners:  # se lo cuentan al dueño
			NPCMemory.add_event(o, "Te contaron que el jugador %s tu casa." % ("se coló por una ventana en" if window else "forzó la puerta de"), -15, true)
			NPCMemory.set_fields(o, {"banned_until": WorldClock.absolute_minutes() + BAN_DAYS * 1440.0})
	forced_door = id
	interiors.enter(id, true)
	return "Entras en %s %s." % [label, "por una ventana" if window else "forzando la puerta"] + (" Te han visto." if not seen.is_empty() else "")


## Entras forzando y hay alguien despierto dentro: no es «¡ah, eres tú!», es un allanamiento.
func caught_inside(npc_id: String) -> void:
	NPCMemory.add_event(npc_id, "El jugador forzó la puerta y se metió en tu casa. Le pillaste dentro.", -15)
	NPCMemory.set_fields(npc_id, {"banned_until": WorldClock.absolute_minutes() + BAN_DAYS * 1440.0})


func banned(npc_id: String) -> bool:
	return float(NPCMemory.get_mem(npc_id).get("banned_until", 0.0)) > WorldClock.absolute_minutes()

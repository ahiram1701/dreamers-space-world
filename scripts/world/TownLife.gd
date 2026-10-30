class_name TownLife
extends Node
## La vida de la gente del lugar, aunque no hables con ella:
##   - hacen cosas en su sitio (limpiar la barra, reparar radios, leer…)
##   - ven lo que haces: quien está cerca y te ve se entera (testigos)
##   - se cuentan las cosas: cada hora, quienes coinciden se pasan lo último que saben de ti
##   - charlan entre ellos (IA), y se les oye si pasas cerca
## Todo lo recuerdan con NPCMemory.add_event, así que luego te hablan sabiéndolo.

const WITNESS_RADIUS := 15.0
const GOSSIP_RADIUS := 10.0
const CHAT_RADIUS := 3.5
const CHAT_PLAYER_RADIUS := 12.0
const CHAT_COOLDOWN := 180.0   # segundos reales entre charlas (cuesta una llamada a la IA)

var scene: LocationScene

var _t := 0.0
var _chat_cool := 60.0
var _chatting := false


func _ready() -> void:
	WorldClock.hour_changed.connect(func(_h): gossip())


func _process(delta: float) -> void:
	_t += delta
	_chat_cool -= delta
	if _t < 4.0:
		return
	_t = 0.0
	# Cada uno a lo suyo: si está en su sitio sin hacer nada, retoma su actividad un rato
	for id in scene._npcs:
		var npc: TownNPC = scene._npcs[id]
		if npc.is_idle() and not npc.activity_gesture.is_empty() and npc.current_gesture().is_empty() and randf() < 0.6:
			npc.play_gesture(npc.activity_gesture, randf_range(5.0, 9.0))
	if _chat_cool <= 0.0 and not _chatting:
		_try_chat()


## Quien está cerca y lo ve se entera de lo que pasó (`what`, contado desde fuera).
func witness(what: String, at: Vector3, exclude: Array = []) -> Array:
	var saw := []
	for id in scene._npcs:
		if id in exclude:
			continue
		var npc: TownNPC = scene._npcs[id]
		if not npc.is_present() or npc.global_position.distance_to(at) > WITNESS_RADIUS:
			continue
		if not _sees(npc, at):
			continue
		NPCMemory.add_event(id, "Viste esto: %s" % what)
		saw.append(id)
	return saw


func _sees(npc: TownNPC, at: Vector3) -> bool:
	var space := scene.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(npc.global_position + Vector3(0, 1.6, 0), at + Vector3(0, 1.2, 0), Layers.WORLD)
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.position.distance_to(at + Vector3(0, 1.2, 0)) < 1.0


## Rumores: quienes están juntos se pasan lo más reciente que uno sabe del jugador y el otro no.
func gossip() -> int:
	var ids: Array = scene._npcs.keys().filter(func(i): return scene._npcs[i].is_present())
	var passed := 0
	for a in ids:
		for b in ids:
			if a == b or scene._npcs[a].global_position.distance_to(scene._npcs[b].global_position) > GOSSIP_RADIUS:
				continue
			var news := _news_for(a, b)
			if not news.is_empty():
				var teller: String = WorldDB.get_entity("npc", a).get("name", "Alguien").split(" ")[0]
				NPCMemory.add_event(b, "%s te contó: «%s»" % [teller, news])
				passed += 1
	return passed


## Lo último que `a` vivió o vio del jugador y que `b` aún no sabe (sin rumores de rumores).
func _news_for(a: String, b: String) -> String:
	var known := str(NPCMemory.get_mem(b).recent.map(func(e): return e.text))
	var recent: Array = NPCMemory.get_mem(a).recent
	for i in range(recent.size() - 1, -1, -1):
		var text: String = recent[i].text
		if " te contó: " in text or known.contains(text.left(40)):
			continue
		if WorldClock.absolute_minutes() - float(recent[i].at) > 60.0 * 24.0:
			break
		return text
	return ""


## Dos vecinos juntos y el jugador cerca: charlan (dos a cuatro frases, en bocadillos).
func _try_chat() -> void:
	if Settings.use_mock or not Settings.has_api_key():
		return
	var player := scene._player
	var ids := []
	for i in scene._npcs:
		if scene._npcs[i].is_idle() and scene._npcs[i].global_position.distance_to(player.global_position) < CHAT_PLAYER_RADIUS:
			ids.append(i)
	for a in ids:
		for b in ids:
			if a < b and scene._npcs[a].global_position.distance_to(scene._npcs[b].global_position) < CHAT_RADIUS:
				_chat(a, b)
				return


func _chat(a: String, b: String) -> void:
	_chatting = true
	_chat_cool = CHAT_COOLDOWN
	var ea := WorldDB.get_entity("npc", a)
	var eb := WorldDB.get_entity("npc", b)
	var messages := [
		{"role": "system", "content": ContentGenerator.world_rules_prompt() + "\n\nEscribes una charla breve y natural entre dos vecinos que se encuentran. El jugador está cerca y puede oírles. Hablan de su día, de lo que les preocupa o de lo que ha pasado (si saben algo del jugador, puede salir). Frases cortas, coloquiales, en español."},
		{"role": "user", "content": "%s\n\nA: %s (%s), %s. Lo que sabe del jugador:\n%s\n\nB: %s (%s), %s. Lo que sabe del jugador:\n%s\n\nEscribe de 2 a 4 líneas alternando; \"who\" es \"a\" o \"b\"." % [
			"\n".join(scene.perception(false)), ea.name, ea.occupation, ", ".join(PackedStringArray(ea.personality)), NPCMemory.describe(a),
			eb.name, eb.occupation, ", ".join(PackedStringArray(eb.personality)), NPCMemory.describe(b)]},
	]
	var res := await ContentGenerator.request_valid("ambient_chat", messages)
	if res.ok and is_instance_valid(scene):
		for line in res.data.lines:
			var who: String = a if str(line.who).to_lower().begins_with("a") else b
			var other: String = b if who == a else a
			if not (scene._npcs.has(who) and scene._npcs.has(other)) or not scene._npcs[who].is_idle():
				break
			var npc: TownNPC = scene._npcs[who]
			npc.face(scene._npcs[other].global_position)
			npc.say(str(line.text), 4.0)
			await get_tree().create_timer(clampf(str(line.text).length() * 0.06, 2.5, 5.0)).timeout
	_chatting = false

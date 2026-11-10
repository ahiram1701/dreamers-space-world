extends Node
## La vida social del mundo: el calendario del pueblo (mercado los sábados, partido los domingos,
## fiesta una vez al mes), las amistades y enemistades que surgen entre vecinos y el periódico
## con lo que ha pasado (también lo que hiciste tú). Lo recibe la IA en el contexto.

signal event_started(id: String, text: String)

const EVENTS := {
	"market": {"text": "Mercado de los sábados en la plaza", "from": 8.0, "to": 14.0},
	"football": {"text": "Partido de fútbol del domingo en el campo junto al pueblo", "from": 11.0, "to": 13.0},
	"fiesta": {"text": "Fiesta del pueblo en la plaza: música y farolillos", "from": 19.0, "to": 23.5},
}

var _last_announced := {}
var _tick := 0.0


## Los eventos de hoy y si están en marcha ahora: [{id, text, from, to, now}].
func today() -> Array:
	var out := []
	var wd := WorldClock.weekday()
	var day := int(WorldClock.absolute_minutes() / 1440.0)
	var h := WorldClock.hour()
	var ids := []
	if wd == "sábado":
		ids.append("market")
	if wd == "domingo":
		ids.append("football")
	if day % 28 == 20:  # una vez al mes (cada 28 días de juego)
		ids.append("fiesta")
	for id in ids:
		var e: Dictionary = EVENTS[id].duplicate()
		e["id"] = id
		e["now"] = h >= float(e.from) and h <= float(e.to)
		out.append(e)
	return out


func is_on(id: String) -> bool:
	return today().any(func(e): return e.id == id and e.now)


## Texto para la IA: qué hay hoy en el pueblo.
func describe_today() -> String:
	var parts := PackedStringArray()
	for e in today():
		parts.append("%s (%s, %s)" % [e.text, WorldClock.span(e.from, e.to), "ahora mismo" if e.now else "hoy"])
	return ("HOY EN EL PUEBLO: " + "; ".join(parts) + ".") if not parts.is_empty() else ""


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 3.0 or not WorldDB.is_loaded():
		return
	_tick = 0.0
	for e in today():
		var key := "%s_%d" % [e.id, int(WorldClock.absolute_minutes() / 1440.0)]
		if e.now and not _last_announced.has(key):
			_last_announced[key] = true
			event_started.emit(e.id, e.text)
			add_news("Hoy: %s." % e.text)
	_daily_bonds()


## Una vez al día, dos vecinos que se han visto charlar se hacen amigos (o se pelean): el mundo
## sigue aunque no estés delante.
func _daily_bonds() -> void:
	var day := int(WorldClock.absolute_minutes() / 1440.0)
	if int(WorldDB.get_state("bonds_day", -1)) == day:
		return
	WorldDB.set_state("bonds_day", day)
	var ids := ["npc_marina", "npc_teo", "npc_samir"].filter(func(i): return not WorldDB.get_entity("npc", i).is_empty())
	if ids.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(WorldDB.world_id) + day
	if rng.randf() > 0.35:
		return
	var a: String = ids[rng.randi() % ids.size()]
	var b: String = ids[(ids.find(a) + 1 + rng.randi() % (ids.size() - 1)) % ids.size()]
	var na: String = str(WorldDB.get_entity("npc", a).name).get_slice(" ", 0)
	var nb: String = str(WorldDB.get_entity("npc", b).name).get_slice(" ", 0)
	var friendly := rng.randf() < 0.75
	var note := ("%s y %s cenaron juntos y se rieron mucho." if friendly else "%s y %s discutieron por una tontería y no se hablan.") % [na, nb]
	NPCMemory.add_bond(a, b, note)
	NPCMemory.add_bond(b, a, note)
	add_news(note)


## El periódico: lo último que ha pasado en el pueblo y lo que hiciste tú.
func add_news(text: String) -> void:
	var list: Array = WorldDB.get_state("news", [])
	list.append({"at": WorldClock.absolute_minutes(), "text": text})
	while list.size() > 20:
		list.pop_front()
	WorldDB.set_state("news", list)


func newspaper() -> String:
	var lines := PackedStringArray(["EL ECO DE LA BAHÍA — %s, %s" % [WorldClock.weekday().capitalize(), Weather.season()], ""])
	for e in today():
		lines.append("· AGENDA: %s, %s." % [e.text, WorldClock.span(e.from, e.to)])
	var news: Array = WorldDB.get_state("news", [])
	for i in range(news.size() - 1, maxi(-1, news.size() - 7), -1):
		lines.append("· " + str(news[i].text))
	# Lo que hiciste tú (encargos cumplidos, compras grandes…)
	for q in Quests.all_quests():
		if q.status == "done" and q.get("location_id", "") == GameState.HOME:
			lines.append("· Vecinos agradecen a un vecino su ayuda con «%s»." % q.title)
	lines.append("· El tiempo: %s Unos %d °C." % [Weather.describe(), roundi(Weather.temperature())])
	lines.append("· Avisos: mercado los sábados por la mañana en la plaza; partido los domingos a mediodía; autobús a Puerto Alto de 6 a. m. a 11 p. m. ($2).")
	return "\n".join(lines)

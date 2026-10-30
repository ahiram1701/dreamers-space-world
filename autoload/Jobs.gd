extends Node
## Tu trabajo: quién te contrató, dónde, de qué, en qué horario y por cuánto. Vas a tu sitio en tu
## turno y trabajas (E): pasan las horas y cobras. Si llegas tarde cobras menos; si faltas, tu jefe
## lo recuerda y, a la tercera falta seguida, te despide.

signal hired(job: Dictionary)
signal fired(reason: String)
signal shift_done(result: Dictionary)

const LATE_AFTER := 0.5        # horas de cortesía
const FIRE_AFTER_MISSES := 3

var _last_check := -1.0


func job() -> Dictionary:
	return WorldDB.get_state("job", {}) if WorldDB.is_loaded() else {}


func has_job() -> bool:
	return not job().is_empty()


## Un PNJ te contrata. `place`: id de la puerta (o nombre del sitio) donde se trabaja.
func hire(employer: String, title: String, wage: int, start_hour: int, end_hour: int, place: String, place_label: String, text: String = "") -> Dictionary:
	if start_hour == end_hour:
		end_hour = (start_hour + 6) % 24
	var j := {"employer": employer, "title": title.left(60), "wage": clampi(wage, 1, Wallet.MAX_PER_ACTION),
		"start_hour": clampi(start_hour, 0, 23), "end_hour": clampi(end_hour, 0, 23), "days": [0, 1, 2, 3, 4],
		"place": place, "place_label": place_label, "location": GameState.current_location(), "text": text.left(200),
		"missed": 0, "worked": 0, "last_day": int(WorldClock.absolute_minutes() / 1440.0) - 1}
	WorldDB.set_state("job", j)
	NPCMemory.add_event(employer, "Contrataste al jugador como %s (%s, de %02d:00 a %02d:00, $%d por turno)." % [j.title, place_label, j.start_hour, j.end_hour, j.wage])
	hired.emit(j)
	return j


func quit(reason: String) -> void:
	var j := job()
	if j.is_empty():
		return
	WorldDB.set_state("job", {})
	NPCMemory.add_event(j.employer, reason)
	fired.emit(reason)


func _day() -> int:
	return int(WorldClock.absolute_minutes() / 1440.0)


func _weekday() -> int:
	return WorldClock.WEEKDAYS.find(WorldClock.weekday())


func works_today() -> bool:
	var j := job()
	return not j.is_empty() and _weekday() in j.days and int(j.get("last_day", -1)) != _day()


## Horas del turno (si acaba después de medianoche, end > 24).
func _span() -> Vector2:
	var j := job()
	var s := float(j.start_hour)
	var e := float(j.end_hour)
	return Vector2(s, e if e > s else e + 24.0)


## ¿Se puede empezar el turno ahora? (desde media hora antes hasta una hora antes de acabar)
func can_work_now() -> bool:
	if not works_today():
		return false
	var span := _span()
	var h := WorldClock.hour()
	return h >= span.x - 0.5 and h <= span.y - 1.0


## Horas que faltan para el turno de hoy (negativo si ya empezó; INF si hoy no toca).
func hours_until_shift() -> float:
	if not works_today():
		return INF
	return _span().x - WorldClock.hour()


## Trabajar el turno: pasan las horas que quedan, cobras (menos si llegas tarde).
func work_shift() -> Dictionary:
	var j := job()
	if j.is_empty() or not can_work_now():
		return {}
	var span := _span()
	var h := WorldClock.hour()
	var late := maxf(h - span.x, 0.0)
	var hours := span.y - maxf(h, span.x)
	var pay := int(round(j.wage * clampf(hours / (span.y - span.x), 0.2, 1.0)))
	WorldClock.advance(maxf(span.y - h, 0.0) * 60.0)
	Wallet.reason = "Sueldo: %s" % j.title
	Wallet.earn(pay)
	j.worked = int(j.worked) + 1
	j.missed = 0
	j.last_day = _day()
	WorldDB.set_state("job", j)
	if late > LATE_AFTER:
		NPCMemory.add_event(j.employer, "El jugador llegó %d minutos tarde a su turno." % roundi(late * 60.0), -4)
	else:
		NPCMemory.add_event(j.employer, "El jugador cumplió su turno de %s." % j.title, 2)
	var result := {"paid": pay, "late_minutes": roundi(late * 60.0), "hours": hours, "title": j.title}
	shift_done.emit(result)
	return result


## Faltas: si el turno de hoy terminó y no fuiste, cuenta. A la tercera seguida, despido.
func check_missed() -> void:
	var j := job()
	if j.is_empty() or not works_today():
		return
	var span := _span()
	if WorldClock.hour() < span.y or span.y > 24.0:
		return
	j.missed = int(j.missed) + 1
	j.last_day = _day()
	WorldDB.set_state("job", j)
	NPCMemory.add_event(j.employer, "El jugador faltó a su turno sin avisar (%d %s seguidas)." % [j.missed, "falta" if j.missed == 1 else "faltas"], -6)
	if int(j.missed) >= FIRE_AFTER_MISSES:
		quit("Despediste al jugador por faltar %d veces seguidas." % j.missed)


## Si su jefe/a está en su turno, quien está trabajando es el jugador (para el contexto de la IA).
func describe() -> String:
	var j := job()
	if j.is_empty():
		return "No tienes trabajo."
	var boss: String = WorldDB.get_entity("npc", j.employer).get("name", "alguien")
	var d := "Trabajas de %s en %s para %s, de %02d:00 a %02d:00 de lunes a viernes, por $%d el turno." % [j.title, j.place_label, boss, j.start_hour, j.end_hour, j.wage]
	if int(j.missed) > 0:
		d += " Llevas %d falta(s) seguidas." % j.missed
	var until := hours_until_shift()
	if until != INF and until > 0.0 and until < 3.0:
		d += " Tu turno de hoy empieza en %d min." % roundi(until * 60.0)
	elif can_work_now():
		d += " Ahora mismo es tu turno."
	return d


func _process(_delta: float) -> void:
	if not WorldDB.is_loaded():
		return
	var m := WorldClock.absolute_minutes()
	if m - _last_check >= 15.0:
		_last_check = m
		check_missed()

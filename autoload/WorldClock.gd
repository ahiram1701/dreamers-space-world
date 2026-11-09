extends Node
## Hora del mundo. Un día de juego dura Settings.day_minutes reales (2 h por defecto; se puede
## elegir hasta tiempo real). Mueve el sol, enciende farolas y ventanas, y los PNJs siguen su rutina.
## Se guarda en WorldDB ("clock"), así que cada mundo tiene su propia hora.

signal hour_changed(hour: int)

const START_HOUR := 18.5     # el Acto 0 empieza al atardecer
const SAVE_EVERY := 20.0     # segundos reales entre guardados

var paused := false

var _minutes := START_HOUR * 60.0
var _day := 0                # días completos que han pasado (para "hasta mañana", rencores…)
var _last_hour := -1
var _since_save := 0.0
var _loaded_world := ""


func _process(delta: float) -> void:
	if not WorldDB.is_loaded():
		return
	if _loaded_world != WorldDB.world_id:  # otro mundo: su propia hora
		_loaded_world = WorldDB.world_id
		_minutes = float(WorldDB.get_state("clock", START_HOUR * 60.0))
		_day = int(WorldDB.get_state("clock_day", 0))
		_last_hour = -1
	if paused or get_tree().paused:
		return
	_minutes += delta * (24.0 / maxf(Settings.day_minutes, 1.0))
	if _minutes >= 24.0 * 60.0:
		_minutes -= 24.0 * 60.0
		_day += 1
		WorldDB.set_state("clock_day", _day)
	var h := int(_minutes / 60.0)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	_since_save += delta
	if _since_save > SAVE_EVERY:
		_since_save = 0.0
		WorldDB.set_state("clock", _minutes)


## Hora con decimales (18.5 = 18:30).
func hour() -> float:
	return _minutes / 60.0


func set_hour(h: float) -> void:
	_minutes = fposmod(h, 24.0) * 60.0
	if WorldDB.is_loaded():
		WorldDB.set_state("clock", _minutes)
	_last_hour = -1


## Pasa el tiempo de golpe (una acción que dura, dormir…). Cuenta los días que cruza.
func advance(minutes: float) -> void:
	var total := _minutes + maxf(minutes, 0.0)
	_day += int(total / (24.0 * 60.0))
	if WorldDB.is_loaded():
		WorldDB.set_state("clock_day", _day)
	set_hour(fmod(total, 24.0 * 60.0) / 60.0)


const WEEKDAYS := ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]


## Día de la semana (cada mundo empieza un jueves).
func weekday() -> String:
	return WEEKDAYS[(_day + 3) % 7]


## Minutos de juego desde el principio del mundo (no vuelve a 0 a medianoche).
func absolute_minutes() -> float:
	return _day * 24.0 * 60.0 + _minutes


## La hora de ahora en formato de 12 horas: «3:33 a. m.», «12:05 p. m.».
func text() -> String:
	return fmt(_minutes / 60.0)


## Una hora (3.5 = 3:30) en formato de 12 horas, como se dice en México.
static func fmt(h: float) -> String:
	var total := int(round(fposmod(h, 24.0) * 60.0)) % 1440
	var h24 := total / 60
	var h12 := h24 % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, total % 60, "a. m." if h24 < 12 else "p. m."]


## Un intervalo de horas enteras: «de 9:00 a. m. a 8:00 p. m.».
static func span(from_h: float, to_h: float) -> String:
	return "de %s a %s" % [fmt(from_h), fmt(to_h)]


## Altura del sol: 1 a mediodía, 0 al amanecer/atardecer (6:00 y 20:00), negativa de noche.
func sun_height() -> float:
	var h := hour()
	return sin((h - 6.5) / 13.5 * PI) if h >= 6.5 and h <= 20.0 else -sin(fposmod(h - 20.0, 24.0) / 10.5 * PI) * 0.6


## 0 de día, 1 de noche cerrada.
func night() -> float:
	return clampf(-sun_height() * 4.0 + 0.15, 0.0, 1.0)


func describe() -> String:
	var h := hour()
	var part := "de madrugada" if h < 6 else "por la mañana" if h < 12 else "a mediodía" if h < 14 \
		else "por la tarde" if h < 19 else "al atardecer" if h < 21 else "de noche"
	return "Es %s y son las %s (%s)." % [weekday(), text(), part]

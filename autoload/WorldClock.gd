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
	return WEEKDAYS[weekday_index()]


## 0 = lunes … 4 = viernes, 5 = sábado, 6 = domingo.
func weekday_index() -> int:
	return (_day + 3) % 7


func is_weekend() -> bool:
	return weekday_index() >= 5


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


## Sol de verdad: latitud del pueblo (costa del Pacífico mexicano), mediodía solar (con el horario
## local cae pasada la una) y un año de juego de 4 estaciones de 30 días (Weather.season()).
const LATITUDE := 20.0
const SOLAR_NOON := 13.25
const YEAR_DAYS := 120.0
const TILT := 23.44


## Día del año de juego (0 = equinoccio de primavera, 30 = solsticio de verano…).
func day_of_year() -> float:
	return fposmod(absolute_minutes() / 1440.0, YEAR_DAYS)


## Declinación del sol (grados) ese día: +23.4 en pleno verano, -23.4 en invierno.
static func declination(doy: float) -> float:
	return TILT * sin(doy / YEAR_DAYS * TAU)


## Seno de la elevación del sol a una hora y día: 1 = en el cénit, 0 = en el horizonte,
## negativo de noche (-0.2 ≈ noche cerrada).
static func solar_height(h: float, doy: float) -> float:
	var lat := deg_to_rad(LATITUDE)
	var dec := deg_to_rad(declination(doy))
	var ha := deg_to_rad((h - SOLAR_NOON) * 15.0)
	return sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)


## Horas de sol (amanecer, ocaso) de un día: más largo en verano, más corto en invierno.
static func daylight(doy: float) -> Vector2:
	var lat := deg_to_rad(LATITUDE)
	var dec := deg_to_rad(declination(doy))
	var half := rad_to_deg(acos(clampf(-tan(lat) * tan(dec), -1.0, 1.0))) / 15.0
	return Vector2(SOLAR_NOON - half, SOLAR_NOON + half)


## Amanecer y ocaso de hoy (horas con decimales).
func sunrise() -> float:
	return daylight(day_of_year()).x


func sunset() -> float:
	return daylight(day_of_year()).y


## Altura del sol ahora (ver solar_height): 0 al amanecer y al ocaso, negativa de noche.
func sun_height() -> float:
	return solar_height(hour(), day_of_year())


## Hacia dónde está el sol (vector unitario) a una hora y día. Los ejes del pueblo de siempre:
## sale por -X, a mediodía está hacia +Z (el sur) y se pone por +X.
static func solar_direction(h: float, doy: float) -> Vector3:
	var lat := deg_to_rad(LATITUDE)
	var dec := deg_to_rad(declination(doy))
	var ha := deg_to_rad((h - SOLAR_NOON) * 15.0)
	var east := -cos(dec) * sin(ha)
	var north := cos(lat) * sin(dec) - sin(lat) * cos(dec) * cos(ha)
	var up := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)
	return Vector3(-east, up, -north).normalized()


func sun_direction() -> Vector3:
	return solar_direction(hour(), day_of_year())


## 0 de día, 1 de noche cerrada.
func night() -> float:
	return clampf(-sun_height() * 4.0 + 0.15, 0.0, 1.0)


func describe() -> String:
	var h := hour()
	var part := "de madrugada" if h < 6 else "por la mañana" if h < 12 else "a mediodía" if h < 14 \
		else "por la tarde" if h < 19 else "al atardecer" if h < 21 else "de noche"
	return "Es %s y son las %s (%s)." % [weekday(), text(), part]

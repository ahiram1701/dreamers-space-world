extends Node
## El cuerpo del jugador: hambre, sed, descanso e higiene (0 = fatal, 100 = perfecto). Bajan con
## el tiempo de juego y se recuperan comiendo, bebiendo, durmiendo o lavándose (lo decide la IA con
## `change_need`, o dormir en una cama). Efectos suaves: nunca matan, solo ralentizan y se notan.

signal need_changed(need: String, value: float)

const NEEDS := ["hunger", "thirst", "rest", "hygiene"]
const LABELS := {"hunger": "Hambre", "thirst": "Sed", "rest": "Descanso", "hygiene": "Higiene"}
## Horas de juego en vaciarse del todo.
const HOURS_TO_EMPTY := {"hunger": 16.0, "thirst": 10.0, "rest": 18.0, "hygiene": 30.0}
const LOW := 25.0
const SAVE_EVERY := 20.0

## Esfuerzo actual (1 andar, ~1.8 correr o nadar): cansa más deprisa. Lo pone el jugador.
var exertion := 1.0

var _values := {"hunger": 85.0, "thirst": 85.0, "rest": 90.0, "hygiene": 90.0}
var _last_minutes := -1.0
var _loaded_world := ""
var _since_save := 0.0


func _process(delta: float) -> void:
	if not WorldDB.is_loaded():
		return
	if _loaded_world != WorldDB.world_id:
		_load()
	var now := WorldClock.absolute_minutes()
	if _last_minutes < 0.0:
		_last_minutes = now
	var minutes := now - _last_minutes
	_last_minutes = now
	if minutes > 0.0 and minutes < 60.0 * 24.0 * 3.0:
		_decay(minutes)
	_since_save += delta
	if _since_save > SAVE_EVERY:
		_since_save = 0.0
		save()


func _load() -> void:
	_loaded_world = WorldDB.world_id
	var saved: Dictionary = WorldDB.get_state("body", {})
	for n in NEEDS:
		_values[n] = float(saved.get(n, 85.0))
	_last_minutes = WorldClock.absolute_minutes()


func save() -> void:
	if WorldDB.is_loaded():
		WorldDB.set_state("body", _values.duplicate())


func _decay(minutes: float) -> void:
	for n in NEEDS:
		var rate: float = 100.0 / (HOURS_TO_EMPTY[n] * 60.0)
		if n == "rest" or n == "thirst":
			rate *= exertion
		_store(n, _values[n] - rate * minutes)


func get_need(n: String) -> float:
	return float(_values.get(n, 100.0))


## Sube o baja una necesidad (comer +40 hambre, ducharse +80 higiene…).
func change(n: String, amount: float) -> void:
	if _values.has(n):
		_store(n, _values[n] + amount)
		save()


func set_need(n: String, value: float) -> void:
	if _values.has(n):
		_store(n, value)
		save()


func _store(n: String, v: float) -> void:
	var old: float = _values[n]
	_values[n] = clampf(v, 0.0, 100.0)
	if absf(old - _values[n]) >= 0.5 or (old >= LOW) != (_values[n] >= LOW):
		need_changed.emit(n, _values[n])


## Multiplicador de velocidad: con mucha hambre, sed o sueño se va más despacio (nunca menos de 0.7).
func speed_factor() -> float:
	var f := 1.0
	if get_need("rest") < 15.0:
		f -= 0.2
	if get_need("hunger") < LOW or get_need("thirst") < LOW:
		f -= 0.1
	return maxf(f, 0.7)


## Lo que siente el cuerpo, en palabras (para la IA y los avisos).
func describe() -> String:
	var parts := PackedStringArray()
	var words := {
		"hunger": ["estás famélico/a", "tienes mucha hambre", "tienes algo de hambre"],
		"thirst": ["estás muerto/a de sed", "tienes mucha sed", "tienes algo de sed"],
		"rest": ["te caes de sueño", "estás muy cansado/a", "estás algo cansado/a"],
		"hygiene": ["hueles bastante mal", "vas sucio/a", "necesitarías una ducha"],
	}
	for n in NEEDS:
		var v := get_need(n)
		if v < 10.0:
			parts.append(words[n][0])
		elif v < LOW:
			parts.append(words[n][1])
		elif v < 45.0:
			parts.append(words[n][2])
	if parts.is_empty():
		return "Te encuentras bien."
	var s := ", ".join(parts)
	return s.left(1).to_upper() + s.substr(1) + "."


## La necesidad más urgente (o "").
func most_urgent() -> String:
	var best := ""
	var low := 45.0
	for n in NEEDS:
		if get_need(n) < low:
			best = n
			low = get_need(n)
	return best

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
## Lo que se ve en ti (0..1): mojado (lluvia, nadar, ducha) y sucio (talar, cavar, trabajar).
var wet := 0.0
var dirt := 0.0
## Complexión que cambia despacio con cómo vives (-1 más delgado … +1 más ancho).
var shape := 0.0

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
	_weather(delta)
	_since_save += delta
	if _since_save > SAVE_EVERY:
		_since_save = 0.0
		save()


func _load() -> void:
	_loaded_world = WorldDB.world_id
	var saved: Dictionary = WorldDB.get_state("body", {})
	for n in NEEDS:
		_values[n] = float(saved.get(n, 85.0))
	wet = float(saved.get("wet", 0.0))
	dirt = float(saved.get("dirt", 0.0))
	shape = float(saved.get("shape", 0.0))
	_last_minutes = WorldClock.absolute_minutes()


func save() -> void:
	if WorldDB.is_loaded():
		var out := _values.duplicate()
		out["wet"] = snappedf(wet, 0.01)
		out["dirt"] = snappedf(dirt, 0.01)
		out["shape"] = snappedf(shape, 0.001)
		WorldDB.set_state("body", out)


func _decay(minutes: float) -> void:
	for n in NEEDS:
		var rate: float = 100.0 / (HOURS_TO_EMPTY[n] * 60.0)
		if n == "rest" or n == "thirst":
			rate *= exertion
		if n == "hygiene":
			rate *= 1.0 + dirt * 2.0  # sucio, la higiene se va antes
		_store(n, _values[n] - rate * minutes)
	# El cuerpo cambia despacio (semanas de juego): bien comido y sin moverte, te ensanchas; moverte
	# mucho o pasar hambre te afina. Muy poco por hora.
	var fed := 1.0 if get_need("hunger") > 75.0 else (-1.0 if get_need("hunger") < 25.0 else 0.0)
	var active := 1.0 if exertion > 1.2 else 0.0
	shape = clampf(shape + (fed * 0.6 - active * 1.2 - 0.05) * minutes / (60.0 * 24.0 * 14.0), -1.0, 1.0)


## Lluvia y agua: sin techo te mojas; bajo techo o al sol te secas poco a poco.
func _weather(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var swimming: bool = player.get("_swimming") == true
	var indoors := player.global_position.y < -300.0  # en un interior (bajo InteriorManager.ORIGIN)
	if swimming:
		wet = 1.0
	elif Weather.is_raining() and not indoors:
		wet = minf(wet + delta / 40.0, 1.0)   # en menos de un minuto, calado
	else:
		wet = maxf(wet - delta / (150.0 if indoors else 240.0), 0.0)


## Ensuciarte haciendo algo (talar, cavar, arrodillarte en el suelo, trabajar).
func soil(amount: float) -> void:
	dirt = clampf(dirt + amount, 0.0, 1.0)


## Ducha: limpio (y un poco mojado, el pelo).
func shower() -> void:
	dirt = 0.0
	wet = maxf(wet, 0.35)
	set_need("hygiene", 100.0)


## Ropa limpia: lo sucio era la ropa, la piel sigue igual (la mitad).
func set_clean_clothes() -> void:
	dirt *= 0.5
	wet *= 0.3


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
	if wet > 0.6:
		parts.append("estás empapado/a")
	elif wet > 0.25:
		parts.append("vas algo mojado/a")
	if dirt > 0.5:
		parts.append("llevas la ropa manchada de tierra")
	elif dirt > 0.2:
		parts.append("tienes la ropa algo sucia")
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

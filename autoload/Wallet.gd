extends Node
## El dinero del jugador (dólares). Empieza con $40 en cada mundo. Solo se paga lo que se tiene, y ninguna
## acción mueve más de MAX_PER_ACTION de una vez (la IA no te hace millonario por pedirlo).

signal changed(amount: int, delta: int)

const START := 40
const MAX_PER_ACTION := 300
const SYMBOL := "$"
const MAX_LOG := 20


func amount() -> int:
	return int(WorldDB.get_state("money", START)) if WorldDB.is_loaded() else START


func can_pay(x: int) -> bool:
	return x >= 0 and x <= amount()


## Paga `x` (true si había bastante). Lo que no se puede pagar no se paga.
func pay(x: int) -> bool:
	x = clampi(x, 0, MAX_PER_ACTION)
	if x == 0 or not can_pay(x):
		return false
	_store(amount() - x, -x)
	return true


## Recibe `x` (acotado a MAX_PER_ACTION).
func earn(x: int) -> int:
	x = clampi(x, 0, MAX_PER_ACTION)
	if x > 0:
		_store(amount() + x, x)
	return x


func text(x: int = -1) -> String:
	return "%s%d" % [SYMBOL, amount() if x < 0 else x]


## Últimos movimientos (para el banco del celular): [{at, delta, what}]
func log_entries() -> Array:
	return WorldDB.get_state("money_log", []) if WorldDB.is_loaded() else []


## Qué fue el último movimiento (lo pone quien paga o cobra).
var reason := ""


func _store(v: int, delta: int) -> void:
	WorldDB.set_state("money", maxi(v, 0))
	var log: Array = WorldDB.get_state("money_log", [])
	log.append({"at": WorldClock.absolute_minutes(), "delta": delta, "what": reason})
	while log.size() > MAX_LOG:
		log.pop_front()
	WorldDB.set_state("money_log", log)
	reason = ""
	changed.emit(maxi(v, 0), delta)

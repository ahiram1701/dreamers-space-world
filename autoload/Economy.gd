extends Node
## La vida cuesta dinero: alquilar un piso, pagar facturas cada semana, ahorrar en el banco o
## pedir un préstamo. Se guarda en WorldDB ("economy").
##
## economy = { rent: {door, label, weekly} | {}, savings, loan, loan_weekly, unpaid_weeks,
##             last_bill_day, history: [...] }

signal bill_paid(text: String)
signal bill_unpaid(text: String)
signal evicted(text: String)

const UTILITIES := 15          # luz y agua por semana
const SAVINGS_RATE := 0.01     # 1 % semanal de interés
const LOAN_RATE := 0.08        # 8 % por pedirlo
const LOAN_WEEKS := 8
const MAX_UNPAID := 2          # a la tercera semana sin pagar, desahucio

var _check_t := 0.0


func _state() -> Dictionary:
	return WorldDB.get_state("economy", {"rent": {}, "savings": 0, "loan": 0, "loan_weekly": 0, "unpaid_weeks": 0,
		"last_bill_day": -1, "history": []}) if WorldDB.is_loaded() else {}


func _save(s: Dictionary) -> void:
	WorldDB.set_state("economy", s)


func rental() -> Dictionary:
	return _state().get("rent", {})


func savings() -> int:
	return int(_state().get("savings", 0))


func loan() -> int:
	return int(_state().get("loan", 0))


## Alquilas un piso: pagas la primera semana y fianza. Devuelve el texto de lo que pasó.
func rent(door: String, label: String, weekly: int) -> String:
	var s := _state()
	if not s.rent.is_empty():
		return "Ya tienes alquilado %s." % s.rent.label
	if Wallet.amount() < weekly * 2:
		return "Para alquilar %s necesitas %s (la primera semana y la fianza)." % [label, Wallet.text(weekly * 2)]
	Wallet.reason = "Alquiler y fianza"
	Wallet.pay(weekly * 2)
	s.rent = {"door": door, "label": label, "weekly": weekly}
	s.last_bill_day = _day()
	s.unpaid_weeks = 0
	_log(s, "Alquilaste %s por %s a la semana." % [label, Wallet.text(weekly)])
	_save(s)
	Journal.add("Contrato de alquiler: %s, %s por semana más %s de luz y agua. Se cobra cada 7 días." % [label, Wallet.text(weekly), Wallet.text(UTILITIES)])
	return "Firmas el contrato: %s es tu casa. Pagas %s cada semana, más luz y agua." % [label, Wallet.text(weekly)]


func end_rent() -> String:
	var s := _state()
	if s.rent.is_empty():
		return "No tienes nada alquilado."
	var label: String = s.rent.label
	s.rent = {}
	_save(s)
	return "Dejas %s y devuelves las llaves." % label


func deposit(amount: int) -> String:
	amount = mini(amount, Wallet.amount())
	if amount <= 0:
		return "No llevas dinero para ingresar."
	var s := _state()
	Wallet.reason = "Ingreso en el banco"
	Wallet.pay(amount)
	s.savings = int(s.savings) + amount
	_log(s, "Ingresaste %s." % Wallet.text(amount))
	_save(s)
	return "Ingresas %s. En la cuenta tienes %s." % [Wallet.text(amount), Wallet.text(s.savings)]


func withdraw(amount: int) -> String:
	var s := _state()
	amount = mini(amount, int(s.savings))
	if amount <= 0:
		return "No tienes ahorros en la cuenta."
	s.savings = int(s.savings) - amount
	Wallet.reason = "Retirada del banco"
	Wallet.earn(amount)
	_log(s, "Retiraste %s." % Wallet.text(amount))
	_save(s)
	return "Sacas %s. Te quedan %s en la cuenta." % [Wallet.text(amount), Wallet.text(s.savings)]


func take_loan(amount: int) -> String:
	var s := _state()
	if int(s.loan) > 0:
		return "Ya tienes un préstamo: te quedan %s por pagar." % Wallet.text(s.loan)
	var total := int(round(amount * (1.0 + LOAN_RATE)))
	s.loan = total
	s.loan_weekly = int(ceil(total / float(LOAN_WEEKS)))
	Wallet.reason = "Préstamo del banco"
	Wallet.earn(amount)
	_log(s, "Pediste un préstamo de %s (devuelves %s en %d semanas)." % [Wallet.text(amount), Wallet.text(total), LOAN_WEEKS])
	_save(s)
	return "El banco te presta %s. Pagarás %s cada semana durante %d semanas." % [Wallet.text(amount), Wallet.text(s.loan_weekly), LOAN_WEEKS]


## Lo que se cobra esta semana (alquiler + luz y agua + cuota del préstamo).
func weekly_bill() -> int:
	var s := _state()
	var total := 0
	if not s.rent.is_empty():
		total += int(s.rent.weekly) + UTILITIES
	if int(s.loan) > 0:
		total += mini(int(s.loan_weekly), int(s.loan))
	return total


func _process(delta: float) -> void:
	_check_t += delta
	if _check_t < 2.0 or not WorldDB.is_loaded():
		return
	_check_t = 0.0
	check_week()


## Cada 7 días de juego: se cobra la semana, los ahorros dan interés y, si no pagas, avisos y,
## a la tercera, desahucio.
func check_week() -> void:
	var s := _state()
	if s.is_empty():
		return
	if int(s.last_bill_day) < 0:
		s.last_bill_day = _day()
		_save(s)
		return
	if _day() - int(s.last_bill_day) < 7:
		return
	s.last_bill_day = int(s.last_bill_day) + 7
	if int(s.savings) > 0:
		s.savings = int(s.savings) + int(floor(int(s.savings) * SAVINGS_RATE))
	var bill := weekly_bill()
	if bill <= 0:
		_save(s)
		return
	if Wallet.amount() >= bill:
		Wallet.reason = "Facturas de la semana"
		Wallet.pay(bill)
		if int(s.loan) > 0:
			s.loan = maxi(0, int(s.loan) - int(s.loan_weekly))
		s.unpaid_weeks = 0
		var text := "Pagas las facturas de la semana: %s." % Wallet.text(bill)
		_log(s, text)
		_save(s)
		bill_paid.emit(text)
		return
	s.unpaid_weeks = int(s.unpaid_weeks) + 1
	if int(s.unpaid_weeks) > MAX_UNPAID and not s.rent.is_empty():
		var label: String = s.rent.label
		s.rent = {}
		s.unpaid_weeks = 0
		var t := "Desahucio: tras %d semanas sin pagar, pierdes %s." % [MAX_UNPAID + 1, label]
		_log(s, t)
		_save(s)
		evicted.emit(t)
		return
	var warn := "No te llega para las facturas (%s). Aviso %d de %d." % [Wallet.text(bill), int(s.unpaid_weeks), MAX_UNPAID]
	_log(s, warn)
	_save(s)
	bill_unpaid.emit(warn)


func describe() -> String:
	var s := _state()
	var parts := PackedStringArray()
	if not s.rent.is_empty():
		parts.append("Vives de alquiler en %s (%s/semana)." % [s.rent.label, Wallet.text(s.rent.weekly)])
	if int(s.savings) > 0:
		parts.append("Ahorros en el banco: %s." % Wallet.text(s.savings))
	if int(s.loan) > 0:
		parts.append("Debes al banco %s." % Wallet.text(s.loan))
	if int(s.unpaid_weeks) > 0:
		parts.append("Tienes facturas sin pagar.")
	return " ".join(parts)


func _day() -> int:
	return int(WorldClock.absolute_minutes() / 1440.0)


func _log(s: Dictionary, text: String) -> void:
	var h: Array = s.get("history", [])
	h.append({"at": WorldClock.absolute_minutes(), "text": text})
	while h.size() > 30:
		h.pop_front()
	s.history = h
	Journal.log_event(text, "money")

extends Node
## Stats del viajero y dónde está. Aparecen con El Despertar: antes, el jugador es una persona común.
## Persiste en WorldDB ("game"), así que cada mundo tiene su propio estado.

signal stat_changed(stat: String, value: int)
signal location_changed(location_id: String)

const MAX_STAT := 100
const JUMP_ENERGY := 25
const JUMP_INSTABILITY := 12
const RETURN_ENERGY := 15            # volver a un lugar ya visitado: la ruta ya está calculada
const SEALED_HOME_ENERGY := 80       # volver al pueblo si sellaste la brecha detrás de ti
const RECHARGE_INSTABILITY_RELIEF := 10
const HOME := "home"                 # location_id especial: Bahía de las Horas (Acto 0)


func is_awakened() -> bool:
	return _state().awakened


func get_stat(stat: String) -> int:
	return int(_state().stats.get(stat, 0))


func set_stat(stat: String, value: int) -> void:
	var s := _state()
	s.stats[stat] = clampi(value, 0, MAX_STAT)
	_save(s)
	stat_changed.emit(stat, s.stats[stat])


func change_stat(stat: String, delta: int) -> void:
	set_stat(stat, get_stat(stat) + delta)


func companion() -> String:
	return _state().companion


func sealed_home() -> bool:
	return _state().sealed_home


func current_location() -> String:
	return _state().location


## Coste en energía de ir a `target` ("new" para un destino nuevo).
func travel_cost(target: String) -> int:
	if target == "new":
		return JUMP_ENERGY
	if target == HOME and sealed_home():
		return SEALED_HOME_ENERGY
	return RETURN_ENERGY


func can_travel(target: String) -> bool:
	return is_awakened() and get_stat("energy") >= travel_cost(target)


## Llamado por StoryDirector al aplicar la decisión del Despertar.
func awaken(companion_id: String, sealed: bool) -> void:
	var s := _state()
	s.awakened = true
	s.companion = companion_id
	s.sealed_home = sealed
	s.stats = {"health": MAX_STAT, "energy": MAX_STAT, "instability": 0}
	_save(s)


## Paga el salto y mueve al jugador. Devuelve false si no hay energía.
func travel(target_location: String, cost: int, new_branch: bool) -> bool:
	if get_stat("energy") < cost:
		return false
	change_stat("energy", -cost)
	change_stat("instability", JUMP_INSTABILITY if new_branch else JUMP_INSTABILITY / 2)
	if get_stat("instability") >= MAX_STAT:
		change_stat("health", -20)  # decoherencia: el cuerpo paga el exceso
	set_location(target_location)
	return true


func recharge() -> void:
	set_stat("energy", MAX_STAT)
	change_stat("instability", -RECHARGE_INSTABILITY_RELIEF)


func set_location(location_id: String) -> void:
	var s := _state()
	s.location = location_id
	_save(s)
	location_changed.emit(location_id)


func _state() -> Dictionary:
	var s: Dictionary = WorldDB.get_state("game", {})
	for k in ["awakened", "companion", "sealed_home", "location", "stats"]:
		if not s.has(k):
			s[k] = {"awakened": false, "companion": "", "sealed_home": false, "location": HOME, "stats": {}}[k]
	return s


func _save(s: Dictionary) -> void:
	WorldDB.set_state("game", s)

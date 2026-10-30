class_name Passersby
extends Node
## Gente de paso: personas sin nombre que van de un sitio a otro y entran por las puertas, más de
## día que de noche y casi nadie de madrugada o con lluvia. No cuestan IA. Si le hablas a una,
## pasa a ser alguien de verdad (se crea su ficha y se queda a vivir en el lugar).

const NAMES_F := ["Lucía", "Valeria", "Camila", "Sofía", "Daniela", "Renata", "Elena", "Paula", "Andrea", "Marta", "Inés", "Julia"]
const NAMES_M := ["Mateo", "Diego", "Tomás", "Andrés", "Pablo", "Joaquín", "Bruno", "Martín", "Hugo", "Iván", "Rafael", "Gabriel"]
const SURNAMES := ["Rojas", "Herrera", "Molina", "Ortiz", "Navarro", "Castro", "Vega", "Ramos", "Silva", "Fuentes", "Paredes", "Cruz"]
const JOBS := ["vecina del barrio", "repartidor", "pescadora", "maestra jubilada", "estudiante", "electricista", "enfermera",
	"carpintero", "dependienta", "jardinero", "taxista", "panadera"]

var scene: LocationScene

var _walkers: Array = []   # TownNPC de paso
var _t := 0.0
var _serial := 0


func target_count() -> int:
	var h := WorldClock.hour()
	var n := 0
	if h >= 7.0 and h < 9.0:
		n = 4
	elif h >= 9.0 and h < 20.0:
		n = 8
	elif h >= 20.0 and h < 23.0:
		n = 4
	elif h >= 23.0 or h < 1.0:
		n = 1
	if Weather.is_raining():
		n = n / 2
	return mini(n, [3, 6, 8][Settings.graphics_quality])


func _process(delta: float) -> void:
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	_walkers = _walkers.filter(func(w): return is_instance_valid(w))
	if scene._interiors.is_inside():
		return
	if _walkers.size() < target_count():
		_spawn()
	elif _walkers.size() > target_count() and not _walkers.is_empty():
		_send_home(_walkers[0])


func _places() -> Array:
	return scene._places.keys().filter(func(n): return scene.ground_at(scene._places[n].x, scene._places[n].z) > scene._water_level + 0.2)


func _spawn() -> void:
	var names := _places()
	if names.size() < 2:
		return
	var from: Vector3 = scene._places[names[randi() % names.size()]]
	if from.distance_to(scene._player.global_position) < 18.0:
		return  # que nadie aparezca de la nada delante de ti
	_serial += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fem := rng.randf() < 0.5
	var look := {"figure": "feminine" if fem else "masculine", "outfit": ["casual", "street", "work_uniform", "formal"][rng.randi() % 4],
		"primary_color": Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), rng.randf_range(0.35, 0.8)).to_html(false),
		"secondary_color": Color.from_hsv(rng.randf(), 0.2, 0.75).to_html(false), "body": ["slim", "average", "sturdy", "tall", "elderly"][rng.randi() % 5]}
	var npc := TownNPC.new()
	scene.add_child(npc)
	npc.setup({"id": "extra_%d" % _serial, "name": "?", "appearance": look})
	npc.set_meta("passerby", {"look": look, "fem": fem})
	npc.global_position = scene._on_ground(from + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))) + Vector3(0, 0.3, 0)
	_walkers.append(npc)
	_wander(npc)


func _wander(npc: TownNPC) -> void:
	var names := _places()
	if names.is_empty() or not is_instance_valid(npc):
		return
	var dest: Vector3 = scene._places[names[randi() % names.size()]]
	npc.walk_to(scene._on_ground(dest + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))))
	npc.arrived.connect(func():
		if not is_instance_valid(npc):
			return
		if randf() < 0.45:
			_send_home(npc)  # entra en algún sitio y desaparece
		else:
			npc.set_activity("parado un momento", ["think", "search", ""][randi() % 3])
			get_tree().create_timer(randf_range(4.0, 12.0)).timeout.connect(func(): _wander(npc)), CONNECT_ONE_SHOT)


## Se va por la puerta más cercana (si no hay, se aleja) y desaparece.
func _send_home(npc: TownNPC) -> void:
	if not is_instance_valid(npc):
		return
	var best := Vector3.INF
	for id in scene._interiors.doors():
		var p: Vector3 = scene._interiors.doors()[id].pos
		if best == Vector3.INF or p.distance_to(npc.global_position) < best.distance_to(npc.global_position):
			best = p
	_walkers.erase(npc)
	if best == Vector3.INF or best.distance_to(npc.global_position) > 60.0:
		npc.queue_free()
		return
	npc.walk_to(best)
	npc.arrived.connect(func(): if is_instance_valid(npc): npc.queue_free(), CONNECT_ONE_SHOT)


## Le hablas a alguien de paso: pasa a existir de verdad (ficha, memoria, se queda a vivir aquí).
func promote(npc: TownNPC) -> String:
	var info: Dictionary = npc.get_meta("passerby", {})
	var fem: bool = info.get("fem", false)
	var name: String = (NAMES_F if fem else NAMES_M)[randi() % 12] + " " + SURNAMES[randi() % SURNAMES.size()]
	var job: String = JOBS[randi() % JOBS.size()]
	var id := Actions.build_npc(name, job, "Alguien del lugar con quien te cruzaste por la calle.", "¿Sí? ¿Te puedo ayudar en algo?", info.get("look", {}))
	if id.is_empty():
		return ""
	Actions.add_resident(id, npc.global_position)
	_walkers.erase(npc)
	npc.npc_id = id
	npc.remove_meta("passerby")
	npc.refresh_name(WorldDB.get_entity("npc", id))
	npc.stop()
	return id

class_name Passersby
extends Node
## Gente de paso: personas sin nombre que van de un sitio a otro y entran por las puertas, más de
## día que de noche y casi nadie de madrugada o con lluvia. No cuestan IA. Si le hablas a una,
## pasa a ser alguien de verdad (se crea su ficha y se queda a vivir en el lugar).


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


## Entra por la puerta más cercana y se queda dentro un rato (si entras, la ves ahí: de visita
## en una casa, de cliente en la cafetería). Si no hay puertas cerca, se aleja y desaparece.
func _send_home(npc: TownNPC) -> void:
	if not is_instance_valid(npc):
		return
	var best := ""
	for id in scene._interiors.doors():
		var p: Vector3 = scene._interiors.doors()[id].pos
		if scene._interiors.locked.has(id) or scene._interiors.doors()[id].kind == "home":
			continue  # ni a una puerta cerrada ni a tu casa
		if best.is_empty() or p.distance_to(npc.global_position) < scene._interiors.door_position(best).distance_to(npc.global_position):
			best = id
	_walkers.erase(npc)
	if best.is_empty() or scene._interiors.door_position(best).distance_to(npc.global_position) > 60.0:
		npc.queue_free()
		return
	npc.walk_to(scene._interiors.door_position(best))
	npc.arrived.connect(func():
		if not is_instance_valid(npc):
			return
		var info: Dictionary = npc.get_meta("passerby", {})
		Households.add_guest(best, info.get("look", {}), info.get("fem", false), randf_range(40.0, 150.0))
		Sfx.at(scene, "door", npc.global_position + Vector3(0, 1, 0))
		npc.queue_free(), CONNECT_ONE_SHOT)


## Le hablas a alguien de paso: pasa a existir de verdad (ficha, memoria, se queda a vivir aquí).
func promote(npc: TownNPC) -> String:
	var info: Dictionary = npc.get_meta("passerby", {})
	var fem: bool = info.get("fem", false)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var name := Names.full(fem, rng)
	var look: Dictionary = info.get("look", {})
	var j := Names.job(fem, rng, "elder" if look.get("body", "") == "elderly" else "street")
	if look.get("body", "") == "elderly" and rng.randf() < 0.5:
		j = Names.job(fem, rng, "street")
		j.age = rng.randi_range(maxi(int(j.age), 62), 84)
	var job: String = j.job
	var id := Actions.build_npc(name, job, "Alguien del lugar con quien te cruzaste por la calle.", "¿Sí? ¿Te puedo ayudar en algo?", info.get("look", {}))
	if id.is_empty():
		return ""
	WorldDB.update_entity("npc", id, {"age": int(j.age)})
	var home := npc.global_position
	if InteriorManager.is_interior_pos(home):  # la conociste dentro de un edificio: vive por aquí fuera
		var door: String = info.get("door", scene._interiors.current_door())
		home = scene._interiors.door_position(door) + Vector3(randf_range(-3, 3), 0, randf_range(2, 4))
		Households.remove_guest(door, info.get("look", {}))
	Actions.add_resident(id, home)
	_walkers.erase(npc)
	npc.npc_id = id
	npc.remove_meta("passerby")
	npc.refresh_name(WorldDB.get_entity("npc", id))
	npc.stop()
	return id

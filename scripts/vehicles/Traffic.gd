class_name Traffic
extends Node
## Tráfico del pueblo: de vez en cuando un vecino pasa en coche por la calle principal, por su
## carril, despacio (hasta tres a la vez). Frena si tiene delante a alguien o a otro coche y no
## circula de madrugada. El coche es sólido (no se atraviesa) pero no usa física: sigue el carril.
## Nunca aparece ni desaparece a la vista: entra por un extremo de la calle cuando no lo ves y, al
## llegar al otro, aparca; se va cuando ya no lo miras (antes se esfumaba en mitad del pueblo).

const LANES := [[Vector3(-4.3, 0, -62), Vector3(-4.3, 0, 62)], [Vector3(-5.7, 0, 62), Vector3(-5.7, 0, -62)]]
const SPEED := 8.0   # m/s (~30 km/h)
const MAX_CARS := 3
const HIDE_DIST := 85.0   # más lejos que esto de la cámara (o fuera de cuadro), puede aparecer o irse

var scene: LocationScene
var _cars: Array = []   # [{body, lane, speed, engine, parked}]
var _wait := 6.0
var _next_lane := 0


func _process(delta: float) -> void:
	_wait -= delta
	var h := WorldClock.hour()
	if _wait <= 0.0 and _cars.size() < MAX_CARS and h > 6.5 and h < 23.0 and not scene._interiors.is_inside():
		_wait = randf_range(14.0, 40.0)
		if not _seen(LANES[_next_lane][0]) and _lane_clear(_next_lane):
			_spawn(_next_lane)
			_next_lane = 1 - _next_lane
	for c in _cars.duplicate():
		_drive(c, delta)


## ¿Lo vería el jugador? (cerca de la cámara y dentro de cuadro)
func _seen(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	if cam.global_position.distance_to(p) > HIDE_DIST:
		return false
	if cam.is_position_behind(p + Vector3(0, 1, 0)):
		return cam.global_position.distance_to(p) < 12.0
	return true


func _lane_clear(lane: int) -> bool:
	for c in _cars:
		if int(c.lane) == lane and (c.body as Node3D).global_position.distance_to(LANES[lane][0]) < 14.0:
			return false
	return true


func _drive(c: Dictionary, delta: float) -> void:
	var car: Node3D = c.body
	if not is_instance_valid(car):
		_cars.erase(c)
		return
	var lane: Array = LANES[int(c.lane)]
	var dir: Vector3 = (lane[1] - lane[0]).normalized()
	if bool(c.parked):
		if not _seen(car.global_position):  # aparcado al final de la calle: se va cuando no miras
			car.queue_free()
			_cars.erase(c)
		return
	# Frena si hay alguien o algo delante en el carril
	var want := SPEED
	var ahead := car.global_position + dir * 4.5
	var people: Array = [scene._player] + scene._npcs.values() + scene.get_children().filter(func(n): return n is TownNPC and n.has_meta("passerby"))
	for body in people:
		if body and is_instance_valid(body) and (body as Node3D).visible and (body as Node3D).global_position.distance_to(ahead) < 4.5:
			want = 0.0
	for other in scene.get_children():
		if other != car and (other is Vehicle or other.name.begins_with("TrafficCar")) and (other as Node3D).global_position.distance_to(ahead + dir * 2.0) < 5.0:
			want = 0.0
	var end: Vector3 = lane[1]
	var left: float = (end - car.global_position).dot(dir)
	if left < 8.0:
		want = minf(want, maxf(left - 0.8, 0.0) * 0.9)  # frena para aparcar al final
	c.speed = move_toward(float(c.speed), want, (3.0 if want > float(c.speed) else 7.0) * delta)
	car.global_position += dir * float(c.speed) * delta
	var engine: EngineAudio = c.engine
	if engine:
		engine.rpm = 900.0 + float(c.speed) * 220.0
		engine.load = 0.6 if want > float(c.speed) else 0.15
	if left < 1.3 and float(c.speed) < 0.3:
		c.parked = true
		if engine:
			engine.running = false


func _spawn(lane_i: int) -> void:
	var kind: String = ["sedan", "sedan", "van", "pickup", "taxi", "suv", "hatchback", "delivery"][randi() % 8]
	var k: Dictionary = Vehicle.KIT[kind]
	var car := AnimatableBody3D.new()
	car.name = "TrafficCar_%d" % randi()
	car.sync_to_physics = false
	car.collision_layer = Layers.WORLD
	var lane: Array = LANES[lane_i]
	var dir: Vector3 = (lane[1] - lane[0]).normalized()
	scene.add_child(car)
	car.global_position = lane[0]
	car.rotation.y = atan2(dir.x, dir.z)
	var model := AssetLibrary.instance(Vehicle.KIT_DIR, str(k.model))
	var bs: Vector3 = Vehicle.BIG_SCALE if k.get("big", false) else Vehicle.BODY_SCALE
	var size := Vector3(2.0, 1.7, 4.2)
	if model:
		var holder := Node3D.new()
		holder.scale = bs
		holder.add_child(model)
		car.add_child(holder)
		var b := AssetLibrary.bounds(model)
		size = b.size * bs
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y / 2.0, 0)
	car.add_child(cs)
	var engine := EngineAudio.new()
	engine.kind = "car"
	engine.running = true
	engine.rpm = 1800.0
	engine.load = 0.3
	engine.roll = 0.25
	engine.position = Vector3(0, 0.6, 1.4)
	car.add_child(engine)
	Decor.landmark(car, Vector3.ZERO, "un coche que pasa por la calle", "traffic")
	_cars.append({"body": car, "lane": lane_i, "speed": SPEED, "engine": engine, "parked": false})


## El primero de los coches que circulan (o null).
func car() -> Node3D:
	for c in _cars:
		if is_instance_valid(c.body):
			return c.body
	return null


func cars() -> Array:
	return _cars.map(func(c): return c.body).filter(func(b): return is_instance_valid(b))

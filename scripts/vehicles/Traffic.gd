class_name Traffic
extends Node
## Tráfico del pueblo: de vez en cuando un vecino pasa en coche por la calle principal, por su
## carril, despacio. Frena si te tiene delante (no te atropella) y no circula de madrugada.
## El coche es sólido (no se atraviesa) pero no usa física: sigue el carril.

const LANES := [[Vector3(-4.3, 0, -62), Vector3(-4.3, 0, 62)], [Vector3(-5.7, 0, 62), Vector3(-5.7, 0, -62)]]
const SPEED := 8.0   # m/s (~30 km/h)

var scene: LocationScene
var _car: AnimatableBody3D
var _lane := 0
var _t := 0.0
var _wait := 6.0
var _speed := 0.0
var _engine: EngineAudio


func _process(delta: float) -> void:
	if _car == null:
		_wait -= delta
		var h := WorldClock.hour()
		if _wait <= 0.0 and h > 6.5 and h < 23.0 and not scene._interiors.is_inside():
			_spawn()
		return
	var lane: Array = LANES[_lane]
	var dir: Vector3 = (lane[1] - lane[0]).normalized()
	# Frena si hay alguien delante en el carril
	var want := SPEED
	var ahead := _car.global_position + dir * 4.0
	var people: Array = [scene._player] + scene._npcs.values() + scene.get_children().filter(func(c): return c is TownNPC and c.has_meta("passerby"))
	for body in people:
		if body and is_instance_valid(body) and (body as Node3D).visible and (body as Node3D).global_position.distance_to(ahead) < 4.5:
			want = 0.0
	_speed = move_toward(_speed, want, (3.0 if want > _speed else 7.0) * delta)
	_car.global_position += dir * _speed * delta
	if _engine:
		_engine.rpm = 900.0 + _speed * 220.0
		_engine.load = 0.6 if want > _speed else 0.15
	if (_car.global_position - lane[0]).length() > (lane[1] - lane[0]).length():
		_car.queue_free()
		_car = null
		_lane = 1 - _lane
		_wait = randf_range(25.0, 60.0)


func _spawn() -> void:
	var kind: String = ["sedan", "sedan", "van", "pickup", "taxi", "suv", "hatchback", "delivery"][randi() % 8]
	var k: Dictionary = Vehicle.KIT[kind]
	_car = AnimatableBody3D.new()
	_car.name = "TrafficCar"
	_car.sync_to_physics = false
	_car.collision_layer = Layers.WORLD
	var lane: Array = LANES[_lane]
	var dir: Vector3 = (lane[1] - lane[0]).normalized()
	scene.add_child(_car)
	_car.global_position = lane[0]
	_car.rotation.y = atan2(dir.x, dir.z)
	var model := AssetLibrary.instance(Vehicle.KIT_DIR, str(k.model))
	var bs: Vector3 = Vehicle.BIG_SCALE if k.get("big", false) else Vehicle.BODY_SCALE
	var size := Vector3(2.0, 1.7, 4.2)
	if model:
		var holder := Node3D.new()
		holder.scale = bs
		holder.add_child(model)
		_car.add_child(holder)
		var b := AssetLibrary.bounds(model)
		size = b.size * bs
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y / 2.0, 0)
	_car.add_child(cs)
	var engine := EngineAudio.new()
	engine.kind = "car"
	engine.running = true
	engine.rpm = 1800.0
	engine.load = 0.3
	engine.roll = 0.25
	engine.position = Vector3(0, 0.6, 1.4)
	_car.add_child(engine)
	_engine = engine
	Decor.landmark(_car, Vector3.ZERO, "un coche que pasa por la calle", "traffic")
	_speed = SPEED


func car() -> Node3D:
	return _car

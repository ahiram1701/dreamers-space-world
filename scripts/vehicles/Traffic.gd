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
	for body in [scene._player] + scene._npcs.values():
		if body and is_instance_valid(body) and (body as Node3D).global_position.distance_to(ahead) < 4.5:
			want = 0.0
	_speed = move_toward(_speed, want, (3.0 if want > _speed else 7.0) * delta)
	_car.global_position += dir * _speed * delta
	if (_car.global_position - lane[0]).length() > (lane[1] - lane[0]).length():
		_car.queue_free()
		_car = null
		_lane = 1 - _lane
		_wait = randf_range(25.0, 60.0)


func _spawn() -> void:
	var f := Vehicle.factory(["sedan", "sedan", "van", "pickup"][randi() % 4])
	_car = AnimatableBody3D.new()
	_car.name = "TrafficCar"
	_car.sync_to_physics = false
	var lane: Array = LANES[_lane]
	var dir: Vector3 = (lane[1] - lane[0]).normalized()
	scene.add_child(_car)
	_car.global_position = lane[0]
	_car.rotation.y = atan2(dir.x, dir.z)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in f.parts.size():
		var p: Dictionary = f.parts[i]
		Creations._part(_car, p, i, false)
		var pb := Creations.part_bounds(p)
		lo = lo.min(pb.position)
		hi = hi.max(pb.end)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hi - lo
	cs.shape = box
	cs.position = (hi + lo) / 2.0
	_car.add_child(cs)
	Decor.landmark(_car, Vector3.ZERO, "un coche que pasa por la calle", "traffic")
	_speed = SPEED


func car() -> Node3D:
	return _car

class_name Boat
extends Node3D
## Barca o balsa que flota con el oleaje. Con E te subes (el personaje se sienta y rema) y
## la manejas con WASD; con E otra vez te bajas en la orilla más cercana, o al agua si no la hay.
## No entra en tierra: se para al tocar fondo.

const MAX_SPEED := 5.5
const TURN_SPEED := 1.1

## Altura del agua y del terreno (la escena los asigna).
var water_level := -0.45
var ground_at: Callable = func(_x: float, _z: float) -> float: return -10.0
var seat_height := 0.35

var _rider: Player
var _speed := 0.0
var _use: Interactable
var _rowing := false


## Monta la barca con un modelo (pack, nombre) de `length` metros de eslora.
func setup(pack: String, model_name: String, length: float, label: String = "Subir a la barca") -> void:
	var model := AssetLibrary.instance(pack, model_name)
	if model:
		var b := AssetLibrary.bounds(model)
		var long_side := maxf(b.size.x, b.size.z)
		var holder := AssetLibrary.place(self, model, Vector3.ZERO, b.size.y * length / long_side, PI / 2 if b.size.x > b.size.z else 0.0, false)
		holder.position.y = -0.15
		seat_height = clampf(b.size.y * length / long_side * 0.35, 0.2, 0.6)
	else:  # casco sencillo si falta el modelo
		var hull := MeshInstance3D.new()
		hull.mesh = BoxMesh.new()
		hull.mesh.size = Vector3(length * 0.4, 0.4, length)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#8b6b4a")
		hull.material_override = m
		add_child(hull)
	_use = Interactable.create(self, Vector3(0, 0.3, 0), maxf(length * 0.5, 2.2), label, _on_use)


func seat_position() -> Vector3:
	return global_transform * Vector3(0, seat_height, 0)


func is_occupied() -> bool:
	return _rider != null


func _on_use(player: Player) -> void:
	if _rider == null:
		_rider = player
		player.riding = self
		player.interact_target = null
		player.play_gesture("sit")
		_use.set_prompt("Bajar")
	else:
		_leave()


func _leave() -> void:
	var player := _rider
	_rider = null
	player.riding = null
	player.stop_gesture()
	_use.set_prompt("Subir a la barca")
	# Bajar en tierra firme cercana; si no hay, al agua (a nadar)
	var here := global_position
	for dist in [2.0, 3.5, 5.0, 7.0]:
		for i in 16:
			var a := TAU * i / 16.0
			var p: Vector3 = here + Vector3(cos(a), 0, sin(a)) * dist
			var g: float = ground_at.call(p.x, p.z)
			if g > water_level + 0.05:
				player.global_position = Vector3(p.x, g + 0.4, p.z)
				return
	player.global_position = here + global_basis.x * 1.6 + Vector3(0, -0.6, 0)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var p := global_position
	# Flotar con las olas y cabecear un poco
	var h := Decor.wave_y(p.x, p.z, t)
	var hx := Decor.wave_y(p.x + 1.0, p.z, t) - h
	var hz := Decor.wave_y(p.x, p.z + 1.0, t) - h
	position.y = water_level + h * 0.8
	rotation.x = lerp_angle(rotation.x, -hz * 0.6, 4.0 * delta)
	rotation.z = lerp_angle(rotation.z, hx * 0.6, 4.0 * delta)
	if _rider == null:
		_speed = move_toward(_speed, 0.0, 2.0 * delta)
		return
	var throttle := 0.0
	var turn := 0.0
	if _rider.controls_enabled:
		throttle = (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (0.6 if Input.is_physical_key_pressed(KEY_S) else 0.0)
		turn = (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
	_speed = move_toward(_speed, throttle * MAX_SPEED, (2.5 if throttle != 0.0 else 1.2) * delta)
	rotation.y += turn * TURN_SPEED * delta * clampf(absf(_speed) / 2.0 + 0.3, 0.3, 1.0)
	var fwd := global_basis.z
	fwd.y = 0
	var next := global_position + fwd.normalized() * _speed * delta
	if ground_at.call(next.x, next.z) > water_level - 0.3:
		_speed = 0.0  # encalla en la orilla
	else:
		global_position.x = next.x
		global_position.z = next.z
	var rowing := absf(throttle) > 0.0 or absf(turn) > 0.0
	if rowing != _rowing:
		_rowing = rowing
		_rider.play_gesture("row" if rowing else "sit")

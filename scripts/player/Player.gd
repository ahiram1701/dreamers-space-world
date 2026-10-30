class_name Player
extends CharacterBody3D
## Persona común en tercera persona. WASD, Shift correr, Espacio saltar, ratón cámara,
## E interactuar (Esc, T e I los gestiona GameplayUI). Usa teclas físicas para no depender del Input Map todavía.

signal interact_requested(target: Node)

const WALK_SPEED := 4.5
const RUN_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const SWIM_SPEED := 2.2
const SWIM_DEPTH := 1.1         # el agua cubre hasta el pecho: a partir de ahí se nada
const FLOAT_DEPTH := 0.2        # nadando, el cuerpo flota justo bajo la superficie

var controls_enabled := true:
	set(value):
		controls_enabled = value
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

## Lo rellena el Area3D de cada PNJ al entrar/salir.
var interact_target: Node = null
## Gravedad del lugar respecto a la Tierra (la define la IA en cada location).
var gravity_scale := 1.0
## Altura del agua en este lugar (-INF si no hay): por debajo, el jugador nada.
var water_level := -INF
## Barca en la que va montado (la mueve ella; el jugador va sentado remando).
var riding: Node3D = null
## Sentado o tumbado: no cae ni se mueve hasta que el jugador camina.
var hold_position := false
var _swimming := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw: Node3D
var _spring: SpringArm3D
var _body: Node3D
var _cam: Camera3D
var _shake_time := 0.0
var _shake_strength := 0.0
var _rig: HumanoidRig


func _ready() -> void:
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 0.9
	add_child(shape)

	_body = Node3D.new()
	add_child(_body)
	var look := {"outfit": "casual", "primary_color": "#3b6ea5", "secondary_color": "#2b2f3a"}
	if not Settings.player_figure.is_empty():
		look["figure"] = Settings.player_figure
	var model := AssetLibrary.character(look, hash(WorldDB.world_id) + 7)
	if model:
		AssetLibrary.place(_body, model, Vector3.ZERO, 1.78, 0.0, false)
		_rig = HumanoidRig.new()
		model.add_child(_rig)
		if not _rig.setup(model):
			_rig = null
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = CapsuleMesh.new()
		mesh.position.y = 0.9
		mesh.material_override = _mat(Color("#e8d5b5"))
		_body.add_child(mesh)

	_yaw = Node3D.new()
	_yaw.position.y = 1.6
	add_child(_yaw)
	_spring = SpringArm3D.new()
	_spring.spring_length = 4.0
	_spring.margin = 0.3
	_spring.rotation.x = -0.35
	_spring.add_excluded_object(get_rid())
	_yaw.add_child(_spring)
	_cam = Camera3D.new()
	_cam.fov = 70
	_spring.add_child(_cam)

	controls_enabled = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw.rotate_y(-event.relative.x * MOUSE_SENSITIVITY * Settings.mouse_sensitivity)
		_spring.rotation.x = clampf(_spring.rotation.x - event.relative.y * MOUSE_SENSITIVITY * Settings.mouse_sensitivity, -1.2, 0.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if controls_enabled and riding != null:
					interact_requested.emit(riding)  # bajarse de la barca
				elif controls_enabled and interact_target != null:
					interact_requested.emit(interact_target)
	elif event is InputEventMouseButton and event.pressed and controls_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## El personaje hace un gesto (talar, sentarse, saludar…). Ver HumanoidRig.
func play_gesture(gesture: String, duration: float = -1.0) -> void:
	if _rig:
		_rig.play(gesture, duration)


func stop_gesture() -> void:
	if _rig:
		_rig.stop_gesture()


## Hacia dónde mira el cuerpo (para colocar lo que construye delante).
func facing_yaw() -> float:
	return _body.rotation.y


func face_towards(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_body.rotation.y = atan2(d.x, d.z)
	if _rig:
		_rig.look_at_point = point + Vector3(0, 1.5, 0)


func clear_look() -> void:
	if _rig:
		_rig.look_at_point = Vector3.INF


func is_swimming() -> bool:
	# Solo cerca de la superficie: los interiores están muy por debajo del agua y no se nada en ellos
	if water_level == -INF or riding != null or global_position.y < water_level - 8.0:
		return false
	# Se empieza a nadar cuando el agua cubre el pecho y se deja al hacer pie en la orilla
	return global_position.y < water_level - (0.15 if _swimming else SWIM_DEPTH)


## Gira la cámara para mirar en una dirección (al entrar o salir de un edificio).
func look_direction(dir: Vector3) -> void:
	_yaw.rotation.y = atan2(-dir.x, -dir.z)
	_body.rotation.y = atan2(dir.x, dir.z)


## Temblor de cámara (el pulso del faro, los saltos).
func shake(duration: float, strength: float) -> void:
	_shake_time = duration
	_shake_strength = strength


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		_cam.h_offset = randf_range(-_shake_strength, _shake_strength)
		_cam.v_offset = randf_range(-_shake_strength, _shake_strength)
	elif _cam.h_offset != 0.0 or _cam.v_offset != 0.0:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


func _physics_process(delta: float) -> void:
	if riding != null:  # sentado en la barca: ella se mueve, el jugador va encima
		velocity = Vector3.ZERO
		global_position = riding.call("seat_position")
		_body.global_rotation.y = riding.global_rotation.y
		if _rig:
			_rig.speed = 0.0
			_rig.airborne = false
		return
	if hold_position:
		var wants_move := controls_enabled and (_key(KEY_W) + _key(KEY_A) + _key(KEY_S) + _key(KEY_D)) > 0.0
		if not wants_move:
			velocity = Vector3.ZERO
			if _rig:
				_rig.speed = 0.0
				_rig.airborne = false
			return
		hold_position = false
		stop_gesture()
	var swimming := is_swimming()
	_swimming = swimming
	if swimming:
		# Flotar: el agua empuja hacia la superficie y frena
		var float_y := water_level - FLOAT_DEPTH
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 3.0, 6.0 * delta)
	elif not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	var input := Vector2.ZERO
	if controls_enabled:
		input.x = _key(KEY_D) - _key(KEY_A)
		input.y = _key(KEY_S) - _key(KEY_W)
		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor() and not swimming:
			velocity.y = JUMP_VELOCITY

	var dir := (_yaw.global_basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	if swimming:
		speed = SWIM_SPEED
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 8.0 * delta)
	move_and_slide()
	if _rig:
		_rig.speed = Vector2(velocity.x, velocity.z).length()
		_rig.airborne = not is_on_floor() and not swimming and velocity.y > -12.0
		_rig.swimming = swimming
		if dir != Vector3.ZERO and _rig.gesture() in ["sit", "sleep", "crouch", "search", "chop", "hammer", "dig", "fish", "think"]:
			_rig.stop_gesture()  # moverse interrumpe lo que estaba haciendo


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

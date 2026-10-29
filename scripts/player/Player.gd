class_name Player
extends CharacterBody3D
## Persona común en tercera persona. WASD, Shift correr, Espacio saltar, ratón cámara,
## E hablar, Esc soltar el ratón. Usa teclas físicas para no depender del Input Map todavía.

signal interact_requested(target: Node)

const WALK_SPEED := 4.5
const RUN_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025

var controls_enabled := true:
	set(value):
		controls_enabled = value
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

## Lo rellena el Area3D de cada PNJ al entrar/salir.
var interact_target: Node = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw: Node3D
var _spring: SpringArm3D
var _body: Node3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 0.9
	add_child(shape)

	_body = Node3D.new()
	add_child(_body)
	var mesh := MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	mesh.position.y = 0.9
	mesh.material_override = _mat(Color("#e8d5b5"))
	_body.add_child(mesh)
	var nose := MeshInstance3D.new()  # para ver hacia dónde mira
	nose.mesh = BoxMesh.new()
	nose.mesh.size = Vector3(0.18, 0.12, 0.25)
	nose.position = Vector3(0, 1.5, 0.48)
	nose.material_override = _mat(Color("#3b6ea5"))
	_body.add_child(nose)

	_yaw = Node3D.new()
	_yaw.position.y = 1.6
	add_child(_yaw)
	_spring = SpringArm3D.new()
	_spring.spring_length = 4.0
	_spring.margin = 0.3
	_spring.rotation.x = -0.35
	_spring.add_excluded_object(get_rid())
	_yaw.add_child(_spring)
	var cam := Camera3D.new()
	cam.fov = 70
	_spring.add_child(cam)

	controls_enabled = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_spring.rotation.x = clampf(_spring.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if controls_enabled:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_E:
				if controls_enabled and interact_target != null:
					interact_requested.emit(interact_target)
	elif event is InputEventMouseButton and event.pressed and controls_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input := Vector2.ZERO
	if controls_enabled:
		input.x = _key(KEY_D) - _key(KEY_A)
		input.y = _key(KEY_S) - _key(KEY_W)
		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = JUMP_VELOCITY

	var dir := (_yaw.global_basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 8.0 * delta)
	move_and_slide()


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

class_name Player
extends CharacterBody3D
## Persona común en tercera persona. Moverse, correr, saltar, cámara con ratón o mando, rueda
## para acercar/alejar (al mínimo, primera persona) y E para interactuar con lo que elige el
## InteractionSystem. Las teclas son acciones del InputMap (ver autoload Controls).

signal interact_requested(target: Node)
## Termina una caminata automática (una acción con F): true si llegó.
signal auto_walk_done(arrived: bool)

const WALK_SPEED := 4.5
const RUN_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const STICK_SENSITIVITY := 2.6   # rad/s con el stick derecho a fondo
const SWIM_SPEED := 2.2
const SWIM_DEPTH := 1.1         # el agua cubre hasta el pecho: a partir de ahí se nada
const FLOAT_DEPTH := 0.2        # nadando, el cuerpo flota justo bajo la superficie
const ZOOM_MIN := 1.2
const ZOOM_MAX := 9.0
const FIRST_PERSON := 0.6       # por debajo de esta distancia, la cámara va en los ojos
const SHOULDER := 0.45          # la cámara va un poco a la derecha, como en los juegos en 3ª persona

var controls_enabled := true:
	set(value):
		controls_enabled = value
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

## Elige con qué se interactúa al pulsar E (PNJs, puertas, sillas…).
var interaction: InteractionSystem
## Lo que se usaría ahora con E (lo calcula `interaction`).
var interact_target: Node:
	get:
		return interaction.target if interaction else null
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
var _zoom := 4.0               # distancia que elige el jugador
var _zoom_override := -1.0     # la impone una conversación o una acción (o -1)
var _first_person := false
var _zoom_dirty := false
var _auto_target := Vector3.INF  # caminata automática (acciones con F)
var _auto_stop := 1.0
var _auto_time := 0.0
var _auto_check := Vector3.ZERO
var _auto_check_t := 0.0
var _auto_detour := 0.0
var _auto_side := 1.0


func _ready() -> void:
	add_to_group("player")
	Layers.character(self)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.32
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
			_rig.footstep.connect(func(_run): Sfx.footstep(self, water_level))
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
	_zoom = clampf(Settings.camera_distance, 0.0, ZOOM_MAX)
	_spring.spring_length = _zoom
	_spring.margin = 0.3
	_spring.collision_mask = Layers.WORLD
	_spring.rotation.x = -0.35
	_spring.add_excluded_object(get_rid())
	_yaw.add_child(_spring)
	_cam = Camera3D.new()
	_cam.fov = Settings.fov
	_spring.add_child(_cam)

	set_light(bool(WorldDB.get_state("light_on", false)))
	interaction = InteractionSystem.new()
	interaction.player = self
	add_child(interaction)
	controls_enabled = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn_camera(event.relative * MOUSE_SENSITIVITY * Settings.mouse_sensitivity)
	elif event.is_action_pressed("interact") and not event.is_echo():
		if controls_enabled and riding != null:
			interact_requested.emit(riding)  # bajarse de la barca
		elif controls_enabled and interact_target != null:
			interact_requested.emit(interact_target)
	elif event.is_action_pressed("zoom_in") and controls_enabled:
		_zoom = 0.0 if _zoom <= ZOOM_MIN + 0.01 else maxf(_zoom * 0.8, ZOOM_MIN)
		_save_zoom()
	elif event.is_action_pressed("zoom_out") and controls_enabled:
		_zoom = ZOOM_MIN if _zoom < ZOOM_MIN else minf(_zoom * 1.25, ZOOM_MAX)
		_save_zoom()
	elif event is InputEventMouseButton and event.pressed and controls_enabled \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _turn_camera(delta: Vector2) -> void:
	_yaw.rotate_y(-delta.x)
	var dy := delta.y * (-1.0 if Settings.invert_y else 1.0)
	_spring.rotation.x = clampf(_spring.rotation.x - dy, -1.3, 0.6 if _first_person else 0.4)


func _save_zoom() -> void:
	Settings.camera_distance = _zoom
	_zoom_dirty = true
	# Se guarda al salir de la escena (no escribir el archivo en cada giro de rueda)


func _exit_tree() -> void:
	if _zoom_dirty:
		Settings.save_settings()


## Hacia dónde mira la cámara en el plano (para elegir con qué interactuar).
func view_forward() -> Vector3:
	var f := -_yaw.global_basis.z
	f.y = 0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


## El personaje hace un gesto (talar, sentarse, saludar…). Ver HumanoidRig.
## Linterna o farol encendido: una luz que te acompaña.
var _lamp: SpotLight3D


func set_light(on: bool) -> void:
	if on and _lamp == null:
		_lamp = SpotLight3D.new()
		_lamp.light_color = Color("#fff1d6")
		_lamp.light_energy = 3.5
		_lamp.spot_range = 22.0
		_lamp.spot_angle = 32.0
		_lamp.shadow_enabled = Settings.graphics_quality >= 1
		_lamp.position = Vector3(0.25, 1.3, 0.2)
		_body.add_child(_lamp)
		_lamp.rotation.y = PI  # hacia delante del cuerpo (+Z)
	if _lamp:
		_lamp.visible = on


func play_gesture(gesture: String, duration: float = -1.0) -> void:
	if _rig:
		_rig.play(gesture, duration)


func stop_gesture() -> void:
	if _rig:
		_rig.stop_gesture()


func current_gesture() -> String:
	return _rig.gesture() if _rig else ""


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


## Encuadre de conversación: la cámara mira al PNJ por encima del hombro del jugador.
func focus_on(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_yaw.rotation.y = atan2(-d.x, -d.z) + 0.25
	_spring.rotation.x = -0.12
	_zoom_override = 2.4


## Durante una acción con F la cámara se aleja un poco para ver al personaje hacerla.
func frame_action(on: bool) -> void:
	_zoom_override = maxf(_zoom, 4.5) if on else -1.0


func end_focus() -> void:
	_zoom_override = -1.0


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


# --- Caminata automática (lo que escribes con F: "voy hasta el árbol") ---------------------

## Camina solo hasta `pos` (rodeando obstáculos). Moverse con WASD lo cancela.
## Uso: var ok: bool = await player.auto_walk_to(p, 1.2)
func auto_walk_to(pos: Vector3, stop_distance: float = 1.0) -> bool:
	if riding != null:
		return false
	hold_position = false
	stop_gesture()
	_auto_target = pos
	_auto_stop = stop_distance
	_auto_time = 0.0
	_auto_check = global_position
	_auto_check_t = 0.0
	_auto_detour = 0.0
	if _flat_distance(pos) <= stop_distance:
		_auto_target = Vector3.INF
		return true
	var arrived: bool = await auto_walk_done
	return arrived


func cancel_auto_walk() -> void:
	if _auto_target != Vector3.INF:
		_auto_target = Vector3.INF
		auto_walk_done.emit(false)


func is_auto_walking() -> bool:
	return _auto_target != Vector3.INF


func _flat_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Dirección para la caminata automática; gestiona atascos y llegada.
func _auto_direction(delta: float) -> Vector3:
	var to := Vector3(_auto_target.x - global_position.x, 0, _auto_target.z - global_position.z)
	if to.length() <= _auto_stop:
		_auto_target = Vector3.INF
		velocity.x = 0
		velocity.z = 0
		auto_walk_done.emit(true)
		return Vector3.ZERO
	_auto_time += delta
	_auto_check_t += delta
	if _auto_check_t > 1.2:  # ¿avanzó algo en el último segundo?
		if global_position.distance_to(_auto_check) < 0.35:
			_auto_detour = 1.0
			_auto_side = -_auto_side if randf() < 0.5 else _auto_side
			if is_on_floor():
				velocity.y = JUMP_VELOCITY * 0.7
		_auto_check = global_position
		_auto_check_t = 0.0
	if _auto_time > 14.0:  # no hay forma de llegar andando: se coloca al lado
		var p := _auto_target - to.normalized() * _auto_stop
		global_position = Vector3(p.x, maxf(global_position.y, _auto_target.y) + 0.3, p.z)
		_auto_target = Vector3.INF
		auto_walk_done.emit(true)
		return Vector3.ZERO
	var dir := to.normalized()
	if _auto_detour > 0.0:
		_auto_detour -= delta
		dir = dir.rotated(Vector3.UP, deg_to_rad(70.0) * _auto_side)
	return dir


func _process(delta: float) -> void:
	if controls_enabled:
		var look := Controls.look_vector()
		if look != Vector2.ZERO:
			_turn_camera(look * STICK_SENSITIVITY * delta * Settings.mouse_sensitivity)
	# Zoom suave; al mínimo, primera persona (la cabeza no tapa la vista: el cuerpo solo da sombra)
	var want := _zoom_override if _zoom_override >= 0.0 else _zoom
	_spring.spring_length = lerpf(_spring.spring_length, want, 1.0 - exp(-10.0 * delta))
	var fp := want < FIRST_PERSON and _zoom_override < 0.0
	if fp != _first_person:
		_first_person = fp
		_set_body_shadow_only(fp)
	_yaw.position.y = lerpf(_yaw.position.y, 1.68 if _first_person else 1.6, 1.0 - exp(-10.0 * delta))
	_spring.position.x = lerpf(_spring.position.x, 0.0 if _first_person else SHOULDER * clampf(_spring.spring_length / 3.0, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	if _cam.fov != Settings.fov:
		_cam.fov = Settings.fov
	if _shake_time > 0.0:
		_shake_time -= delta
		_cam.h_offset = randf_range(-_shake_strength, _shake_strength)
		_cam.v_offset = randf_range(-_shake_strength, _shake_strength)
	elif _cam.h_offset != 0.0 or _cam.v_offset != 0.0:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


func _set_body_shadow_only(on: bool) -> void:
	for n in _body.find_children("*", "GeometryInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _physics_process(delta: float) -> void:
	if riding != null:  # sentado en la barca: ella se mueve, el jugador va encima
		velocity = Vector3.ZERO
		global_position = riding.call("seat_position")
		_body.global_rotation.y = riding.global_rotation.y
		if _rig:
			_rig.speed = 0.0
			_rig.airborne = false
		return
	var input := Controls.move_vector() if controls_enabled else Vector2.ZERO
	if input != Vector2.ZERO and _auto_target != Vector3.INF:
		cancel_auto_walk()  # el jugador retoma el control
	if hold_position:
		if input == Vector2.ZERO:
			velocity = Vector3.ZERO
			if _rig:
				_rig.speed = 0.0
				_rig.airborne = false
			return
		hold_position = false
		stop_gesture()
		for e in get_collision_exceptions():
			remove_collision_exception_with(e)  # se levanta del asiento: vuelve a chocar con él
	var swimming := is_swimming()
	_swimming = swimming
	if swimming:
		# Flotar: el agua empuja hacia la superficie y frena
		var float_y := water_level - FLOAT_DEPTH
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 3.0, 6.0 * delta)
	elif not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	var dir := Vector3.ZERO
	var running := controls_enabled and Input.is_action_pressed("run")
	if _auto_target != Vector3.INF:
		dir = _auto_direction(delta)
		running = _flat_distance(_auto_target) > 8.0 if _auto_target != Vector3.INF else false
	else:
		if controls_enabled and Input.is_action_pressed("jump") and is_on_floor() and not swimming:
			velocity.y = JUMP_VELOCITY
		dir = _yaw.global_basis * Vector3(input.x, 0, input.y)
		dir.y = 0
		dir = dir.limit_length(1.0) if dir.length() > 0.01 else Vector3.ZERO
	var speed := RUN_SPEED if running else WALK_SPEED
	if swimming:
		speed = SWIM_SPEED
	speed *= Body.speed_factor()
	Body.exertion = 1.8 if (swimming or (running and dir != Vector3.ZERO)) else 1.0
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
		if dir != Vector3.ZERO and _rig.gesture() in ["sit", "sleep", "crouch", "search", "chop", "hammer", "dig", "fish", "think", "kneel", "read", "write", "listen"]:
			_rig.stop_gesture()  # moverse interrumpe lo que estaba haciendo


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

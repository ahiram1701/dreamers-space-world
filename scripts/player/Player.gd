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
var _frame_v := 0.0   # desplazamiento vertical de la cámara al conversar
var _auto_target := Vector3.INF  # caminata automática (acciones con F)
var _auto_stop := 1.0
var _auto_time := 0.0
var _auto_check := Vector3.ZERO
var _auto_check_t := 0.0
var _auto_detour := 0.0
var _auto_side := 1.0
var _stuck_t := 0.0   # tiempo intentando moverse sin avanzar
var _down_t := 0.0    # en el suelo tras una caída fuerte (no te puedes mover)
const STEP_MAX := 0.38          # sube solo escalones de hasta esta altura (sin saltar)
const FALL_SAFE := 9.0          # m/s al tocar el suelo sin hacerse daño (~4 m de caída)
const FALL_KO := 22.0           # m/s: te deja sin sentido (~25 m)

## Te has hecho daño al caer (para la escena: avisos, testigos).
signal fell(impact: float, damage: int)
var _cam_vehicle: Node3D = null   # en el que va (la cámara no choca con él y le sigue por detrás)
var _look_idle := 10.0            # segundos sin mover la cámara (al conducir vuelve detrás)
var _safe_pos := Vector3.INF      # último sitio pisando suelo firme (si caes al vacío, vuelves aquí)


func _ready() -> void:
	add_to_group("player")
	Layers.character(self)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.32
	shape.shape.height = 1.8   # de los pies (y = 0) a la cabeza (antes asomaba 10 cm bajo los pies)
	shape.position.y = 0.9
	add_child(shape)
	floor_snap_length = 0.3    # al bajar un escalón no «vuela»: se queda pegado al suelo

	_body = Node3D.new()
	add_child(_body)
	rebuild_look()

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
	_look_idle = 0.0
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
## Pone (o cambia en caliente) el modelo según el aspecto elegido para esta vida (PlayerLook).
func rebuild_look() -> void:
	var lamp_on := _lamp != null and _lamp.visible
	for c in _body.get_children():
		c.queue_free()
	_lamp = null
	_rig = null
	var built := PlayerLook.build(_body, PlayerLook.current().merged({"layers": PlayerLook.layers()}, true), hash(WorldDB.world_id) + 7)
	if built.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.mesh = CapsuleMesh.new()
		mesh.position.y = 0.9
		mesh.material_override = _mat(Color("#e8d5b5"))
		_body.add_child(mesh)
	elif built.rig:
		_rig = built.rig
		_rig.footstep.connect(func(_run): Sfx.footstep(self, water_level))
	_look_mats.clear()
	if not built.is_empty():  # los materiales que se mojan y se ensucian
		for mi in (built.model as Node).find_children("*", "MeshInstance3D", true, false):
			for i in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
				if m and m.has_meta("part"):
					_look_mats.append([m, m.albedo_color, m.roughness, str(m.get_meta("part"))])
	_apply_condition()
	if lamp_on:
		set_light(true)
	if _first_person:
		_set_body_shadow_only.call_deferred(true)


var _look_mats: Array = []   # [material, color base, rugosidad base, "cloth"|"skin"|"hair"]
var _condition_t := 0.0
const MUD := Color("#5a4630")


## Se te ve como estás: la ropa mojada se oscurece y brilla, el barro la mancha, y con los meses
## la complexión cambia un poco según cómo vives (Body).
func _apply_condition() -> void:
	var w := Body.wet
	var d := Body.dirt
	for e in _look_mats:
		var m: StandardMaterial3D = e[0]
		var base: Color = e[1]
		match e[3]:
			"cloth":
				m.albedo_color = base.darkened(0.35 * w).lerp(MUD, 0.45 * d)
				m.roughness = lerpf(e[2], 0.28, w * 0.8)
			"skin":
				m.albedo_color = base.lerp(MUD, 0.18 * d)
				m.roughness = lerpf(e[2], 0.35, w * 0.5)
			"hair":
				m.albedo_color = base.darkened(0.3 * w)
	var wide := 1.0 + Body.shape * 0.06
	_body.scale = Vector3(wide, 1.0, wide)


## Linterna o farol encendido: una luz que te acompaña.
var _lamp: SpotLight3D


func set_light(on: bool) -> void:
	if on and _lamp == null:
		_lamp = SpotLight3D.new()
		_lamp.light_color = Color("#fff1d6")
		_lamp.light_energy = 3.5
		_lamp.spot_range = 22.0
		_lamp.spot_angle = 30.0
		_lamp.shadow_enabled = Settings.graphics_quality >= 1
		_lamp.position = Vector3(0.25, 1.3, 0.2)
		_body.add_child(_lamp)
		_lamp.rotation.y = PI  # hacia delante del cuerpo (+Z)
	if _lamp:
		_lamp.visible = on
	if _rig:  # la linterna se ve en la mano, y la luz sale de ella
		_rig.set_held("survival_pack/Torch" if on else "")


## La luz de la linterna sigue a la mano (donde apunta el brazo).
func _follow_lamp() -> void:
	if _lamp == null or not _lamp.visible or _rig == null:
		return
	var tip: Transform3D = _rig.held_tip()
	if tip.origin == Vector3.INF:  # la mano está ocupada: alumbra desde el pecho
		_lamp.top_level = false
		_lamp.position = Vector3(0.25, 1.3, 0.2)
		_lamp.rotation = Vector3(0, PI, 0)
		return
	_lamp.top_level = true
	_lamp.global_transform = tip


## provided: la herramienta te la dan (en el trabajo); si no, solo sale si la tienes.
## Mantener un gesto que dura (en un vehículo, cada frame): solo lo empieza si no está ya
## sonando. (Antes se reiniciaba cada frame: el pedaleo no avanzaba y el remo se creaba 60 veces
## por segundo.)
func hold_gesture(gesture: String) -> void:
	if _rig and _rig.gesture() == gesture:
		return
	play_gesture(gesture)


func play_gesture(gesture: String, duration: float = -1.0, provided: bool = false) -> void:
	if _rig:
		_rig.play(gesture, duration, provided or has_tool_for(gesture))
	Body.soil(DIRTY.get(gesture, 0.0))


## Cuánto ensucia cada cosa que haces con las manos o en el suelo.
const DIRTY := {"chop": 0.12, "dig": 0.2, "hammer": 0.06, "kneel": 0.05, "crouch": 0.03, "search": 0.03, "pick_up": 0.02}


## Qué objeto hace falta para que se vea la herramienta del gesto ("" = siempre la llevas).
const TOOL_ITEMS := {"chop": ["hacha"], "dig": ["pala"], "hammer": ["martillo", "hacha", "herramienta"], "fish": ["caña", "cana"]}


func has_tool_for(gesture: String) -> bool:
	if not TOOL_ITEMS.has(gesture):
		return true
	for word in TOOL_ITEMS[gesture]:
		if not Inventory.find_by_name(word).is_empty():
			return true
	return false


func stop_gesture() -> void:
	if _rig:
		_rig.stop_gesture()


func current_gesture() -> String:
	return _rig.gesture() if _rig else ""


## Hacia dónde mira el cuerpo (para colocar lo que construye delante).
func facing_yaw() -> float:
	return _body.rotation.y


## Hacia delante del cuerpo (horizontal).
func facing_dir() -> Vector3:
	return Vector3(sin(_body.rotation.y), 0, cos(_body.rotation.y))


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
## (La cara de quien te habla queda en el tercio de arriba, por encima de la conversación.)
func focus_on(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_yaw.rotation.y = atan2(-d.x, -d.z) + 0.32
	if _zoom_override < 0.0:
		_pitch_before_focus = _spring.rotation.x
	_spring.rotation.x = -0.05
	_zoom_override = 2.1
	_frame_v = -0.38


## Durante una acción con F la cámara se aleja un poco para ver al personaje hacerla.
func frame_action(on: bool) -> void:
	_zoom_override = maxf(_zoom, 4.5) if on else -1.0


func end_focus() -> void:
	_zoom_override = -1.0
	_frame_v = 0.0
	if _pitch_before_focus != INF:  # la cámara vuelve a la inclinación que tenías
		create_tween().tween_property(_spring, "rotation:x", _pitch_before_focus, 0.5)
		_pitch_before_focus = INF


var _pitch_before_focus := INF


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
	_follow_lamp()
	_condition_t += delta
	if _condition_t > 0.5:
		_condition_t = 0.0
		_apply_condition()
	if controls_enabled:
		var look := Controls.look_vector()
		if look != Vector2.ZERO:
			_turn_camera(look * STICK_SENSITIVITY * delta * Settings.mouse_sensitivity)
	_update_vehicle_camera(delta)
	# Zoom suave; al mínimo, primera persona (la cabeza no tapa la vista: el cuerpo solo da sombra)
	var want := _zoom_override if _zoom_override >= 0.0 else _zoom
	if _cam_vehicle != null and _zoom_override < 0.0 and _cam_vehicle.has_method("camera_distance"):
		want = maxf(_zoom, float(_cam_vehicle.call("camera_distance")))
	_spring.spring_length = lerpf(_spring.spring_length, want, 1.0 - exp(-10.0 * delta))
	var fp := want < FIRST_PERSON and _zoom_override < 0.0
	if fp != _first_person:
		_first_person = fp
		_set_body_shadow_only(fp)
	if _cam_vehicle == null:
		_yaw.position.y = lerpf(_yaw.position.y, 1.68 if _first_person else 1.6, 1.0 - exp(-10.0 * delta))
	_spring.position.x = lerpf(_spring.position.x, 0.0 if _first_person else SHOULDER * clampf(_spring.spring_length / 3.0, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	if _cam.fov != Settings.fov:
		_cam.fov = Settings.fov
	if _cam_vehicle != null and _cam_vehicle.has_method("speed"):  # sensación de velocidad
		_cam.fov = lerpf(_cam.fov, Settings.fov + clampf(absf(float(_cam_vehicle.call("speed"))) * 0.45, 0.0, 14.0), 1.0 - exp(-3.0 * delta))
	if _shake_time > 0.0:
		_shake_time -= delta
		_cam.h_offset = randf_range(-_shake_strength, _shake_strength)
		_cam.v_offset = randf_range(-_shake_strength, _shake_strength)
	else:  # encuadre (bajar la cámara un poco en las conversaciones)
		_cam.h_offset = 0.0
		_cam.v_offset = lerpf(_cam.v_offset, _frame_v, 1.0 - exp(-6.0 * delta))


## En un vehículo: la cámara no choca con él (si no, se metía dentro), va más alta y, si no la
## mueves en 2 s, vuelve sola detrás, mirando hacia donde vas.
func _update_vehicle_camera(delta: float) -> void:
	var v: Node3D = riding if riding is VehicleBody3D or riding is CharacterBody3D else null
	if v != _cam_vehicle:
		if _cam_vehicle != null and is_instance_valid(_cam_vehicle) and _cam_vehicle is CollisionObject3D:
			_spring.remove_excluded_object((_cam_vehicle as CollisionObject3D).get_rid())
		_cam_vehicle = v
		if v is CollisionObject3D:
			_spring.add_excluded_object((v as CollisionObject3D).get_rid())
		_look_idle = 10.0
	_look_idle += delta
	if _cam_vehicle == null or not is_instance_valid(_cam_vehicle):
		_cam_vehicle = null
		return
	_yaw.position.y = lerpf(_yaw.position.y, 2.4, 1.0 - exp(-4.0 * delta))
	var moving: bool = absf(float(_cam_vehicle.call("speed"))) > 1.5 if _cam_vehicle.has_method("speed") else false
	if _look_idle > 2.0 and moving:
		var behind := _cam_vehicle.global_rotation.y + PI   # la cámara mira hacia -z del muelle: detrás
		_yaw.global_rotation.y = lerp_angle(_yaw.global_rotation.y, behind, 1.0 - exp(-2.5 * delta))
		_spring.rotation.x = lerp_angle(_spring.rotation.x, -0.22, 1.0 - exp(-2.0 * delta))


func _set_body_shadow_only(on: bool) -> void:
	for n in _body.find_children("*", "GeometryInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _physics_process(delta: float) -> void:
	if riding != null:  # sentado en la barca: ella se mueve, el jugador va encima
		velocity = Vector3.ZERO
		global_position = riding.call("seat_position")
		_body.global_rotation.y = riding.global_rotation.y
		var hide_me: bool = riding.get("hides_riders") == true  # en la nave vas dentro, en la cabina
		if _body.visible == hide_me:
			_body.visible = not hide_me
		if _rig:
			_rig.speed = 0.0
			_rig.airborne = false
		return
	if not _body.visible:
		_body.visible = true
	if _down_t > 0.0:  # tirado en el suelo tras la caída: te levantas en un momento
		_down_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * gravity_scale * delta
		move_and_slide()
		if _down_t <= 0.0:
			stop_gesture()
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
	var running := controls_enabled and Input.is_action_pressed("run") and Body.can_run()
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
	var before := global_position
	var fall_v := -velocity.y
	var was_air := not is_on_floor()
	move_and_slide()
	if dir != Vector3.ZERO and not swimming:
		_try_step(dir)
	if was_air and is_on_floor() and not swimming and fall_v > FALL_SAFE:
		_landed_hard(fall_v)
	_check_stuck(dir, speed, before, delta)
	if is_on_floor() and not swimming:
		_safe_pos = global_position
	if _rig:
		_rig.speed = Vector2(velocity.x, velocity.z).length()
		_rig.airborne = not is_on_floor() and not swimming and velocity.y > -12.0
		_rig.swimming = swimming
		if dir != Vector3.ZERO and _rig.gesture() in ["sit", "sleep", "crouch", "search", "chop", "hammer", "dig", "fish", "think", "kneel", "read", "write", "listen"]:
			_rig.stop_gesture()  # moverse interrumpe lo que estaba haciendo


## Escalones: si al andar chocas con algo bajo (un peldaño, un bordillo), subes encima sin saltar.
func _try_step(dir: Vector3) -> void:
	if not is_on_floor() or not is_on_wall():
		return
	var motion := dir.normalized() * 0.3
	var raised := global_transform.translated(Vector3(0, STEP_MAX, 0))
	if test_move(raised, motion):
		return  # sigue chocando aun subiendo: es una pared, no un escalón
	var from := global_position + Vector3(0, STEP_MAX + 0.05, 0) + motion
	var q := PhysicsRayQueryParameters3D.create(from, global_position + motion - Vector3(0, 0.05, 0), Layers.WORLD, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.02 and rise <= STEP_MAX and (hit.normal as Vector3).y > 0.7:
		global_position += Vector3(0, rise + 0.02, 0) + motion * 0.4
		velocity.y = maxf(velocity.y, 0.0)


## Una caída fuerte: duele según lo rápido que llegas al suelo; muy fuerte, pierdes el sentido.
func _landed_hard(impact: float) -> void:
	var damage := int((impact - FALL_SAFE) * 6.5)
	shake(0.5, clampf(impact * 0.012, 0.08, 0.3))
	Sfx.at(self, "thump", global_position + Vector3(0, 0.3, 0))
	if impact > FALL_SAFE + 4.0:
		play_gesture("fallen", 2.5)
		_down_t = clampf((impact - FALL_SAFE) * 0.25, 1.0, 4.0)
	if GameState.is_awakened():
		GameState.change_stat("health", -damage)
	# (antes del Despertar no hay barra de salud: el golpe te deja molido y, si fue brutal, sin sentido)
	Body.change("rest", -minf(damage * 0.4, 40.0))
	fell.emit(impact, damage)
	if impact >= FALL_KO and not GameState.is_awakened():
		_down_t = 6.0


## Si llevas un rato empujando sin avanzar y estás metido dentro de algo (un arbusto, un mueble),
## te saca al hueco libre más cercano. Contra una pared normal no hace nada: ahí no estás dentro.
func _check_stuck(dir: Vector3, speed: float, before: Vector3, delta: float) -> void:
	if dir == Vector3.ZERO or riding != null or _swimming:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
		return
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if moved < speed * delta * 0.15:
		_stuck_t += delta
	else:
		_stuck_t = maxf(_stuck_t - delta * 2.0, 0.0)
	if _stuck_t < 1.0:
		return
	_stuck_t = 0.0
	var feet := global_position
	if not InteriorManager.is_free(self, feet, [self], 0.26):  # de verdad estás dentro de algo
		global_position = InteriorManager.free_spot_near(self, feet, dir, [self]) + Vector3(0, 0.15, 0)
		velocity = Vector3.ZERO


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## Último sitio donde pisabas suelo firme (INF si aún no).
func last_safe_position() -> Vector3:
	return _safe_pos

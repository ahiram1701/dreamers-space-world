class_name TownNPC
extends CharacterBody3D
## Representación 3D de una entidad "npc" de WorldDB: un modelo animado con su traje y sus
## colores (AssetLibrary + HumanoidRig) que camina, te sigue, va a sitios y te mira al hablar.
## Si falta el modelo, se monta con piezas simples como antes.

const BODY_SCALE := {
	"slim": Vector3(0.88, 1.0, 0.88), "average": Vector3.ONE, "sturdy": Vector3(1.18, 1.0, 1.15),
	"tall": Vector3(0.97, 1.1, 0.97), "short": Vector3(1.0, 0.9, 1.0),
	"elderly": Vector3(0.98, 0.94, 0.98), "child": Vector3(0.75, 0.62, 0.75),
}
const HEIGHT := 1.78
const WALK_SPEED := 1.6
const FOLLOW_SPEED := 4.6
const FOLLOW_DISTANCE := 2.6
const RUN_SPEED := 4.2
const BUBBLE_RANGE := 22.0

## Llegó a donde iba con walk_to (para entrar en un edificio al llegar a la puerta, etc.).
signal arrived

var npc_id: String = ""
## Lo que está haciendo ahora (rutina): "limpiando la barra", "leyendo"… Vacío si nada en concreto.
var activity := ""
## Gesto que hace de vez en cuando mientras está en su sitio (limpiar, leer, reparar…).
var activity_gesture := ""
var talking := false:
	set(v):
		talking = v
		if _rig:
			_rig.talking = v

var _name_label: Label3D
var _display_name := "alguien"
var _body: Node3D        # gira hacia donde camina o mira
var _model: Node3D       # el modelo con su esqueleto (para vestirle)
var layers: Array = []   # las prendas que lleva puestas ahora (Wardrobe)
var _rig: HumanoidRig
var _target := Vector3.INF   # a dónde va andando
var _follow: Node3D = null
var _detour := 0.0          # segundos rodeando un obstáculo
var _detour_side := 1.0
var _path := PackedVector3Array()   # camino por la malla de navegación (vacío: en línea recta)
var _path_i := 0
var _path_for := Vector3.INF        # a qué destino corresponde el camino
var _repath_t := 0.0
var _last_bump := -100000         # cuándo chocó por última vez (ms)
var _bumps := 0
var _speed_override := 0.0     # > 0: corre (huir, ir con prisa)
var _walk_time := 0.0
var _walk_limit := 40.0      # si no llega en este tiempo (atascado), se da por llegado
var _bubble: Label3D
var _bubble_t := 0.0
var _present := true
var _shape: CollisionShape3D
var _settled := false      # quieto en un mueble (dormido, sentado, cocinando)
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _riding: Node3D = null    # va de pasajero en un vehículo
var _ride_seat := 0
var _knocked := 0.0           # segundos que le quedan en el suelo tras un golpe
var _limp := 0.0              # segundos que le quedan cojeando
## Lo que lleva en la mano ahora mismo ("" = nada): nombre para la IA ("una escoba").
var held := ""


func setup(entity: Dictionary) -> void:
	npc_id = entity.id
	Layers.character(self)
	var look: Dictionary = entity.get("appearance", {}).duplicate()
	var s: Vector3 = BODY_SCALE.get(look.get("body", "average"), Vector3.ONE)
	if not look.has("layers") and entity.has("occupation"):
		# Su ropa de siempre según su oficio (una vez: se queda en su ficha)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(entity.id) + "/ropa")
		look["layers"] = Wardrobe.for_job(str(entity.occupation), rng)
		if WorldDB.get_entity("npc", str(entity.id)).size() > 0:
			var app: Dictionary = WorldDB.get_entity("npc", str(entity.id)).get("appearance", {}).duplicate()
			app["layers"] = look.layers
			WorldDB.update_entity("npc", str(entity.id), {"appearance": app})
	var full := entity.duplicate()
	full["appearance"] = look
	layers = Wardrobe.for_weather(full) if entity.has("occupation") else look.get("layers", [])
	look["layers"] = layers

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35 * maxf(s.x, s.z)
	capsule.height = HEIGHT * s.y
	shape.shape = capsule
	shape.position.y = HEIGHT * s.y / 2.0
	add_child(shape)
	_shape = shape

	_body = Node3D.new()
	add_child(_body)
	var model := AssetLibrary.character(look, hash(npc_id))
	_model = model
	if model:
		var placed := AssetLibrary.place(_body, model, Vector3.ZERO, HEIGHT * s.y, 0.0, false)
		placed.scale = Vector3(s.x / s.y, 1.0, s.z / s.y)  # complexión (la altura ya va en place)
		_rig = HumanoidRig.new()
		model.add_child(_rig)
		if not _rig.setup(model):
			_rig.queue_free()
			_rig = null
		else:
			_rig.footstep.connect(func(_run): Sfx.footstep(self))
	else:
		_primitive_body(look, s)

	_name_label = _label(HEIGHT * s.y + 0.3)
	refresh_name(entity)

	var area := Area3D.new()
	Layers.zone(area)
	var zone := CollisionShape3D.new()
	zone.shape = SphereShape3D.new()
	zone.shape.radius = 2.2
	zone.position.y = 1.1
	area.add_child(zone)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


## Solo muestra el nombre si ya os conocéis: el mundo se "descubre".
## Se viste (o se quita) según lo que toca ahora: lluvia, frío, dentro de casa. Guarda en su
## ficha lo que lleva puesto, que es lo que la IA sabe de su ropa.
func redress(outdoors: bool = true) -> void:
	var entity := WorldDB.get_entity("npc", npc_id)
	if entity.is_empty() or _model == null:
		return
	var want := Wardrobe.for_weather(entity, outdoors)
	if str(want) == str(layers):
		return
	set_layers(want)


func set_layers(want: Array) -> void:
	layers = want
	if _model:
		Wardrobe.undress(_model)
		Wardrobe.dress(_model, layers)
	var entity := WorldDB.get_entity("npc", npc_id)
	if not entity.is_empty():
		var app: Dictionary = entity.get("appearance", {}).duplicate()
		app["layers"] = layers
		WorldDB.update_entity("npc", npc_id, {"appearance": app})


func refresh_name(entity: Dictionary) -> void:
	var met: bool = NPCMemory.get_mem(npc_id).met
	_name_label.text = entity.name if met else "?"
	_display_name = entity.name.split(" ")[0] if met else "alguien"


func interaction_prompt() -> String:
	return "Hablar con " + _display_name


func interaction_point() -> Vector3:
	return global_position + Vector3(0, 1.2, 0)


func can_interact() -> bool:
	return visible and not talking


func face(target: Vector3) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_body.rotation.y = atan2(d.x, d.z)


const SIT_GESTURES := ["sit", "sit_eat", "sit_read"]


## Gesto (dar algo, saludar, talar…). Ver HumanoidRig. Sentarse solo se puede EN algo: si hay
## una silla o una banca cerca va hasta ella; si no, se queda de pie (nunca sentado en el aire).
func play_gesture(gesture: String, duration: float = -1.0) -> void:
	if gesture in SIT_GESTURES and not _settled:
		var seat := seat_near(6.0)
		if seat == null:
			return
		var spot := seat.global_position
		walk_to(spot)
		await arrived
		if is_instance_valid(seat) and global_position.distance_to(spot) < 1.6 and not _settled:
			settle(spot + Vector3(0, 0.05, 0), spot + seat.global_basis.z * 2.0, gesture, activity)
			if duration > 0.0:
				get_tree().create_timer(duration).timeout.connect(func():
					if is_instance_valid(self) and _settled and not talking:
						unsettle())
		return
	if _rig:
		_rig.play(gesture, duration)


## La silla, banca o asiento libre más cercano (a menos de `radius` m), o null.
func seat_near(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for it in get_tree().get_nodes_in_group("interactables"):
		if not (it is Interactable) or not str(it.prompt).begins_with("Sentarse") or not (it.owner_node is Node3D):
			continue
		var seat: Node3D = it.owner_node
		var d := seat.global_position.distance_to(global_position)
		if d < best_d and absf(seat.global_position.y - global_position.y) < 1.5:
			best = seat
			best_d = d
	return best


func stop_gesture() -> void:
	if _rig:
		_rig.stop_gesture()


func set_emotion(emotion: String) -> void:
	if _rig:
		_rig.emotion = emotion


## Mira a quien tiene cerca (la cabeza sigue al jugador al pasar o al hablar).
func look_at_target(point: Vector3) -> void:
	if _rig:
		_rig.look_at_point = point


## El siguiente punto al que andar: el del camino por la malla (si la hay y llega) o el destino.
func _next_waypoint(goal: Vector3, delta: float) -> Vector3:
	_repath_t -= delta
	var moved := _path_for == Vector3.INF or _path_for.distance_to(goal) > (2.0 if _follow else 0.5)
	if moved and _repath_t <= 0.0:
		_repath_t = 0.8
		_path = NavBaker.path(self, global_position, goal)
		_path_i = 1
		_path_for = goal
	if _path.is_empty():
		return goal
	while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - global_position.x, _path[_path_i].z - global_position.z).length() < 0.6:
		_path_i += 1
	return _path[_path_i] if _path_i < _path.size() - 1 else goal


func walk_to(pos: Vector3, run: bool = false, pace: float = 0.0) -> void:
	_path_for = Vector3.INF
	_repath_t = 0.0
	unsettle()
	_follow = null
	_target = pos
	_walk_time = 0.0
	_speed_override = RUN_SPEED if run else pace
	var dist := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	_walk_limit = dist / maxf(_speed_override if _speed_override > 0.0 else WALK_SPEED, 0.5) * 2.5 + 15.0


## Bocadillo sobre la cabeza durante unos segundos (lo que suelta al reaccionar: "¡Eh!").
func say(text: String, seconds: float = 4.0) -> void:
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.fixed_size = true
		_bubble.font_size = 34
		_bubble.outline_size = 10
		_bubble.pixel_size = 0.0009
		_bubble.width = 520.0
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.modulate = Color("#fff6d8")
		_bubble.position.y = _name_label.position.y + 0.35
		add_child(_bubble)
	_bubble.text = "«%s»" % text
	_bubble.visible = true
	# Lo que dice cerca de ti queda en el registro del Cuaderno
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0].global_position.distance_to(global_position) < 20.0:
		var who := _display_name.capitalize() if _display_name != "alguien" else "Alguien"
		Journal.log_event("%s: «%s»" % [who, text], "say")
	_bubble_t = seconds


## Está en la escena (false: se metió en un edificio y no se le ve fuera).
func set_present(on: bool) -> void:
	_present = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for c in find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", not on or (c == _shape and _settled))
	if not on:
		stop()


## Se queda en un sitio haciendo algo (dormir en la cama, sentarse en el sofá, cocinar): sin
## gravedad ni choques con el mueble. Moverse (walk_to, follow) o unsettle() lo levanta.
func settle(pos: Vector3, look_to: Vector3, gesture: String, text: String) -> void:
	_target = Vector3.INF
	_follow = null
	_settled = true
	velocity = Vector3.ZERO
	set_physics_process(false)
	if _shape:
		_shape.set_deferred("disabled", true)
	global_position = pos
	face(look_to)
	_name_label.visible = gesture != "sleep"  # tumbado, el nombre quedaría flotando
	set_activity(text, gesture)
	if _rig and not gesture.is_empty():
		_rig.play(gesture, 1.0e6)


func unsettle() -> void:
	if not _settled:
		return
	_settled = false
	_name_label.visible = true
	set_physics_process(true)
	if _shape:
		_shape.set_deferred("disabled", not _present)
	if _rig:
		_rig.stop_gesture()
	global_position += _body.global_basis.z * 0.6 + Vector3(0, 0.2, 0)  # se pone de pie al lado


func is_settled() -> bool:
	return _settled


func is_asleep() -> bool:
	return _settled and activity_gesture == "sleep"


func is_present() -> bool:
	return _present


func follow(node: Node3D) -> void:
	unsettle()
	_follow = node
	_target = Vector3.INF


func stop() -> void:
	_follow = null
	_target = Vector3.INF


## Pararse un momento sin olvidar a dónde iba (esperar a alguien) y seguir después.
var _paused_target := Vector3.INF


func pause_walk() -> void:
	if _target != Vector3.INF:
		_paused_target = _target
		_target = Vector3.INF


func resume_walk() -> void:
	if _paused_target != Vector3.INF:
		_target = _paused_target
		_paused_target = Vector3.INF


func is_paused() -> bool:
	return _paused_target != Vector3.INF


## Lo que se lleva en la mano según lo que hace: [palabras, modelo, cómo se llama, largo, agarre].
const HELD_BY_ACTIVITY := [
	[["barr"], "proc:broom", "una escoba", 1.3, 0.55],
	[["limpi", "trapo", "seca ", "secando"], "proc:rag", "un trapo", 0.2, 0.5],
	[["tomando café", "tomando un café", "bebiendo café", "con su café", "tomando té"], "proc:cup", "una taza de café", 0.1, 0.5],
	[["leyendo", "lee "], "proc:book", "un libro", 0.22, 0.4],
	[["sirviendo", "atendiendo las mesas", "lleva una bandeja"], "proc:tray", "una bandeja", 0.4, 0.5],
	[["al teléfono", "hablando por teléfono", "mirando el celular", "con el celular"], "survival_pack/Phone", "el celular", 0.14, 0.5],
]


func set_activity(text: String, gesture: String) -> void:
	activity = text
	activity_gesture = gesture
	# Lo que dice que hace se ve: si barre, lleva una escoba; si no hace nada con las manos, nada
	var low := text.to_lower()
	var want: Array = []
	for h in HELD_BY_ACTIVITY:
		if h[0].any(func(w): return low.contains(w)):
			want = h
			break
	if want.is_empty():
		if not held.is_empty():
			hold("", "")
	elif held != str(want[2]):
		hold(str(want[1]), str(want[2]), float(want[3]), float(want[4]))


func is_idle() -> bool:
	return _present and not talking and not is_walking() and not is_following() and not is_asleep()


func current_gesture() -> String:
	return _rig.gesture() if _rig else ""


## Qué hace, en una frase corta (para la IA): "está hablando contigo", "va caminando", "está leyendo"…
func doing() -> String:
	if talking:
		return "está hablando contigo"
	if is_following():
		return "te acompaña"
	if is_walking():
		return "va caminando a algún sitio"
	return ("está " + activity) if not activity.is_empty() else "está ahí, sin hacer nada en concreto"


func is_following() -> bool:
	return _follow != null


func is_walking() -> bool:
	return _target != Vector3.INF


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		# Lo que dice alguien lejos no se ve: a más de 22 m, el texto (de tamaño fijo en pantalla)
		# quedaba como un punto que de noche brillaba como una luz
		var cam := get_viewport().get_camera_3d()
		_bubble.visible = _bubble_t > 0.0 and (cam == null or cam.global_position.distance_to(global_position) < BUBBLE_RANGE)


func _physics_process(delta: float) -> void:
	if _riding != null:
		if not is_instance_valid(_riding):
			_riding = null
		else:
			velocity = Vector3.ZERO
			global_position = _riding.call("seat_position", _ride_seat)
			_body.global_rotation.y = _riding.global_rotation.y
			if _rig:
				_rig.speed = 0.0
				_rig.airborne = false
			return
	if _knocked > 0.0:  # en el suelo: el golpe le arrastra y frena con el roce
		_knocked -= delta
		if not is_on_floor():
			velocity.y -= _gravity * delta
		else:
			velocity.x = move_toward(velocity.x, 0, 9.0 * delta)
			velocity.z = move_toward(velocity.z, 0, 9.0 * delta)
		move_and_slide()
		if _knocked <= 0.0:
			_get_up()
		return
	if _limp > 0.0:
		_limp -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var goal := Vector3.INF
	var speed := WALK_SPEED
	if talking:
		goal = Vector3.INF
	elif _follow and is_instance_valid(_follow):
		var to_player := _follow.global_position - global_position
		if Vector2(to_player.x, to_player.z).length() > 30.0:  # se quedó atrás: alcanza al jugador
			global_position = _follow.global_position + Vector3(1.5, 0.5, 1.5)
		elif Vector2(to_player.x, to_player.z).length() > FOLLOW_DISTANCE:
			goal = _follow.global_position
			speed = FOLLOW_SPEED if Vector2(to_player.x, to_player.z).length() > 6.0 else WALK_SPEED * 1.6
	elif _target != Vector3.INF:
		_walk_time += delta
		if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 0.8 or _walk_time > _walk_limit:
			_target = Vector3.INF
			_speed_override = 0.0
			arrived.emit()
			if not _present or _settled:
				return  # al llegar entró en un edificio (o se sentó): ya no se mueve aquí
		else:
			goal = _target
			if _speed_override > 0.0:
				speed = _speed_override

	if goal != Vector3.INF:
		goal = _next_waypoint(goal, delta)
		var dir := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z).normalized()
		if _detour > 0.0:  # rodear: caminar en diagonal hasta dejar atrás el obstáculo
			_detour -= delta
			dir = dir.rotated(Vector3.UP, deg_to_rad(75.0) * _detour_side)
		if _limp > 0.0:
			speed = minf(speed, WALK_SPEED * 0.6)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), 8.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 10.0 * delta)
	move_and_slide()
	# Atascado contra algo mientras va a un sitio: lo rodea (y salta si es bajo)
	if goal != Vector3.INF and is_on_wall() and _detour <= 0.0:
		_detour = 0.9
		var now := Time.get_ticks_msec()
		if now - _last_bump < 2500:
			# Volvió a chocar enseguida: por ese lado no se pasa, prueba por el otro (cada vez más lejos)
			_detour_side = -_detour_side
			_detour = 0.9 + 0.5 * mini(_bumps, 4)
			_bumps += 1
		else:
			# Hacia el lado por el que la pared «se abre» camino del destino (no a cara o cruz)
			var n := get_wall_normal()
			var to_goal := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
			_detour_side = 1.0 if n.cross(Vector3.UP).dot(to_goal) < 0.0 else -1.0
			_bumps = 0
		_last_bump = now
		_path_for = Vector3.INF  # y busca otro camino
		if is_on_floor():
			velocity.y = 2.5
	if _rig:
		_rig.speed = Vector2(velocity.x, velocity.z).length()
		_rig.airborne = not is_on_floor() and velocity.y < -2.0


# --- En un vehículo, atropellos y lo que lleva en la mano -------------------------------------

## Se sube de pasajero (lo coloca el vehículo en su asiento cada frame).
func ride(vehicle: Node3D, seat: int) -> void:
	unsettle()
	stop()
	_riding = vehicle
	_ride_seat = seat
	if _shape:
		_shape.set_deferred("disabled", true)
	if _rig:
		_rig.play("sit", 1.0e6)
	set_activity("va en %s" % (vehicle.call("the_name") if vehicle.has_method("the_name") else "el coche"), "sit")


func get_off(at: Vector3) -> void:
	_riding = null
	global_position = at
	velocity = Vector3.ZERO
	if _shape:
		_shape.set_deferred("disabled", not _present)
	if _rig:
		_rig.stop_gesture()
	set_activity("", "")


func is_riding() -> bool:
	return _riding != null and is_instance_valid(_riding)


func riding_vehicle() -> Node3D:
	return _riding if is_riding() else null


## Le da un golpe fuerte (un coche): sale despedido, cae, se queda en el suelo unos segundos y se
## levanta cojeando. `impact`: velocidad del golpe (m/s).
func knock_down(push: Vector3, impact: float) -> void:
	if _riding:
		return
	unsettle()
	_follow = null
	_target = Vector3.INF
	talking = false
	velocity = push
	_knocked = clampf(2.5 + impact * 0.3, 3.0, 8.0)
	_limp = clampf(impact * 8.0, 30.0, 240.0)
	if _rig:
		_rig.play("fallen", 1.0e6)
	set_emotion("scared")


func is_knocked() -> bool:
	return _knocked > 0.0


func _get_up() -> void:
	if _rig:
		_rig.stop_gesture()
	set_emotion("angry" if _limp > 60.0 else "worried")
	global_position.y += 0.15


## Coge algo en la mano (de verdad: se ve). model "pack/Modelo"; name lo que es ("una escoba").
func hold(model: String, name: String, length: float = 0.3, grip: float = 0.3) -> void:
	held = name if not model.is_empty() else ""
	if _rig:
		_rig.set_held(model, length, grip)


## Lo que lleva en la mano, para la IA ("lleva una escoba en la mano" o "no lleva nada en las manos").
func held_desc() -> String:
	return ("lleva %s en la mano" % held) if not held.is_empty() else "no lleva nada en las manos"


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.interaction.add_candidate(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		body.interaction.remove_candidate(self)


func _primitive_body(look: Dictionary, s: Vector3) -> void:
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = s.y
	body.scale = s
	body.material_override = _mat(Color(look.get("primary_color", "#888888")))
	_body.add_child(body)


## Nombre sobre la cabeza: tamaño fijo en pantalla, tapado por las paredes y solo de cerca.
func _label(height: float) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.font_size = 40
	l.outline_size = 10
	l.pixel_size = 0.0009
	l.modulate = Color(1, 1, 1, 0.92)
	l.visibility_range_end = 16.0
	l.visibility_range_end_margin = 3.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	l.position.y = height
	add_child(l)
	return l


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

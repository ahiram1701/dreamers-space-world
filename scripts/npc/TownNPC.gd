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
var _rig: HumanoidRig
var _target := Vector3.INF   # a dónde va andando
var _follow: Node3D = null
var _detour := 0.0          # segundos rodeando un obstáculo
var _detour_side := 1.0
var _speed_override := 0.0     # > 0: corre (huir, ir con prisa)
var _walk_time := 0.0
var _bubble: Label3D
var _bubble_t := 0.0
var _present := true
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(entity: Dictionary) -> void:
	npc_id = entity.id
	Layers.character(self)
	var look: Dictionary = entity.get("appearance", {})
	var s: Vector3 = BODY_SCALE.get(look.get("body", "average"), Vector3.ONE)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35 * maxf(s.x, s.z)
	capsule.height = HEIGHT * s.y
	shape.shape = capsule
	shape.position.y = HEIGHT * s.y / 2.0
	add_child(shape)

	_body = Node3D.new()
	add_child(_body)
	var model := AssetLibrary.character(look, hash(npc_id))
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


## Gesto (dar algo, saludar, talar…). Ver HumanoidRig.
func play_gesture(gesture: String, duration: float = -1.0) -> void:
	if _rig:
		_rig.play(gesture, duration)


func set_emotion(emotion: String) -> void:
	if _rig:
		_rig.emotion = emotion


## Mira a quien tiene cerca (la cabeza sigue al jugador al pasar o al hablar).
func look_at_target(point: Vector3) -> void:
	if _rig:
		_rig.look_at_point = point


func walk_to(pos: Vector3, run: bool = false) -> void:
	_follow = null
	_target = pos
	_walk_time = 0.0
	_speed_override = RUN_SPEED if run else 0.0


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
		c.set_deferred("disabled", not on)
	if not on:
		stop()


func is_present() -> bool:
	return _present


func follow(node: Node3D) -> void:
	_follow = node
	_target = Vector3.INF


func stop() -> void:
	_follow = null
	_target = Vector3.INF


func set_activity(text: String, gesture: String) -> void:
	activity = text
	activity_gesture = gesture


func is_idle() -> bool:
	return _present and not talking and not is_walking() and not is_following()


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
		if _bubble_t <= 0.0:
			_bubble.visible = false


func _physics_process(delta: float) -> void:
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
		if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 0.8 or _walk_time > 40.0:
			_target = Vector3.INF
			_speed_override = 0.0
			arrived.emit()
		else:
			goal = _target
			if _speed_override > 0.0:
				speed = _speed_override

	if goal != Vector3.INF:
		var dir := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z).normalized()
		if _detour > 0.0:  # rodear: caminar en diagonal hasta dejar atrás el obstáculo
			_detour -= delta
			dir = dir.rotated(Vector3.UP, deg_to_rad(75.0) * _detour_side)
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
		_detour_side = 1.0 if randf() < 0.5 else -1.0
		if is_on_floor():
			velocity.y = 2.5
	if _rig:
		_rig.speed = Vector2(velocity.x, velocity.z).length()
		_rig.airborne = not is_on_floor() and velocity.y < -2.0


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

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

var npc_id: String = ""
var talking := false:
	set(v):
		talking = v
		if _rig:
			_rig.talking = v

var _name_label: Label3D
var _hint: Label3D
var _body: Node3D        # gira hacia donde camina o mira
var _rig: HumanoidRig
var _target := Vector3.INF   # a dónde va andando
var _follow: Node3D = null
var _detour := 0.0          # segundos rodeando un obstáculo
var _detour_side := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(entity: Dictionary) -> void:
	npc_id = entity.id
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
		_primitive_body(look, s)

	_name_label = _label(HEIGHT * s.y + 0.45, 48)
	_hint = _label(HEIGHT * s.y + 0.2, 32)
	_hint.text = "[E] Hablar"
	_hint.visible = false
	refresh_name(entity)

	var area := Area3D.new()
	var zone := CollisionShape3D.new()
	zone.shape = SphereShape3D.new()
	zone.shape.radius = 2.6
	zone.position.y = 1.0
	area.add_child(zone)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


## Solo muestra el nombre si ya os conocéis: el mundo se "descubre".
func refresh_name(entity: Dictionary) -> void:
	var met: bool = NPCMemory.get_mem(npc_id).met
	_name_label.text = entity.name if met else "?"


func face(target: Vector3) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_body.rotation.y = atan2(d.x, d.z)


func walk_to(pos: Vector3) -> void:
	_follow = null
	_target = pos


func follow(node: Node3D) -> void:
	_follow = node
	_target = Vector3.INF


func stop() -> void:
	_follow = null
	_target = Vector3.INF


func is_following() -> bool:
	return _follow != null


func is_walking() -> bool:
	return _target != Vector3.INF


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
		if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 0.6:
			_target = Vector3.INF
		else:
			goal = _target

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


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.interact_target = self
		_hint.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body is Player and body.interact_target == self:
		body.interact_target = null
	if body is Player:
		_hint.visible = false


func _primitive_body(look: Dictionary, s: Vector3) -> void:
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = s.y
	body.scale = s
	body.material_override = _mat(Color(look.get("primary_color", "#888888")))
	_body.add_child(body)


func _label(height: float, font_size: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = font_size
	l.outline_size = 8
	l.pixel_size = 0.006
	l.position.y = height
	add_child(l)
	return l


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

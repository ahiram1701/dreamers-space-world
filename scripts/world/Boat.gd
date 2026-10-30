class_name Boat
extends Node3D
## Barca o balsa que flota con el oleaje. Con E te subes (el personaje se sienta y rema) y
## la manejas con WASD o el stick; con E otra vez te bajas en la orilla más cercana, o al agua si
## no la hay. Es sólida (no se atraviesa) y por dentro está seca: una tapa invisible que solo
## escribe profundidad impide que el agua se dibuje dentro del casco.

const MAX_SPEED := 5.5
const TURN_SPEED := 1.1
const MASK_SHADER := preload("res://shaders/water_mask.gdshader")

## Altura del agua y del terreno (la escena los asigna).
var water_level := -0.45
var ground_at: Callable = func(_x: float, _z: float) -> float: return -10.0
var seat_height := 0.35

var _rider: Player
var _speed := 0.0
var _use: Interactable
var _rowing := false
var _draft := 0.25        # cuánto se hunde el casco bajo la línea de flotación
var _hull: AnimatableBody3D


## Monta la barca con un modelo (pack, nombre) de `length` metros de eslora.
func setup(pack: String, model_name: String, length: float, label: String = "Subir a la barca") -> void:
	var size := Vector3(length * 0.4, 0.6, length)
	var model := AssetLibrary.instance(pack, model_name)
	if model:
		var b := AssetLibrary.bounds(model)
		var long_side := maxf(b.size.x, b.size.z)
		var scale := length / long_side
		var holder := AssetLibrary.place(self, model, Vector3.ZERO, b.size.y * scale, PI / 2 if b.size.x > b.size.z else 0.0, false)
		size = holder.get_meta("size", size)
		if b.size.x > b.size.z:
			size = Vector3(size.z, size.y, size.x)
		# Casco: hasta la borda (las velas y mástiles no cuentan); se hunde ~30 % de su altura
		var hull_h := minf(size.y, length * 0.28)
		_draft = clampf(hull_h * 0.3, 0.12, 0.45)
		holder.position.y = -_draft
		seat_height = clampf(hull_h * 0.45 - _draft, 0.1, 0.6)
		size.y = hull_h
	else:  # casco sencillo si falta el modelo
		var hull := MeshInstance3D.new()
		hull.mesh = BoxMesh.new()
		hull.mesh.size = Vector3(length * 0.4, 0.4, length)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#8b6b4a")
		hull.material_override = m
		add_child(hull)
	_add_hull(size)
	_add_water_mask(size)
	_use = Interactable.create(self, Vector3(0, 0.6, 0), maxf(length * 0.5, 2.2), label, _on_use, self)


## Colisión del casco: se mueve con la barca (el jugador y los PNJs no la atraviesan).
func _add_hull(size: Vector3) -> void:
	_hull = AnimatableBody3D.new()
	_hull.sync_to_physics = false
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(size.x * 0.9, size.y, size.z * 0.92)
	cs.position.y = size.y / 2.0 - _draft
	_hull.add_child(cs)
	add_child(_hull)


## Tapa a la altura de la borda, un poco más pequeña que el casco por dentro.
func _add_water_mask(size: Vector3) -> void:
	var cap := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size.x * 0.8, size.z * 0.85)
	cap.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = MASK_SHADER
	mat.render_priority = -10
	cap.material_override = mat
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.position.y = maxf(size.y * 0.55 - _draft, 0.08)
	add_child(cap)


func seat_position() -> Vector3:
	return global_transform * Vector3(0, seat_height, 0)


func is_occupied() -> bool:
	return _rider != null


func _on_use(player: Player) -> void:
	if _rider == null:
		_rider = player
		player.riding = self
		player.add_collision_exception_with(_hull)
		player.play_gesture("sit")
		_use.set_prompt("Bajar")
		Sfx.at(self, "splash", global_position)
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
	var landed := false
	for dist in [2.5, 3.5, 5.0, 7.0]:
		for i in 16:
			var a := TAU * i / 16.0
			var p: Vector3 = here + Vector3(cos(a), 0, sin(a)) * dist
			var g: float = ground_at.call(p.x, p.z)
			if g > water_level + 0.05:
				player.global_position = Vector3(p.x, g + 0.4, p.z)
				landed = true
				break
		if landed:
			break
	if not landed:
		player.global_position = here + global_basis.x * 2.2 + Vector3(0, -0.6, 0)
		Sfx.at(self, "splash", player.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_instance_valid(player):
		player.remove_collision_exception_with(_hull)


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
		var input := Controls.move_vector()
		throttle = -input.y * (1.0 if input.y < 0.0 else 0.6)
		turn = -input.x
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

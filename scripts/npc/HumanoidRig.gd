class_name HumanoidRig
extends Node
## Anima por código el esqueleto de los personajes Quaternius (las copias GLB vienen sin
## animaciones). Sistema de poses en 3 ejes del cuerpo con capas que se mezclan:
##   1. locomoción: reposo (respira, cambia el peso, mira alrededor), caminar, correr, saltar,
##      nadar y remar;
##   2. gesto: talar, martillar, cavar, sentarse, dormir, saludar, entregar algo… (play());
##   3. expresión al hablar según la emoción.
## Las poses son grados por hueso: x = adelante/atrás, y = giro, z = hacia fuera del cuerpo.
## En brazos y piernas x > 0 lleva el miembro hacia delante; en la columna, inclina hacia delante.
##
## Uso:  var rig := HumanoidRig.new(); model.add_child(rig); rig.setup(model)
##       rig.speed = m/s; rig.airborne; rig.talking; rig.emotion; rig.look_at_point = Vector3
##       rig.play("chop", 4.0); rig.stop_gesture()

const BONES := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head", "Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
	"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R", "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
const SPINE := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head"]
const BLEND := 0.25            # segundos para entrar o salir de un gesto
## Gestos que duran hasta que se paran (los demás son de un par de segundos).
const LOOPING := ["chop", "hammer", "dig", "search", "fish", "dance", "sleep", "sit", "crouch", "row", "swim", "think", "cross_arms"]
## Herramienta en la mano derecha durante el gesto: [modelo, altura en m, giro en grados]
const TOOLS := {
	"chop": ["survival_pack/Axe", 0.75, Vector3(0, 0, -90)], "dig": ["survival_pack/Shovel", 1.1, Vector3(0, 0, -90)],
	"hammer": ["survival_pack/Axe_Small", 0.38, Vector3(0, 0, -90)], "fish": ["", 1.8, Vector3(0, 0, -60)],
	"drink": ["survival_pack/WaterBottle_1", 0.22, Vector3.ZERO], "row": ["survival_pack/Raft_Paddle", 1.4, Vector3(90, 0, 0)],
}

var speed := 0.0
var airborne := false
var swimming := false
var talking := false
var emotion := "neutral"
## Punto del mundo al que mira la cabeza (Vector3.INF: mira alrededor).
var look_at_point := Vector3.INF

var _sk: Skeleton3D
var _model: Node3D
var _model_pos := Vector3.ZERO
var _model_rot := Vector3.ZERO
var _idx := {}
var _base := {}
var _parent_of := {}
var _down := Vector3.DOWN
var _fwd := Vector3.FORWARD
var _side := Vector3.RIGHT
var _out_sign := 1.0         # signo para separar los brazos y piernas del cuerpo
var _pitch_axis := Vector3.RIGHT
var _t := 0.0
var _phase := 0.0
var _pose := {}              # pose suavizada actual
var _gesture := ""
var _gesture_t := 0.0
var _gesture_len := 0.0
var _gesture_w := 0.0
var _tool: Node3D
var _hand_attach: BoneAttachment3D


func setup(model: Node3D) -> bool:
	_model = model
	_model_pos = model.position
	_model_rot = model.rotation
	_sk = _find_skeleton(model)
	if _sk == null:
		return false
	for b in BONES:
		_idx[b] = _sk.find_bone(b)
		if _idx[b] == -1:
			_sk = null
			return false
	var to_model := _skeleton_to_model(model)
	_down = (to_model.basis.inverse() * Vector3.DOWN).normalized()
	_fwd = (to_model.basis.inverse() * Vector3.BACK).normalized()   # los modelos miran hacia +Z
	_side = (_sk.get_bone_global_pose(_idx["UpperArm.R"]).origin - _sk.get_bone_global_pose(_idx["UpperArm.L"]).origin).normalized()
	_pitch_axis = _down.cross(_fwd).normalized()  # girar +θ lleva "abajo" hacia "delante"
	_out_sign = signf(_fwd.cross(_down).dot(_side))
	# De la pose en T a brazos relajados
	_aim("UpperArm.L", "LowerArm.L", (_down - _side * 0.2).normalized())
	_aim("UpperArm.R", "LowerArm.R", (_down + _side * 0.2).normalized())
	for b in BONES:
		_base[b] = _sk.get_bone_pose_rotation(_idx[b])
		_parent_of[b] = _sk.get_bone_parent(_idx[b])
		_pose[b] = Vector3.ZERO
	_pose["_y"] = 0.0
	_pose["_lie"] = 0.0
	_pose["_swim"] = 0.0
	_phase = randf() * TAU
	_t = randf() * 10.0
	return true


## Empieza un gesto. duration < 0: el de por defecto (los de bucle duran hasta stop_gesture()).
func play(gesture: String, duration: float = -1.0) -> void:
	if _sk == null or gesture.is_empty():
		return
	_gesture = gesture
	_gesture_t = 0.0
	_gesture_len = duration if duration > 0.0 else (INF if gesture in LOOPING else 2.2)
	_set_tool(gesture)


func stop_gesture() -> void:
	_gesture_len = minf(_gesture_len, _gesture_t)  # sale con la mezcla


func gesture() -> String:
	return _gesture if _gesture_w > 0.01 else ""


func _process(delta: float) -> void:
	if _sk == null:
		return
	_t += delta
	var target := _locomotion(delta)
	# Capa de gesto
	if not _gesture.is_empty():
		_gesture_t += delta
		var active := _gesture_t < _gesture_len
		_gesture_w = move_toward(_gesture_w, 1.0 if active else 0.0, delta / BLEND)
		if _gesture_w <= 0.0 and not active:
			_gesture = ""
			_set_tool("")
		else:
			_mix(target, _gesture_pose(_gesture, _gesture_t), _gesture_w)
	# Capa de expresión al hablar (más suave si ya hay un gesto)
	if talking and _gesture_w < 0.5:
		_mix(target, _talk_pose(), 1.0 - _gesture_w * 2.0)
	_apply_look(target)
	# Suavizado: nada salta de una pose a otra
	var k := 1.0 - exp(-14.0 * delta)
	for key in target:
		_pose[key] = lerp(_pose.get(key, target[key] * 0.0), target[key], k)
	_apply()


# --- Capa 1: locomoción --------------------------------------------------------------

func _locomotion(delta: float) -> Dictionary:
	var p := _empty()
	var walk := clampf(speed / 4.0, 0.0, 1.0)
	var run := clampf((speed - 4.8) / 3.0, 0.0, 1.0)
	_phase += delta * (1.8 + speed * 1.45)
	var s := sin(_phase)
	var c := cos(_phase)
	var still := 1.0 - walk

	if swimming:
		var sw := sin(_t * 2.6)
		p["_swim"] = 1.0
		p["UpperArm.L"] = Vector3(100 + sw * 70, 0, 20)
		p["UpperArm.R"] = Vector3(100 - sw * 70, 0, 20)
		p["LowerArm.L"] = Vector3(20, 0, 0)
		p["LowerArm.R"] = Vector3(20, 0, 0)
		p["UpperLeg.L"] = Vector3(sin(_t * 6.0) * 18, 0, 5)
		p["UpperLeg.R"] = Vector3(-sin(_t * 6.0) * 18, 0, 5)
		p["Head"] = Vector3(-40, 0, 0)
		return p
	if airborne:
		p["UpperLeg.L"] = Vector3(35, 0, 4)
		p["LowerLeg.L"] = Vector3(-55, 0, 0)
		p["UpperLeg.R"] = Vector3(-5, 0, 4)
		p["LowerLeg.R"] = Vector3(-25, 0, 0)
		p["UpperArm.L"] = Vector3(25, 0, 30)
		p["UpperArm.R"] = Vector3(25, 0, 30)
		p["LowerArm.L"] = Vector3(35, 0, 0)
		p["LowerArm.R"] = Vector3(35, 0, 0)
		p["Torso"] = Vector3(8, 0, 0)
		return p

	# Reposo: respirar, cambiar el peso de pierna, manos relajadas
	var breath := sin(_t * 1.7)
	var sway := sin(_t * 0.45)
	p["Chest"] = Vector3(breath * 1.5 * still, 0, 0)
	p["Hips"] = Vector3(0, 0, sway * 2.5 * still)
	p["Abdomen"] = Vector3(0, 0, -sway * 1.5 * still)
	p["UpperLeg.L"] = Vector3(0, 0, -sway * 2.0 * still)
	p["UpperLeg.R"] = Vector3(0, 0, sway * 2.0 * still)
	p["UpperArm.L"] = Vector3(3 + breath * 1.5, 0, 0)
	p["UpperArm.R"] = Vector3(3 + breath * 1.5, 0, 0)
	p["LowerArm.L"] = Vector3(12, 0, 0)
	p["LowerArm.R"] = Vector3(12, 0, 0)
	p["Hand.L"] = Vector3(6, 0, 0)
	p["Hand.R"] = Vector3(6, 0, 0)

	if walk > 0.01:
		var leg := 26.0 + 14.0 * run
		_add(p, "UpperLeg.L", Vector3(s * leg, 0, 0) * walk)
		_add(p, "UpperLeg.R", Vector3(-s * leg, 0, 0) * walk)
		# La rodilla se dobla al levantar el pie (fase de vuelo) y casi nada al apoyar
		_add(p, "LowerLeg.L", Vector3(-(8 + (35 + 45 * run) * maxf(0.0, -sin(_phase - 0.8))), 0, 0) * walk)
		_add(p, "LowerLeg.R", Vector3(-(8 + (35 + 45 * run) * maxf(0.0, sin(_phase - 0.8))), 0, 0) * walk)
		_add(p, "Foot.L", Vector3(s * 12, 0, 0) * walk)
		_add(p, "Foot.R", Vector3(-s * 12, 0, 0) * walk)
		var arm := 20.0 + 35.0 * run
		_add(p, "UpperArm.L", Vector3(-s * arm, 0, 4) * walk)
		_add(p, "UpperArm.R", Vector3(s * arm, 0, 4) * walk)
		_add(p, "LowerArm.L", Vector3(10 + 65 * run, 0, 0) * walk)
		_add(p, "LowerArm.R", Vector3(10 + 65 * run, 0, 0) * walk)
		# Cadera y hombros giran en contra; el tronco se inclina al correr
		_add(p, "Hips", Vector3(0, s * 7, c * 2) * walk)
		_add(p, "Chest", Vector3(0, -s * 9, 0) * walk)
		_add(p, "Torso", Vector3(4 + 14 * run, 0, 0) * walk)
		_add(p, "Head", Vector3(-(2 + 8 * run), -s * 2, 0) * walk)
		p["_y"] = -absf(c) * 0.04 * walk - 0.05 * run
	return p


# --- Capa 2: gestos ------------------------------------------------------------------

## Solo las claves que el gesto toca: el resto sigue la locomoción (respirar, mirar…).
func _gesture_pose(g: String, t: float) -> Dictionary:
	var p := {}
	var w := sin(t * 2.0)
	match g:
		"chop":   # hacha por encima del hombro y golpe hacia abajo
			var cyc := fmod(t, 1.2) / 1.2
			var up := smoothstep(0.0, 0.55, cyc) - smoothstep(0.62, 0.78, cyc)
			_both_arms(p, Vector3(40 + up * 120, 0, -8), Vector3(20 + up * 30, 0, 0))
			p["Torso"] = Vector3(25 - up * 30, 15 - up * 15, 0)
			p["Chest"] = Vector3(8, 0, 0)
			_legs_apart(p, 12)
			p["LowerLeg.L"] = Vector3(-15, 0, 0)
			p["LowerLeg.R"] = Vector3(-15, 0, 0)
		"hammer":
			var hit := absf(sin(t * 5.0))
			p["UpperArm.R"] = Vector3(55 + hit * 35, 0, 5)
			p["LowerArm.R"] = Vector3(60 - hit * 30, 0, 0)
			p["UpperArm.L"] = Vector3(45, 0, -5)
			p["LowerArm.L"] = Vector3(55, 0, 0)
			_kneel(p, 0.55)
			p["Torso"] = Vector3(30, 0, 0)
		"dig":
			var cyc := sin(t * 2.4)
			_both_arms(p, Vector3(55 + cyc * 25, 0, -5), Vector3(30 - cyc * 15, 0, 0))
			p["Torso"] = Vector3(30 + cyc * 12, 0, 0)
			_legs_apart(p, 10)
			p["UpperLeg.L"] = Vector3(20, 0, 8)
			p["LowerLeg.L"] = Vector3(-30, 0, 0)
		"pick_up", "search", "crouch":
			_crouch(p)
			if g != "crouch":
				p["UpperArm.R"] = Vector3(70 + w * 15, 0, 5)
				p["UpperArm.L"] = Vector3(60 - w * 15, 0, 5)
				p["LowerArm.R"] = Vector3(20, 0, 0)
				p["LowerArm.L"] = Vector3(25, 0, 0)
				p["Head"] = Vector3(25, w * 15, 0)
		"sit", "row":
			p["_y"] = -0.48
			p["UpperLeg.L"] = Vector3(88, 0, 6)
			p["UpperLeg.R"] = Vector3(88, 0, 6)
			p["LowerLeg.L"] = Vector3(-88, 0, 0)
			p["LowerLeg.R"] = Vector3(-88, 0, 0)
			p["UpperArm.L"] = Vector3(25, 0, 6)
			p["UpperArm.R"] = Vector3(25, 0, 6)
			p["LowerArm.L"] = Vector3(40, 0, 0)
			p["LowerArm.R"] = Vector3(40, 0, 0)
			if g == "row":
				var pull := sin(t * 2.2)
				_both_arms(p, Vector3(55 + pull * 30, 0, 10), Vector3(35 - pull * 30, 0, 0))
				p["Torso"] = Vector3(pull * 14, 0, 0)
		"sleep":
			p["_lie"] = 1.0
			p["UpperArm.L"] = Vector3(0, 0, 4)
			p["UpperArm.R"] = Vector3(0, 0, 4)
			p["LowerArm.L"] = Vector3(25, 0, 0)
			p["Head"] = Vector3(0, 20, 0)
			p["Chest"] = Vector3(sin(t * 1.1) * 2, 0, 0)
			p["UpperLeg.R"] = Vector3(10, 0, 0)
			p["LowerLeg.R"] = Vector3(-15, 0, 0)
		"drink", "eat":
			var lift := 0.6 + 0.4 * sin(t * 1.6)
			p["UpperArm.R"] = Vector3(35 + lift * 20, 0, 12)
			p["LowerArm.R"] = Vector3(70 + lift * 60, 0, 0)
			p["Head"] = Vector3(-10 * lift, 0, 0)
		"wave":
			p["UpperArm.R"] = Vector3(20, 0, 145)
			p["LowerArm.R"] = Vector3(25, 0, sin(t * 9.0) * 25)
			p["Head"] = Vector3(-5, 0, 6)
		"point":
			p["UpperArm.R"] = Vector3(85, -10, 6)
			p["LowerArm.R"] = Vector3(5, 0, 0)
			p["Head"] = Vector3(-5, -10, 0)
		"give":
			var reach := smoothstep(0.0, 0.6, t)
			p["UpperArm.R"] = Vector3(55 * reach, 0, 8)
			p["LowerArm.R"] = Vector3(25 + 15 * (1.0 - reach), 0, 0)
			p["Torso"] = Vector3(10 * reach, 0, 0)
			p["Head"] = Vector3(12, 0, 0)
		"fish":
			_both_arms(p, Vector3(45 + sin(t * 0.8) * 4, 0, -10), Vector3(45, 0, 0))
			p["Torso"] = Vector3(-6, 0, 0)
		"dance":
			var b := sin(t * 6.0)
			p["Hips"] = Vector3(0, b * 12, b * 8)
			p["UpperArm.L"] = Vector3(40 + b * 40, 0, 50 + b * 30)
			p["UpperArm.R"] = Vector3(40 - b * 40, 0, 50 - b * 30)
			p["LowerArm.L"] = Vector3(60, 0, 0)
			p["LowerArm.R"] = Vector3(60, 0, 0)
			p["UpperLeg.L"] = Vector3(maxf(0.0, b) * 35, 0, 6)
			p["UpperLeg.R"] = Vector3(maxf(0.0, -b) * 35, 0, 6)
			p["LowerLeg.L"] = Vector3(-maxf(0.0, b) * 50, 0, 0)
			p["LowerLeg.R"] = Vector3(-maxf(0.0, -b) * 50, 0, 0)
			p["_y"] = -absf(b) * 0.06
			p["Head"] = Vector3(b * 8, 0, -b * 8)
		"think":
			p["UpperArm.R"] = Vector3(35, 0, 10)
			p["LowerArm.R"] = Vector3(125, 0, 0)
			p["UpperArm.L"] = Vector3(25, 25, -10)
			p["LowerArm.L"] = Vector3(90, 0, 0)
			p["Head"] = Vector3(10, 0, 8 + sin(t) * 3)
		"cross_arms":
			p["UpperArm.L"] = Vector3(25, 30, -12)
			p["UpperArm.R"] = Vector3(25, -30, -12)
			p["LowerArm.L"] = Vector3(105, 0, 0)
			p["LowerArm.R"] = Vector3(110, 0, 0)
			p["Head"] = Vector3(-6, 0, 0)
			p["Hips"] = Vector3(0, 0, 4)
		"shrug":
			var up := sin(clampf(t / 1.2, 0.0, 1.0) * PI)
			p["Shoulder.L"] = Vector3(0, 0, 14 * up)
			p["Shoulder.R"] = Vector3(0, 0, 14 * up)
			p["UpperArm.L"] = Vector3(15, 0, 20 * up)
			p["UpperArm.R"] = Vector3(15, 0, 20 * up)
			p["LowerArm.L"] = Vector3(70 * up, 0, 0)
			p["LowerArm.R"] = Vector3(70 * up, 0, 0)
			p["Head"] = Vector3(0, 0, 10 * up)
		"nod":
			p["Head"] = Vector3(sin(t * 7.0) * 14 * (1.0 - clampf(t / 2.0, 0.0, 1.0)), 0, 0)
		"shake_head":
			p["Head"] = Vector3(0, sin(t * 7.0) * 22 * (1.0 - clampf(t / 2.0, 0.0, 1.0)), 0)
	return p


## Gestos de fondo mientras habla, según cómo se siente.
func _talk_pose() -> Dictionary:
	var p := {}
	var a := sin(_t * 2.1)
	var b := sin(_t * 1.3 + 1.0)
	match emotion:
		"angry":
			p["UpperArm.R"] = Vector3(40 + a * 20, 0, 10)
			p["LowerArm.R"] = Vector3(70, 0, 0)
			p["Head"] = Vector3(-6 + a * 4, 0, 0)
			p["Torso"] = Vector3(8, 0, 0)
		"sad":
			p["Head"] = Vector3(18, 0, 0)
			p["Chest"] = Vector3(10, 0, 0)
			p["Shoulder.L"] = Vector3(0, 0, -6)
			p["Shoulder.R"] = Vector3(0, 0, -6)
		"worried", "scared":
			p["UpperArm.L"] = Vector3(30, 20, -6)
			p["LowerArm.L"] = Vector3(85, 0, 0)
			p["UpperArm.R"] = Vector3(30, -20, -6)
			p["LowerArm.R"] = Vector3(85, 0, 0)
			p["Head"] = Vector3(6, b * 10, 0)
		"curious", "mysterious":
			p["UpperArm.R"] = Vector3(35, 0, 10)
			p["LowerArm.R"] = Vector3(115 + a * 8, 0, 0)
			p["Head"] = Vector3(4, 0, 9)
		_:  # manos que acompañan lo que dice
			p["UpperArm.R"] = Vector3(28 + maxf(a, 0.0) * 22, 0, 12)
			p["LowerArm.R"] = Vector3(55 + a * 20, 0, 0)
			p["UpperArm.L"] = Vector3(18 + maxf(b, 0.0) * 18, 0, 10)
			p["LowerArm.L"] = Vector3(45 + b * 15, 0, 0)
			p["Head"] = Vector3(a * 4, b * 5, 0)
	return p


# --- Mirar a alguien ------------------------------------------------------------------

func _apply_look(p: Dictionary) -> void:
	var yaw := sin(_t * 0.25) * 25.0 * (1.0 - clampf(speed, 0.0, 1.0))  # mira alrededor en reposo
	var pitch := 0.0
	if look_at_point != Vector3.INF and _gesture_w < 0.5:
		var head := _sk.global_transform * _sk.get_bone_global_pose(_idx["Head"]).origin
		var to := _sk.global_transform.basis.inverse() * (look_at_point - head)
		var flat := to - _down * to.dot(_down)
		if flat.length() > 0.01:
			yaw = clampf(rad_to_deg(_fwd.signed_angle_to(flat, -_down)), -70.0, 70.0)
			pitch = clampf(rad_to_deg(asin(clampf(to.normalized().dot(_down), -1.0, 1.0))), -25.0, 25.0)
	_add(p, "Neck", Vector3(pitch * 0.4, yaw * 0.4, 0))
	_add(p, "Head", Vector3(pitch * 0.6, yaw * 0.6, 0))


# --- Aplicar la pose al esqueleto -----------------------------------------------------

func _apply() -> void:
	for b in BONES:
		var e: Vector3 = _pose[b]
		var i: int = _idx[b]
		if e == Vector3.ZERO:
			_sk.set_bone_pose_rotation(i, _base[b])
			continue
		var limb: bool = not (b in SPINE)
		var pitch := deg_to_rad(e.x) * (1.0 if limb else -1.0)  # en la columna, + es inclinarse
		var out := deg_to_rad(e.z) * _out_sign * (-1.0 if b.ends_with(".L") else 1.0)
		var q := Quaternion(-_down, deg_to_rad(e.y)) * Quaternion(_fwd, out) * Quaternion(_pitch_axis, pitch)
		var parent: int = _parent_of[b]
		var pq := _sk.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion() if parent >= 0 else Quaternion()
		_sk.set_bone_pose_rotation(i, (pq.inverse() * q * pq) * _base[b])
	if _model:
		var lie: float = _pose["_lie"]
		var swim: float = _pose["_swim"]
		# Tumbarse (boca arriba) o nadar (boca abajo) gira todo el modelo sobre los pies
		_model.position = _model_pos + Vector3(0, _pose["_y"] + lie * 0.25, 0)
		_model.rotation = _model_rot + Vector3(-PI / 2 * lie + PI / 2 * 0.85 * swim, 0, 0)


# --- Herramientas ---------------------------------------------------------------------

func _set_tool(g: String) -> void:
	if _tool:
		_tool.queue_free()
		_tool = null
	if not TOOLS.has(g) or not is_inside_tree():
		return
	if _hand_attach == null:
		_hand_attach = BoneAttachment3D.new()
		_hand_attach.bone_name = "Hand.R"
		_sk.add_child(_hand_attach)
	var spec: Array = TOOLS[g]
	var model: Node3D = null
	var b := AABB(Vector3(-0.025, -0.5, -0.025), Vector3(0.05, 1.0, 0.05))
	if not str(spec[0]).is_empty():
		var parts := str(spec[0]).split("/")
		model = AssetLibrary.instance(parts[0], parts[1])
		if model:
			b = AssetLibrary.bounds(model)
	if model == null:  # caña o herramienta sin modelo: una vara
		model = MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.01
		rod.bottom_radius = 0.025
		rod.height = 1.0
		(model as MeshInstance3D).mesh = rod
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#6b4a2b")
		(model as MeshInstance3D).material_override = m
	_tool = Node3D.new()
	_hand_attach.add_child(_tool)
	var holder := Node3D.new()
	_tool.add_child(holder)
	var s: float = float(spec[1]) / maxf(maxf(b.size.x, b.size.y), maxf(b.size.z, 0.01))  # por su lado más largo
	model.scale = Vector3.ONE * s
	model.position = -b.get_center() * s
	holder.add_child(model)
	holder.rotation_degrees = spec[2]
	# Contrarrestar la escala del esqueleto (el armature viene escalado ~100x) para que la
	# herramienta mida lo que debe. El esqueleto ya está en el árbol; el BoneAttachment aún no.
	_tool.scale = Vector3.ONE / maxf(_sk.global_basis.get_scale().x, 0.0001)


# --- Utilidades -----------------------------------------------------------------------

func _empty() -> Dictionary:
	var p := {}
	for b in BONES:
		p[b] = Vector3.ZERO
	p["_y"] = 0.0
	p["_lie"] = 0.0
	p["_swim"] = 0.0
	return p


func _add(p: Dictionary, bone: String, v: Vector3) -> void:
	p[bone] = p[bone] + v


func _mix(into: Dictionary, other: Dictionary, w: float) -> void:
	for k in other:
		into[k] = lerp(into[k], other[k], w)


func _both_arms(p: Dictionary, upper: Vector3, lower: Vector3) -> void:
	p["UpperArm.L"] = upper
	p["UpperArm.R"] = upper
	p["LowerArm.L"] = lower
	p["LowerArm.R"] = lower


func _legs_apart(p: Dictionary, deg: float) -> void:
	p["UpperLeg.L"] = Vector3(0, 0, deg)
	p["UpperLeg.R"] = Vector3(0, 0, deg)


func _crouch(p: Dictionary) -> void:
	p["_y"] = -0.55
	p["UpperLeg.L"] = Vector3(95, 0, 10)
	p["UpperLeg.R"] = Vector3(85, 0, 10)
	p["LowerLeg.L"] = Vector3(-125, 0, 0)
	p["LowerLeg.R"] = Vector3(-120, 0, 0)
	p["Foot.L"] = Vector3(30, 0, 0)
	p["Foot.R"] = Vector3(30, 0, 0)
	p["Torso"] = Vector3(30, 0, 0)


func _kneel(p: Dictionary, depth: float) -> void:
	p["_y"] = -depth
	p["UpperLeg.L"] = Vector3(90, 0, 6)
	p["LowerLeg.L"] = Vector3(-90, 0, 0)
	p["UpperLeg.R"] = Vector3(0, 0, 6)
	p["LowerLeg.R"] = Vector3(-95, 0, 0)
	p["Foot.R"] = Vector3(40, 0, 0)


## Orienta un hueso para que apunte hacia `dir` (en espacio del esqueleto).
func _aim(bone: String, child: String, dir: Vector3) -> void:
	var i: int = _idx[bone]
	var g := _sk.get_bone_global_pose(i)
	var cur := (_sk.get_bone_global_pose(_idx[child]).origin - g.origin).normalized()
	var new_basis := Basis(Quaternion(cur, dir)) * g.basis.orthonormalized()
	var parent := _sk.get_bone_parent(i)
	var pg := _sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	_sk.set_bone_pose_rotation(i, (pg.inverse() * new_basis).get_rotation_quaternion())


## Transformación del esqueleto relativa al padre del modelo (el armature viene rotado y escalado).
func _skeleton_to_model(model: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = _sk
	while n != null and n != model.get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

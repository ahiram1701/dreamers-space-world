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
const LOOPING := ["chop", "hammer", "dig", "search", "fish", "dance", "sleep", "sit", "crouch", "row", "swim", "think", "cross_arms",
	"kneel", "write", "read", "listen", "call", "hug", "wipe", "cook", "sit_eat", "sit_read"]

## Cada vez que un pie toca el suelo al andar o correr (para el sonido de los pasos).
signal footstep(running: bool)
## Herramienta en la mano derecha durante el gesto: [modelo, largo en m, dónde la agarra la mano
## derecha y dónde la izquierda (fracción del largo desde el extremo del mango; < 0: una sola mano)].
## La dirección de la herramienta es la del antebrazo girada "_tool" grados (lo marca cada gesto):
## la muñeca se dobla al levantar el hacha y se estira al golpear.
const TOOLS := {
	"chop": ["survival_pack/Axe", 0.75, 0.2, 0.05], "dig": ["survival_pack/Shovel", 1.1, 0.04, 0.42],
	"hammer": ["survival_pack/Axe_Small", 0.38, 0.22, -1.0], "fish": ["", 1.8, 0.08, 0.24],
	"drink": ["survival_pack/WaterBottle_1", 0.22, 0.45, -1.0], "row": ["survival_pack/Raft_Paddle", 1.4, 0.12, 0.45],
	"call": ["survival_pack/Phone", 0.14, 0.5, -1.0], "read": ["survival_pack/Phone", 0.14, 0.5, -1.0],
	"sit_read": ["survival_pack/Phone", 0.14, 0.5, -1.0],
}
const TOOL_ANGLE := {"sit_read": 10.0, "chop": 60.0, "dig": -35.0, "hammer": 70.0, "fish": 80.0, "drink": -90.0, "row": -70.0, "call": -15.0, "read": 10.0}
const FINGERS := ["Index2", "Index3", "Index4", "Middle2", "Middle3", "Middle4", "Ring2", "Ring3", "Ring4",
	"Pinky2", "Pinky3", "Pinky4", "Thumb2", "Thumb3"]
const PALM := 0.075   # de la muñeca al centro de la palma (m)
static var _shapes := {}   # análisis de la forma de cada modelo de herramienta (mango, cabeza)
## Si los dedos se cierran hacia la palma con el signo + (se decide al cargar, ver _finger_sign)
static var finger_sign := 1.0

var speed := 0.0
var airborne := false
var swimming := false
var talking := false
var emotion := "neutral"
## Punto del mundo al que mira la cabeza (Vector3.INF: mira alrededor).
var look_at_point := Vector3.INF
## Animar siempre a pleno ritmo (el jugador). El resto, según la distancia y si se ve.
var full_rate := false
## Cómo se dobla el codo al andar y correr (x: flexión hacia delante, y: hacia dentro). Los gestos
## (sujetar el celular, beber…) usan GESTURE_ELBOW, que junta las manos delante del cuerpo.
static var loco_elbow := Vector2(1.0, 0.0)
const GESTURE_ELBOW := Vector2(0.3, 1.0)
var _bend := {"LowerArm.L": 0.0, "LowerArm.R": 0.0}   # cuánto del codo viene de un gesto (0..1)
const LOD_NEAR := 35.0   # más lejos (o fuera de cámara): una de cada 4 frames
const LOD_FAR := 70.0    # más lejos aún: quieto
var _skip := 0
var _acc := 0.0

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
var _tool_shape := {}
var _grip := 0.0      # fracción del mango donde agarra la derecha
var _second := -1.0   # y la izquierda (< 0: no la usa)
var _tool_len := 0.0
var _fingers := {}    # hueso del dedo -> [índice, rotación base]
var _grip_w := 0.0    # cuánto se cierra el puño
## Algo que lleva en la mano todo el rato (la linterna), aparte de las herramientas de los gestos.
var _held: Node3D
var _held_shape := {}
var _held_len := 0.0
var _held_grip := 0.0
var _held_w := 0.0    # cuánto pesa la pose de sujetarlo (0 mientras un gesto usa la mano)


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
	for side in [".L", ".R"]:
		for f in FINGERS:
			var fi := _sk.find_bone(f + side)
			if fi != -1:
				_fingers[f + side] = [fi, _sk.get_bone_pose_rotation(fi)]
	_pose["_y"] = 0.0
	_pose["_lie"] = 0.0
	_pose["_swim"] = 0.0
	_pose["_tool"] = 0.0
	_phase = randf() * TAU
	_t = randf() * 10.0
	return true


## Empieza un gesto. duration < 0: el de por defecto (los de bucle duran hasta stop_gesture()).
## with_tool: false si no tiene con qué (lo hace con las manos vacías).
func play(gesture: String, duration: float = -1.0, with_tool: bool = true) -> void:
	if _sk == null or gesture.is_empty():
		return
	_gesture = gesture
	_gesture_t = 0.0
	_gesture_len = duration if duration > 0.0 else (INF if gesture in LOOPING else 2.2)
	_set_tool(gesture if with_tool else "")


func stop_gesture() -> void:
	_gesture_len = minf(_gesture_len, _gesture_t)  # sale con la mezcla


func gesture() -> String:
	return _gesture if _gesture_w > 0.01 else ""


func _process(delta: float) -> void:
	if _sk == null:
		return
	if not full_rate:  # nivel de detalle: lejos o fuera de la vista, menos trabajo
		var cam := get_viewport().get_camera_3d()
		if cam:
			var at := _sk.global_position
			var d := cam.global_position.distance_to(at)
			if d > LOD_FAR:
				return
			if d > LOD_NEAR or not cam.is_position_in_frustum(at + Vector3(0, 1, 0)):
				_acc += delta
				_skip = (_skip + 1) % 4
				if _skip != 0:
					return
				delta = _acc
		_acc = 0.0
	_t += delta
	var target := _locomotion(delta)
	var hand_busy := _tool != null and _gesture_w > 0.05
	_held_w = move_toward(_held_w, 1.0 if (_held and not hand_busy) else 0.0, delta * 5.0)
	if _held_w > 0.0:  # el brazo derecho adelante, alumbrando (el braceo de andar se nota menos)
		target["UpperArm.R"] = target["UpperArm.R"].lerp(Vector3(38, 0, 6), 0.8 * _held_w)
		target["LowerArm.R"] = target["LowerArm.R"].lerp(Vector3(62, 0, 0), 0.8 * _held_w)
		target["Hand.R"] = target["Hand.R"].lerp(Vector3(-8, 0, 0), _held_w)
	for k in _bend:  # el peso de los gestos en el codo se desvanece si ya no lo usan
		_bend[k] = move_toward(_bend[k], 0.0, delta * 4.0)
	# Capa de gesto
	if not _gesture.is_empty():
		_gesture_t += delta
		var active := _gesture_t < _gesture_len
		_gesture_w = move_toward(_gesture_w, 1.0 if active else 0.0, delta / BLEND)
		if _gesture_w <= 0.0 and not active:
			_gesture = ""
			_set_tool("")
		else:
			var gp := _gesture_pose(_gesture, _gesture_t)
			if not gp.has("_tool"):
				gp["_tool"] = TOOL_ANGLE.get(_gesture, 0.0)
			_mix(target, gp, _gesture_w)
			for k in _bend:
				if gp.has(k):
					_bend[k] = maxf(_bend[k], _gesture_w)
	# Capa de expresión al hablar (más suave si ya hay un gesto)
	if talking and _gesture_w < 0.5:
		var tp := _talk_pose()
		_mix(target, tp, 1.0 - _gesture_w * 2.0)
		for k in _bend:
			if tp.has(k):
				_bend[k] = maxf(_bend[k], 1.0 - _gesture_w * 2.0)
	_apply_look(target)
	# Suavizado: nada salta de una pose a otra
	var k := 1.0 - exp(-14.0 * delta)
	for key in target:
		_pose[key] = lerp(_pose.get(key, target[key] * 0.0), target[key], k)
	_apply()
	_grip_w = move_toward(_grip_w, maxf(_gesture_w if _tool else 0.0, _held_w), delta * 5.0)
	_hand_to_face()
	if _tool:
		_place_tool()
	if _held:
		_held.visible = _held_w > 0.3
		if _held.visible:
			_place_item(_held, _held_shape, _held_len, _held_grip, -6.0)
	_curl_fingers()


# --- Capa 1: locomoción --------------------------------------------------------------

func _locomotion(delta: float) -> Dictionary:
	var p := _empty()
	var walk := clampf(speed / 4.0, 0.0, 1.0)
	var run := clampf((speed - 4.8) / 3.0, 0.0, 1.0)
	var before := sin(_phase)
	_phase += delta * (1.8 + speed * 1.45)
	if walk > 0.3 and not swimming and not airborne and signf(sin(_phase)) != signf(before):
		footstep.emit(speed > 5.0)
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
			p["_tool"] = 20.0 + up * 85.0   # arriba, la muñeca doblada; al golpear, el hacha sigue al brazo
			p["Torso"] = Vector3(25 - up * 30, 15 - up * 15, 0)
			p["Chest"] = Vector3(8, 0, 0)
			_legs_apart(p, 12)
			p["LowerLeg.L"] = Vector3(-15, 0, 0)
			p["LowerLeg.R"] = Vector3(-15, 0, 0)
		"hammer":
			var hit := absf(sin(t * 5.0))
			p["UpperArm.R"] = Vector3(55 + hit * 35, 0, 5)
			p["LowerArm.R"] = Vector3(60 - hit * 30, 0, 0)
			p["_tool"] = 45.0 + hit * 40.0
			p["UpperArm.L"] = Vector3(45, 0, -5)
			p["LowerArm.L"] = Vector3(55, 0, 0)
			_kneel(p, 0.55)
			p["Torso"] = Vector3(30, 0, 0)
		"dig":
			var cyc := sin(t * 2.4)
			_both_arms(p, Vector3(55 + cyc * 25, 0, -5), Vector3(30 - cyc * 15, 0, 0))
			p["_tool"] = -35.0 - cyc * 10.0
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
		"sit", "row", "sit_eat", "sit_read":
			p["_y"] = -0.48
			p["UpperLeg.L"] = Vector3(88, 0, 6)
			p["UpperLeg.R"] = Vector3(88, 0, 6)
			p["LowerLeg.L"] = Vector3(-88, 0, 0)
			p["LowerLeg.R"] = Vector3(-88, 0, 0)
			p["UpperArm.L"] = Vector3(25, 0, 6)
			p["UpperArm.R"] = Vector3(25, 0, 6)
			p["LowerArm.L"] = Vector3(40, 0, 0)
			p["LowerArm.R"] = Vector3(40, 0, 0)
			if g == "sit_eat":  # come a la mesa: la mano va del plato a la boca
				var lift := 0.5 + 0.5 * sin(t * 1.4)
				p["UpperArm.R"] = Vector3(30 + lift * 20, 0, 10)
				p["LowerArm.R"] = Vector3(70 + lift * 55, 0, 0)
				p["UpperArm.L"] = Vector3(35, 0, 8)
				p["LowerArm.L"] = Vector3(60, 0, 0)
				p["Head"] = Vector3(12 - 8 * lift, 0, 0)
			elif g == "sit_read":
				p["UpperArm.R"] = Vector3(30, 0, 8)
				p["LowerArm.R"] = Vector3(80, 0, 0)
				p["UpperArm.L"] = Vector3(30, 0, 8)
				p["LowerArm.L"] = Vector3(80, 0, 0)
				p["Head"] = Vector3(25, 0, 0)
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
			p["_tool"] = -90.0 + lift * 60.0   # la botella se inclina al beber
			p["Head"] = Vector3(-10 * lift, 0, 0)
		"wave":
			p["UpperArm.R"] = Vector3(20, 0, 145)
			p["LowerArm.R"] = Vector3(25, 0, sin(t * 9.0) * 25)
			p["Head"] = Vector3(-5, 0, 6)
		"knock":  # nudillos contra la puerta: tres golpes
			var tap := maxf(0.0, sin(t * 14.0)) * (1.0 - smoothstep(0.9, 1.2, t))
			p["UpperArm.R"] = Vector3(70, 0, 10)
			p["LowerArm.R"] = Vector3(95 - 30 * tap, 0, 0)
			p["Head"] = Vector3(4, 0, 0)
		"climb":  # trepar: brazos arriba por turnos y las piernas buscando apoyo
			var c := sin(t * 5.0)
			p["UpperArm.L"] = Vector3(150 + 15 * c, 0, -8)
			p["UpperArm.R"] = Vector3(150 - 15 * c, 0, 8)
			p["LowerArm.L"] = Vector3(25 - 20 * c, 0, 0)
			p["LowerArm.R"] = Vector3(25 + 20 * c, 0, 0)
			p["UpperLeg.L"] = Vector3(maxf(0.0, c) * 45, 0, 4)
			p["UpperLeg.R"] = Vector3(maxf(0.0, -c) * 45, 0, 4)
			p["LowerLeg.L"] = Vector3(-maxf(0.0, c) * 70, 0, 0)
			p["LowerLeg.R"] = Vector3(-maxf(0.0, -c) * 70, 0, 0)
			p["Head"] = Vector3(-15, 0, 0)
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
		"yawn":  # se estira: brazos arriba y la cabeza hacia atrás
			var s := sin(clampf(t / 1.6, 0.0, 1.0) * PI)
			_both_arms(p, Vector3(20 + 130 * s, 0, 15 * s), Vector3(30 * s, 0, 0))
			p["Head"] = Vector3(-18 * s, 0, 0)
			p["Chest"] = Vector3(-6 * s, 0, 0)
		"nod":
			p["Head"] = Vector3(sin(t * 7.0) * 14 * (1.0 - clampf(t / 2.0, 0.0, 1.0)), 0, 0)
		"shake_head":
			p["Head"] = Vector3(0, sin(t * 7.0) * 22 * (1.0 - clampf(t / 2.0, 0.0, 1.0)), 0)
		"punch":  # carga atrás y golpe recto con la derecha
			var wind := smoothstep(0.0, 0.3, t) - smoothstep(0.3, 0.42, t)
			var hit := smoothstep(0.3, 0.42, t) - smoothstep(0.75, 1.1, t)
			p["UpperArm.R"] = Vector3(-15 * wind + 85 * hit, 0, 10 + 15 * wind)
			p["LowerArm.R"] = Vector3(115 * wind + 10 * hit + 60 * (1.0 - wind - hit), 0, 0)
			p["UpperArm.L"] = Vector3(55, 0, 8)
			p["LowerArm.L"] = Vector3(100, 0, 0)
			p["Torso"] = Vector3(6 + 8 * hit, 22 * wind - 28 * hit, 0)
			p["Hips"] = Vector3(0, 10 * wind - 12 * hit, 0)
			_legs_apart(p, 10)
			p["UpperLeg.L"] = Vector3(18, 0, 6)
			p["LowerLeg.L"] = Vector3(-20, 0, 0)
		"push":
			var shove := smoothstep(0.1, 0.4, t) - smoothstep(0.8, 1.2, t)
			_both_arms(p, Vector3(30 + 55 * shove, 0, 8), Vector3(80 - 70 * shove, 0, 0))
			p["Torso"] = Vector3(4 + 16 * shove, 0, 0)
			p["UpperLeg.L"] = Vector3(22 * shove, 0, 6)
			p["LowerLeg.L"] = Vector3(-18 * shove, 0, 0)
		"kick":
			var lift := smoothstep(0.0, 0.3, t) - smoothstep(0.7, 1.1, t)
			var snap := smoothstep(0.3, 0.45, t) - smoothstep(0.7, 1.1, t)
			p["UpperLeg.R"] = Vector3(20 * lift + 55 * snap, 0, 4)
			p["LowerLeg.R"] = Vector3(-90 * (lift - snap) - 10, 0, 0)
			p["UpperLeg.L"] = Vector3(0, 0, -4)
			p["LowerLeg.L"] = Vector3(-12, 0, 0)
			_both_arms(p, Vector3(20, 0, 35), Vector3(40, 0, 0))
			p["Torso"] = Vector3(-10 * lift, 0, 0)
		"hug":
			var close_in := smoothstep(0.0, 0.7, t)
			_both_arms(p, Vector3(70 * close_in, -25 * close_in, 18), Vector3(70 * close_in, 0, 0))
			p["Torso"] = Vector3(10 * close_in, 0, 0)
			p["Head"] = Vector3(8, 20 * close_in, 0)
		"handshake":
			var reach := smoothstep(0.0, 0.5, t)
			p["UpperArm.R"] = Vector3(45 * reach + sin(t * 11.0) * 6 * reach, 0, 6)
			p["LowerArm.R"] = Vector3(35, 0, 0)
			p["Torso"] = Vector3(8 * reach, 0, 0)
			p["Head"] = Vector3(-4, 0, 0)
		"throw":
			var back := smoothstep(0.0, 0.45, t) - smoothstep(0.45, 0.6, t)
			var fly := smoothstep(0.45, 0.6, t) - smoothstep(1.0, 1.5, t)
			p["UpperArm.R"] = Vector3(150 * back + 80 * fly, 0, 15)
			p["LowerArm.R"] = Vector3(70 * back + 10 * fly, 0, 0)
			p["UpperArm.L"] = Vector3(60 * back, 0, 10)
			p["Torso"] = Vector3(-8 * back + 18 * fly, 25 * back - 20 * fly, 0)
			_legs_apart(p, 12)
		"pat":
			p["UpperArm.R"] = Vector3(85, -10, 8)
			p["LowerArm.R"] = Vector3(25 + absf(sin(t * 8.0)) * 18, 0, 0)
			p["Head"] = Vector3(6, 0, 0)
		"kneel":
			_kneel(p, 1.0)
			_both_arms(p, Vector3(35, 0, 6), Vector3(40, 0, 0))
			p["Head"] = Vector3(15, 0, 0)
		"write", "read":  # algo en las manos delante del cuerpo (un libro, el celular), mirando hacia abajo
			p["UpperArm.R"] = Vector3(30, 0, 8)
			p["LowerArm.R"] = Vector3(80 + (sin(t * 9.0) * 5 if g == "write" else 0.0), 0, 0)
			p["UpperArm.L"] = Vector3(30, 0, 8)
			p["LowerArm.L"] = Vector3(80, 0, 0)
			p["Head"] = Vector3(28, 0, 0)
		"wipe":  # limpiar una barra o una mesa: la mano en círculos
			var c := t * 3.0
			p["UpperArm.R"] = Vector3(45 + sin(c) * 8, 0, 10 + cos(c) * 10)
			p["LowerArm.R"] = Vector3(55, 0, 0)
			p["UpperArm.L"] = Vector3(30, 0, 8)
			p["LowerArm.L"] = Vector3(50, 0, 0)
			p["Torso"] = Vector3(14, 0, 0)
			p["Head"] = Vector3(18, 0, 0)
		"cook":  # delante del fogón: remueve con una mano y sujeta con la otra
			p["UpperArm.R"] = Vector3(38, 0, 10 + sin(t * 4.0) * 6)
			p["LowerArm.R"] = Vector3(75 + sin(t * 4.0) * 10, 0, 0)
			p["UpperArm.L"] = Vector3(32, 0, 6)
			p["LowerArm.L"] = Vector3(80, 0, 0)
			p["Torso"] = Vector3(8, 0, 0)
			p["Head"] = Vector3(24, sin(t * 0.6) * 10, 0)
		"listen", "call":  # una radio o un teléfono junto a la oreja
			p["UpperArm.R"] = Vector3(25, 0, 62)
			p["LowerArm.R"] = Vector3(140, 0, 0)
			p["Hand.R"] = Vector3(0, 0, 20)
			p["Head"] = Vector3(4, -6, 10 + sin(t * 0.8) * 3)
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
		if b.begins_with("LowerArm"):
			# El codo: al andar se dobla hacia delante; en los gestos, además hacia dentro (las manos
			# se juntan delante del cuerpo). Se mezcla según cuánto pesa el gesto ahora.
			var m: Vector2 = loco_elbow.lerp(GESTURE_ELBOW, _bend[b])
			e = Vector3(e.x * m.x, e.y, e.z - e.x * m.y)
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
	if not TOOLS.has(g) or not is_inside_tree() or _model == null:
		return
	var spec: Array = TOOLS[g]
	var model: Node3D = null
	if not str(spec[0]).is_empty():
		var parts := str(spec[0]).split("/")
		model = AssetLibrary.instance(parts[0], parts[1])
	if model == null:  # caña o herramienta sin modelo: una vara
		model = MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.008
		rod.bottom_radius = 0.022
		rod.height = 1.0
		(model as MeshInstance3D).mesh = rod
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#6b4a2b")
		(model as MeshInstance3D).material_override = m
	_tool_shape = _shape_of(str(spec[0]), model)
	_tool_len = float(spec[1])
	_grip = float(spec[2])
	_second = float(spec[3])
	# Fuera de la jerarquía de huesos: se coloca cada frame según el antebrazo (ver _place_tool)
	_tool = model
	_tool.top_level = true
	_model.add_child(_tool)
	_place_tool()


## Pone la herramienta en la palma derecha, en la dirección del antebrazo girada "_tool" grados,
## con la cabeza (filo, pala) hacia donde va el golpe. Si es de dos manos, la izquierda va al mango.
func _place_tool() -> void:
	var palm_w := _place_item(_tool, _tool_shape, _tool_len, _grip, float(_pose.get("_tool", 0.0)))
	if _second >= 0.0 and _gesture_w > 0.01:
		var d_w: Vector3 = _last_aim
		var hold_w := palm_w + d_w * (_second - _grip) * _tool_len
		_reach("UpperArm.L", "LowerArm.L", "Hand.L", _sk.global_transform.affine_inverse() * hold_w, _gesture_w)


var _last_aim := Vector3.FORWARD   # dirección de lo último que se colocó en la mano (mundo)


## Coloca un objeto en la palma derecha: su mango en la mano, apuntando en la dirección del
## antebrazo girada `angle` grados. Devuelve dónde está la palma (mundo).
func _place_item(item: Node3D, sh: Dictionary, length: float, grip: float, angle: float) -> Vector3:
	var to_world := _sk.global_transform
	var elbow := _sk.get_bone_global_pose(_idx["LowerArm.R"]).origin
	var wrist := _sk.get_bone_global_pose(_idx["Hand.R"]).origin
	var fore := (wrist - elbow).normalized()
	var aim := Quaternion(_pitch_axis, deg_to_rad(angle)) * fore
	var lead := Quaternion(_pitch_axis, -PI / 2) * aim   # hacia donde avanza el golpe
	var d_w := (to_world.basis * aim).normalized()
	var h_w := (to_world.basis * lead).normalized()
	h_w = (h_w - d_w * h_w.dot(d_w)).normalized()
	var palm_w := to_world * wrist + (to_world.basis * fore).normalized() * PALM
	var local_b := Basis(sh.long, sh.head, sh.long.cross(sh.head))
	var world_b := Basis(d_w, h_w, d_w.cross(h_w))
	var rot := world_b * local_b.inverse()
	var s: float = length / sh.length
	var grip_local: Vector3 = sh.start + sh.long * sh.length * grip
	item.global_transform = Transform3D(rot * Basis.from_scale(Vector3.ONE * s), palm_w - rot * (grip_local * s))
	_last_aim = d_w
	return palm_w


## Llevar algo en la mano todo el rato ("" para soltarlo). model: "pack/Modelo".
func set_held(model: String, length: float = 0.24, grip: float = 0.3) -> void:
	if _held:
		_held.queue_free()
		_held = null
	if model.is_empty() or _model == null or _sk == null:
		return
	var parts := model.split("/")
	var node := AssetLibrary.instance(parts[0], parts[1])
	if node == null:
		return
	_held_shape = _shape_of(model, node)
	_held_len = length
	_held_grip = grip
	_held = node
	_held.top_level = true
	_model.add_child(_held)


## Punta de lo que lleva en la mano (para la luz de la linterna): origen y hacia dónde apunta.
func held_tip() -> Transform3D:
	if _held == null or not _held.visible:
		return Transform3D(Basis(), Vector3.INF)
	var wrist := _sk.global_transform * _sk.get_bone_global_pose(_idx["Hand.R"]).origin
	var tip := wrist + _last_held_aim() * (_held_len * (1.0 - _held_grip) + PALM)
	return Transform3D(Basis.looking_at(_last_held_aim(), Vector3.UP), tip)


func _last_held_aim() -> Vector3:
	var elbow := _sk.get_bone_global_pose(_idx["LowerArm.R"]).origin
	var wrist := _sk.get_bone_global_pose(_idx["Hand.R"]).origin
	var fore := Quaternion(_pitch_axis, deg_to_rad(-6.0)) * (wrist - elbow).normalized()
	return (_sk.global_transform.basis * fore).normalized()


## Beber y hablar por teléfono: la mano derecha va de verdad a la boca o a la oreja.
func _hand_to_face() -> void:
	if _gesture_w <= 0.01 or not (_gesture in ["drink", "eat", "call", "listen", "sit_eat"]):
		return
	var head := _sk.get_bone_global_pose(_idx["Head"]).origin
	var neck := _sk.get_bone_global_pose(_idx["Neck"]).origin
	var up := (head - neck).normalized()
	var unit := 1.0 / maxf(_sk.global_basis.get_scale().y, 0.0001)   # 1 m en unidades del esqueleto
	var target: Vector3
	if _gesture in ["call", "listen"]:
		target = head + up * 0.06 * unit + _side * 0.11 * unit
	else:
		var lift := 0.6 + 0.4 * sin(_gesture_t * 1.6)   # acerca y aleja la botella
		target = head + up * 0.02 * unit + _fwd * (0.16 + 0.12 * (1.0 - lift)) * unit + _side * 0.03 * unit - up * 0.12 * (1.0 - lift) * unit
	_reach("UpperArm.R", "LowerArm.R", "Hand.R", target, _gesture_w)


## IK de dos huesos: lleva la palma de la mano a `target` (espacio del esqueleto), con el codo hacia
## fuera y abajo. `w`: cuánto (se mezcla con la pose que ya tiene).
func _reach(upper: String, lower: String, hand: String, target: Vector3, w: float) -> void:
	var s := _sk.get_bone_global_pose(_idx[upper]).origin
	var e := _sk.get_bone_global_pose(_idx[lower]).origin
	var h := _sk.get_bone_global_pose(_idx[hand]).origin
	var l1 := s.distance_to(e)
	var palm := PALM / maxf(_sk.global_basis.get_scale().y, 0.0001)
	var l2 := e.distance_to(h) + palm
	var to := target - s
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to.normalized()
	var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var lift := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var out := -_side if upper.ends_with(".L") else _side
	var pole := (out + _down * 0.6 - _fwd * 0.3)
	pole = (pole - dir * pole.dot(dir)).normalized()
	var elbow := s + dir * a + pole * lift
	_aim(upper, lower, (elbow - s).normalized(), w)
	_aim(lower, hand, (s + dir * d - elbow).normalized(), w)


## Cierra los dedos alrededor de lo que lleva en la mano derecha (y en la izquierda si la usa).
func _curl_fingers() -> void:
	if _fingers.is_empty():
		return
	for key in _fingers:
		var both := _second >= 0.0
		var w := _grip_w if (key.ends_with(".R") or both) else 0.0
		var fi: int = _fingers[key][0]
		if w <= 0.001:
			_sk.set_bone_pose_rotation(fi, _fingers[key][1])
			continue
		var thumb: bool = key.begins_with("Thumb")
		var deg := (35.0 if thumb else 75.0) * w * finger_sign
		var pg := _sk.get_bone_global_pose(_sk.get_bone_parent(fi)).basis.orthonormalized().get_rotation_quaternion()
		var hand_side := ".L" if key.ends_with(".L") else ".R"
		var across := (_sk.get_bone_global_pose(_sk.find_bone("Index2" + hand_side)).origin
			- _sk.get_bone_global_pose(_sk.find_bone("Pinky2" + hand_side)).origin).normalized()
		var axis := across if not thumb else (_sk.get_bone_global_pose(_idx["Hand" + hand_side]).origin
			- _sk.get_bone_global_pose(_idx["LowerArm" + hand_side]).origin).normalized()
		if hand_side == ".L":
			axis = -axis
		var q := Quaternion(axis, deg_to_rad(deg))
		_sk.set_bone_pose_rotation(fi, (pg.inverse() * q * pg) * _fingers[key][1])


## Forma de una herramienta (en espacio del modelo): eje largo del mango a la cabeza, hacia qué
## lado sale la cabeza, dónde empieza el mango y el largo. El mango es el extremo más fino.
static func _shape_of(key: String, model: Node3D) -> Dictionary:
	if _shapes.has(key) and not key.is_empty():
		return _shapes[key]
	var pts := PackedVector3Array()
	var meshes: Array = [model] if model is MeshInstance3D else AssetLibrary._meshes(model)
	for mi in meshes:
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != model and n != null:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		if mi == model:
			t = Transform3D.IDENTITY
		for v in (mi as MeshInstance3D).mesh.get_faces():
			pts.append(t * v)
	var box := AABB(pts[0], Vector3.ZERO)
	for v in pts:
		box = box.expand(v)
	var ax := box.get_longest_axis_index()
	var axis := Vector3.ZERO
	axis[ax] = 1.0
	var length: float = box.size[ax]
	var lo := box.position[ax]
	var hi := lo + length
	# Lo que hay en cada punta (15 % del largo): centro y grosor
	var ends := [[Vector3.ZERO, 0, AABB()], [Vector3.ZERO, 0, AABB()]]
	for v in pts:
		var which := 0 if v[ax] < lo + length * 0.15 else (1 if v[ax] > hi - length * 0.15 else -1)
		if which < 0:
			continue
		var e: Array = ends[which]
		e[2] = AABB(v, Vector3.ZERO) if e[1] == 0 else (e[2] as AABB).expand(v)
		e[0] += v
		e[1] += 1
	var thick := func(e: Array) -> float:
		var sz: Vector3 = (e[2] as AABB).size
		sz[ax] = 0.0
		return sz.length()
	var handle_lo: bool = thick.call(ends[0]) <= thick.call(ends[1])
	var hc: Vector3 = ends[0 if handle_lo else 1][0] / maxf(ends[0 if handle_lo else 1][1], 1)
	var kc: Vector3 = ends[1 if handle_lo else 0][0] / maxf(ends[1 if handle_lo else 0][1], 1)
	var long := axis if handle_lo else -axis
	var head := kc - hc
	head -= long * head.dot(long)
	if head.length() < length * 0.02:  # simétrica (botella, celular): cualquier lado perpendicular
		head = Vector3(1, 0, 0) if ax != 0 else Vector3(0, 1, 0)
	head = head.normalized()
	var start := hc
	start[ax] = lo if handle_lo else hi
	var out := {"long": long, "head": head, "start": start, "length": maxf(length, 0.001)}
	if not key.is_empty():
		_shapes[key] = out
	return out


# --- Utilidades -----------------------------------------------------------------------

func _empty() -> Dictionary:
	var p := {}
	for b in BONES:
		p[b] = Vector3.ZERO
	p["_tool"] = 0.0
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


## Orienta un hueso para que apunte hacia `dir` (en espacio del esqueleto); `w` < 1: solo en parte.
func _aim(bone: String, child: String, dir: Vector3, w: float = 1.0) -> void:
	var i: int = _idx[bone]
	var g := _sk.get_bone_global_pose(i)
	var cur := (_sk.get_bone_global_pose(_idx[child]).origin - g.origin).normalized()
	if w < 1.0:
		dir = cur.slerp(dir.normalized(), clampf(w, 0.0, 1.0))
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

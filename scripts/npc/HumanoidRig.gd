class_name HumanoidRig
extends Node
## Anima por código el esqueleto de los personajes Quaternius (las copias GLB vienen sin
## animaciones): baja los brazos de la pose en T y añade respirar, caminar y gesticular.
## No depende de nombres de animación, así que sirve para todos los trajes.
##
## Uso:  var rig := HumanoidRig.new(); model.add_child(rig); rig.setup(model)
##       rig.speed = velocidad horizontal (m/s); rig.talking = true mientras habla.

var speed := 0.0
var talking := false

var _sk: Skeleton3D
var _idx := {}
var _base := {}     # hueso → rotación local en reposo (ya con los brazos bajados)
var _axis := {}     # hueso → eje lateral del cuerpo en el espacio de su padre
var _side := Vector3.RIGHT
var _phase := 0.0
var _t := 0.0
var _model: Node3D
var _model_y := 0.0

const BONES := ["Hips", "Chest", "Neck", "Head", "UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R",
	"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"]


func setup(model: Node3D) -> bool:
	_model = model
	_model_y = model.position.y
	_sk = _find_skeleton(model)
	if _sk == null:
		return false
	for b in BONES:
		_idx[b] = _sk.find_bone(b)
		if _idx[b] == -1:
			_sk = null
			return false
	var down := _down_in_skeleton(model)
	var l := _sk.get_bone_global_pose(_idx["UpperArm.L"]).origin
	var r := _sk.get_bone_global_pose(_idx["UpperArm.R"]).origin
	_side = (r - l).normalized()
	# De la pose en T a brazos relajados, un poco separados del cuerpo
	_aim("UpperArm.L", "LowerArm.L", (down - _side * 0.22).normalized())
	_aim("UpperArm.R", "LowerArm.R", (down + _side * 0.22).normalized())
	for b in BONES:
		var i: int = _idx[b]
		_base[b] = _sk.get_bone_pose_rotation(i)
		var parent := _sk.get_bone_parent(i)
		var p_basis := _sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
		_axis[b] = (p_basis.inverse() * _side).normalized()
	return true


func _process(delta: float) -> void:
	if _sk == null:
		return
	_t += delta
	var walk := clampf(speed / 4.5, 0.0, 1.6)
	_phase += delta * (2.0 + speed * 1.6)
	var s := sin(_phase)
	var legs := 0.55 * walk
	_swing("UpperLeg.L", s * legs)
	_swing("UpperLeg.R", -s * legs)
	_swing("LowerLeg.L", -maxf(0.0, -s) * legs * 1.3)
	_swing("LowerLeg.R", -maxf(0.0, s) * legs * 1.3)
	var arms := 0.45 * walk
	var breath := sin(_t * 1.8) * 0.03
	var gesture := (sin(_t * 3.1) * 0.25 + 0.35) if talking else 0.0
	_swing("UpperArm.L", -s * arms + breath)
	_swing("UpperArm.R", s * arms + breath - gesture * 0.6)
	_swing("LowerArm.L", -0.15 - walk * 0.25)
	_swing("LowerArm.R", -0.15 - walk * 0.25 - gesture)
	_swing("Chest", breath * 0.6)
	_swing("Head", (sin(_t * 2.3) * 0.06) if talking else sin(_t * 0.7) * 0.03)
	# Rebote al andar
	if _model:
		_model.position.y = _model_y + absf(sin(_phase)) * 0.05 * minf(walk, 1.0)


## Gira un hueso sobre el eje lateral del cuerpo (adelante/atrás), desde su pose base.
func _swing(bone: String, angle: float) -> void:
	# Girar sobre el eje lateral no cambia ese eje, así que vale el calculado en reposo
	_sk.set_bone_pose_rotation(_idx[bone], Quaternion(_axis[bone], angle) * _base[bone])


## Orienta un hueso para que apunte hacia `dir` (en espacio del esqueleto).
func _aim(bone: String, child: String, dir: Vector3) -> void:
	var i: int = _idx[bone]
	var g := _sk.get_bone_global_pose(i)
	var cur := (_sk.get_bone_global_pose(_idx[child]).origin - g.origin).normalized()
	var new_basis := Basis(Quaternion(cur, dir)) * g.basis.orthonormalized()
	var parent := _sk.get_bone_parent(i)
	var pg := _sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	_sk.set_bone_pose_rotation(i, (pg.inverse() * new_basis).get_rotation_quaternion())


## "Abajo" del mundo expresado en el espacio del esqueleto (el armature viene rotado y escalado).
func _down_in_skeleton(model: Node3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var n: Node = _sk
	while n != null and n != model.get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return (t.basis.inverse() * Vector3.DOWN).normalized()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

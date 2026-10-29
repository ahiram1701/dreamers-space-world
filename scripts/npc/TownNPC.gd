class_name TownNPC
extends StaticBody3D
## Representación 3D de una entidad "npc" de WorldDB. Se monta con piezas simples
## según appearance (cuerpo, colores); NPCBuilder lo sustituirá por modelos modulares.

const BODY_SCALE := {
	"slim": Vector3(0.85, 1.0, 0.85), "average": Vector3.ONE, "sturdy": Vector3(1.25, 1.0, 1.2),
	"tall": Vector3(0.95, 1.15, 0.95), "short": Vector3(1.0, 0.85, 1.0),
	"elderly": Vector3(0.95, 0.92, 0.95), "child": Vector3(0.7, 0.6, 0.7),
}

var npc_id: String = ""
var _name_label: Label3D
var _hint: Label3D


func setup(entity: Dictionary) -> void:
	npc_id = entity.id
	var look: Dictionary = entity.get("appearance", {})
	var s: Vector3 = BODY_SCALE.get(look.get("body", "average"), Vector3.ONE)

	# La forma de colisión no se escala (Godot no soporta escala no uniforme en física)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5 * maxf(s.x, s.z)
	capsule.height = 2.0 * s.y
	shape.shape = capsule
	shape.position.y = s.y
	add_child(shape)

	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = s.y
	body.scale = s
	body.material_override = _mat(Color(look.get("primary_color", "#888888")))
	add_child(body)
	var band := MeshInstance3D.new()  # segundo color: bufanda/cinturón
	band.mesh = CylinderMesh.new()
	band.mesh.top_radius = 0.52
	band.mesh.bottom_radius = 0.52
	band.mesh.height = 0.18
	band.position.y = 1.35 * s.y
	band.scale = s
	band.material_override = _mat(Color(look.get("secondary_color", "#cccccc")))
	add_child(band)

	_name_label = _label(2.3 * s.y, 48)
	_hint = _label(2.0 * s.y, 32)
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
	var flat := Vector3(target.x, global_position.y, target.z)
	if flat.distance_to(global_position) > 0.1:
		look_at(flat, Vector3.UP, true)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.interact_target = self
		_hint.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body is Player and body.interact_target == self:
		body.interact_target = null
	if body is Player:
		_hint.visible = false


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

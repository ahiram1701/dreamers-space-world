class_name Pickup
extends Node3D
## Un objeto del mundo que se puede recoger (E). Gira y brilla para que se vea de lejos.

var item_id := ""
var _gem: MeshInstance3D
var _name := "objeto"


func setup(entity: Dictionary) -> void:
	item_id = entity.id
	_gem = MeshInstance3D.new()
	_gem.mesh = BoxMesh.new()
	_gem.mesh.size = Vector3.ONE * 0.45
	_gem.rotation_degrees = Vector3(45, 0, 45)
	_gem.position.y = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ffe08a")
	mat.emission_enabled = true
	mat.emission = Color("#ffcc55")
	mat.emission_energy_multiplier = 2.0
	_gem.material_override = mat
	add_child(_gem)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffcc55")
	light.omni_range = 4.0
	light.position.y = 1.0
	add_child(light)
	_name = entity.get("name", "objeto")
	var label := Label3D.new()
	label.text = _name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.font_size = 36
	label.outline_size = 8
	label.pixel_size = 0.0009
	label.visibility_range_end = 25.0
	label.position.y = 1.7
	add_child(label)
	var area := Area3D.new()
	Layers.zone(area)
	var zone := CollisionShape3D.new()
	zone.shape = SphereShape3D.new()
	zone.shape.radius = 2.2
	zone.position.y = 1.0
	area.add_child(zone)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _gem:
		_gem.rotate_y(delta * 1.5)
		_gem.position.y = 1.0 + sin(Time.get_ticks_msec() / 400.0) * 0.12


func interaction_prompt() -> String:
	return "Recoger: " + _name


func interaction_point() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.interaction.add_candidate(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		body.interaction.remove_candidate(self)

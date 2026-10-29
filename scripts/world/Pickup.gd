class_name Pickup
extends Node3D
## Un objeto del mundo que se puede recoger (E). Gira y brilla para que se vea de lejos.

var item_id := ""
var _gem: MeshInstance3D
var _hint: Label3D


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
	var label := Label3D.new()
	label.text = entity.get("name", "?")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.pixel_size = 0.006
	label.position.y = 1.8
	add_child(label)
	_hint = Label3D.new()
	_hint.text = "[E] Recoger"
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.font_size = 30
	_hint.outline_size = 8
	_hint.pixel_size = 0.006
	_hint.position.y = 1.5
	_hint.visible = false
	add_child(_hint)
	var area := Area3D.new()
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


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.interact_target = self
		_hint.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		if body.interact_target == self:
			body.interact_target = null
		_hint.visible = false

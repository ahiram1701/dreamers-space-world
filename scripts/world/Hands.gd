class_name Hands
extends Node
## Las manos (v0.15.0): lo que está suelto se coge, se lleva, se suelta, se lanza o se empuja,
## como en la vida real, y se queda donde lo dejas (también al volver otro día).
##   - Hasta 25 kg (una silla, una caja, una planta, una papelera): G para cogerlo y llevarlo
##     delante; G otra vez lo deja en el suelo y clic (o ← en el mando) lo lanza, con más fuerza
##     cuanto menos pesa. Llevar algo pesado cansa (gasta aliento).
##   - De 25 a 120 kg (un sofá, una mesa grande, la nevera): andando contra ello se empuja,
##     despacio y con un roce que se oye.
##   - Más pesado, o fijo (una estantería empotrada, un edificio): no se mueve.
## Si mueves algo en casa ajena y alguien de la casa está dentro, lo ve y se acuerda.

const CARRY_MAX := 25.0   # kg que se llevan en brazos
const PUSH_MAX := 120.0   # kg que se empujan andando
const REACH := 1.7        # m: hasta dónde llegan las manos
const SETTLE_SPEED := 0.15  # m/s: por debajo, lo lanzado ya se ha parado
const STATE := "moved"    # WorldDB: dónde quedó cada cosa movida

## Peso (kg) de lo que se puede mover, por el nombre del modelo (empieza por…).
const WEIGHTS := {
	"Chair_": 6.0, "Stool": 4.0, "Trashcan_Small": 2.0, "Trashcan_Cylindric": 4.0, "Trashcan_Green": 6.0,
	"Trashcan_Large": 9.0, "Houseplant_": 5.0, "Light_Floor": 6.0, "Light_Stand": 6.0, "Light_Desk": 1.5,
	"NightStand_": 14.0, "Table_RoundSmall": 12.0, "Couch_Small": 35.0, "Couch_Medium": 50.0, "Couch_Large": 75.0,
	"Couch_L": 95.0, "Table_RoundLarge": 35.0, "Drawer_": 45.0, "Bed_Single": 40.0, "Bed_Bunk": 70.0, "Bed_King": 80.0,
	"Bathroom_WashingMachine": 70.0, "Kitchen_Fridge": 90.0, "Props_Crate": 20.0, "Props_CrateLong": 35.0,
	"Props_Vessel": 15.0, "Props_Vessel_Tall": 22.0, "Props_ContainerFull": 110.0, "WoodLog": 20.0, "Backpack": 4.0,
	"box": 10.0, "cone": 3.0, "Table_": 12.0,
}
## Cómo se llama cada cosa al cogerla (si no tiene ya su nombre de mueble).
const NAMES := {
	"Chair_": "la silla", "Stool": "el taburete", "Trashcan_": "la papelera", "Houseplant_": "la planta",
	"Light_Floor": "la lámpara", "Light_Stand": "la lámpara", "Light_Desk": "la lámpara", "NightStand_": "la mesita",
	"Table_": "la mesa", "Couch_": "el sofá", "Drawer_": "la cómoda", "Bed_": "la cama", "Bathroom_WashingMachine": "la lavadora",
	"Kitchen_Fridge": "la nevera", "Props_Crate": "la caja", "Props_Vessel": "el bidón", "Props_ContainerFull": "el contenedor",
	"WoodLog": "el tronco", "Backpack": "la mochila", "box": "la caja", "cone": "el cono",
}

var player: Player
## Lo que llevas en brazos ahora (o null).
var carried: Node3D = null
var _thrown: Array = []     # [{rb, node}] lo lanzado o soltado mientras cae y se para
var _layer: CanvasLayer
var _hint: Label
var _push_sound_t := 0.0


## Hace que `node` (la raíz que devuelve AssetLibrary.place) se pueda mover. Si se movió antes,
## vuelve a donde lo dejaste.
static func make_movable(node: Node3D, kg: float = -1.0, what: String = "") -> void:
	var model := _model_name(node)
	if kg < 0.0:
		kg = weight_of(model)
	if kg <= 0.0 or kg > PUSH_MAX:
		return
	node.set_meta("movable_kg", kg)
	if not what.is_empty():
		node.set_meta("thing", what)
	elif not node.has_meta("thing"):
		node.set_meta("thing", name_of(model))
	node.add_to_group("movable")
	node.add_to_group("things")  # (la tecla F y la IA también lo conocen: «cojo la silla»)
	_restore.call_deferred(node)


## kg de un modelo por su nombre (0 si no se mueve).
static func weight_of(model_name: String) -> float:
	var best := ""
	for k in WEIGHTS:
		if model_name.begins_with(k) and k.length() > best.length():
			best = k
	return float(WEIGHTS.get(best, 0.0))


static func name_of(model_name: String) -> String:
	var best := ""
	for k in NAMES:
		if model_name.begins_with(k) and k.length() > best.length():
			best = k
	return str(NAMES.get(best, "eso"))


static func _model_name(node: Node3D) -> String:
	for c in node.get_children():
		if not (c is CollisionObject3D) and not (c is Interactable):
			return AssetLibrary.model_name_of(c)
	return ""


## Dónde estaba al construirse (la clave para recordar dónde lo dejaste).
static func _key(node: Node3D) -> String:
	return "%s|%s" % [Toggle.place_key(node.global_position), _model_name(node)]


static func _restore(node: Node3D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var key := _key(node)
	node.set_meta("move_key", key)
	var saved: Variant = WorldDB.get_state(STATE, {}).get(key)
	if saved is Array and saved.size() >= 4:
		node.global_position = Vector3(saved[0], saved[1], saved[2])
		node.global_rotation = Vector3(0, float(saved[3]), 0)


static func _save(node: Node3D) -> void:
	if not node.has_meta("move_key"):
		return
	var all: Dictionary = WorldDB.get_state(STATE, {})
	var p := node.global_position
	all[node.get_meta("move_key")] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(node.global_rotation.y, 0.01)]
	WorldDB.set_state(STATE, all)


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 0.77
	_hint.anchor_bottom = 0.77
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.modulate.a = 0.8
	_hint.visible = false
	_layer.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_use():
		return
	if event.is_action_pressed("grab") and not event.is_echo():
		if carried:
			drop()
		else:
			var it := target()
			if it:
				grab(it)
	elif carried and event.is_action_pressed("throw") and not event.is_echo():
		throw()


func _can_use() -> bool:
	return player != null and player.controls_enabled and player.riding == null and not player.hold_position


## Lo movible que tienes delante, al alcance de la mano (o null).
func target() -> Node3D:
	if player == null:
		return null
	var fwd := player.facing_dir()
	var best: Node3D = null
	var best_score := INF
	for n in player.get_tree().get_nodes_in_group("movable"):
		var node := n as Node3D
		if node == null or node == carried or not node.is_inside_tree() or not node.is_visible_in_tree():
			continue
		var to := node.global_position - player.global_position
		if absf(to.y) > 1.2:
			continue
		var flat := Vector3(to.x, 0, to.z)
		var size: Vector3 = node.get_meta("size", Vector3.ONE)
		var d := flat.length() - maxf(size.x, size.z) / 2.0
		if d > REACH:
			continue
		var ang := fwd.angle_to(flat.normalized()) if flat.length() > 0.05 else 0.0
		if ang > deg_to_rad(65.0):
			continue
		var score := d + ang
		if score < best_score:
			best_score = score
			best = node
	return best


## Coger algo (si pesa demasiado, te lo dice). Devuelve una frase de lo que pasó.
func grab(node: Node3D) -> String:
	var kg := float(node.get_meta("movable_kg", 0.0))
	var what := str(node.get_meta("thing", "eso"))
	if kg > CARRY_MAX:
		return _say("%s pesa demasiado para llevarlo en brazos (unos %d kg): empújalo andando." % [what.capitalize(), int(kg)])
	if carried:
		drop()
	carried = node
	_set_solid(node, false)
	player.play_gesture("pick_up", 0.6)
	Sfx.at(player, "step_wood", node.global_position + Vector3(0, 0.3, 0), 0.1, -4.0)
	_witness("cogió %s" % what)
	return _say("Coges %s." % what)


## Soltarlo delante, en el suelo (cae y se para con su peso).
func drop() -> String:
	if carried == null:
		return ""
	var what := str(carried.get_meta("thing", "eso"))
	_release(player.velocity * 0.5)
	return _say("Dejas %s." % what)


## Lanzarlo hacia donde miras: lo ligero vuela lejos, lo pesado apenas.
func throw() -> String:
	if carried == null:
		return ""
	var kg := float(carried.get_meta("movable_kg", 5.0))
	var what := str(carried.get_meta("thing", "eso"))
	var speed := clampf(28.0 / sqrt(maxf(kg, 0.5)), 1.5, 14.0)
	var dir := player.aim_direction()
	player.play_gesture("throw", 0.7)
	Sfx.at(player, "whoosh", player.global_position + Vector3(0, 1.4, 0))
	Body.change("rest", -minf(kg * 0.05, 2.0))
	_release(dir * speed + Vector3(0, 1.6, 0) + player.velocity)
	_witness("lanzó %s" % what)
	return _say("Lanzas %s." % what)


## Lo suelta con una velocidad: cae con física de verdad y, cuando se para, vuelve a ser un
## mueble quieto (no se quedan cientos de cuerpos rodando).
func _release(velocity: Vector3) -> void:
	var node := carried
	carried = null
	var rb := RigidBody3D.new()
	rb.mass = float(node.get_meta("movable_kg", 5.0))
	rb.collision_layer = Layers.WORLD
	rb.collision_mask = Layers.WORLD | Layers.CHARACTERS
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	for body in node.get_children():
		if body is StaticBody3D:
			for cs in body.get_children():
				if cs is CollisionShape3D and cs.shape and not (cs.shape is ConcavePolygonShape3D):
					var copy := CollisionShape3D.new()
					copy.shape = cs.shape
					copy.transform = cs.transform
					rb.add_child(copy)
	if rb.get_child_count() == 0:  # (una forma exacta no vale para algo que rueda: su caja)
		var size: Vector3 = node.get_meta("size", Vector3(0.5, 0.5, 0.5))
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.shape.size = size
		cs.position.y = size.y / 2.0
		rb.add_child(cs)
	var parent := node.get_parent()
	parent.add_child(rb)
	rb.global_transform = node.global_transform
	rb.add_collision_exception_with(player)
	node.reparent(rb, true)
	rb.linear_velocity = velocity
	rb.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * clampf(velocity.length() * 0.3, 0.0, 3.0)
	rb.body_entered.connect(func(_b):
		if rb.linear_velocity.length() > 2.0:
			Sfx.at(rb, "thump", rb.global_position, 0.15, clampf(rb.linear_velocity.length() - 6.0, -10.0, 0.0)))
	_thrown.append({"rb": rb, "node": node, "parent": parent, "t": 0.0})


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if carried and not is_instance_valid(carried):
		carried = null
	if carried:
		if not _can_use():
			drop()
		else:
			_carry(delta)
	_settle(delta)
	_push(delta)
	var show := _can_use() and (carried != null or target() != null)
	_hint.visible = show
	if show:
		var g := Controls.label_for("grab")
		if carried:
			_hint.text = "[%s] Dejar  ·  [%s] Lanzar" % [g, "Clic" if not Controls.using_gamepad else "←"]
		else:
			var t := target()
			var kg := float(t.get_meta("movable_kg", 0.0))
			_hint.text = ("[%s] Coger %s" % [g, t.get_meta("thing", "eso")]) if kg <= CARRY_MAX else "Empújalo andando (%d kg)" % int(kg)


## Lo llevas delante, a la altura de la cintura, y cansa según lo que pesa.
func _carry(delta: float) -> void:
	var size: Vector3 = carried.get_meta("size", Vector3(0.5, 0.5, 0.5))
	var fwd := player.facing_dir()
	var want := player.global_position + fwd * (0.45 + maxf(size.x, size.z) / 2.0) + Vector3(0, clampf(1.0 - size.y / 2.0, 0.15, 0.9), 0)
	carried.global_position = carried.global_position.lerp(want, 1.0 - exp(-14.0 * delta))
	carried.global_rotation.y = lerp_angle(carried.global_rotation.y, atan2(fwd.x, fwd.z), 1.0 - exp(-8.0 * delta))
	var kg := float(carried.get_meta("movable_kg", 5.0))
	if kg > 8.0:
		Body.change("rest", -kg * 0.004 * delta)


## Lo lanzado o soltado: cuando se para (o al cabo de un rato), vuelve a ser estático donde quedó.
func _settle(delta: float) -> void:
	for e in _thrown.duplicate():
		var rb: RigidBody3D = e.rb
		if not is_instance_valid(rb):
			_thrown.erase(e)
			continue
		e.t += delta
		var still: bool = rb.linear_velocity.length() < SETTLE_SPEED and rb.angular_velocity.length() < 0.3
		if (still and e.t > 0.4) or e.t > 6.0 or rb.global_position.y < -200.0:
			var node: Node3D = e.node
			var parent: Node = e.parent if is_instance_valid(e.parent) else rb.get_parent()
			node.reparent(parent, true)
			# De pie otra vez si quedó tumbado (una silla vuelca, pero así se puede volver a usar)
			var yaw := node.global_rotation.y
			node.global_rotation = Vector3(0, yaw, 0)
			_set_solid(node, true)
			rb.queue_free()
			_thrown.erase(e)
			_save(node)


## Empujar andando: si vas contra algo movible y pesado, avanza despacio delante de ti.
func _push(delta: float) -> void:
	if carried or not _can_use() or not player.is_on_floor():
		return
	var want := Vector3(player.velocity.x, 0, player.velocity.z)
	var input := Controls.move_vector()
	if input == Vector2.ZERO:
		return
	for i in player.get_slide_collision_count():
		var col := player.get_slide_collision(i)
		var body := col.get_collider() as Node
		if body == null or not (body is StaticBody3D):
			continue
		var node := body.get_parent() as Node3D
		if node == null or not node.has_meta("movable_kg"):
			continue
		var kg := float(node.get_meta("movable_kg"))
		var n := -col.get_normal()
		n.y = 0.0
		if n.length() < 0.5:
			continue
		n = n.normalized()
		var dir := player.facing_dir() if want.length() < 0.1 else want.normalized()
		if dir.dot(n) < 0.5:
			continue
		var speed := clampf(70.0 / kg, 0.25, 1.4)  # (lo ligero se mueve de un empujón; lo pesado, poco a poco)
		var step := n * speed * delta
		if _blocked(node, body as StaticBody3D, step):
			return
		node.global_position += step
		Body.change("rest", -kg * 0.003 * delta)
		_push_sound_t -= delta
		if _push_sound_t <= 0.0:
			_push_sound_t = 0.45
			Sfx.at(node, "scrape", node.global_position + Vector3(0, 0.1, 0), 0.2, -8.0, 0.55)
		node.set_meta("pushed", true)
		_save.call_deferred(node)
		if not node.has_meta("push_noted"):
			node.set_meta("push_noted", true)
			_witness("arrastró %s" % node.get_meta("thing", "eso"))
		return


## ¿Choca con algo (una pared, otro mueble) si se mueve `step`?
func _blocked(node: Node3D, body: StaticBody3D, step: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	for cs in body.get_children():
		if not (cs is CollisionShape3D) or cs.shape == null:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = (cs as Node3D).global_transform.translated(step + Vector3(0, 0.03, 0))
		q.collision_mask = Layers.WORLD
		q.exclude = [body.get_rid(), player.get_rid()]
		q.margin = 0.01
		for hit in space.intersect_shape(q, 4):
			var other: Object = hit.collider
			if other is StaticBody3D and _is_floor(other as StaticBody3D, node):
				continue
			return true
	return false


## El suelo no cuenta como estorbo al empujar (lo que está por debajo de la base del mueble).
func _is_floor(other: StaticBody3D, node: Node3D) -> bool:
	for cs in other.get_children():
		if cs is CollisionShape3D and cs.shape:
			var top: float = (cs as Node3D).global_position.y
			if cs.shape is BoxShape3D:
				top += (cs.shape as BoxShape3D).size.y / 2.0
			elif cs.shape is ConcavePolygonShape3D or cs.shape is HeightMapShape3D:
				return true  # (terreno: se va por encima)
			if top <= node.global_position.y + 0.06:
				return true
	return false


func _set_solid(node: Node3D, on: bool) -> void:
	for body in node.get_children():
		if body is StaticBody3D:
			if not on and not body.has_meta("layer"):
				body.set_meta("layer", body.collision_layer)
			body.collision_layer = int(body.get_meta("layer", Layers.WORLD)) if on else 0


## Si estás en casa ajena y hay alguien de la casa dentro, te ve.
func _witness(what: String) -> void:
	var scene := player.get_parent()
	var interiors: Variant = scene.get("_interiors") if scene else null
	if interiors == null or not interiors.is_inside() or interiors.current_kind() == "home":
		return
	var door: String = interiors.current_door()
	for npc_id in Households.members(door):
		var npc: Node3D = scene.get("_npcs").get(npc_id) if scene.get("_npcs") is Dictionary else null
		if npc != null and npc.is_inside_tree() and npc.global_position.distance_to(player.global_position) < 15.0:
			NPCMemory.add_event(npc_id, "En su casa, %s %s sin pedir permiso." % [PlayerProfile.player_name(), what], -1)


func _say(text: String) -> String:
	var scene := player.get_parent() if player else null
	var ui: Variant = scene.get("_ui") if scene else null
	if ui and ui.has_method("toast"):
		ui.toast(text)
	return text

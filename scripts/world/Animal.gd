class_name Animal
extends CharacterBody3D
## Un animal con cuerpo: choca (no atraviesa vallas, casas, personas ni a ti), anda moviendo las
## patas, pasta, duerme de noche y reacciona a ti. Los domésticos se dejan acariciar o dar de
## comer; la vaca se ordeña y la gallina pone huevos; los salvajes huyen si corres hacia ellos.
##
##   var a := Animal.make("cow", pen_center, Vector2(9, 6), rng)
##   add_child(a); a.global_position = ...

const SPECIES := {
	# tamaño, colores, velocidad, salvaje, etiqueta
	"cow": {"s": 1.0, "body": Vector3(0.75, 0.7, 1.5), "colors": ["#3b3027", "#e6dfd3", "#8a5a3a"], "speed": 0.7, "wild": false, "label": "una vaca", "sound": "Muuu."},
	"sheep": {"s": 0.62, "body": Vector3(0.8, 0.7, 1.2), "colors": ["#efe9dc", "#d8d0c0"], "speed": 0.7, "wild": false, "label": "una oveja", "sound": "Beee."},
	"pig": {"s": 0.6, "body": Vector3(0.7, 0.6, 1.2), "colors": ["#e8a8a0", "#c88a80"], "speed": 0.7, "wild": false, "label": "un cerdo", "sound": "Oinc."},
	"hen": {"s": 0.32, "body": Vector3(0.6, 0.6, 0.8), "colors": ["#f2efe6", "#a0522d"], "speed": 0.9, "wild": false, "label": "una gallina", "sound": "Coc, coc."},
	"horse": {"s": 1.15, "body": Vector3(0.6, 0.7, 1.7), "colors": ["#5a3a22", "#2b2018", "#c8b090"], "speed": 1.2, "wild": false, "label": "un caballo", "sound": "Resopla."},
	"dog": {"s": 0.55, "body": Vector3(0.35, 0.3, 0.8), "colors": ["#8a5a2b", "#2b2b2b", "#d8c7a8", "#a06a3a"], "speed": 1.3, "wild": false, "label": "un perro del barrio", "sound": "¡Guau!"},
	"cat": {"s": 0.32, "body": Vector3(0.35, 0.3, 0.8), "colors": ["#e08a3a", "#3a3a3a", "#d8d0c4"], "speed": 1.1, "wild": false, "label": "un gato callejero", "sound": "Miau."},
	"deer": {"s": 0.9, "body": Vector3(0.5, 0.55, 1.2), "colors": ["#8a6040", "#a07850"], "speed": 1.0, "wild": true, "label": "un ciervo", "sound": ""},
	"rabbit": {"s": 0.22, "body": Vector3(0.5, 0.5, 0.8), "colors": ["#9a8a78", "#e8e0d4"], "speed": 1.2, "wild": true, "label": "un conejo", "sound": ""},
	"fox": {"s": 0.45, "body": Vector3(0.35, 0.35, 0.9), "colors": ["#c8642a"], "speed": 1.3, "wild": true, "label": "un zorro", "sound": ""},
}

var species := "cow"
var pen_center := Vector3.ZERO
var pen_half := Vector2(8, 8)
var ground_at: Callable

var _legs: Array[Node3D] = []
var _head: Node3D
var _tail: Node3D
var _goal := Vector3.INF
var _wait := 0.0
var _phase := 0.0
var _flee := 0.0
var _follow: Node3D = null
var _grav: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _asleep := false
var _lod_t := 0.0


static func make(kind: String, center: Vector3, half: Vector2, rng: RandomNumberGenerator) -> Animal:
	var a := Animal.new()
	a.species = kind if SPECIES.has(kind) else "cow"
	a.pen_center = center
	a.pen_half = half
	a._build(rng)
	return a


func _build(rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = SPECIES[species]
	var s: float = sp.s
	var col := Color(sp.colors[rng.randi() % sp.colors.size()])
	name = sp.label.get_slice(" ", 1).capitalize()
	add_to_group("animals")
	Layers.character(self)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(sp.body.x, 0.2) * s * 0.5
	cap.height = maxf(sp.body.z * s, cap.radius * 2.0 + 0.05)
	shape.shape = cap
	shape.rotation.x = PI / 2
	shape.position.y = (0.6 + sp.body.y * 0.5) * s
	add_child(shape)
	var body := Node3D.new()
	body.name = "Cuerpo"
	add_child(body)
	PropsBuilder._box(body, Vector3(0, (0.6 + sp.body.y * 0.5) * s, 0), sp.body * s, col, false)
	_head = Node3D.new()
	_head.position = Vector3(0, (0.7 + sp.body.y) * s, sp.body.z * 0.5 * s)
	body.add_child(_head)
	var hs := Vector3(sp.body.x * 0.6, sp.body.y * 0.6, sp.body.x * 0.7) * s
	if species == "horse":
		hs = Vector3(0.28, 0.32, 0.7) * s
	PropsBuilder._box(_head, Vector3(0, 0, hs.z * 0.4), hs, col.darkened(0.15), false)
	if species in ["rabbit", "fox", "cat", "dog", "deer", "horse"]:  # orejas
		for x in [-0.08, 0.08]:
			PropsBuilder._box(_head, Vector3(x * s * (3.0 if species == "rabbit" else 1.5), hs.y * 0.6 + (0.12 if species == "rabbit" else 0.04), 0.0), Vector3(0.05, 0.16 if species == "rabbit" else 0.08, 0.04) * s * 3.0, col.darkened(0.2), false)
	if species == "deer":
		for x in [-0.1, 0.1]:
			PropsBuilder._box(_head, Vector3(x, hs.y + 0.18, 0), Vector3(0.03, 0.35, 0.03), Color("#e8dcc0"), false)
	if species == "hen":
		PropsBuilder._box(_head, Vector3(0, hs.y * 0.6, hs.z * 0.3), Vector3(0.05, 0.08, 0.1) * 3.0 * s, Color("#d9302a"), false)
	_tail = Node3D.new()
	_tail.position = Vector3(0, (0.75 + sp.body.y * 0.6) * s, -sp.body.z * 0.5 * s)
	body.add_child(_tail)
	PropsBuilder._box(_tail, Vector3(0, -0.1 * s, -0.08 * s), Vector3(0.06, 0.25, 0.06) * s * 2.0, col.darkened(0.2), false)
	var legs := 2 if species == "hen" else 4
	for i in legs:
		var leg := Node3D.new()
		var lx: float = (sp.body.x * 0.35) * (-1.0 if i % 2 == 0 else 1.0)
		var lz: float = 0.0 if legs == 2 else (sp.body.z * 0.35) * (-1.0 if i < 2 else 1.0)
		leg.position = Vector3(lx * s, 0.6 * s, lz * s)
		body.add_child(leg)
		PropsBuilder._box(leg, Vector3(0, -0.3 * s, 0), Vector3(0.12, 0.6, 0.12) * s, Color("#2a2420") if species in ["cow", "horse", "deer"] else col.darkened(0.3), false)
		_legs.append(leg)
	if species == "cow" and col.v < 0.5:
		PropsBuilder._box(body, Vector3(0.2 * s, 1.1 * s, -0.2 * s), Vector3(0.36, 0.3, 0.5) * s, Color("#f0ece4"), false)
	# Lo que se puede hacer con él (E)
	var verbs := _verb()
	if not verbs.is_empty():
		var it := Interactable.create(self, Vector3(0, (0.9 + sp.body.y) * s, 0), maxf(1.2, sp.body.z * s), verbs, func(p): _use(p), self)
		it.name = "Animal"
	Decor.landmark(self, Vector3.ZERO, sp.label, "animal")


func _verb() -> String:
	match species:
		"dog", "cat":
			return "Acariciar al %s" % ("perro" if species == "dog" else "gato")
		"cow":
			return "Ordeñar la vaca"
		"hen":
			return "Buscar huevos"
		"horse", "sheep", "pig":
			return "Acariciar"
	return ""


func _use(player: Node) -> void:
	var sp: Dictionary = SPECIES[species]
	var ui = get_tree().get_first_node_in_group("gameplay_ui")
	_goal = Vector3.INF
	_wait = 4.0
	velocity = Vector3.ZERO
	look_at_point((player as Node3D).global_position)
	match species:
		"cow", "hen":
			var day := int(WorldClock.absolute_minutes() / 1440.0)
			var key := "%s_%d_%d" % [species, get_instance_id(), day]
			var done: Dictionary = WorldDB.get_state("animal_today", {})
			player.play_gesture("crouch" if species == "hen" else "kneel", 2.5)
			if done.has(key):
				if ui: ui.toast("Hoy ya no hay más.")
				return
			done[key] = true
			WorldDB.set_state("animal_today", done)
			var item := {"name": "Leche fresca", "lore": "Un jarro de leche recién ordeñada, todavía tibia.", "effect": "nourish"} if species == "cow" \
				else {"name": "Huevos", "lore": "Tres huevos todavía calientes del nido.", "effect": "nourish"}
			var id := WorldDB.add_entity("item", {"name": item.name, "kind": "consumable", "effect": item.effect, "power": 15, "lore": item.lore, "tags": ["granja"]}, "animal")
			Inventory.add(id)
			if ui: ui.toast("Consigues: %s." % item.name, "item")
		_:
			player.play_gesture("pat", 2.0)
			Body.change("rest", 2.0)  # da calma
			if ui: ui.toast("%s %s" % ["Le acaricias.", str(sp.sound)])
			# Si llevas comida, se la das y te sigue un rato (los perros, sobre todo)
			var food := ""
			for iid in Inventory.items():
				if str(WorldDB.get_entity("item", iid).get("effect", "")) == "nourish":
					food = iid
					break
			if not food.is_empty() and species in ["dog", "cat", "horse", "pig", "sheep"]:
				Inventory.remove(food)
				if ui: ui.toast("Le das de comer. Ahora te sigue un rato.")
				_follow = player as Node3D
				get_tree().create_timer(90.0).timeout.connect(func(): _follow = null)


func look_at_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		rotation.y = atan2(d.x, d.z)


func _physics_process(delta: float) -> void:
	# Lejos de ti, menos trabajo
	var players := get_tree().get_nodes_in_group("player")
	var player: Node3D = players[0] if not players.is_empty() else null
	var far := player == null or player.global_position.distance_to(global_position) > 60.0
	if far:
		_lod_t += delta
		if _lod_t < 0.25:
			return
		delta = _lod_t
	_lod_t = 0.0
	var sp: Dictionary = SPECIES[species]
	var speed: float = sp.speed
	# De noche duermen (tumbados, sin moverse)
	var night := WorldClock.hour() < 6.0 or WorldClock.hour() > 22.0
	if night != _asleep:
		_asleep = night
		$Cuerpo.position.y = -0.25 * float(sp.s) if night else 0.0
	if _asleep:
		velocity = Vector3.ZERO
		return
	var want := Vector3.ZERO
	if player and not far:
		var d := global_position.distance_to(player.global_position)
		# Los salvajes huyen si te acercas corriendo (o mucho); los domésticos se apartan un poco
		var running := player.get("velocity") != null and (player.velocity as Vector3).length() > 4.0
		if bool(sp.wild) and (d < 6.0 or (running and d < 14.0)):
			_flee = 4.0
		if _flee > 0.0:
			_flee -= delta
			var away := global_position - player.global_position
			away.y = 0.0
			want = away.normalized() * speed * 3.5
			_goal = Vector3.INF
	if want == Vector3.ZERO and _follow and is_instance_valid(_follow):
		var to := _follow.global_position - global_position
		to.y = 0.0
		if to.length() > 2.0:
			want = to.normalized() * speed * 2.5
	if want == Vector3.ZERO:
		if _wait > 0.0:
			_wait -= delta
		elif _goal == Vector3.INF or Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length() < 0.4:
			_goal = pen_center + Vector3(randf_range(-pen_half.x, pen_half.x), 0, randf_range(-pen_half.y, pen_half.y))
			_wait = randf_range(3.0, 9.0)  # pasta un rato
		else:
			var to2 := _goal - global_position
			to2.y = 0.0
			want = to2.normalized() * speed
	velocity.x = want.x
	velocity.z = want.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _grav * delta
	# Si el suelo aún no estaba (el terreno se carga por trozos) y se coló, vuelve encima
	if ground_at.is_valid():
		var g: float = ground_at.call(global_position.x, global_position.z)
		if global_position.y < g - 0.4:
			global_position.y = g + 0.1
			velocity.y = 0.0
	move_and_slide()
	# Si choca con algo, elige otro sitio (rodea vallas y casas en vez de empujarlas)
	if get_slide_collision_count() > 0 and want.length() > 0.1 and _flee <= 0.0:
		for i in get_slide_collision_count():
			if absf(get_slide_collision(i).get_normal().y) < 0.5:
				_goal = Vector3.INF
				_wait = randf_range(0.5, 1.5)
				break
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), minf(1.0, 5.0 * delta))
	# Patas que se mueven al andar (en diagonal), cabeza que pasta y cola
	_phase += delta * hv * 6.0
	for i in _legs.size():
		var sgn := 1.0 if (i == 0 or i == 3) else -1.0
		_legs[i].rotation.x = sin(_phase) * 0.5 * sgn * minf(hv, 1.5)
	if _head:
		_head.rotation.x = lerpf(_head.rotation.x, 0.6 if (hv < 0.05 and _wait > 0.0 and not bool(sp.wild)) else 0.0, minf(1.0, 3.0 * delta))
	if _tail:
		_tail.rotation.z = sin(Time.get_ticks_msec() / 300.0) * 0.3

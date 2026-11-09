class_name Behaviors
extends RefCounted
## Comportamientos que se le pueden poner a cualquier creación (Creations): lo que la hace útil.
## Se guardan como {type, params} y se montan al construirla. La IA los combina como piezas:
## una caja + "container" es un baúl; unas piezas + "seat" un banco; con "wheels" y "engine",
## un vehículo que se conduce.

const TYPES := {
	"seat": "se puede sentar (params: -)",
	"bed": "se puede dormir (params: -)",
	"container": "guarda cosas (params: -)",
	"light": "da luz y se enciende o apaga (params: color, range m, on)",
	"heat": "fuego o calor; da luz cálida y te puedes sentar junto a él (params: -)",
	"door": "las piezas con role \"door\" se abren y se cierran (params: locked)",
	"sign": "letrero con texto (params: text)",
	"machine": "transforma algo: entra un objeto y sale otro (params: input, output, minutes, verb)",
	"rigid": "tiene física: se puede empujar y cae (params: mass)",
	"float": "flota en el agua (params: -)",
	"sound": "suena al usarlo (params: sound: knock, door, hit, chop, splash, whoosh)",
	"wheels": "tiene ruedas: las piezas con shape \"wheel\" (params: -)",
	"engine": "motor: con ruedas es un vehículo de tierra, con float una lancha (params: power 1-10, fuel)",
	"pedals": "se mueve pedaleando, sin motor (params: -)",
	"thruster": "propulsor para volar, también en el espacio (params: power 1-10)",
	"cockpit": "cabina o asiento del piloto (params: -)",
	"tank": "depósito de combustible (params: capacity)",
	"rule": "regla automática: cuando pasa algo, hace algo (params: when, value, do [...], undo [...]; ver REGLAS)",
}
## Lenguaje de reglas (cerrado y seguro: no hay código, solo estas palabras).
##   when: weather (value: rain, clear, fog…), night, day, hour (value: 0-23), player_near (value: metros), use (value: texto del botón)
##   do / undo: lista de {act: light_on | light_off | toggle_light | open | close | sound (value) | say (value)
##                         | color (value #rrggbb) | give (value: nombre del objeto) | wait (value: segundos)}
const RULE_WHEN := ["weather", "night", "day", "hour", "player_near", "use"]
const RULE_ACTS := ["light_on", "light_off", "toggle_light", "open", "close", "sound", "say", "color", "give", "wait"]


## Comprueba una regla antes de guardarla. "" si está bien; si no, el error.
static func check_rule(p: Dictionary) -> String:
	if not str(p.get("when", "")) in RULE_WHEN:
		return "when debe ser uno de: %s" % ", ".join(PackedStringArray(RULE_WHEN))
	for key in ["do", "undo"]:
		var list = p.get(key, [])
		if not list is Array:
			return "%s debe ser una lista" % key
		if list.size() > 6:
			return "máximo 6 pasos en %s" % key
		for s in list:
			if not s is Dictionary or not str(s.get("act", "")) in RULE_ACTS:
				return "cada paso es {act, value}; act: %s" % ", ".join(PackedStringArray(RULE_ACTS))
	if (p.get("do", []) as Array).is_empty():
		return "falta \"do\": qué hace"
	return ""


static func attach(root: Node3D, b: Dictionary, scene: Node, e: Dictionary) -> void:
	var p: Dictionary = b.get("params", {}) if b.get("params", {}) is Dictionary else {}
	var name := str(e.get("name", "esto"))
	var on_use: Callable = scene.get("_on_placed_use") if scene.has_method("_on_placed_use") else Callable()
	var top := Creations.top_of(root)
	match str(b.get("type", "")):
		"seat":
			Interactable.create(root, Vector3(0, minf(top, 0.8), 0), 1.4, "Sentarse", func(player): _use(scene, "chair", root, player), root)
		"bed":
			Interactable.create(root, Vector3(0, minf(top, 0.6), 0), 1.6, "Dormir", func(player): _use(scene, "bed", root, player), root)
		"container":
			Interactable.create(root, Vector3(0, minf(top, 0.8), 0), 1.4, "Guardar o sacar: %s" % name, func(player): _use(scene, "storage", root, player), root)
		"heat":
			var fire := OmniLight3D.new()
			fire.light_color = Color("#ff9a4a")
			fire.omni_range = 7.0
			fire.light_energy = 1.6
			fire.position = Vector3(0, minf(top, 1.0), 0)
			root.add_child(fire)
			var tw := fire.create_tween().set_loops()
			tw.tween_property(fire, "light_energy", 1.1, 0.13)
			tw.tween_property(fire, "light_energy", 1.8, 0.17)
			Interactable.create(root, Vector3(0, 0.5, 0), 1.8, "Sentarse junto al fuego", func(player): _use(scene, "campfire", root, player), root)
		"light":
			var lamp := OmniLight3D.new()
			lamp.name = "Lamp"
			lamp.light_color = Color(str(p.color)) if Color.html_is_valid(str(p.get("color", ""))) else Color("#ffe6b0")
			lamp.omni_range = clampf(float(p.get("range", 8.0)), 2.0, 25.0)
			lamp.light_energy = 1.3
			lamp.position = Vector3(0, top + 0.1, 0)
			lamp.visible = bool(p.get("on", true))
			root.add_child(lamp)
			Interactable.create(root, Vector3(0, minf(top, 1.0), 0), 1.4, "Encender o apagar: %s" % name, func(_player):
				lamp.visible = not lamp.visible
				var bs: Array = Creations.get_entry(str(e.id)).get("behaviors", []).duplicate(true)
				for x in bs:
					if x.get("type", "") == "light":
						x["params"] = (x.get("params", {}) if x.get("params", {}) is Dictionary else {}).merged({"on": lamp.visible}, true)
				Creations.update(str(e.id), {"behaviors": bs}), root)
		"door":
			var hinges := root.find_children("Hinge_*", "Node3D", true, false)
			if hinges.is_empty():
				return
			var locked := bool(p.get("locked", false))
			Interactable.create(root, (hinges[0] as Node3D).position + Vector3(0.4, 1.0, 0.3), 1.3, "Abrir o cerrar: %s" % name, func(_player):
				if locked:
					Sfx.deny(scene)
					return
				for h in hinges:
					var hn := h as Node3D
					var open := absf(hn.rotation.y) > 0.5
					hn.create_tween().tween_property(hn, "rotation:y", 0.0 if open else deg_to_rad(-95.0), 0.5)
				Sfx.at(scene, "door", root.global_position + Vector3(0, 1, 0)), root)
		"sign":
			var l := Label3D.new()
			l.text = str(p.get("text", name)).left(80)
			l.font_size = 36
			l.pixel_size = 0.005
			l.outline_size = 6
			l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			l.position = Vector3(0, top + 0.25, 0)
			root.add_child(l)
		"machine":
			var verb := str(p.get("verb", "Usar"))
			Interactable.create(root, Vector3(0, minf(top, 1.0), 0), 1.4, "%s: %s" % [verb, name], func(_player):
				var msg := run_machine(p)
				if scene.get("_ui") and scene.get("_ui").has_method("toast"):
					scene.get("_ui").toast(msg), root)
		"float":
			var bob := FloatBob.new()
			bob.water_level = float(scene.get("_water_level")) if scene.get("_water_level") != null else 0.0
			if not is_finite(bob.water_level):
				bob.queue_free()  # sin agua aquí: no flota
				return
			root.add_child(bob)
		"rule":
			if check_rule(p).is_empty():
				var r := RuleRunner.new()
				r.rule = p
				r.scene = scene
				r.entry_id = str(e.get("id", ""))
				root.add_child(r)
				if str(p.when) == "use":
					Interactable.create(root, Vector3(0, minf(top, 1.0), 0), 1.4, str(p.get("value", "Usar: " + name)).left(40), func(_player): r.fire(true), root)
		"sound":
			var kind := str(p.get("sound", "knock"))
			Interactable.create(root, Vector3(0, minf(top, 1.0), 0), 1.4, "Hacer sonar: %s" % name, func(_player):
				Sfx.at(scene, kind, root.global_position + Vector3(0, 1, 0), 0.05), root)


static func _use(scene: Node, kind: String, root: Node3D, player: Variant) -> void:
	if scene.has_method("_on_placed_use"):
		scene.call("_on_placed_use", kind, root, player)


## Una máquina: si llevas lo que necesita, lo transforma (pasa el tiempo que tarda).
static func run_machine(p: Dictionary) -> String:
	var input := str(p.get("input", "")).to_lower()
	var output := str(p.get("output", "algo"))
	var minutes := clampf(float(p.get("minutes", 10.0)), 1.0, 600.0)
	var used := ""
	if not input.is_empty():
		for id in Inventory.items():
			if str(WorldDB.get_entity("item", id).get("name", "")).to_lower().contains(input):
				used = id
				break
		if used.is_empty():
			return "Necesitas %s." % input
		Inventory.remove(used)
	WorldClock.advance(minutes)
	var new_id := WorldDB.add_entity("item", {"name": output.left(40), "kind": "consumable", "effect": str(p.get("effect", "none")),
		"power": 15, "lore": "Hecho con %s." % (input if not input.is_empty() else "la máquina"), "tags": ["hecho"]}, "machine")
	Inventory.add(new_id)
	return "Tras %d min, obtienes: %s." % [int(minutes), output]


## Ejecuta una regla: mira cada 2 s si su condición cambió y hace sus pasos (do al empezar,
## undo al terminar). Máximo 6 disparos por minuto: una regla no puede colgar el juego.
class RuleRunner extends Node:
	var rule: Dictionary = {}
	var scene: Node
	var entry_id := ""
	var _state := false
	var _t := 0.0
	var _fired: Array = []

	func _ready() -> void:
		_state = _condition()
		if _state and str(rule.when) != "hour":
			fire(true)

	func _process(delta: float) -> void:
		_t += delta
		if _t < 2.0 or str(rule.when) == "use":
			return
		_t = 0.0
		var now := _condition()
		if now != _state:
			_state = now
			if now:
				fire(true)
			elif not (rule.get("undo", []) as Array).is_empty():
				fire(false)

	func _condition() -> bool:
		var v = rule.get("value", "")
		match str(rule.when):
			"weather":
				return Weather.current() == str(v)
			"night":
				return WorldClock.night() > 0.5
			"day":
				return WorldClock.night() <= 0.5
			"hour":
				return int(WorldClock.hour()) == int(float(v))
			"player_near":
				var pl = scene.get("_player") if scene else null
				return pl != null and (pl as Node3D).global_position.distance_to(get_parent().global_position) <= clampf(float(v), 1.0, 50.0)
		return false

	func fire(forward: bool) -> void:
		var now := Time.get_ticks_msec()
		_fired = _fired.filter(func(t): return now - t < 60000)
		if _fired.size() >= 6:
			return
		_fired.append(now)
		var root := get_parent() as Node3D
		for s in (rule.get("do", []) if forward else rule.get("undo", [])):
			var val = s.get("value", "")
			match str(s.get("act", "")):
				"light_on", "light_off", "toggle_light":
					for l in root.find_children("Lamp", "OmniLight3D", true, false):
						l.visible = true if s.act == "light_on" else false if s.act == "light_off" else not l.visible
				"open", "close":
					for h in root.find_children("Hinge_*", "Node3D", true, false):
						(h as Node3D).create_tween().tween_property(h, "rotation:y", deg_to_rad(-95.0) if s.act == "open" else 0.0, 0.5)
				"sound":
					Sfx.at(root, str(val) if str(val) in ["knock", "door", "hit", "chop", "splash", "whoosh"] else "knock", root.global_position + Vector3(0, 1, 0), 0.05)
				"say":
					if scene and scene.get("_ui") and scene.get("_ui").has_method("toast"):
						scene.get("_ui").toast(ContentValidator.fit_text(str(val), 240))
				"color":
					if Color.html_is_valid(str(val)):
						for m in root.find_children("Part_*", "MeshInstance3D", true, false):
							var mat := (m as MeshInstance3D).material_override as StandardMaterial3D
							if mat:
								mat.albedo_color = Color(str(val))
				"give":
					var id := WorldDB.add_entity("item", {"name": str(val).left(40), "kind": "consumable", "effect": "none", "power": 10,
						"lore": "Salió de %s." % root.name, "tags": ["regla"]}, "rule")
					Inventory.add(id)
				"wait":
					await get_tree().create_timer(clampf(float(val), 0.1, 30.0)).timeout


## Mece algo sobre el agua con las mismas olas del mar.
class FloatBob extends Node:
	var water_level := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var root := get_parent() as Node3D
		if root == null or root is RigidBody3D:
			return
		var p := root.global_position
		root.global_position.y = water_level + Decor.wave_y(p.x, p.z, _t) - 0.1

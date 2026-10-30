class_name InteriorBuilder
extends RefCounted
## Habitaciones interiores con muebles (modelos CC0 de Quaternius). Los edificios de fuera son
## cáscaras sin interior, así que al cruzar la puerta se construye la habitación en una zona
## apartada de la escena. Determinista: el mismo edificio tiene siempre los mismos muebles.
##
## build() devuelve { root, spawn, exit, npc_spots: [Vector3], seats: [], beds: [] }

const FURNITURE := "house_interior_pack"
const SCALE := 0.5          # los muebles de este pack vienen al doble de tamaño real
const HEIGHT := 3.2

## Tamaño de cada tipo de interior (ancho x fondo) y colores de pared y suelo.
const ROOMS := {
	"home": {"size": Vector2(10, 8), "wall": "#d9cbb0", "floor": "#8a6a4a", "name": "Tu casa"},
	"cafe": {"size": Vector2(14, 10), "wall": "#c98b6a", "floor": "#6e5038", "name": "Cafetería del Muelle"},
	"station": {"size": Vector2(18, 10), "wall": "#8c8279", "floor": "#5e5a55", "name": "Estación"},
	"lighthouse": {"size": Vector2(10, 10), "wall": "#e8e2d4", "floor": "#7a7468", "name": "Faro"},
	"house": {"size": Vector2(10, 8), "wall": "#e4d8c0", "floor": "#7d5f42", "name": "Casa"},
	"scifi": {"size": Vector2(12, 10), "wall": "#4a5568", "floor": "#2d3340", "name": "Módulo"},
	"shop": {"size": Vector2(12, 9), "wall": "#efe3c8", "floor": "#9c7b56", "name": "Tienda"},
	"workshop": {"size": Vector2(12, 10), "wall": "#a39a8c", "floor": "#55524d", "name": "Taller"},
	"office": {"size": Vector2(11, 9), "wall": "#dfe4e8", "floor": "#6f6a64", "name": "Oficina"},
}


static func build(parent: Node3D, kind: String, seed: int, origin: Vector3) -> Dictionary:
	var room: Dictionary = ROOMS.get(kind, ROOMS.house)
	var w: float = room.size.x
	var d: float = room.size.y
	var root := Node3D.new()
	root.position = origin
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wall := Color(room.wall).lerp(Color(["#f0e6d2", "#d8e4e8", "#e8d4c8", "#dfe6d0"][rng.randi() % 4]), 0.3 if kind == "house" else 0.0)
	_shell(root, w, d, wall, Color(room.floor), kind == "scifi")

	var out := {"root": root, "spawn": origin + Vector3(0, 0.1, d / 2.0 - 2.4), "exit": origin + Vector3(0, 0.1, d / 2.0 - 0.4),
		"npc_spots": [], "seats": [], "beds": [], "uses": []}
	match kind:
		"home":
			_put(root, "Bed_Single", Vector3(-w / 2 + 1.2, 0, -d / 2 + 1.3), 0.0, out.beds)
			_put(root, "NightStand_1", Vector3(-w / 2 + 2.4, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Couch_Medium1", Vector3(2.0, 0, -d / 2 + 0.8), 0.0, out.seats)
			_put(root, "Carpet_1", Vector3(2.0, 0, -0.6), 0.0)
			_put(root, "Table_RoundSmall", Vector3(-1.2, 0, 0.6), 0.0)
			_put(root, "Chair_1", Vector3(-1.9, 0, 0.6), PI / 2, out.seats)
			_put(root, "Chair_1", Vector3(-0.5, 0, 0.6), -PI / 2, out.seats)
			_use(root, "Kitchen_Fridge", Vector3(w / 2 - 0.6, 0, 1.5), -PI / 2, out, "eat", "Comer algo de la nevera")
			_put(root, "Kitchen_3Drawers", Vector3(w / 2 - 0.5, 0, 0.4), -PI / 2)
			_use(root, "Kitchen_Sink", Vector3(w / 2 - 0.5, 0, -0.5), -PI / 2, out, "drink", "Beber agua")
			_put(root, "Bookshelf", Vector3(-w / 2 + 0.4, 0, 1.0), PI / 2)
			_use(root, "Bathroom_Shower1", Vector3(w / 2 - 0.8, 0, -d / 2 + 0.8), 0.0, out, "shower", "Ducharse")
			_put(root, "Bathroom_Toilet", Vector3(w / 2 - 2.2, 0, -d / 2 + 0.45), 0.0)
			_put(root, "Light_Floor1", Vector3(-w / 2 + 0.6, 0, -0.6), 0.0)
			out.npc_spots = [origin + Vector3(2.5, 0, -0.6)]
		"cafe":
			for i in 4:  # barra
				_put(root, "Kitchen_2Drawers", Vector3(-3.0 + i * 0.75, 0, -d / 2 + 2.2), PI)
			_put(root, "Kitchen_Oven", Vector3(-3.4, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Kitchen_Fridge", Vector3(-1.4, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Shelf_Small1", Vector3(0.4, 1.3, -d / 2 + 0.25), 0.0)
			for i in 4:
				_put(root, "Stool", Vector3(-3.0 + i * 0.75, 0, -d / 2 + 3.1), 0.0, out.seats)
			for t in [Vector3(3.0, 0, -1.5), Vector3(4.5, 0, 1.5), Vector3(1.5, 0, 2.0)]:
				_put(root, "Table_RoundSmall", t, 0.0)
				_put(root, "Chair_2", t + Vector3(-0.75, 0, 0), PI / 2, out.seats)
				_put(root, "Chair_2", t + Vector3(0.75, 0, 0), -PI / 2, out.seats)
			_put(root, "Houseplant_3", Vector3(w / 2 - 0.6, 0, -d / 2 + 0.6), 0.0)
			_put(root, "Houseplant_5", Vector3(-w / 2 + 0.6, 0, d / 2 - 1.2), 0.0)
			out.npc_spots = [origin + Vector3(-2.0, 0, -d / 2 + 1.3), origin + Vector3(3.0, 0, 0.5)]
		"station":
			for i in 5:  # bancos de la sala de espera
				_put(root, "Couch_Small1", Vector3(-6.0 + i * 1.6, 0, 1.6), PI, out.seats)
			_put(root, "Kitchen_Cabinet1", Vector3(5.5, 0, -d / 2 + 0.5), 0.0)  # taquilla
			_put(root, "Table_RoundLarge", Vector3(-4.0, 0, -d / 2 + 1.4), 0.0)  # mesa del taller de Samir
			_put(root, "Chair_3", Vector3(-4.0, 0, -d / 2 + 2.4), PI, out.seats)
			_put(root, "Shelf_Large", Vector3(-7.4, 0, -d / 2 + 0.4), 0.0)
			for i in 3:
				var radio := AssetLibrary.instance("survival_pack", "Radio")
				if radio:
					AssetLibrary.place(root, radio, Vector3(-4.6 + i * 0.6, 0.56, -d / 2 + 1.3), 0.32, rng.randf_range(-0.4, 0.4), false)
			_put(root, "Light_Desk", Vector3(-3.2, 0.56, -d / 2 + 1.2), 0.0)
			_put(root, "Trashcan_Large", Vector3(w / 2 - 0.6, 0, d / 2 - 1.5), 0.0)
			out.npc_spots = [origin + Vector3(-2.4, 0, -d / 2 + 2.6), origin + Vector3(4.0, 0, 0)]  # junto a su mesa, no encima de la silla
		"lighthouse":
			# Escalera de caracol al fondo; la mesa de Marina a un lado, lejos de la puerta
			for i in 12:
				var a := TAU * i / 12.0
				PropsBuilder._box(root, Vector3(cos(a) * 1.6, 0.25 + i * 0.25, sin(a) * 1.6) + Vector3(-2.2, 0, -2.4),
					Vector3(1.2, 0.08, 0.5), Color("#5a5048"), true).rotation.y = -a
			PropsBuilder._cylinder(root, Vector3(-2.2, HEIGHT / 2, -2.4), 0.12, 0.12, HEIGHT, Color("#3a3a3a"), true)
			_put(root, "Table_RoundSmall", Vector3(3.0, 0, -2.6), 0.0)
			_put(root, "Chair_4", Vector3(3.0, 0, -1.8), PI, out.seats)
			_put(root, "Shelf_Small2", Vector3(-w / 2 + 0.3, 1.2, 1.5), PI / 2)
			_put(root, "Light_Stand1", Vector3(w / 2 - 0.6, 0, -d / 2 + 0.6), 0.0)
			_put(root, "Bookshelf", Vector3(w / 2 - 0.4, 0, 0.6), -PI / 2)
			out.npc_spots = [origin + Vector3(3.0, 0, -1.0)]
		"scifi":
			var props := ["Props_Computer", "Props_ComputerSmall", "Props_Shelf", "Props_Capsule", "Props_Crate", "Props_Pod", "Props_Vessel"]
			for i in 8:
				var m := AssetLibrary.instance("modular_sci_fi", props[rng.randi() % props.size()])
				if m:
					var b := AssetLibrary.bounds(m)
					var sx := -w / 2 + 1.0 if i % 2 == 0 else w / 2 - 1.0
					AssetLibrary.place(root, m, Vector3(sx, 0, -d / 2 + 1.2 + (i / 2) * 2.0), b.size.y * 2.0, PI / 2 if i % 2 == 0 else -PI / 2, true)
			out.npc_spots = [origin + Vector3(0, 0, -1.0)]
		"shop":  # mostrador, estanterías llenas y el dependiente detrás
			for i in 4:
				_put(root, "Kitchen_2Drawers", Vector3(-2.2 + i * 0.75, 0, -d / 2 + 2.0), PI)
			for x in [-w / 2 + 0.5, w / 2 - 0.5]:
				for z in [-1.0, 1.4]:
					_put(root, "Shelf_Large", Vector3(x, 0, z), PI / 2 if x < 0 else -PI / 2)
			_put(root, "Kitchen_Cabinet1", Vector3(2.6, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Kitchen_Fridge", Vector3(4.0, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Houseplant_4", Vector3(-w / 2 + 0.6, 0, d / 2 - 1.2), 0.0)
			out.npc_spots = [origin + Vector3(-1.0, 0, -d / 2 + 1.1)]
		"workshop":
			_put(root, "Table_RoundLarge", Vector3(-3.0, 0, -1.5), 0.0)
			_put(root, "Table_RoundLarge", Vector3(2.5, 0, -2.5), 0.0)
			_put(root, "Shelf_Large", Vector3(-w / 2 + 0.4, 0, 0.5), PI / 2)
			_put(root, "Drawer_3", Vector3(w / 2 - 0.5, 0, 0.5), -PI / 2)
			_put(root, "Trashcan_Large", Vector3(w / 2 - 0.6, 0, d / 2 - 1.5), 0.0)
			_put(root, "Chair_3", Vector3(-3.0, 0, -0.6), PI, out.seats)
			for t in [["Axe_Small", Vector3(-3.3, 0.78, -1.5), 0.3], ["Battery_Big", Vector3(-2.6, 0.78, -1.7), 0.25],
					["GasCan", Vector3(w / 2 - 1.2, 0, -d / 2 + 0.6), 0.5], ["Radio", Vector3(2.3, 0.78, -2.5), 0.3]]:
				var m := AssetLibrary.instance("survival_pack", t[0])
				if m:
					AssetLibrary.place(root, m, t[1], t[2], rng.randf() * TAU, t[1].y < 0.1)
			out.npc_spots = [origin + Vector3(2.5, 0, -1.4)]
		"office":
			for i in 2:
				_put(root, "Table_RoundLarge", Vector3(-2.5 + i * 5.0, 0, -1.8), 0.0)
				_put(root, "Chair_%d" % (1 + i), Vector3(-2.5 + i * 5.0, 0, -0.9), PI, out.seats)
				_put(root, "Light_Desk", Vector3(-2.2 + i * 5.0, 0.78, -2.0), 0.0)
			_put(root, "Bookshelf", Vector3(-w / 2 + 0.4, 0, 1.0), PI / 2)
			_put(root, "Couch_Small1", Vector3(w / 2 - 0.8, 0, 1.6), -PI / 2, out.seats)
			_put(root, "Houseplant_6", Vector3(w / 2 - 0.6, 0, -d / 2 + 0.6), 0.0)
			out.npc_spots = [origin + Vector3(-2.5, 0, -2.8)]
		_:  # casa de un vecino: muebles al azar pero siempre los mismos
			if rng.randf() < 0.6:
				_put(root, ["Bed_Single", "Bed_King"][rng.randi() % 2], Vector3(-w / 2 + 1.6, 0, -d / 2 + 1.3), 0.0, out.beds)
			else:
				_put(root, "Couch_Large1", Vector3(-w / 2 + 1.8, 0, -d / 2 + 0.8), 0.0, out.seats)
			_put(root, ["Table_RoundLarge", "Table_RoundSmall"][rng.randi() % 2], Vector3(1.5, 0, 0), 0.0)
			_put(root, "Chair_%d" % (1 + rng.randi() % 4), Vector3(0.6, 0, 0), PI / 2, out.seats)
			_put(root, "Chair_%d" % (1 + rng.randi() % 4), Vector3(2.4, 0, 0), -PI / 2, out.seats)
			_put(root, ["Bookshelf", "Shelf_Large", "Drawer_1", "Drawer_3"][rng.randi() % 4], Vector3(w / 2 - 0.5, 0, -1.0), -PI / 2)
			_put(root, "Kitchen_Fridge", Vector3(w / 2 - 0.6, 0, 1.6), -PI / 2)
			_put(root, "Houseplant_%d" % (1 + rng.randi() % 8), Vector3(-w / 2 + 0.6, 0, d / 2 - 1.6), 0.0)
			_put(root, "Carpet_%s" % ["1", "2", "Round"][rng.randi() % 3], Vector3(1.5, 0, 0.2), 0.0)
			_put(root, "Light_Floor%d" % (1 + rng.randi() % 4), Vector3(-w / 2 + 0.6, 0, 0.5), 0.0)
			out.npc_spots = [origin + Vector3(2.6, 0, -1.2)]
	return out


## Suelo, paredes, techo, ventanas y luz. La pared de delante tiene la puerta (hacia +Z).
static func _shell(root: Node3D, w: float, d: float, wall: Color, floor_color: Color, scifi: bool) -> void:
	PropsBuilder._box(root, Vector3(0, -0.1, 0), Vector3(w, 0.2, d), floor_color, true)
	PropsBuilder._box(root, Vector3(0, HEIGHT + 0.1, 0), Vector3(w, 0.2, d), wall.darkened(0.15), true)
	PropsBuilder._box(root, Vector3(0, HEIGHT / 2, -d / 2), Vector3(w, HEIGHT, 0.2), wall, true)
	PropsBuilder._box(root, Vector3(-w / 2, HEIGHT / 2, 0), Vector3(0.2, HEIGHT, d), wall, true)
	PropsBuilder._box(root, Vector3(w / 2, HEIGHT / 2, 0), Vector3(0.2, HEIGHT, d), wall, true)
	var gap := 1.4  # hueco de la puerta
	PropsBuilder._box(root, Vector3(-(w / 2 + gap / 2) / 2, HEIGHT / 2, d / 2), Vector3(w / 2 - gap / 2, HEIGHT, 0.2), wall, true)
	PropsBuilder._box(root, Vector3((w / 2 + gap / 2) / 2, HEIGHT / 2, d / 2), Vector3(w / 2 - gap / 2, HEIGHT, 0.2), wall, true)
	PropsBuilder._box(root, Vector3(0, HEIGHT - 0.4, d / 2), Vector3(gap, 0.8, 0.2), wall, true)
	# La puerta abierta deja ver una luz de exterior (y no se puede cruzar: se sale con E)
	var outside := PropsBuilder._box(root, Vector3(0, (HEIGHT - 0.8) / 2, d / 2 + 0.12), Vector3(gap, HEIGHT - 0.8, 0.05), Color("#ffe9c4"), true)
	outside.material_override.emission_enabled = true
	outside.material_override.emission = Color("#fff1d6")
	outside.material_override.emission_energy_multiplier = 0.6
	# Zócalo y ventanas en las paredes laterales
	PropsBuilder._box(root, Vector3(0, 0.15, -d / 2 + 0.11), Vector3(w, 0.3, 0.02), wall.darkened(0.35), false)
	for side in [-1, 1]:
		for z in [-d / 4, d / 4]:
			var win := PropsBuilder._box(root, Vector3(side * (w / 2 - 0.11), 1.7, z), Vector3(0.02, 1.0, 1.2), Color("#9fc8e8"), false)
			win.material_override.emission_enabled = true
			win.material_override.emission = Color("#bfe0ff") if not scifi else Color("#4fc3f7")
			win.material_override.emission_energy_multiplier = 0.5
	# Luces cálidas de techo
	for x in [-w / 4, w / 4]:
		var light := OmniLight3D.new()
		light.light_color = Color("#ffe2b8") if not scifi else Color("#cfe8ff")
		light.omni_range = maxf(w, d) * 0.8
		light.light_energy = 1.3
		light.shadow_enabled = Settings.graphics_quality >= 2
		light.position = Vector3(x, HEIGHT - 0.4, 0)
		root.add_child(light)
		_put(root, "Light_Ceiling1", Vector3(x, HEIGHT, 0), 0.0)


## Un mueble que se usa con E (nevera, grifo, ducha): `what` dice qué hace al usarlo.
static func _use(root: Node3D, model_name: String, pos: Vector3, yaw: float, out: Dictionary, what: String, prompt: String) -> void:
	_put(root, model_name, pos, yaw, out.uses)
	if not out.uses.is_empty() and out.uses[-1].name == model_name:
		out.uses[-1]["what"] = what
		out.uses[-1]["prompt"] = prompt


## Coloca un mueble del pack de interiores a su tamaño real. Si se pasa `list`, guarda su
## posición (asientos, camas) para poder usarlo con E.
static func _put(root: Node3D, model_name: String, pos: Vector3, yaw: float, list: Variant = null) -> void:
	var m := AssetLibrary.instance(FURNITURE, model_name)
	if m == null:
		return
	var b := AssetLibrary.bounds(m)
	# Todo lo que tiene cuerpo choca (también sillas y camas: al usarlas, el jugador ignora ese
	# mueble mientras está sentado). Solo se atraviesan alfombras, lámparas de techo y cosas diminutas.
	var flat := model_name.begins_with("Carpet") or model_name.begins_with("Light_Ceiling")
	var solid: bool = not flat and b.size.y * SCALE > 0.25 and maxf(b.size.x, b.size.z) * SCALE > 0.2
	var placed := AssetLibrary.place(root, m, pos, b.size.y * SCALE, yaw, solid)
	if model_name.begins_with("Light_Ceiling"):
		placed.position.y -= b.size.y * SCALE
	if list is Array:
		list.append({"node": placed, "name": model_name})

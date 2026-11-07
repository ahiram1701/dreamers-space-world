class_name InteriorBuilder
extends RefCounted
## Habitaciones interiores con muebles (modelos CC0 de Quaternius). Los edificios de fuera son
## cáscaras sin interior, así que al cruzar la puerta se construye la habitación en una zona
## apartada de la escena. Determinista: el mismo edificio tiene siempre los mismos muebles.
##
## build() devuelve { root, spawn, exit, npc_spots: [Vector3], seats: [], beds: [], uses: [],
##   sofa: [], table: [] (asientos por función), kitchen: [{pos, face}] (donde se cocina) }
## opts.sleepers: cuánta gente duerme en la casa (camas para todos).

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
	"clothes": {"size": Vector2(12, 9), "wall": "#f1e9e4", "floor": "#a8907a", "name": "Tienda de ropa"},
	"salon": {"size": Vector2(10, 8), "wall": "#e6eef0", "floor": "#c9c2b8", "name": "Peluquería"},
	"grocery": {"size": Vector2(12, 9), "wall": "#f3ead8", "floor": "#8f8a80", "name": "Abarrotes"},
	"restaurant": {"size": Vector2(14, 10), "wall": "#f0d9b5", "floor": "#7a5236", "name": "Fonda"},
	"pharmacy": {"size": Vector2(10, 8), "wall": "#eef4f2", "floor": "#b9c2c0", "name": "Farmacia"},
	"hardware": {"size": Vector2(12, 9), "wall": "#d8d2c6", "floor": "#6b6660", "name": "Ferretería"},
}

## Cómo es cada sitio por dentro (lo que la IA puede dar por cierto; lo demás no existe).
const DESCRIPTIONS := {
	"lighthouse": "una torre con UNA sola puerta, la delantera (no hay puerta trasera, sótano ni pasadizos a la vista). Dentro, en una sola sala: la mesa y la cama de Marina, estanterías, libros y una escalera de caracol que sube hacia la lámpara",
	"cafe": "una sola puerta delantera; barra, mesas y sillas, y la cocina detrás de la barra",
	"station": "estación de tren cerrada; una puerta delantera, sala de espera con bancos y la ventanilla, y una escalera a la oficina de arriba",
	"house": "casa con una puerta delantera; sala-comedor, cocina, baño y recámara (las de dos plantas, con las recámaras arriba)",
	"home": "la casa del jugador: una puerta delantera; sala-comedor, cocina, baño y recámara",
	"clothes": "tienda de ropa con una puerta delantera, percheros y probador",
	"salon": "peluquería con una puerta delantera, sillón y espejo",
	"grocery": "tienda de abarrotes con una puerta delantera, estantes, refrigeradores y la caja",
	"restaurant": "fonda con una puerta delantera, mesas con mantel, mostrador y la cocina",
	"pharmacy": "farmacia con una puerta delantera, mostrador y estantes de medicinas",
	"hardware": "ferretería con una puerta delantera, mesas y estantes de herramientas",
}


static func build(parent: Node3D, kind: String, seed: int, origin: Vector3, opts: Dictionary = {}) -> Dictionary:
	var room: Dictionary = ROOMS.get(kind, ROOMS.house)
	var w: float = room.size.x
	var d: float = room.size.y
	var root := Node3D.new()
	root.position = origin
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wall := Color(room.wall).lerp(Color(["#f0e6d2", "#d8e4e8", "#e8d4c8", "#dfe6d0"][rng.randi() % 4]), 0.3 if kind == "house" else 0.0)
	# Edificios de dos plantas por fuera (casas, tiendas, la estación…): también por dentro, con
	# escalera de verdad hasta arriba. El faro tiene la suya (de caracol, hasta la linterna).
	var floors := clampi(int(opts.get("floors", 1)), 1, 2) if kind != "lighthouse" else 1
	var hole := Rect2(-2.2 - 2.35, -2.4 - 2.35, 4.7, 4.7) if kind == "lighthouse" else Rect2()
	_shell(root, w, d, wall, Color(room.floor), kind == "scifi", floors, hole)
	if kind in ["house", "home"]:
		_home_rooms(root, w, d, wall, floors)
	elif floors > 1:
		_stairs_up(root, w, d)

	var out := {"root": root, "spawn": origin + Vector3(0, 0.1, d / 2.0 - 2.4), "exit": origin + Vector3(0, 0.1, d / 2.0 - 0.4),
		"npc_spots": [], "seats": [], "beds": [], "uses": [], "sofa": [], "table": [], "kitchen": []}
	match kind:
		"home":  # tu casa: recámara, baño, sala-comedor y cocina (y arriba, si tiene dos plantas)
			var bed_y := HEIGHT if floors > 1 else 0.0
			_put(root, "Bed_Single", Vector3(-w / 2 + 1.2, bed_y, -d / 2 + 1.3), 0.0, out.beds)
			_put(root, "NightStand_1", Vector3(-w / 2 + 2.4, bed_y, -d / 2 + 0.5), 0.0)
			_use(root, "Drawer_5", Vector3(-1.2, bed_y, -d / 2 + 0.45), 0.0, out, "wardrobe", "Cambiarte de ropa")
			_living(root, w, d, floors, out, rng, origin)
			_use(root, "Kitchen_Fridge", Vector3(w / 2 - 0.6, 0, 2.6), -PI / 2, out, "eat", "Comer algo de la nevera")
			_put(root, "Kitchen_Oven", Vector3(w / 2 - 0.5, 0, 1.6), -PI / 2)
			_use(root, "Kitchen_Sink", Vector3(w / 2 - 0.5, 0, 0.7), -PI / 2, out, "drink", "Beber agua")
			out.kitchen = [{"pos": origin + Vector3(w / 2 - 1.5, 0, 1.6), "face": origin + Vector3(w / 2, 0, 1.6)}]
			_use(root, "Bathroom_Shower1", Vector3(w / 2 - 0.8, 0, -d / 2 + 0.8), 0.0, out, "shower", "Ducharse")
			_put(root, "Bathroom_Toilet", Vector3(w / 2 - 2.2, 0, -d / 2 + 0.45), 0.0)
			_put(root, "Bathroom_Sink", Vector3(w / 2 - 0.45, 0, -d / 2 + 2.0), -PI / 2)
			out.npc_spots = [origin + Vector3(0.8, 0, 0.2)]
		"cafe":
			for i in 4:  # barra
				_put(root, "Kitchen_2Drawers", Vector3(-3.0 + i * 0.75, 0, -d / 2 + 2.2), PI)
			_use_at(root, Vector3(-1.9, 0, -d / 2 + 2.6), out, "order", "Pedir en la barra")
			_put(root, "Kitchen_Oven", Vector3(-3.4, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Kitchen_Fridge", Vector3(-1.4, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Shelf_Small1", Vector3(0.4, 1.3, -d / 2 + 0.25), 0.0)
			for i in 4:
				_seat(root, "Stool", Vector3(-3.0 + i * 0.75, 0, -d / 2 + 3.1), 0.0, out, "table")
			for t in [Vector3(3.0, 0, -1.5), Vector3(4.5, 0, 1.5), Vector3(1.5, 0, 2.0)]:
				_put(root, "Table_RoundSmall", t, 0.0)
				_seat(root, "Chair_2", t + Vector3(-0.75, 0, 0), PI / 2, out, "table")
				_seat(root, "Chair_2", t + Vector3(0.75, 0, 0), -PI / 2, out, "table")
			_put(root, "Houseplant_3", Vector3(w / 2 - 0.6, 0, -d / 2 + 0.6), 0.0)
			_put(root, "Houseplant_5", Vector3(-w / 2 + 0.6, 0, d / 2 - 1.2), 0.0)
			out.npc_spots = [origin + Vector3(-2.0, 0, -d / 2 + 1.3), origin + Vector3(3.0, 0, 0.5)]
		"station":
			for i in 5:  # bancos de la sala de espera
				_seat(root, "Couch_Small1", Vector3(-6.0 + i * 1.6, 0, 1.6), PI, out, "sofa")
			_put(root, "Kitchen_Cabinet1", Vector3(5.5, 0, -d / 2 + 0.5), 0.0)  # taquilla
			_put(root, "Table_RoundLarge", Vector3(-4.0, 0, -d / 2 + 1.4), 0.0)  # mesa del taller de Samir
			_put(root, "Chair_3", Vector3(-4.0, 0, -d / 2 + 2.4), PI, out.seats)
			_put(root, "Shelf_Large", Vector3(-7.4, 0, -d / 2 + 0.4), 0.0)
			_put(root, "Bed_Single", Vector3(w / 2 - 1.0, 0, -d / 2 + 1.3), 0.0, out.beds)  # el catre de Samir
			for i in 3:
				var radio := AssetLibrary.instance("survival_pack", "Radio")
				if radio:
					AssetLibrary.place(root, radio, Vector3(-4.6 + i * 0.6, 0.56, -d / 2 + 1.3), 0.32, rng.randf_range(-0.4, 0.4), false)
			_put(root, "Light_Desk", Vector3(-3.2, 0.56, -d / 2 + 1.2), 0.0)
			_put(root, "Trashcan_Large", Vector3(w / 2 - 0.6, 0, d / 2 - 1.5), 0.0)
			out.npc_spots = [origin + Vector3(-2.4, 0, -d / 2 + 2.6), origin + Vector3(4.0, 0, 0)]  # junto a su mesa, no encima de la silla
		"lighthouse":
			# Escalera de caracol al fondo, con barandilla, que sube por una trampilla del techo hasta
			# la linterna (arriba sales al balcón de la torre); la mesa de Marina a un lado
			for i in 12:
				var a := TAU * i / 12.0
				PropsBuilder._box(root, Vector3(cos(a) * 1.6, 0.25 + i * 0.25, sin(a) * 1.6) + Vector3(-2.2, 0, -2.4),
					Vector3(1.2, 0.08, 0.5), Color("#5a5048"), true).rotation.y = -a
				var post := PropsBuilder._box(root, Vector3(cos(a) * 2.15, 0.75 + i * 0.25, sin(a) * 2.15) + Vector3(-2.2, 0, -2.4),
					Vector3(0.04, 1.0, 0.04), Color("#2d3238"), false)
				post.rotation.y = -a
			PropsBuilder._cylinder(root, Vector3(-2.2, HEIGHT / 2, -2.4), 0.12, 0.12, HEIGHT, Color("#3a3a3a"), true)
			var top_a := TAU * 11 / 12.0
			var top := Vector3(cos(top_a) * 1.6, 0.25 + 11 * 0.25, sin(top_a) * 1.6) + Vector3(-2.2, 0, -2.4)
			# El techo tiene un hueco sobre la escalera (antes era macizo y te dabas con la cabeza a
			# media subida): sube un tubo de piedra y arriba está la trampilla de la linterna
			var shaft_h := 2.8
			var hc := hole.get_center()
			for side in [-1.0, 1.0]:
				PropsBuilder._box(root, Vector3(hc.x + side * (hole.size.x / 2 + 0.1), HEIGHT + shaft_h / 2, hc.y), Vector3(0.2, shaft_h, hole.size.y + 0.4), wall.darkened(0.1), true)
				PropsBuilder._box(root, Vector3(hc.x, HEIGHT + shaft_h / 2, hc.y + side * (hole.size.y / 2 + 0.1)), Vector3(hole.size.x, shaft_h, 0.2), wall.darkened(0.1), true)
			PropsBuilder._box(root, Vector3(hc.x, HEIGHT + shaft_h + 0.1, hc.y), Vector3(hole.size.x + 0.4, 0.2, hole.size.y + 0.4), wall.darkened(0.2), true)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color("#ffe2b8")
			lamp.omni_range = 5.0
			lamp.light_energy = 0.9
			lamp.position = Vector3(hc.x, HEIGHT + shaft_h - 0.4, hc.y)
			root.add_child(lamp)
			# La trampilla, en lo alto del tubo, justo encima del último peldaño
			PropsBuilder._box(root, Vector3(top.x, HEIGHT + shaft_h - 0.02, top.z), Vector3(1.1, 0.06, 1.1), Color("#121212"), false)
			PropsBuilder._box(root, Vector3(top.x, HEIGHT + shaft_h - 0.06, top.z), Vector3(1.3, 0.08, 1.3), Color("#5a4632"), false)
			_use_at(root, top + Vector3(0, 0.05, 0), out, "climb_up", "Subir a la linterna")
			out["hatch"] = origin + top + Vector3(0, 0.1, 0)
			_use(root, "Kitchen_Fridge", Vector3(-w / 2 + 0.6, 0, 3.2), PI / 2, out, "eat", "Comer algo de la nevera")
			_use(root, "Kitchen_Sink", Vector3(-w / 2 + 0.5, 0, 2.3), PI / 2, out, "drink", "Beber agua")
			_put(root, "Table_RoundSmall", Vector3(3.0, 0, -2.6), 0.0)
			_put(root, "Chair_4", Vector3(3.0, 0, -1.8), PI, out.seats)
			_put(root, "Shelf_Small2", Vector3(-w / 2 + 0.3, 1.2, 1.5), PI / 2)
			_put(root, "Light_Stand1", Vector3(w / 2 - 0.6, 0, -d / 2 + 0.6), 0.0)
			_put(root, "Bed_Single", Vector3(0.6, 0, -d / 2 + 1.3), 0.0, out.beds)  # Marina vive aquí
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
		"clothes":  # percheros, espejo, mostrador y un probador con cortina
			for x in [-w / 2 + 0.5, w / 2 - 0.5]:
				for z in [-2.0, 0.6]:
					_put(root, "Shelf_Large", Vector3(x, 0, z), PI / 2 if x < 0 else -PI / 2)
			_use(root, "Table_RoundLarge", Vector3(0, 0, 0.2), 0.0, out, "clothes_shop", "Ver la ropa y probártela")
			for i in 3:
				_put(root, "Kitchen_2Drawers", Vector3(1.5 + i * 0.75, 0, -d / 2 + 1.6), PI)
			_put(root, "Bathroom_Mirror1", Vector3(-2.5, 1.2, -d / 2 + 0.15), 0.0)
			_put(root, "Curtains_Single", Vector3(-4.0, 0, -d / 2 + 0.3), 0.0)
			_put(root, "Houseplant_2", Vector3(w / 2 - 0.6, 0, d / 2 - 1.2), 0.0)
			out.npc_spots = [origin + Vector3(2.2, 0, -d / 2 + 0.8)]
		"grocery":  # estantes llenos, refrigerador de bebidas y la caja
			for x in [-w / 2 + 0.5, w / 2 - 0.5]:
				for z in [-2.2, 0.4, 2.6]:
					_put(root, "Shelf_Large", Vector3(x, 0, z), PI / 2 if x < 0 else -PI / 2)
					_stock(root, Vector3(x + (0.25 if x < 0 else -0.25), 0, z), rng, ["#c0392b", "#e6b422", "#2e86c1", "#27ae60", "#f5f0e1", "#8e5a2b"])
			for z in [-1.0, 1.4]:  # góndola en medio
				PropsBuilder._box(root, Vector3(0, 0.55, z), Vector3(3.0, 1.1, 0.6), Color("#9aa0a6"), true)
				_stock(root, Vector3(0, 0.55, z), rng, ["#c0392b", "#e6b422", "#2e86c1", "#f5f0e1"], true)
			_put(root, "Kitchen_Fridge", Vector3(1.6, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Kitchen_Fridge", Vector3(2.6, 0, -d / 2 + 0.5), 0.0)
			for i in 2:
				_put(root, "Kitchen_2Drawers", Vector3(-3.0 + i * 0.75, 0, d / 2 - 2.0), 0.0)
			_use_at(root, Vector3(-2.6, 0, d / 2 - 2.6), out, "shop_buy", "Comprar")
			out.npc_spots = [origin + Vector3(-2.6, 0, d / 2 - 1.4)]
		"restaurant":  # mesas con mantel, la barra y la cocina al fondo
			for t in [Vector3(-3.5, 0, -0.5), Vector3(0.0, 0, -0.5), Vector3(3.5, 0, -0.5), Vector3(-3.5, 0, 2.6), Vector3(3.5, 0, 2.6)]:
				_put(root, "Table_RoundSmall", t, 0.0)
				PropsBuilder._cylinder(root, t + Vector3(0, 0.79, 0), 0.55, 0.55, 0.02, Color("#d9534f"), false)  # mantel
				_seat(root, "Chair_1", t + Vector3(-0.8, 0, 0), PI / 2, out, "table")
				_seat(root, "Chair_1", t + Vector3(0.8, 0, 0), -PI / 2, out, "table")
			for i in 5:
				_put(root, "Kitchen_2Drawers", Vector3(-1.5 + i * 0.75, 0, -d / 2 + 2.0), PI)
			_put(root, "Kitchen_Oven_Large", Vector3(-2.0, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Kitchen_Fridge", Vector3(2.5, 0, -d / 2 + 0.5), 0.0)
			_put(root, "Kitchen_Sink", Vector3(0.4, 0, -d / 2 + 0.45), 0.0)
			_use_at(root, Vector3(0.0, 0, -d / 2 + 2.6), out, "order", "Pedir de comer")
			out.kitchen = [{"pos": origin + Vector3(-2.0, 0, -d / 2 + 1.3), "face": origin + Vector3(-2.0, 0, -d / 2)}]
			out.npc_spots = [origin + Vector3(0.6, 0, -d / 2 + 1.3)]
		"pharmacy":  # mostrador, estantes con medicinas y botiquines
			for x in [-w / 2 + 0.5, w / 2 - 0.5]:
				for z in [-1.6, 1.0]:
					_put(root, "Shelf_Large", Vector3(x, 0, z), PI / 2 if x < 0 else -PI / 2)
					_stock(root, Vector3(x + (0.25 if x < 0 else -0.25), 0, z), rng, ["#ffffff", "#e8f4f8", "#3aa76d", "#2e86c1", "#d9534f"])
			for i in 4:
				_put(root, "Kitchen_2Drawers", Vector3(-1.1 + i * 0.75, 0, -d / 2 + 2.0), PI)
			for i in 3:
				var kit := AssetLibrary.instance("survival_pack", "FirstAidKit" if i != 1 else "FirstAidKit_Hard")
				if kit:
					AssetLibrary.place(root, kit, Vector3(-0.8 + i * 0.9, 0.92, -d / 2 + 2.0), 0.22, rng.randf() * TAU, false)
			_put(root, "Shelf_Large", Vector3(0, 0, -d / 2 + 0.4), 0.0)
			_use_at(root, Vector3(0.0, 0, -d / 2 + 2.6), out, "shop_buy", "Comprar")
			out.npc_spots = [origin + Vector3(0.4, 0, -d / 2 + 1.2)]
		"hardware":  # herramientas de verdad en mesas y estantes
			for x in [-w / 2 + 0.5, w / 2 - 0.5]:
				for z in [-2.0, 0.8]:
					_put(root, "Shelf_Large", Vector3(x, 0, z), PI / 2 if x < 0 else -PI / 2)
					_stock(root, Vector3(x + (0.25 if x < 0 else -0.25), 0, z), rng, ["#7f8c8d", "#c0392b", "#e67e22", "#2c3e50", "#95a5a6"])
			_put(root, "Table_RoundLarge", Vector3(0, 0, 0.6), 0.0)
			for t in [["Axe", Vector3(-0.4, 0.78, 0.4), 0.7], ["Shovel", Vector3(0.5, 0.78, 0.7), 1.0], ["Axe_Small", Vector3(0.1, 0.78, 1.0), 0.35],
					["Torch", Vector3(-0.2, 0.78, 0.9), 0.22], ["GasCan", Vector3(w / 2 - 1.3, 0, d / 2 - 1.4), 0.5]]:
				var m := AssetLibrary.instance("survival_pack", t[0])
				if m:
					var placed := AssetLibrary.place(root, m, t[1], t[2], rng.randf() * TAU, true)
					if t[1].y > 0.1:
						placed.rotation.z = PI / 2  # tumbada sobre la mesa
			for i in 3:
				_put(root, "Kitchen_2Drawers", Vector3(1.5 + i * 0.75, 0, -d / 2 + 1.8), PI)
			_use_at(root, Vector3(2.2, 0, -d / 2 + 2.4), out, "shop_buy", "Comprar")
			out.npc_spots = [origin + Vector3(2.2, 0, -d / 2 + 1.1)]
		"salon":  # el sillón frente al espejo, el lavacabezas y un sofá para esperar
			_use(root, "Chair_3", Vector3(-1.5, 0, -d / 2 + 1.4), PI, out, "haircut", "Cortarte el pelo")
			_put(root, "Bathroom_Mirror2", Vector3(-1.5, 1.3, -d / 2 + 0.15), 0.0)
			_put(root, "Bathroom_Sink", Vector3(1.0, 0, -d / 2 + 0.4), 0.0)
			_put(root, "Shelf_Small1", Vector3(2.6, 1.3, -d / 2 + 0.2), 0.0)
			_seat(root, "Couch_Small1", Vector3(w / 2 - 1.0, 0, 1.2), -PI / 2, out, "sofa")
			_put(root, "Houseplant_6", Vector3(-w / 2 + 0.6, 0, d / 2 - 1.2), 0.0)
			out.npc_spots = [origin + Vector3(-0.6, 0, -d / 2 + 1.9)]
		_:  # casa de un vecino: camas para quien vive aquí, sofá, mesa y cocina (siempre los mismos)
			var sleepers := int(opts.get("sleepers", 1 + rng.randi() % 2))
			var bed_y := HEIGHT if floors > 1 else 0.0
			# Recámara de los padres (o de quien vive solo) y la de los hijos al lado
			_put(root, "Bed_King" if sleepers >= 2 else "Bed_Single", Vector3(-w / 2 + 1.6, bed_y, -d / 2 + 1.3), 0.0, out.beds)
			_put(root, "NightStand_%d" % (1 + rng.randi() % 3), Vector3(-w / 2 + 3.0, bed_y, -d / 2 + 0.4), 0.0)
			for k in clampi(sleepers - 2, 0, 2):  # los hijos: en su cuarto (arriba si hay dos plantas)
				var kid_x := (1.0 + k * 1.4) if floors > 1 else (-1.4 + k * 0.0)
				if floors == 1 and k == 1:
					break  # en una planta solo cabe una cama más en la recámara: el otro, en el sofá
				_put(root, "Bed_Single", Vector3(kid_x, bed_y, -d / 2 + 1.3), 0.0, out.beds)
			_living(root, w, d, floors, out, rng, origin)
			if sleepers >= 3:
				_seat(root, "Chair_%d" % (1 + rng.randi() % 4), Vector3(1.6, 0, 1.5), PI, out, "table")
			_use(root, "Bathroom_Shower1", Vector3(w / 2 - 0.8, 0, -d / 2 + 0.8), 0.0, out, "shower", "Ducharse")
			_put(root, "Bathroom_Toilet", Vector3(w / 2 - 2.2, 0, -d / 2 + 0.45), 0.0)
			_use(root, "Kitchen_Fridge", Vector3(w / 2 - 0.6, 0, 2.6), -PI / 2, out, "eat", "Comer algo de la nevera")
			_put(root, "Kitchen_Oven", Vector3(w / 2 - 0.5, 0, 1.6), -PI / 2)
			_use(root, "Kitchen_Sink", Vector3(w / 2 - 0.5, 0, 0.7), -PI / 2, out, "drink", "Beber agua")
			out.kitchen = [{"pos": origin + Vector3(w / 2 - 1.5, 0, 1.6), "face": origin + Vector3(w / 2, 0, 1.6)},
				{"pos": origin + Vector3(w / 2 - 1.5, 0, 0.7), "face": origin + Vector3(w / 2, 0, 0.7)}]
			out.npc_spots = [origin + Vector3(0.8, 0, 0.2), origin + Vector3(-1.0, 0, 1.6), origin + Vector3(3.4, 0, 0.0)]
	if floors > 1 and not (kind in ["house", "home"]):
		_upper_floor(root, w, d, kind, out, rng)
	return out


## La planta de arriba de un local: más mesas en un café o una fonda; la oficina en la estación;
## el almacén (estantes y cajas) en las tiendas y talleres.
static func _upper_floor(root: Node3D, w: float, d: float, kind: String, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var y := HEIGHT
	if kind in ["cafe", "restaurant"]:
		for t in [Vector3(1.6, y, -d / 2 + 2.0), Vector3(w / 2 - 1.8, y, 0.4)]:
			_put(root, "Table_RoundSmall", t, 0.0)
			_seat(root, "Chair_2", t + Vector3(-0.75, 0, 0), PI / 2, out, "table")
			_seat(root, "Chair_2", t + Vector3(0.75, 0, 0), -PI / 2, out, "table")
		_put(root, "Houseplant_%d" % (1 + rng.randi() % 8), Vector3(w / 2 - 0.6, y, -d / 2 + 0.6), 0.0)
	elif kind in ["station", "office", "scifi"]:
		_put(root, "Table_RoundLarge", Vector3(1.8, y, -d / 2 + 1.4), 0.0)
		_seat(root, "Chair_3", Vector3(1.8, y, -d / 2 + 2.4), PI, out, "table")
		_put(root, "Shelf_Large", Vector3(w / 2 - 0.5, y, -1.0), -PI / 2)
		_put(root, "Light_Desk", Vector3(2.4, y + 0.56, -d / 2 + 1.2), 0.0)
	else:
		for i in 3:
			_put(root, ["Shelf_Large", "Shelf_1", "Shelf_2"][i], Vector3(-0.4 + i * 1.6, y, -d / 2 + 0.4), 0.0)
		for i in 4:
			PropsBuilder._box(root, Vector3(w / 2 - 1.2 - (i % 2) * 0.9, y + 0.3 + (i / 2) * 0.6, 1.0 + rng.randf_range(-0.2, 0.2)), Vector3(0.8, 0.6, 0.6), Color("#a07c52").darkened(rng.randf() * 0.2), true)


## Suelo, paredes, techo, ventanas y luz. La pared de delante tiene la puerta (hacia +Z).
static func _shell(root: Node3D, w: float, d: float, wall: Color, floor_color: Color, scifi: bool, floors: int = 1, hole: Rect2 = Rect2()) -> void:
	var top := HEIGHT * floors
	PropsBuilder._box(root, Vector3(0, -0.1, 0), Vector3(w, 0.2, d), floor_color, true)
	if hole.size == Vector2.ZERO:
		PropsBuilder._box(root, Vector3(0, top + 0.1, 0), Vector3(w, 0.2, d), wall.darkened(0.15), true)
	else:  # techo con un hueco (x, z) para una escalera
		var x0 := -w / 2
		var x1 := w / 2
		var z0 := -d / 2
		var z1 := d / 2
		var hx0 := hole.position.x
		var hx1 := hole.end.x
		var hz0 := hole.position.y
		var hz1 := hole.end.y
		var ceil_c := wall.darkened(0.15)
		PropsBuilder._box(root, Vector3((x0 + hx0) / 2, top + 0.1, 0), Vector3(hx0 - x0, 0.2, d), ceil_c, true)
		PropsBuilder._box(root, Vector3((hx1 + x1) / 2, top + 0.1, 0), Vector3(x1 - hx1, 0.2, d), ceil_c, true)
		PropsBuilder._box(root, Vector3((hx0 + hx1) / 2, top + 0.1, (z0 + hz0) / 2), Vector3(hx1 - hx0, 0.2, hz0 - z0), ceil_c, true)
		PropsBuilder._box(root, Vector3((hx0 + hx1) / 2, top + 0.1, (hz1 + z1) / 2), Vector3(hx1 - hx0, 0.2, z1 - hz1), ceil_c, true)
	PropsBuilder._box(root, Vector3(0, top / 2, -d / 2), Vector3(w, top, 0.2), wall, true)
	PropsBuilder._box(root, Vector3(-w / 2, top / 2, 0), Vector3(0.2, top, d), wall, true)
	PropsBuilder._box(root, Vector3(w / 2, top / 2, 0), Vector3(0.2, top, d), wall, true)
	var gap := 1.4  # hueco de la puerta
	PropsBuilder._box(root, Vector3(-(w / 2 + gap / 2) / 2, top / 2, d / 2), Vector3(w / 2 - gap / 2, top, 0.2), wall, true)
	PropsBuilder._box(root, Vector3((w / 2 + gap / 2) / 2, top / 2, d / 2), Vector3(w / 2 - gap / 2, top, 0.2), wall, true)
	PropsBuilder._box(root, Vector3(0, (HEIGHT - 0.8 + top) / 2, d / 2), Vector3(gap, top - HEIGHT + 0.8, 0.2), wall, true)
	for f in range(1, floors):  # ventanas y luces también arriba
		for side in [-1, 1]:
			for z in [-d / 4, d / 4]:
				var up := PropsBuilder._box(root, Vector3(side * (w / 2 - 0.11), 1.7 + HEIGHT * f, z), Vector3(0.02, 1.0, 1.2), Color("#9fc8e8"), false)
				up.material_override.emission_enabled = true
				up.material_override.emission = Color("#bfe0ff")
				up.material_override.emission_energy_multiplier = 0.5
		for x in [-w / 4, w / 4]:
			var l2 := OmniLight3D.new()
			l2.light_color = Color("#ffe2b8")
			l2.omni_range = maxf(w, d) * 0.8
			l2.light_energy = 1.2
			l2.shadow_enabled = false
			l2.position = Vector3(x, HEIGHT * (f + 1) - 0.4, 0)
			root.add_child(l2)
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
		light.add_to_group("quality_shadows")
		light.position = Vector3(x, HEIGHT - 0.4, 0)
		root.add_child(light)
		_put(root, "Light_Ceiling1", Vector3(x, HEIGHT, 0), 0.0)


## Un mueble que se usa con E (nevera, grifo, ducha): `what` dice qué hace al usarlo.
static func _use(root: Node3D, model_name: String, pos: Vector3, yaw: float, out: Dictionary, what: String, prompt: String) -> void:
	_put(root, model_name, pos, yaw, out.uses)
	if not out.uses.is_empty() and out.uses[-1].name == model_name:
		out.uses[-1]["what"] = what
		out.uses[-1]["prompt"] = prompt


## Los cuartos de una casa: tabiques con hueco de puerta. En una planta, la recámara (fondo a la
## izquierda) y el baño (fondo a la derecha); en dos, el baño abajo y las recámaras arriba, con
## una escalera junto a la pared izquierda y un hueco con barandilla en el suelo de arriba.
static func _home_rooms(root: Node3D, w: float, d: float, wall: Color, floors: int) -> void:
	var c := wall.darkened(0.04)
	# Baño: fondo a la derecha
	_wall_line(root, Vector2(w / 2 - 3.0, -d / 2), Vector2(w / 2 - 3.0, -d / 2 + 2.6), 0.62, c)
	_wall_line(root, Vector2(w / 2 - 3.0, -d / 2 + 2.6), Vector2(w / 2, -d / 2 + 2.6), -1.0, c)
	if floors == 1:  # recámara: fondo a la izquierda
		_wall_line(root, Vector2(-0.6, -d / 2), Vector2(-0.6, -d / 2 + 3.4), -1.0, c)
		_wall_line(root, Vector2(-w / 2, -d / 2 + 3.4), Vector2(-0.6, -d / 2 + 3.4), 0.72, c)
		return
	_stairs_up(root, w, d)
	# Arriba, dos cuartos
	_wall_line(root, Vector2(0.4, -d / 2), Vector2(0.4, -d / 2 + 3.0), -1.0, c, HEIGHT)


## Escalera a la planta de arriba: de delante (junto a la entrada) hacia el fondo, pegada a la
## pared izquierda; el suelo de arriba con su hueco y barandilla.
static func _stairs_up(root: Node3D, w: float, d: float) -> void:
	var x := -w / 2 + 0.75
	var z0 := d / 2 - 0.7     # abajo
	var run := 4.2
	var z1 := z0 - run        # arriba
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var slope := Vector2(run, HEIGHT).length()
	box.size = Vector3(1.3, 0.12, slope)
	shape.shape = box
	ramp.add_child(shape)
	ramp.position = Vector3(x, HEIGHT / 2.0, (z0 + z1) / 2.0)
	ramp.rotation.x = atan2(HEIGHT, run)  # sube hacia el fondo (-z)
	root.add_child(ramp)
	var steps := 14
	for i in steps:  # peldaños que se ven (la rampa invisible es la que se pisa)
		var t := (i + 0.5) / steps
		PropsBuilder._box(root, Vector3(x, HEIGHT * t - 0.1, lerpf(z0, z1, t)), Vector3(1.3, 0.2, run / steps + 0.02), Color("#7a5a3c"), false)
	# Suelo de arriba con el hueco de la escalera
	var hole_x := -w / 2 + 1.5
	PropsBuilder._box(root, Vector3((hole_x + w / 2) / 2.0, HEIGHT, 0), Vector3(w / 2 - hole_x, 0.2, d), Color("#7d5f42"), true)
	PropsBuilder._box(root, Vector3((-w / 2 + hole_x) / 2.0, HEIGHT, (-d / 2 + z1) / 2.0), Vector3(hole_x + w / 2, 0.2, z1 + d / 2), Color("#7d5f42"), true)
	PropsBuilder._box(root, Vector3(hole_x, HEIGHT + 0.5, (z1 + d / 2) / 2.0), Vector3(0.06, 1.0, d / 2 - z1), Color("#5b4636"), true)  # barandilla


## La planta baja que se vive: sofá, mesa con sillas, alfombra y algo de decoración.
static func _living(root: Node3D, w: float, d: float, floors: int, out: Dictionary, rng: RandomNumberGenerator, origin: Vector3) -> void:
	if floors == 1:
		_seat(root, ["Couch_Medium1", "Couch_Medium2"][rng.randi() % 2], Vector3(-w / 2 + 0.9, 0, 1.6), PI / 2, out, "sofa")
		_put(root, "Carpet_%s" % ["1", "2", "Round"][rng.randi() % 3], Vector3(-w / 2 + 2.4, 0, 1.6), 0.0)
	else:
		_seat(root, ["Couch_Medium1", "Couch_Large1"][rng.randi() % 2], Vector3(-1.4, 0, -d / 2 + 0.8), 0.0, out, "sofa")
		_put(root, "Carpet_%s" % ["1", "2", "Round"][rng.randi() % 3], Vector3(-1.4, 0, -1.6), 0.0)
	_put(root, ["Table_RoundLarge", "Table_RoundSmall"][rng.randi() % 2], Vector3(1.6, 0, 0.6), 0.0)
	_seat(root, "Chair_%d" % (1 + rng.randi() % 4), Vector3(0.7, 0, 0.6), PI / 2, out, "table")
	_seat(root, "Chair_%d" % (1 + rng.randi() % 4), Vector3(2.5, 0, 0.6), -PI / 2, out, "table")
	_put(root, "Houseplant_%d" % (1 + rng.randi() % 8), Vector3(w / 2 - 0.6, 0, d / 2 - 0.8), 0.0)
	_put(root, "Light_Floor%d" % (1 + rng.randi() % 4), Vector3(w / 2 - 3.4, 0, -d / 2 + 3.0), 0.0)


## Un tabique recto (alineado con x o z) de `a` a `b`, con un hueco de puerta de 1 m centrado en
## `door_at` (fracción del largo; < 0: sin puerta). `y0`: planta (0 abajo, HEIGHT arriba).
static func _wall_line(root: Node3D, a: Vector2, b: Vector2, door_at: float, c: Color, y0: float = 0.0) -> void:
	var length := a.distance_to(b)
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var pieces := [[0.0, length]]
	if door_at >= 0.0:
		var mid := length * door_at
		pieces = [[0.0, mid - 0.5], [mid + 0.5, length]]
		# dintel sobre el hueco
		var p := a.lerp(b, door_at)
		PropsBuilder._box(root, Vector3(p.x, y0 + HEIGHT - 0.4, p.y), Vector3(1.0, 0.8, 0.12) if along_x else Vector3(0.12, 0.8, 1.0), c, true)
	for piece in pieces:
		var l: float = piece[1] - piece[0]
		if l <= 0.05:
			continue
		var center := a.lerp(b, (piece[0] + piece[1]) / 2.0 / length)
		var size := Vector3(l, HEIGHT, 0.12) if along_x else Vector3(0.12, HEIGHT, l)
		PropsBuilder._box(root, Vector3(center.x, y0 + HEIGHT / 2.0, center.y), size, c, true)


## Algo que se usa con E sin mueble propio (pedir en la barra, pagar en la caja): un punto.
static func _use_at(root: Node3D, pos: Vector3, out: Dictionary, what: String, prompt: String) -> void:
	var marker := Node3D.new()
	marker.position = pos
	root.add_child(marker)
	out.uses.append({"node": marker, "name": what, "what": what, "prompt": prompt})


## Mercancía en un estante: filas de cajitas y botes de colores en tres alturas. `flat`: encima
## de una góndola (una sola altura, a los dos lados).
static func _stock(root: Node3D, at: Vector3, rng: RandomNumberGenerator, colors: Array, flat: bool = false) -> void:
	var levels := [0.62] if flat else [0.42, 0.95, 1.48]
	for y in levels:
		for k in 6:
			var c := Color(colors[rng.randi() % colors.size()])
			var size := Vector3(0.16, rng.randf_range(0.14, 0.26), 0.12)
			var along := -0.75 + k * 0.3
			var p := at + (Vector3(along, y + size.y / 2.0, 0) if flat else Vector3(0, y + size.y / 2.0, along))
			PropsBuilder._box(root, p, size, c, false)


## Un asiento con función ("sofa", "table"): se puede usar con E y la gente lo usa según la hora.
static func _seat(root: Node3D, model_name: String, pos: Vector3, yaw: float, out: Dictionary, group: String) -> void:
	var before: int = out.seats.size()
	_put(root, model_name, pos, yaw, out.seats)
	if out.seats.size() > before:
		out[group].append(out.seats[-1])


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

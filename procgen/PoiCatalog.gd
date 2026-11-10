class_name PoiCatalog
extends RefCounted
## Lo que se puede construir de verdad en un lugar generado. La IA elige el tipo ("kind") de cada
## punto de interés de esta lista, y el motor lo construye con su forma: un faro es un faro (con
## puerta y sala redonda), una consola es una consola. Así lo que se cuenta y lo que se ve
## coinciden, y la etiqueta al examinar es el nombre de verdad.

## Tipo → cómo se describe (para la IA y al examinar).
const KINDS := {
	"lighthouse": "un faro (torre con puerta y escalera de caracol por dentro)",
	"antenna": "una antena con una luz roja",
	"console": "una consola con pantalla",
	"archive": "un archivo: estanterías con cajas y carpetas",
	"wreck": "los restos de una nave",
	"ruins": "unas ruinas con columnas rotas",
	"temple": "un templo de columnas con techo de piedra",
	"camp": "un campamento con tienda y hoguera",
	"cabin": "una cabaña de madera con puerta",
	"well": "un pozo con brocal y tejadillo",
	"crater": "un cráter",
	"monolith": "una piedra alta",
	"tower": "una torre de vigilancia",
	"market": "unos puestos de mercado",
	"dock": "un muelle de tablas",
	"greenhouse": "un invernadero de cristal",
	"mine": "la boca de una mina",
	"marker": "un mojón de piedras apiladas",
	"terminal": "una terminal (punto de recarga del Ancla)",
}

## Palabras → tipo, de lo más concreto a lo más general (para lugares antiguos sin "kind").
const WORDS := [
	["lighthouse", ["faro"]],
	["console", ["consola", "terminal", "panel de control", "computadora", "ordenador", "puesto de mando", "cabina de control"]],
	["archive", ["archivo", "biblioteca", "registro", "almacén", "almacen", "depósito", "deposito"]],
	["greenhouse", ["invernadero", "huerto", "vivero"]],
	["dock", ["muelle", "embarcadero", "puerto", "atracadero"]],
	["mine", ["mina", "excavación", "excavacion", "cantera", "túnel", "tunel"]],
	["market", ["mercado", "bazar", "puestos", "feria"]],
	["cabin", ["cabaña", "cabana", "choza", "casa", "refugio", "cobertizo", "taller"]],
	["well", ["pozo", "aljibe", "cisterna"]],
	["temple", ["templo", "santuario", "capilla", "altar"]],
	["tower", ["torre", "atalaya", "mirador"]],
	["antenna", ["antena", "baliza", "emisor", "radio", "transmisor", "repetidor", "mástil", "mastil"]],
	["wreck", ["restos", "naufragio", "pecio", "chatarra", "nave estrellada", "accidente"]],
	["camp", ["campamento", "tienda", "hoguera", "vivac"]],
	["ruins", ["ruina", "columna", "estatua"]],
	["crater", ["cráter", "crater", "impacto", "charco", "lago", "manantial", "géiser", "geiser", "fuente"]],
	["monolith", ["monolito", "obelisco", "megalito", "piedra", "roca", "cristal"]],
]


## Deja points_of_interest como lista de nombres (lo que usa el resto del juego) y los tipos
## aparte, en poi_kinds. Acepta las dos formas: objetos {name, kind} o nombres sueltos.
static func normalize_location(d: Dictionary) -> Dictionary:
	var names := []
	var kinds := []
	for p in d.get("points_of_interest", []):
		var name := str(p.get("name", "")) if p is Dictionary else str(p)
		if name.strip_edges().length() < 2:
			continue
		var kind := str(p.get("kind", "")) if p is Dictionary else ""
		if not KINDS.has(kind) or kind == "marker":
			var guess := classify(name)
			kind = guess if kind.is_empty() or kind == "marker" or not KINDS.has(kind) else kind
		names.append(name.strip_edges())
		kinds.append(kind)
	# El mundo manda: lo que la descripción da por hecho (un faro, una consola…) se construye
	var text := (str(d.get("name", "")) + ". " + str(d.get("description", ""))).to_lower()
	for k in MUST_BUILD:
		if names.size() >= 6:
			break
		if k in kinds:
			continue
		for w in _words_of(k):
			var i := (" " + text).find(" " + w)
			if i >= 0:
				names.push_front(_name_from(text, i, w))
				kinds.push_front(k)
				break
	d["points_of_interest"] = names
	d["poi_kinds"] = kinds
	return d


## Lo que, si se menciona, tiene que estar (lo demás —una roca, un charco— puede ser paisaje).
const MUST_BUILD := ["lighthouse", "console", "archive", "antenna", "dock", "greenhouse", "mine", "temple", "tower", "market", "well"]


static func _words_of(kind: String) -> Array:
	for pair in WORDS:
		if pair[0] == kind:
			return pair[1]
	return []


## «…junto al viejo faro de la bahía…» → «Faro de la bahía» (o la palabra sola, con mayúscula).
static func _name_from(text: String, at: int, word: String) -> String:
	var rest := text.substr(at, 40)
	for stop in [",", ".", ";", " y ", " que ", " con ", " donde ", " junto "]:
		var j := rest.find(stop, word.length())
		if j > 0:
			rest = rest.left(j)
	rest = rest.strip_edges()
	return rest.substr(0, 1).to_upper() + rest.substr(1)


## El tipo de un punto por su nombre, buscando palabras enteras (para mundos de antes).
static func classify(name: String) -> String:
	var low := " " + name.to_lower() + " "
	for pair in WORDS:
		for w in pair[1]:
			var i := low.find(w)
			if i > 0 and not low.substr(i - 1, 1).is_valid_identifier():  # empieza palabra
				return pair[0]
	return "marker"


## Lo que se lee al examinarlo: «Consola de recepción — una consola con pantalla».
static func label(name: String, kind: String) -> String:
	return "%s — %s" % [name, KINDS.get(kind, KINDS.marker)]


## Construye el punto bajo `root` (ya colocado y girado). Devuelve info extra:
## {"door": {"offset": Vector3, "kind": String, "size": Vector3, "shape": String}} si tiene puerta,
## y "stand": un sitio delante donde se pone quien trabaja allí.
static func build(root: Node3D, kind: String, rng: RandomNumberGenerator, stone: Color) -> Dictionary:
	var out := {"stand": Vector3(0, 0, 1.6)}
	match kind:
		"lighthouse":
			var white := Color("#ecebe4")
			_cyl(root, Vector3(0, 0.15, 0), 2.9, 3.1, 0.3, stone, true)  # zócalo bajo: se sube sin saltar
			_cyl(root, Vector3(0, 0.3 + 5.5, 0), 2.1, 2.6, 11.0, white, true)
			_cyl(root, Vector3(0, 5.0, 0), 2.37, 2.37, 1.2, Color("#c0392b"), false)  # franja roja
			# Galería pisable alrededor de la linterna, con barandilla (se sale a ella desde la trampilla)
			_cyl(root, Vector3(0, 12.0, 0), 3.0, 3.0, 0.2, Color("#2f3338"), true)
			for k in 16:
				var a := k * TAU / 16.0
				var post := _box(root, Vector3(sin(a) * 2.9, 12.6, cos(a) * 2.9), Vector3(0.06, 1.0, 0.06), Color("#2f3338"), true)
				post.rotation.y = a
				var rail := _box(root, Vector3(sin(a + PI / 16.0) * 2.86, 13.08, cos(a + PI / 16.0) * 2.86), Vector3(1.15, 0.05, 0.05), Color("#2f3338"), false)
				rail.rotation.y = a + PI / 16.0 + PI / 2.0
			var lamp := _cyl(root, Vector3(0, 13.0, 0), 1.5, 1.5, 1.7, Color("#fff4c2"), false)
			_glow(lamp, Color("#ffe9a0"), 1.5)
			var cap := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.1
			cone.bottom_radius = 1.8
			cone.height = 1.2
			cap.mesh = cone
			cap.material_override = _mat(Color("#2f3338"))
			cap.position = Vector3(0, 14.45, 0)
			root.add_child(cap)
			_box(root, Vector3(0, 1.35, 2.5), Vector3(1.1, 2.1, 0.3), Color("#5b3b22"), false)  # puerta
			var light := OmniLight3D.new()
			light.light_color = Color("#ffe9a0")
			light.light_energy = 1.2
			light.omni_range = 18.0
			light.position = Vector3(0, 13.0, 0)
			root.add_child(light)
			out.door = {"offset": Vector3(0, 0.3, 3.15), "kind": "lighthouse", "size": Vector3(5.2, 15.0, 5.2), "shape": "round"}
			out.gallery = Vector3(0, 12.15, 2.45)
			out.stand = Vector3(1.6, 0.3, 3.6)
		"console":
			var desk := _box(root, Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.8), Color("#3a3f46"), true)
			desk.name = "Consola"
			for k in 2:
				var screen := _box(root, Vector3(-0.45 + k * 0.9, 1.25, -0.15), Vector3(0.8, 0.55, 0.06), Color("#0b2a3a"), false)
				screen.rotation_degrees.x = -12.0
				_glow(screen, Color("#4fc3f7"), 0.9)
			var keys := _box(root, Vector3(0, 0.93, 0.15), Vector3(1.2, 0.04, 0.35), Color("#22262b"), false)
			keys.rotation_degrees.x = 8.0
			var l := OmniLight3D.new()
			l.light_color = Color("#4fc3f7")
			l.light_energy = 0.7
			l.omni_range = 4.0
			l.position = Vector3(0, 1.4, 0.6)
			root.add_child(l)
			var chair := AssetLibrary.instance("modular_sci_fi", "Props_Base")
			if chair:
				AssetLibrary.place(root, chair, Vector3(0, 0, 1.0), 0.5, 0.0, false)
			out.stand = Vector3(0, 0, 1.05)
		"archive":
			for k in 3:
				var x := -2.0 + k * 2.0
				var shelf := AssetLibrary.instance("modular_sci_fi", "Props_Shelf_Tall")
				if shelf:
					AssetLibrary.place(root, shelf, Vector3(x, 0, -0.6), 2.4, 0.0, true)
				else:
					_box(root, Vector3(x, 1.2, -0.6), Vector3(1.6, 2.4, 0.5), Color("#6b5a44"), true)
			for k in 4:
				_box(root, Vector3(rng.randf_range(-2.5, 2.5), 0.25, rng.randf_range(0.6, 1.4)), Vector3(0.6, 0.5, 0.45), Color("#8b6b4a"), true)
			# un tejadillo encima, para que se lea como un sitio y no cajas sueltas
			_box(root, Vector3(0, 3.0, -0.2), Vector3(7.0, 0.15, 2.6), Color("#4a4f55"), false)
			for x in [-3.3, 3.3]:
				_cyl(root, Vector3(x, 1.5, 0.9), 0.08, 0.08, 3.0, Color("#4a4f55"), true)
			out.stand = Vector3(0, 0, 1.2)
			out.door = {"offset": Vector3(0, 0, 1.7), "kind": "archive", "size": Vector3(7.0, 3.0, 2.6), "shape": "box"}
		"temple":
			_box(root, Vector3(0, 0.25, 0), Vector3(7.0, 0.5, 5.0), stone, true)
			for x in [-2.8, 2.8]:
				for z in [-1.8, 1.8]:
					_cyl(root, Vector3(x, 2.25, z), 0.32, 0.36, 3.5, stone.lightened(0.15), true)
			_box(root, Vector3(0, 4.2, 0), Vector3(7.2, 0.5, 5.2), stone.darkened(0.1), false)
			_box(root, Vector3(0, 1.0, -1.0), Vector3(1.2, 1.0, 0.8), stone.darkened(0.2), true)  # altar
			# Muros entre las columnas (atrás y a los lados) y un portal delante: se entra
			_box(root, Vector3(0, 2.25, -2.3), Vector3(6.4, 3.5, 0.3), stone.lightened(0.05), true)
			for x in [-3.0, 3.0]:
				_box(root, Vector3(x, 2.25, 0), Vector3(0.3, 3.5, 4.4), stone.lightened(0.05), true)
			for x in [-2.0, 2.0]:
				_box(root, Vector3(x, 2.25, 2.3), Vector3(2.2, 3.5, 0.3), stone.lightened(0.05), true)
			_box(root, Vector3(0, 1.4, 2.32), Vector3(1.6, 2.4, 0.1), Color("#4a3020"), false)  # puerta
			out.stand = Vector3(1.4, 0.5, 3.0)
			out.door = {"offset": Vector3(0, 0.5, 2.9), "kind": "temple", "size": Vector3(7.0, 4.5, 5.0), "shape": "box"}
		"cabin":
			var wood := Color("#7a5a3a")
			_box(root, Vector3(0, 1.4, -0.3), Vector3(4.4, 2.8, 4.0), wood, true)
			var roof := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(5.0, 1.6, 4.6)
			roof.mesh = prism
			roof.material_override = _mat(Color("#5a3b26"))
			roof.position = Vector3(0, 3.6, -0.3)
			root.add_child(roof)
			_box(root, Vector3(0, 1.05, 1.72), Vector3(0.95, 2.1, 0.1), Color("#4a3020"), false)
			for x in [-1.4, 1.4]:
				var win := _box(root, Vector3(x, 1.6, 1.72), Vector3(0.7, 0.6, 0.06), Color("#ffd27a"), false)
				_glow(win, Color("#ffcf7a"), 0.4)
			out.door = {"offset": Vector3(0, 0, 2.3), "kind": "house", "size": Vector3(4.4, 3.6, 4.0), "shape": "box"}
			out.stand = Vector3(1.8, 0, 2.6)
		"well":
			_cyl(root, Vector3(0, 0.45, 0), 0.9, 0.95, 0.9, stone, true)
			var water := _cyl(root, Vector3(0, 0.8, 0), 0.7, 0.7, 0.05, Color("#1d3b52"), false)
			_glow(water, Color("#2a5b7a"), 0.1)
			for x in [-0.95, 0.95]:
				_box(root, Vector3(x, 1.4, 0), Vector3(0.12, 1.9, 0.12), Color("#6b4a2b"), false)
			var top := MeshInstance3D.new()
			var p := PrismMesh.new()
			p.size = Vector3(2.4, 0.6, 1.4)
			top.mesh = p
			top.material_override = _mat(Color("#5a3b26"))
			top.position = Vector3(0, 2.6, 0)
			root.add_child(top)
		"tower":
			_box(root, Vector3(0, 4.0, 0), Vector3(2.6, 8.0, 2.6), stone, true)
			_box(root, Vector3(0, 8.3, 0), Vector3(3.4, 0.6, 3.4), stone.darkened(0.15), true)
			_box(root, Vector3(0, 1.1, 1.32), Vector3(0.9, 2.1, 0.06), Color("#4a3020"), false)  # puerta
			out.door = {"offset": Vector3(0, 0, 1.9), "kind": "tower", "size": Vector3(2.6, 8.0, 2.6), "shape": "box"}
			out.gallery = Vector3(0, 8.65, 0.9)
			out.stand = Vector3(1.4, 0, 2.0)
			for k in 4:
				var a := k * TAU / 4.0
				var win := _box(root, Vector3(sin(a) * 1.32, 6.0, cos(a) * 1.32), Vector3(0.5, 0.8, 0.05), Color("#1a1a1a"), false)
				win.rotation.y = a
		"market":
			var cloths := [Color("#c0392b"), Color("#e6b33a"), Color("#2e86c1")]
			for k in 3:
				var x := -3.2 + k * 3.2
				_box(root, Vector3(x, 0.45, 0), Vector3(2.2, 0.9, 1.0), Color("#7a5a3a"), true)
				for px in [-1.0, 1.0]:
					_box(root, Vector3(x + px, 1.2, -0.45), Vector3(0.08, 2.4, 0.08), Color("#5a3b26"), false)
				var awning := _box(root, Vector3(x, 2.35, 0.1), Vector3(2.4, 0.05, 1.6), cloths[k], false)
				awning.rotation_degrees.x = 10.0
				for f in 3:
					_box(root, Vector3(x - 0.6 + f * 0.6, 0.98, 0.1), Vector3(0.35, 0.15, 0.35), Color.from_hsv(rng.randf(), 0.6, 0.8), false)
			out.stand = Vector3(0, 0, -1.2)
		"dock":
			for k in 10:
				_box(root, Vector3(0, 0.35, -k * 0.9), Vector3(2.2, 0.12, 0.8), Color("#7a5a3a"), true)
			for k in 5:
				for x in [-1.05, 1.05]:
					_cyl(root, Vector3(x, 0.1, -k * 2.0), 0.1, 0.1, 1.2, Color("#5a3b26"), false)
			out.stand = Vector3(0.6, 0.4, -1.0)
		"greenhouse":
			var frame := Color("#cfd8dc")
			for x in [-2.5, 2.5]:
				for z in [-1.8, 1.8]:
					_box(root, Vector3(x, 1.2, z), Vector3(0.08, 2.4, 0.08), frame, false)
			var glass := _box(root, Vector3(0, 1.2, 0), Vector3(5.0, 2.4, 3.6), Color(0.75, 0.95, 0.85, 0.25), false)
			var gm := _mat(Color(0.75, 0.95, 0.85, 0.22))
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.material_override = gm
			_box(root, Vector3(0, 1.2, 0), Vector3(5.0, 2.4, 3.6), Color.WHITE, true).visible = false  # el cristal no se atraviesa…
			out.door = {"offset": Vector3(0, 0, 2.3), "kind": "greenhouse", "size": Vector3(5.0, 2.4, 3.6), "shape": "box"}  # …se entra por la puerta
			for k in 6:
				var plant := _cyl(root, Vector3(-2.0 + (k % 3) * 2.0, 0.45, -0.8 + (k / 3) * 1.6), 0.35, 0.2, 0.9, Color("#3f8f4a"), false)
				plant.name = "Planta"
			out.stand = Vector3(0, 0, 2.4)
		"mine":
			var mound := _cyl(root, Vector3(0, 1.6, -2.5), 1.5, 4.5, 3.2, stone.darkened(0.2), true)
			mound.name = "Ladera"
			_box(root, Vector3(0, 1.1, -0.4), Vector3(2.2, 2.2, 0.3), Color("#0d0d0d"), false)  # la boca
			for x in [-1.2, 1.2]:
				_box(root, Vector3(x, 1.2, -0.2), Vector3(0.22, 2.4, 0.22), Color("#6b4a2b"), true)
			_box(root, Vector3(0, 2.45, -0.2), Vector3(2.7, 0.22, 0.25), Color("#6b4a2b"), false)
			for k in 6:
				_box(root, Vector3(-0.4 + (k % 2) * 0.8, 0.02, 0.4 + k * 0.6), Vector3(0.1, 0.06, 0.5), Color("#555"), false)
			_box(root, Vector3(0.5, 0.45, 1.6), Vector3(0.9, 0.6, 1.3), Color("#5c6168"), true)  # vagoneta
			out.stand = Vector3(1.8, 0, 0.8)
			out.door = {"offset": Vector3(0, 0, 0.3), "kind": "mine", "size": Vector3(3.0, 3.0, 3.0), "shape": "box"}
		"marker":  # piedras de verdad, apiladas
			var made := 0
			for k in 4:
				var rock := AssetLibrary.nature("barren", 2, rng)
				if rock:
					AssetLibrary.place(root, rock, Vector3(rng.randf_range(-0.08, 0.08), k * 0.32, 0), 0.42 - k * 0.06, rng.randf() * TAU, k == 0)
					made += 1
			if made == 0:
				for k in 4:
					var s := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.4 - k * 0.07
					sm.height = (0.4 - k * 0.07) * 1.3
					s.mesh = sm
					s.material_override = _mat(stone.lightened(k * 0.05))
					s.position = Vector3(0, 0.25 + k * 0.38, 0)
					root.add_child(s)
	return out


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


static func _glow(mi: MeshInstance3D, c: Color, energy: float) -> void:
	var m := _mat(mi.material_override.albedo_color if mi.material_override else c)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	mi.material_override = m


static func _box(root: Node3D, pos: Vector3, size: Vector3, c: Color, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	root.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		root.add_child(body)
	return mi


static func _cyl(root: Node3D, pos: Vector3, r_top: float, r_bottom: float, h: float, c: Color, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position = pos
	root.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bottom)
		sh.height = h
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		root.add_child(body)
	return mi

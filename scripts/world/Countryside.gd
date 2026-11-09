class_name Countryside
extends Node3D
## El campo alrededor de Bahía de las Horas (v0.8.0): caminos de tierra que salen del pueblo,
## praderas con flores y sitios a los que ir — la granja (con ovejas y vacas), el lago (se pesca),
## el campamento, las ruinas, el mirador de la montaña, la cabaña del pescador y el cruce de
## caminos con su letrero. Pájaros en el cielo de día. Setas, moras y conchas que se recogen
## (vuelven a salir al día siguiente). Todo determinista: siempre en el mismo sitio.
##
## La forma del terreno (allanar donde hay algo, el hueco del lago) y el color (caminos, flores)
## son funciones estáticas y puras: las usan los hilos que construyen el terreno por trozos.

const SPOTS := [
	{"id": "granja", "name": "la granja", "kind": "farm", "pos": Vector2(-230, -70), "r": 26.0},
	{"id": "lago", "name": "el lago", "kind": "lake", "pos": Vector2(-330, 60), "r": 34.0},
	{"id": "campamento", "name": "el campamento", "kind": "camp", "pos": Vector2(-150, -235), "r": 11.0},
	{"id": "ruinas", "name": "las ruinas", "kind": "ruins", "pos": Vector2(-125, 250), "r": 15.0},
	{"id": "mirador", "name": "el mirador", "kind": "lookout", "pos": Vector2(-560, -40), "r": 10.0},
	{"id": "cabana", "name": "la cabaña del pescador", "kind": "hut", "pos": Vector2(14, 172), "r": 9.0},
	{"id": "cruce", "name": "el cruce de caminos", "kind": "crossing", "pos": Vector2(-200, 20), "r": 5.0},
]
## Caminos de tierra (tramos rectos): del pueblo al cruce y de ahí a cada sitio.
const PATHS := [
	[Vector2(-48, -6), Vector2(-200, 20)], [Vector2(-200, 20), Vector2(-230, -70)], [Vector2(-200, 20), Vector2(-300, 52)],
	[Vector2(-360, 50), Vector2(-560, -40)], [Vector2(-12, -70), Vector2(-150, -235)], [Vector2(-12, 70), Vector2(-125, 250)],
	[Vector2(8, 66), Vector2(14, 172)],
]
const PATH_W := 1.7

static var _centers := {}          # id -> altura del terreno en el centro (antes de allanar)
static var _ready_noise := false

var scene: Node3D
var _ground: Callable
var _animals: Array = []
var _birds: Node3D
var _bird_t := 0.0


## Prepara lo que usan los hilos (llamar en el hilo principal, antes de construir el terreno).
static func prepare(base_height: Callable) -> void:
	_ready_noise = true
	_centers.clear()
	for s in SPOTS:
		_centers[s.id] = float(base_height.call(s.pos.x, s.pos.y))


## Allana el terreno donde hay algo y cava el lago.
static func shape(x: float, z: float, h: float) -> float:
	if _centers.is_empty():
		return h
	for s in SPOTS:
		var d := Vector2(x, z).distance_to(s.pos)
		var r: float = s.r
		if d > r * 1.6:
			continue
		var base: float = maxf(float(_centers[s.id]), 0.6)
		if s.kind == "lake":
			var bed := lerpf(-2.6, base, smoothstep(r * 0.55, r, d))  # el fondo del lago, bajo el nivel del agua
			return lerpf(bed, h, smoothstep(r, r * 1.5, d))
		return lerpf(base, h, smoothstep(r * 0.8, r * 1.6, d))
	return h


static func _path_dist(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for seg in PATHS:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Color del suelo del campo: caminos de tierra, manchas de flores y tierra en la granja.
static func tint(x: float, z: float, h: float, c: Color) -> Color:
	if h < 0.2:
		return c
	var pd := _path_dist(x, z)
	if pd < PATH_W + 1.0:
		return c.lerp(Color("#8a7350"), 1.0 - smoothstep(PATH_W - 0.4, PATH_W + 1.0, pd))
	if h < 6.0 and _ready_noise:
		var f := _noise(x, z)
		if f > 0.35:  # pradera con flores: puntitos de color sobre la hierba
			var pick := absf(sin(x * 12.9898 + z * 78.233) * 43758.5453)
			pick -= floorf(pick)
			var flower: Color = [Color("#e8d24a"), Color("#c46fd0"), Color("#f2f2f2"), Color("#e86a4a")][int(pick * 4.0) % 4]
			c = c.lerp(c.lerp(flower, 0.5), smoothstep(0.4, 0.7, f) * 0.35)
	var farm := Vector2(x, z).distance_to(SPOTS[0].pos)
	if farm < 20.0 and absf(fmod(absf(x), 4.0) - 2.0) < 0.7 and x < SPOTS[0].pos.x:  # surcos del huerto
		c = c.lerp(Color("#6b4f33"), 0.7)
	return c


## ¿Hay flores aquí? (para poner matas de flores en los trozos)
static func flowery(x: float, z: float) -> bool:
	return _ready_noise and _noise(x, z) > 0.45 and _path_dist(x, z) > PATH_W + 1.5


## Ruido suave (-1..1) para las praderas de flores. Sin recursos (FastNoiseLite en una variable
## estática daba fallos al cerrar el juego): valor por celda interpolado.
static func _noise(x: float, z: float) -> float:
	var fx := x * 0.035
	var fz := z * 0.035
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := _cell(ix, iz)
	var b := _cell(ix + 1, iz)
	var c := _cell(ix, iz + 1)
	var d := _cell(ix + 1, iz + 1)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz) * 1.6 - 0.6


static func _cell(ix: int, iz: int) -> float:
	var h := absf(sin(float(ix) * 127.1 + float(iz) * 311.7 + 4242.0) * 43758.5453)
	return h - floorf(h)


## ¿Dejar libre de árboles? (caminos y sitios)
static func keep_clear(x: float, z: float) -> bool:
	if _path_dist(x, z) < PATH_W + 2.5:
		return true
	for s in SPOTS:
		if Vector2(x, z).distance_to(s.pos) < float(s.r) * 1.3:
			return true
	return false


# --- Lo que hay en cada sitio ------------------------------------------------------------------

func build(s: Node3D, ground: Callable, places: Dictionary) -> void:
	scene = s
	_ground = ground
	name = "Campo"
	for spot in SPOTS:
		var p2: Vector2 = spot.pos
		var at := Vector3(p2.x, float(ground.call(p2.x, p2.y)), p2.y)
		places[spot.name] = at
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(spot.id)
		match str(spot.kind):
			"farm": _farm(at, rng, ground)
			"lake": _lake(at, rng, ground)
			"camp": _camp(at, rng)
			"ruins": _ruins(at, rng)
			"lookout": _lookout(at)
			"hut": _hut(at, rng)
			"crossing": _crossing(at)
	# Pescar también desde la punta del muelle del pueblo
	_fishing_spot(Vector3(38.0, 0.6, 6.0), "el muelle")
	_town_life(ground)
	_birds = Node3D.new()
	_birds.name = "Pajaros"
	add_child(_birds)
	for i in 7:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.05, 0.22)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#2a2a2e")
		b.material_override = m
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.set_meta("phase", i * 0.9)
		_birds.add_child(b)


func _sign(at: Vector3, text: String) -> void:
	PropsBuilder._box(self, at + Vector3(0, 0.7, 0), Vector3(0.12, 1.4, 0.12), Color("#6a4b2e"), true)
	PropsBuilder._box(self, at + Vector3(0, 1.35, 0), Vector3(1.4, 0.45, 0.06), Color("#8a6640"), false)
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.006
	l.modulate = Color("#2b1d10")
	l.outline_size = 0
	l.position = at + Vector3(0, 1.35, 0.04)
	l.double_sided = true
	l.visibility_range_end = 16.0
	add_child(l)
	Examine.sign(self, at + Vector3(0, 1.0, 0), text, {"Granja": "Granja. Huevos, leche y verdura de temporada. Se vende en la puerta.", "Lago": "Lago. Se permite pescar con caña. Prohibido tirar basura.", "Campamento": "Campamento. Apaga el fuego antes de irte.", "Ruinas": "Ruinas. Nadie sabe bien quién las levantó. Cuidado con las piedras sueltas.", "Mirador": "Mirador. Desde aquí se ve todo Bahía de las Horas y el mar.", "Cabaña": "Cabaña del pescador. Si tomas la caña, devuélvela."}.get(text, text))


## Un edificio del campo con puerta de verdad (se entra con E), redondo por dentro si lo es fuera.
func _enterable(root: Node3D, id: String, label: String) -> void:
	if scene == null or not scene.has_method("_add_door") or scene.get("_interiors") == null:
		return
	root.set_meta("size", AssetLibrary.bounds(root).size)
	scene.call("_add_door", root, "house", id, label)
	scene.get("_interiors").set_door_option(id, "shape", "round")


## Una barca que se usa (Subir con E), en el agua: si donde se pidió hay tierra, la más cercana orilla adentro.
func _real_boat(near: Vector3, model: String, length: float) -> void:
	var water := float(scene.get("_water_level")) if scene and scene.get("_water_level") != null else -0.45
	var spot := Vector3.INF
	for r in [0.0, 3.0, 5.0, 8.0, 11.0, 15.0, 20.0, 26.0, 34.0, 44.0, 56.0]:
		for k in 12:
			var a := k * TAU / 12.0
			var p: Vector3 = near + Vector3(cos(a), 0, sin(a)) * r
			if _ground.call(p.x, p.z) < water - 0.5:
				spot = p
				break
		if spot != Vector3.INF:
			break
	if spot == Vector3.INF:
		_model("ships_pack", model, near, 1.2, 0.4, true)  # sin agua cerca: se queda varada (y lo dice)
		return
	var boat := Boat.new()
	boat.water_level = water
	boat.ground_at = _ground
	add_child(boat)
	boat.position = Vector3(spot.x, water, spot.z)
	boat.rotation.y = randf() * TAU
	boat.setup("ships_pack", model, length)
	if scene and scene.get("_boats") != null:
		scene.get("_boats").append(boat)


func _model(pack: String, model: String, at: Vector3, height: float, yaw: float, collide: Variant = true) -> Node3D:
	var m := AssetLibrary.instance(pack, model)
	if m == null:
		return null
	return AssetLibrary.place(self, m, at, height, yaw, collide)


func _fence_ring(center: Vector3, half: Vector2, ground: Callable, gap_side: int = 0) -> void:
	var posts := []
	var n := 10
	for e in 4:
		for i in n:
			var t := float(i) / n
			var p := Vector2()
			match e:
				0: p = Vector2(lerpf(-half.x, half.x, t), -half.y)
				1: p = Vector2(half.x, lerpf(-half.y, half.y, t))
				2: p = Vector2(lerpf(half.x, -half.x, t), half.y)
				3: p = Vector2(-half.x, lerpf(half.y, -half.y, t))
			if e == gap_side and i in [4, 5]:
				continue  # la entrada
			posts.append(Vector2(center.x + p.x, center.z + p.y))
	for i in posts.size():
		var a: Vector2 = posts[i]
		var y := float(ground.call(a.x, a.y))
		PropsBuilder._box(self, Vector3(a.x, y + 0.55, a.y), Vector3(0.12, 1.1, 0.12), Color("#7a5a3a"), true)
		if i + 1 < posts.size() and (posts[i + 1] as Vector2).distance_to(a) < half.x * 2.0 / n + 0.5:
			var b: Vector2 = posts[i + 1]
			var mid := (a + b) / 2.0
			var rail := PropsBuilder._box(self, Vector3(mid.x, y + 0.8, mid.y), Vector3(a.distance_to(b), 0.08, 0.06), Color("#8a6a48"), true)
			rail.rotation.y = -atan2(b.y - a.y, b.x - a.x)


func _farm(at: Vector3, rng: RandomNumberGenerator, ground: Callable) -> void:
	_model("buildings_pack_3", "1Story_GableRoof_Mat", at + Vector3(8, 0, -10), 6.0, 0.0)
	_model("kenney_cars", "tractor", at + Vector3(2, 0, -14), 2.4, 0.6)
	_fence_ring(at + Vector3(-2, 0, 8), Vector2(10, 7), ground, 0)
	PropsBuilder._box(self, at + Vector3(13, 0.4, 6), Vector3(2.4, 0.8, 0.8), Color("#6a4b2e"), true)  # comedero
	Decor.landmark(self, at, "la granja: un granero, un tractor, un huerto y un corral con ovejas y vacas", "farm")
	_sign(at + Vector3(-10, 0, -2), "Granja")
	for i in 7:
		var cow := i < 2
		var a := _animal(cow, rng)
		a.position = at + Vector3(-2 + rng.randf_range(-7, 7), 0, 8 + rng.randf_range(-5, 5))
		a.set_meta("goal", a.position)
		a.set_meta("pen", [at + Vector3(-2, 0, 8), Vector2(9, 6)])
		_animals.append(a)
	_forage(at + Vector3(14, 0, -2), "Recoger moras", "Moras", "Un puñado de moras del zarzal de la granja.", "nourish", "BushBerries_1")


func _animal(cow: bool, rng: RandomNumberGenerator) -> Node3D:
	var a := Node3D.new()
	a.name = "Vaca" if cow else "Oveja"
	add_child(a)
	var col := Color("#3b3027") if cow and rng.randf() < 0.5 else (Color("#efe9dc") if not cow else Color("#e6dfd3"))
	var s := 1.0 if cow else 0.62
	PropsBuilder._box(a, Vector3(0, 0.95 * s, 0), Vector3(0.75, 0.7, 1.5) * s, col, false)
	PropsBuilder._box(a, Vector3(0, 1.25 * s, 0.85 * s), Vector3(0.42, 0.42, 0.5) * s, col.darkened(0.25) if not cow else col, false)
	for lx in [-0.25, 0.25]:
		for lz in [-0.55, 0.55]:
			PropsBuilder._box(a, Vector3(lx * s, 0.3 * s, lz * s), Vector3(0.14, 0.6, 0.14) * s, Color("#2a2420"), false)
	if cow and col.v < 0.5:
		PropsBuilder._box(a, Vector3(0.2 * s, 1.1 * s, -0.2), Vector3(0.36, 0.3, 0.5) * s, Color("#f0ece4"), false)
	a.set_meta("goal", a.position)
	a.set_meta("wait", rng.randf_range(0.0, 4.0))
	return a


func _lake(at: Vector3, rng: RandomNumberGenerator, _ground: Callable) -> void:
	# Un embarcadero de tablas que entra en el agua, una barca y un banco
	var shore := at + Vector3(0, 0, 31)
	shore.y = maxf(shore.y, 0.2)
	for i in 6:
		PropsBuilder._box(self, Vector3(at.x, 0.15, at.z + 30 - i * 1.2), Vector3(1.6, 0.12, 1.1), Color("#7a5a3a"), true)
	for i in [0, 5]:
		for sx in [-0.75, 0.75]:
			PropsBuilder._box(self, Vector3(at.x + sx, -0.6, at.z + 30 - i * 1.2), Vector3(0.14, 1.6, 0.14), Color("#5a4029"), true)
	_real_boat(Vector3(at.x + 3, 0, at.z + 24), "Lifeboat", 3.6)
	_fishing_spot(Vector3(at.x, 0.3, at.z + 24.5), "el lago")
	Decor.landmark(self, at, "el lago: agua dulce y tranquila, un embarcadero de madera y una barca", "lake")
	_sign(shore + Vector3(3, 0, 2), "Lago")
	_forage(at + Vector3(-30, 0, 8), "Recoger setas", "Setas", "Unas setas del borde del bosque. Mejor cocinadas.", "nourish", "")


func _camp(at: Vector3, rng: RandomNumberGenerator) -> void:
	_model("survival_pack", "Tent", at + Vector3(-3, 0, -2), 1.8, 0.4)
	_model("survival_pack", "Bonfire_Fire", at + Vector3(1, 0, 1), 0.6, 0.0, true)
	for i in 3:
		var a := TAU * i / 3.0 + 0.3
		_model("survival_pack", "WoodLog", at + Vector3(1 + cos(a) * 1.8, 0, 1 + sin(a) * 1.8), 0.4, a, true)
	var fire := OmniLight3D.new()
	fire.light_color = Color("#ff9a4a")
	fire.omni_range = 7.0
	fire.light_energy = 1.4
	fire.position = at + Vector3(1, 0.8, 1)
	fire.distance_fade_enabled = true
	fire.distance_fade_begin = 60.0
	add_child(fire)
	Decor.landmark(self, at, "un campamento en el bosque: una tienda de campaña, una hoguera encendida y troncos para sentarse", "camp")
	_sign(at + Vector3(5, 0, -3), "Campamento")
	_forage(at + Vector3(-6, 0, 4), "Recoger setas", "Setas", "Unas setas de bosque.", "nourish", "")


func _ruins(at: Vector3, rng: RandomNumberGenerator) -> void:
	var stone := Color("#8f8a80")
	for i in 9:  # lo que queda de los muros
		var a := TAU * i / 9.0
		var h := rng.randf_range(0.6, 3.2)
		var b := PropsBuilder._box(self, at + Vector3(cos(a) * 8, h / 2.0, sin(a) * 8), Vector3(3.2, h, 0.7), stone.darkened(rng.randf() * 0.2), true)
		b.rotation.y = -a + PI / 2
	for i in 3:  # columnas
		PropsBuilder._cylinder(self, at + Vector3(-2 + i * 2, 1.6, -1), 0.35, 0.35, rng.randf_range(1.5, 3.2), stone, true)
	Decor.landmark(self, at, "unas ruinas de piedra: muros caídos y columnas de algo muy antiguo", "ruins")
	_sign(at + Vector3(10, 0, 6), "Ruinas")
	_forage(at + Vector3(3, 0, 3), "Rebuscar entre las piedras", "Chatarra vieja", "Piezas de metal oxidado: alguien te daría algo por ellas.", "none", "")


func _lookout(at: Vector3) -> void:
	PropsBuilder._box(self, at + Vector3(0, 0.3, 0), Vector3(5, 0.25, 5), Color("#7a5a3a"), true)
	for sx in [-1, 1]:
		PropsBuilder._box(self, at + Vector3(sx * 2.45, 0.85, 0), Vector3(0.08, 0.9, 5), Color("#5a4029"), true)
	PropsBuilder._box(self, at + Vector3(0, 0.85, 2.45), Vector3(5, 0.9, 0.08), Color("#5a4029"), true)
	PropsBuilder._box(self, at + Vector3(0, 0.75, -1.5), Vector3(1.8, 0.08, 0.45), Color("#7a5a3a"), true)  # banco
	for bx in [-0.8, 0.8]:
		PropsBuilder._box(self, at + Vector3(bx, 0.55, -1.5), Vector3(0.08, 0.45, 0.4), Color("#5a4029"), true)
	Decor.landmark(self, at, "el mirador de la montaña: una plataforma de madera desde la que se ve el pueblo, el mar y las islas", "lookout")
	_sign(at + Vector3(3, 0, -3), "Mirador")


func _hut(at: Vector3, rng: RandomNumberGenerator) -> void:
	var hut := _model("buildings_pack_3", "1Story_RoundRoof_Mat", at + Vector3(-3, 0, 0), 4.2, PI / 2)
	if hut:
		_enterable.call_deferred(hut, "choza", "la cabaña del pescador")
	_real_boat(at + Vector3(6, 0, 3), "Boat", 4.0)
	Decor.landmark(self, at, "la cabaña del pescador en la playa (se puede entrar), con su barca en la orilla y una caña vieja apoyada en la pared", "hut")
	_sign(at + Vector3(2, 0, -4), "Cabaña")
	var rod := Interactable.create(self, at + Vector3(0.5, 1.0, 2.0), 1.6, "Tomar la caña vieja", func(_p): _take_rod())
	rod.name = "Cana"
	PropsBuilder._cylinder(self, at + Vector3(0.5, 1.0, 2.0), 0.02, 0.03, 2.0, Color("#6a4b2e"), false).rotation.z = 0.3
	_forage(at + Vector3(10, 0, -4), "Recoger conchas", "Conchas", "Conchas de la playa. Bonitas; poco más.", "none", "")


func _crossing(at: Vector3) -> void:
	PropsBuilder._box(self, at + Vector3(0, 1.2, 0), Vector3(0.14, 2.4, 0.14), Color("#6a4b2e"), true)
	var arms := [["Pueblo →", 0.15], ["← Lago", PI - 0.3], ["Granja ↑", -1.4]]
	for i in arms.size():
		var arm := Node3D.new()
		arm.position = at + Vector3(0, 2.1 - i * 0.35, 0)
		arm.rotation.y = float(arms[i][1])
		add_child(arm)
		PropsBuilder._box(arm, Vector3(0.6, 0, 0), Vector3(1.2, 0.26, 0.05), Color("#8a6640"), false)
		var l := Label3D.new()
		l.text = str(arms[i][0])
		l.font_size = 32
		l.pixel_size = 0.005
		l.modulate = Color("#2b1d10")
		l.outline_size = 0
		l.double_sided = true
		l.position = Vector3(0.6, 0, 0.03)
		l.visibility_range_end = 18.0
		arm.add_child(l)
	Decor.landmark(self, at, "un cruce de caminos de tierra con un poste de letreros: al pueblo, al lago y a la granja", "crossing")


# --- Recoger y pescar ------------------------------------------------------------------------

func _forage(at: Vector3, prompt: String, item: String, desc: String, effect: String, model: String) -> void:
	make_forage(self, scene, at, prompt, item, desc, effect, model)


## Algo que se recoge del suelo (setas, moras, conchas, minerales…): vuelve a salir al día siguiente.
static func make_forage(parent: Node3D, scene_ref: Node, at: Vector3, prompt: String, item: String, desc: String, effect: String, model: String) -> void:
	var holder := Node3D.new()
	holder.position = at
	parent.add_child(holder)
	var key := "%s_%d_%d" % [GameState.current_location(), int(at.x), int(at.z)]
	if not model.is_empty():
		var m := AssetLibrary.instance("nature_pack", model)
		if m:
			AssetLibrary.place(holder, m, Vector3.ZERO, 0.9, 0.0, "bush")
	else:
		var col := Color("#d8c9a8")
		if item == "Conchas" or item.begins_with("Concha"):
			col = Color("#f0e2d0")
		elif not (effect in ["nourish"]):
			col = Color("#9fd8ff") if item.contains("ristal") or item.contains("ielo") else Color("#6c6a70")
		for i in 4:
			PropsBuilder._sphere(holder, Vector3(randf_range(-0.4, 0.4), 0.08, randf_range(-0.4, 0.4)), 0.09 + randf() * 0.05, col, false)
	var it := Interactable.create(holder, Vector3(0, 0.6, 0), 1.3, prompt, func(_p): _pick(scene_ref, holder, key, item, desc, effect))
	it.name = "Recoger"
	var picked: Dictionary = WorldDB.get_state("forage", {})
	holder.visible = int(picked.get(key, -1)) != int(WorldClock.absolute_minutes() / 1440.0)
	Decor.landmark(parent, at, "%s en el suelo" % item.to_lower(), "forage")


static func _pick(scene_ref: Node, holder: Node3D, key: String, item: String, desc: String, effect: String) -> void:
	if not holder.visible:
		return
	var picked: Dictionary = WorldDB.get_state("forage", {})
	picked[key] = int(WorldClock.absolute_minutes() / 1440.0)
	WorldDB.set_state("forage", picked)
	holder.visible = false
	if scene_ref and scene_ref.get("_player"):
		scene_ref.get("_player").play_gesture("pick_up", 1.2)
	var notes := Actions.execute("", [{"type": "give_item", "item_name": item, "item_description": desc, "item_effect": effect}])
	if scene_ref and scene_ref.get("_ui") and scene_ref.get("_ui").has_method("toast"):
		scene_ref.get("_ui").toast("Recoges: %s." % item.to_lower() if notes.is_empty() else str(notes[0]))


func _take_rod() -> void:
	if not Inventory.find_by_name("caña").is_empty():
		_toast("Ya tienes una caña.")
		return
	Actions.execute("", [{"type": "give_item", "item_name": "Caña de pescar", "item_description": "Una caña vieja del pescador, aún sirve. Con ella se pesca en el muelle o en el lago.", "item_effect": "tool"}])
	_toast("Tomas la caña vieja. Ahora puedes pescar en el muelle o en el lago.")


var _fishing := {}   # estado de la pesca en curso


func _fishing_spot(at: Vector3, where: String) -> void:
	var it := Interactable.create(self, at, 1.8, "Pescar", func(_p): _fish(where))
	it.name = "Pescar"
	Decor.landmark(self, at, "un buen sitio para pescar en %s" % where, "fishing")


func _fish(where: String) -> void:
	if not _fishing.is_empty():
		return
	if Inventory.find_by_name("caña").is_empty():
		_toast("Necesitas una caña de pescar (el pescador tiene una vieja en su cabaña, en la playa del sur).")
		return
	var player: Node = scene.get("_player") if scene else null
	if player == null:
		return
	player.play_gesture("fish", 60.0)
	player.hold_position = true
	_fishing = {"t": randf_range(4.0, 10.0), "bite": -1.0, "where": where}
	_toast("Lanzas el anzuelo y esperas… (E cuando pique)")


func _process(delta: float) -> void:
	_move_animals(delta)
	_update_puddles(delta)
	_move_birds(delta)
	if _fishing.is_empty():
		return
	var player: Node = scene.get("_player") if scene else null
	if player == null or not player.hold_position:  # te moviste: dejas de pescar
		_fishing = {}
		return
	if float(_fishing.bite) < 0.0:
		_fishing.t = float(_fishing.t) - delta
		if float(_fishing.t) <= 0.0:
			_fishing.bite = 1.4
			Sfx.at(self, "step_water", player.global_position + Vector3(0, 0.2, 0))
			_toast("¡Pica! ¡Ahora! (E)")
	else:
		_fishing.bite = float(_fishing.bite) - delta
		if Input.is_action_just_pressed("interact"):
			_catch(player, true)
		elif float(_fishing.bite) <= 0.0:
			_catch(player, false)


func _catch(player: Node, ok: bool) -> void:
	_fishing = {}
	player.stop_gesture()
	player.hold_position = false
	if not ok:
		_toast("Se te escapó. Otra vez será.")
		return
	var fish: Array = [["Sardina", "Una sardina plateada, pequeña."], ["Lubina", "Una lubina de buen tamaño."], ["Trucha", "Una trucha de agua dulce."],
		["Pargo", "Un pargo rojo; en la cafetería se lo comerían."]][randi() % 4]
	Actions.execute("", [{"type": "give_item", "item_name": fish[0], "item_description": fish[1] + " Se puede comer (mejor cocinado) o vender.", "item_effect": "nourish"}])
	WorldClock.advance(15)
	_toast("¡Pescas: %s!" % fish[0].to_lower())


func _toast(text: String) -> void:
	if scene and scene.get("_ui") and scene.get("_ui").has_method("toast"):
		scene.get("_ui").toast(text)


# --- Vida en el pueblo: perros y gatos, tendederos, charcos al llover -------------------------

var _puddles: Array = []
var _puddle_t := 0.0


func _town_life(ground: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	# Perros y gatos que deambulan por las calles (cada uno por su zona)
	var homes := [Vector3(-12, 0, -30), Vector3(-14, 0, 22), Vector3(4, 0, 40), Vector3(-30, 0, 0)]
	for i in homes.size():
		var dog := i % 2 == 0
		var a := _pet(dog, rng)
		var h: Vector3 = homes[i]
		a.position = h + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		a.set_meta("goal", a.position)
		a.set_meta("pen", [h, Vector2(9, 9)])
		_animals.append(a)
		Decor.landmark(a, Vector3.ZERO, "un perro del barrio" if dog else "un gato callejero", "pet")
	# Tendederos con ropa detrás de algunas casas
	var doors: Dictionary = scene.get("_interiors").doors() if scene and scene.get("_interiors") else {}
	var k := 0
	for id in doors:
		if k >= 4 or not str(id).begins_with("casa"):
			continue
		var b: Dictionary = doors[id].get("building", {})
		if b.is_empty():
			continue
		k += 1
		var front := Vector3(sin(float(b.yaw)), 0, cos(float(b.yaw)))
		var side := front.cross(Vector3.UP)
		var back: Vector3 = (b.base as Vector3) - front * ((b.size as Vector3).z / 2.0 + 2.2)
		back.y = float(ground.call(back.x, back.z))
		for sx in [-1.2, 1.2]:
			PropsBuilder._cylinder(self, back + side * sx + Vector3(0, 0.9, 0), 0.03, 0.03, 1.8, Color("#6a6a6a"), false)
		var line := PropsBuilder._box(self, back + Vector3(0, 1.75, 0), Vector3(2.4, 0.01, 0.01), Color("#dddddd"), false)
		line.rotation.y = atan2(side.x, side.z) + PI / 2
		for c in 4:
			var cloth := PropsBuilder._box(self, back + side * (-0.9 + c * 0.6) + Vector3(0, 1.45, 0), Vector3(0.45, 0.55, 0.02), Color.from_hsv(rng.randf(), 0.45, 0.85), false)
			cloth.rotation.y = atan2(side.x, side.z) + PI / 2
		Decor.landmark(self, back, "un tendedero con ropa secándose", "laundry")
	# Charcos en la calle (solo se ven cuando llueve)
	for i in 14:
		var p := Vector3(rng.randf_range(-7.5, -2.5), 0, rng.randf_range(-55, 55))
		p.y = float(ground.call(p.x, p.z)) + 0.02
		var pud := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.4, 1.1)
		cm.bottom_radius = cm.top_radius
		cm.height = 0.01
		pud.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.14, 0.16, 0.7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.6
		m.roughness = 0.05
		pud.material_override = m
		pud.scale = Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
		pud.position = p
		pud.visible = false
		pud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pud)
		_puddles.append(pud)


func _pet(dog: bool, rng: RandomNumberGenerator) -> Node3D:
	var a := Node3D.new()
	a.name = "Perro" if dog else "Gato"
	add_child(a)
	var col: Color = [Color("#8a5a2b"), Color("#2b2b2b"), Color("#d8c7a8"), Color("#a06a3a")][rng.randi() % 4] if dog else [Color("#e08a3a"), Color("#3a3a3a"), Color("#d8d0c4")][rng.randi() % 3]
	var s := 0.55 if dog else 0.32
	PropsBuilder._box(a, Vector3(0, 0.55 * s, 0), Vector3(0.35, 0.3, 0.8) * s, col, false)
	PropsBuilder._box(a, Vector3(0, 0.8 * s, 0.5 * s), Vector3(0.28, 0.26, 0.3) * s, col, false)
	PropsBuilder._box(a, Vector3(0, 0.75 * s, -0.48 * s), Vector3(0.06, 0.06, 0.35) * s, col, false).rotation.x = -0.6
	for lx in [-0.12, 0.12]:
		for lz in [-0.28, 0.28]:
			PropsBuilder._box(a, Vector3(lx * s, 0.2 * s, lz * s), Vector3(0.08, 0.4, 0.08) * s, col.darkened(0.2), false)
	a.set_meta("wait", rng.randf_range(0.0, 3.0))
	return a


func _update_puddles(delta: float) -> void:
	_puddle_t -= delta
	if _puddle_t > 0.0 or _puddles.is_empty():
		return
	_puddle_t = 2.0
	var wet := Weather.current() in ["rain", "storm"]
	for pd in _puddles:
		(pd as Node3D).visible = wet


# --- Animales y pájaros ------------------------------------------------------------------------

func _move_animals(delta: float) -> void:
	for a in _animals:
		var an: Node3D = a
		var w: float = float(an.get_meta("wait")) - delta
		var goal: Vector3 = an.get_meta("goal")
		if w > 0.0:
			an.set_meta("wait", w)
			continue
		var to := goal - an.position
		to.y = 0.0
		if to.length() < 0.3:
			var pen: Array = an.get_meta("pen")
			var c: Vector3 = pen[0]
			var half: Vector2 = pen[1]
			an.set_meta("goal", c + Vector3(randf_range(-half.x, half.x), 0, randf_range(-half.y, half.y)))
			an.set_meta("wait", randf_range(3.0, 9.0))  # pasta un rato
			continue
		an.position += to.normalized() * 0.6 * delta
		an.rotation.y = lerp_angle(an.rotation.y, atan2(to.x, to.z), 3.0 * delta)
		if scene and scene.has_method("ground_at"):
			an.position.y = float(scene.call("ground_at", an.position.x, an.position.z))


func _move_birds(delta: float) -> void:
	if _birds == null:
		return
	var day := WorldClock.night() < 0.4 and Weather.current() != "rain"
	_birds.visible = day
	if not day:
		return
	_bird_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# La bandada da vueltas por el cielo a tu alrededor (a veces cerca, a veces lejos)
	var center := cam.global_position + Vector3(sin(_bird_t * 0.05) * 60.0, 28.0, cos(_bird_t * 0.04) * 60.0)
	for b in _birds.get_children():
		var ph: float = b.get_meta("phase")
		var a := _bird_t * 0.35 + ph * 0.25
		var target := center + Vector3(cos(a) * 18.0 + sin(ph) * 4.0, sin(_bird_t * 0.8 + ph) * 1.5, sin(a) * 18.0 + cos(ph) * 4.0)
		var bn := b as Node3D
		bn.global_position = bn.global_position.lerp(target, clampf(0.8 * delta, 0.0, 1.0)) if bn.global_position.distance_to(target) < 80.0 else target
		bn.rotation.y = -a
		bn.rotation.z = sin(_bird_t * 9.0 + ph) * 0.5  # aletean

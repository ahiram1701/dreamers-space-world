class_name StarSystem
extends RefCounted
## El sistema solar de este mundo: un sol, varios planetas (el tuyo entre ellos), lunas, un
## cinturón de asteroides y una estación orbital. Se genera una vez por mundo, con su semilla,
## y se guarda (también qué lugar hay en la superficie de cada planeta cuando aterrizas).
## La escala está comprimida para que se pueda volar (un planeta mide cientos de metros de radio
## y las órbitas, kilómetros); el modo crucero acorta los viajes largos.

const KINDS := {
	"terran": {"label": "templado, con mares y bosques", "biome": "temperate", "colors": ["#3b7bc4", "#4f8a3a", "#e8e2d4"], "gravity": [0.8, 1.2], "land": true},
	"desert": {"label": "desierto de arena roja", "biome": "desert", "colors": ["#c47a3b", "#e0b070", "#8a4b2f"], "gravity": [0.4, 0.9], "land": true},
	"ice": {"label": "helado", "biome": "ice", "colors": ["#dfe9f2", "#9fc4e0", "#ffffff"], "gravity": [0.3, 0.8], "land": true},
	"jungle": {"label": "cubierto de selva", "biome": "jungle", "colors": ["#2f6b4f", "#4f8a3a", "#1d4030"], "gravity": [0.9, 1.4], "land": true},
	"ocean": {"label": "un océano casi sin tierra", "biome": "ocean", "colors": ["#1d4f8a", "#2a8c9c", "#e8e2d4"], "gravity": [0.9, 1.3], "land": true},
	"volcanic": {"label": "volcánico, con ríos de lava", "biome": "volcanic", "colors": ["#2b2220", "#c0392b", "#5a2e2e"], "gravity": [0.8, 1.5], "land": true},
	"crystal": {"label": "de cristales gigantes", "biome": "crystal", "colors": ["#7b3f8c", "#b8e0f0", "#3a2a5a"], "gravity": [0.5, 1.0], "land": true},
	"barren": {"label": "rocoso y sin aire, como una luna", "biome": "barren", "colors": ["#8a8f96", "#5a5f66", "#b8bcc2"], "gravity": [0.15, 0.5], "land": true},
	"gas": {"label": "un gigante gaseoso (no tiene superficie)", "biome": "void", "colors": ["#d8b48a", "#a0522d", "#e8e2d4"], "gravity": [2.0, 3.0], "land": false},
}
const SYL := ["ka", "re", "to", "mi", "sa", "lo", "ven", "dra", "ki", "nu", "tal", "or", "es", "zan", "pe", "ri", "um", "ax", "bel", "go"]


static func get_or_create() -> Dictionary:
	var sys: Dictionary = WorldDB.get_state("star_system", {})
	if not sys.is_empty():
		return sys
	sys = generate(hash(str(WorldDB.world_id)))
	WorldDB.set_state("star_system", sys)
	return sys


static func save(sys: Dictionary) -> void:
	WorldDB.set_state("star_system", sys)


static func _name(rng: RandomNumberGenerator) -> String:
	var n := ""
	for i in rng.randi_range(2, 3):
		n += SYL[rng.randi() % SYL.size()]
	return n.capitalize()


static func generate(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var star := _name(rng)
	var planets := []
	var count := rng.randi_range(5, 7)
	var home_at := rng.randi_range(1, 2)
	var orbit := 9000.0
	var kinds := KINDS.keys().filter(func(k): return k != "terran")
	for i in count:
		orbit += rng.randf_range(5000.0, 9000.0)
		var kind: String = "terran" if i == home_at else kinds[rng.randi() % kinds.size()]
		if i >= count - 2 and rng.randf() < 0.6:
			kind = "gas"
		var info: Dictionary = KINDS[kind]
		var gr: Array = info.gravity
		var radius := rng.randf_range(450.0, 800.0) * (2.2 if kind == "gas" else 1.0)
		var p := {"name": "Tierra" if i == home_at else _name(rng), "kind": kind, "radius": snappedf(radius, 1.0),
			"orbit": snappedf(orbit, 1.0), "angle": snappedf(rng.randf() * TAU, 0.001),
			"gravity": 1.0 if i == home_at else snappedf(rng.randf_range(gr[0], gr[1]), 0.05),
			"colors": info.colors, "rings": kind == "gas" and rng.randf() < 0.6, "location_id": "home" if i == home_at else "",
			"home": i == home_at}
		planets.append(p)
	var home: Dictionary = planets[home_at]
	var station := {"name": "Estación %s" % _name(rng), "kind": "station", "radius": 60.0, "orbit": home.orbit, "angle": home.angle + 0.06,
		"gravity": 0.9, "colors": ["#b8bcc2", "#2c5d8f", "#e8e2d4"], "location_id": "", "home": false}
	planets.append(station)
	return {"star": star, "planets": planets, "belt": snappedf(orbit * 0.55, 1.0)}


static func position_of(p: Dictionary) -> Vector3:
	var a := float(p.angle)
	return Vector3(cos(a), 0.0, sin(a)) * float(p.orbit)


static func home_planet(sys: Dictionary) -> Dictionary:
	for p in sys.planets:
		if p.get("home", false):
			return p
	return sys.planets[0]


static func describe(p: Dictionary) -> String:
	if p.kind == "station":
		return "estación orbital"
	return "planeta %s, gravedad %.1f g" % [KINDS[p.kind].label, float(p.gravity)]


static func can_land(p: Dictionary) -> bool:
	return p.kind == "station" or KINDS.get(p.kind, {}).get("land", false)

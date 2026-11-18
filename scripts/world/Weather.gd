class_name Weather
extends RefCounted
## El tiempo que hace. Determinista por mundo y franja de 2 horas de juego: sin guardar nada, el
## mismo mundo tiene el mismo tiempo a la misma hora. Lo pinta EnvironmentFX y lo sabe la IA.
##
## Es una cadena de Markov: cada franja sale de la anterior y solo puede pasar a un tiempo
## «vecino» (de despejado se nubla antes de llover; la tormenta llega después de la lluvia y se
## va igual). Las probabilidades cambian con la estación: en verano, temporada de lluvias con
## tormentas por la tarde; en invierno, seco, con niebla al amanecer.

const KINDS := ["clear", "cloudy", "rain", "fog", "wind", "storm"]
const LABELS := {"clear": "Despejado", "cloudy": "Nublado", "rain": "Lluvia", "fog": "Niebla", "wind": "Viento", "storm": "Tormenta"}
const SEASONS := ["primavera", "verano", "otoño", "invierno"]
const PHRASES := {"clear": "Hace buen tiempo, cielo despejado.", "cloudy": "El cielo está cubierto de nubes.",
	"rain": "Está lloviendo: todo está mojado y la gente busca dónde resguardarse.", "fog": "Hay niebla espesa; no se ve lejos.",
	"wind": "Sopla un viento fuerte que levanta arena y hace crujir las ventanas.",
	"storm": "Hay tormenta: llueve con fuerza, sopla el viento y caen rayos a lo lejos."}
const DRIZZLE := "Llovizna: cae una lluvia fina y todo empieza a estar húmedo."
const BLOCK_MINUTES := 120.0

## Transiciones por franja (desde → {hacia: peso}). Solo a tiempos vecinos.
const TRANSITIONS := {
	"clear": {"clear": 70, "cloudy": 18, "fog": 6, "wind": 6},
	"cloudy": {"clear": 25, "cloudy": 45, "rain": 22, "fog": 4, "wind": 4},
	"rain": {"cloudy": 35, "rain": 45, "storm": 15, "fog": 5},
	"storm": {"rain": 55, "storm": 35, "cloudy": 10},
	"fog": {"clear": 35, "cloudy": 30, "fog": 35},
	"wind": {"clear": 35, "cloudy": 25, "wind": 40},
}
## Cómo pesa cada estación sobre los tiempos de llegada.
const SEASON_BIAS := {
	"primavera": {"rain": 0.7, "storm": 0.6, "wind": 1.3},
	"verano": {"rain": 1.6, "storm": 1.8, "fog": 0.5},
	"otoño": {"rain": 1.1, "wind": 1.2, "fog": 1.2},
	"invierno": {"rain": 0.5, "storm": 0.3, "fog": 2.2, "clear": 1.2},
}
## Viento (m/s) típico de cada tiempo: [mínimo, máximo].
const WIND := {"clear": [1.0, 4.0], "cloudy": [2.5, 6.0], "rain": [4.0, 8.0], "fog": [0.0, 1.2],
	"wind": [9.0, 14.0], "storm": [12.0, 19.0]}
## Lo cubierto que está el cielo (0..1).
const COVER := {"clear": 0.08, "cloudy": 0.7, "rain": 0.92, "fog": 0.6, "wind": 0.35, "storm": 1.0}

## Fuerza un tiempo concreto (pruebas, escenas especiales). "" = el que toque.
static var forced := ""

## La cadena de este mundo, franja a franja desde el principio (índices de KINDS). Se calcula
## una vez y crece con el tiempo: 12 franjas por día de juego, nada.
static var _seq := PackedByteArray()
static var _seq_world := ""


static func _block() -> int:
	return int(floor(WorldClock.absolute_minutes() / BLOCK_MINUTES))


static func _season_of_block(block: int) -> String:
	return SEASONS[int(block * BLOCK_MINUTES / (1440.0 * 30.0)) % 4]


static func _hour_of_block(block: int) -> float:
	return fposmod(block * BLOCK_MINUTES / 60.0, 24.0)


## El tiempo de una franja: cada una sale de la anterior (la misma cadena para todo el mundo).
static func kind_at(block: int) -> String:
	var wid: String = WorldDB.world_id if WorldDB.is_loaded() else ""
	if wid != _seq_world:
		_seq_world = wid
		_seq = PackedByteArray()
	var seed_world := hash(wid)
	if _seq.is_empty():
		var rng0 := RandomNumberGenerator.new()
		rng0.seed = seed_world ^ 0x2545f491
		_seq.append(KINDS.find("clear" if rng0.randf() < 0.6 else "cloudy"))
	var b := maxi(block, 0)
	var rng := RandomNumberGenerator.new()
	while _seq.size() <= b:
		var i := _seq.size()
		rng.seed = seed_world ^ (i * 7919) ^ 0x5bd1e995
		_seq.append(KINDS.find(_step(KINDS[_seq[i - 1]], _season_of_block(i), _hour_of_block(i), rng.randf())))
	return KINDS[_seq[b]]


## Un paso de la cadena: del tiempo `from` al siguiente, con un número 0..1.
static func _step(from: String, season: String, hour: float, roll: float) -> String:
	var options: Dictionary = TRANSITIONS.get(from, TRANSITIONS.clear)
	var bias: Dictionary = SEASON_BIAS.get(season, {})
	var weights := {}
	var total := 0.0
	for to in options:
		var w := float(options[to]) * float(bias.get(to, 1.0))
		if to == "fog" and hour > 10.0 and hour < 20.0:
			w = 0.0  # la niebla se forma de noche y al amanecer
		if to == "storm" and season == "verano" and hour >= 14.0 and hour <= 20.0:
			w *= 1.6  # tormentas de la tarde en temporada de lluvias
		weights[to] = w
		total += w
	var acc := 0.0
	for to in weights:
		acc += float(weights[to]) / maxf(total, 0.001)
		if roll < acc:
			return to
	return from


static func current() -> String:
	if not forced.is_empty():
		return forced
	if not WorldDB.is_loaded():
		return "clear"
	var k := kind_at(_block())
	if k == "fog" and WorldClock.hour() > 11.0 and WorldClock.hour() < 20.0:
		return "cloudy"  # el sol ya levantó la niebla
	return k


## El tiempo de la franja anterior (para mezclar el cambio poco a poco).
static func previous() -> String:
	if not forced.is_empty() or not WorldDB.is_loaded():
		return current()
	return kind_at(maxi(_block() - 1, 0))


## Cuánto llevamos de la franja (0..1).
static func block_progress() -> float:
	return fposmod(WorldClock.absolute_minutes(), BLOCK_MINUTES) / BLOCK_MINUTES


## Fuerza del tiempo de ahora (0..1): la lluvia empieza como llovizna, arrecia y amaina.
static func intensity() -> float:
	if not forced.is_empty():
		return 1.0 if forced in ["rain", "storm", "fog", "wind"] else 0.0
	if not WorldDB.is_loaded():
		return 0.0
	var k := current()
	if k in ["clear", "cloudy"]:
		return 0.0
	var p := block_progress()
	var came := previous() == k
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(WorldDB.world_id) ^ (_block() * 31337)
	var peak := rng.randf_range(0.6, 1.0)
	var rise := 1.0 if came else smoothstep(0.0, 0.35, p)
	return clampf(peak * rise * (0.75 + 0.25 * sin(p * TAU * 2.0 + rng.randf() * TAU)), 0.15, 1.0)


static func label() -> String:
	if is_raining() and current() == "rain" and intensity() < 0.35:
		return "Llovizna"
	return LABELS.get(current(), "")


static func describe() -> String:
	if is_raining() and current() == "rain" and intensity() < 0.35:
		return DRIZZLE
	var s: String = PHRASES.get(current(), "")
	var w := wind_speed()
	if w >= 7.0 and current() not in ["wind", "storm"]:
		s += " Sopla bastante viento (%d km/h)." % roundi(w * 3.6)
	return s


static func is_raining() -> bool:
	return current() in ["rain", "storm"]


## Lo cubierto que está el cielo (0 despejado … 1 cerrado).
static func cloud_cover() -> float:
	return float(COVER.get(current(), 0.0))


## Velocidad del viento (m/s): según el tiempo, con rachas que suben y bajan.
static func wind_speed() -> float:
	var k := current()
	var r: Array = WIND.get(k, [1.0, 3.0])
	var m := WorldClock.absolute_minutes()
	var gust := 0.5 + 0.5 * sin(m * 0.21) * sin(m * 0.047 + 1.3)
	return lerpf(float(r[0]), float(r[1]), clampf(gust, 0.0, 1.0))


## De dónde a dónde sopla (unitario en XZ): gira despacio a lo largo del día (brisa del mar
## por la tarde, terral de madrugada).
static func wind_direction() -> Vector2:
	var seed_world := hash(WorldDB.world_id) if WorldDB.is_loaded() else 0
	var base := float(seed_world % 360) / 360.0 * TAU
	var h := WorldClock.hour()
	var a := base + sin((h - 15.0) / 24.0 * TAU) * 0.9
	return Vector2(cos(a), sin(a))


## Viento como vector (m/s) en XZ.
static func wind() -> Vector2:
	return wind_direction() * wind_speed()


## Estación del año: cada 30 días de juego cambia (el mundo empieza en primavera).
static func season() -> String:
	return SEASONS[int(WorldClock.absolute_minutes() / (1440.0 * 30.0)) % 4]


## Humedad relativa aproximada (%).
static func humidity() -> int:
	var base: float = {"primavera": 55.0, "verano": 78.0, "otoño": 68.0, "invierno": 50.0}[season()]
	base += {"rain": 18.0, "storm": 20.0, "fog": 25.0, "cloudy": 8.0, "wind": -8.0}.get(current(), 0.0)
	base -= sin((WorldClock.hour() - 9.0) / 24.0 * TAU) * 12.0  # más húmedo de madrugada
	return clampi(roundi(base), 15, 100)


## Temperatura aproximada (°C): estación, hora del día, nubes, lluvia y viento.
static func temperature() -> float:
	var base: float = {"primavera": 22.0, "verano": 27.0, "otoño": 21.0, "invierno": 16.0}[season()]
	var h := WorldClock.hour()
	# Con el cielo cubierto el día calienta menos y la noche enfría menos
	base += sin((h - 9.0) / 24.0 * TAU) * 6.0 * (1.0 - cloud_cover() * 0.6)
	if is_raining():
		base -= 3.0 * maxf(intensity(), 0.4)
	var w := wind_speed()
	if w > 5.0:
		base -= (w - 5.0) * 0.25  # sensación de frío con viento
	return base

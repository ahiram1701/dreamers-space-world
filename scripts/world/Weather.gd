class_name Weather
extends RefCounted
## El tiempo que hace. Determinista por mundo y franja de 4 horas de juego: sin guardar nada, el
## mismo mundo tiene el mismo tiempo a la misma hora. Lo pinta EnvironmentFX y lo sabe la IA.

const KINDS := ["clear", "cloudy", "rain", "fog", "wind", "storm"]
const WEIGHTS := [43, 25, 14, 8, 6, 4]
const LABELS := {"clear": "Despejado", "cloudy": "Nublado", "rain": "Lluvia", "fog": "Niebla", "wind": "Viento", "storm": "Tormenta"}
const SEASONS := ["primavera", "verano", "otoño", "invierno"]
const PHRASES := {"clear": "Hace buen tiempo, cielo despejado.", "cloudy": "El cielo está cubierto de nubes.",
	"rain": "Está lloviendo: todo está mojado y la gente busca dónde resguardarse.", "fog": "Hay niebla espesa; no se ve lejos.",
	"wind": "Sopla un viento fuerte que levanta arena y hace crujir las ventanas.",
	"storm": "Hay tormenta: llueve con fuerza, sopla el viento y caen rayos a lo lejos."}

## Fuerza un tiempo concreto (pruebas, escenas especiales). "" = el que toque.
static var forced := ""


static func current() -> String:
	if not forced.is_empty():
		return forced
	if not WorldDB.is_loaded():
		return "clear"
	var block := int(WorldClock.absolute_minutes() / 240.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(WorldDB.world_id) ^ (block * 7919)
	var roll := rng.randi_range(0, 99)
	var acc := 0
	for i in KINDS.size():
		acc += WEIGHTS[i]
		if roll < acc:
			var k: String = KINDS[i]
			if k == "fog" and WorldClock.hour() > 13.0 and WorldClock.hour() < 20.0:
				return "cloudy"  # la niebla es de madrugada y de noche
			return k
	return "clear"


static func label() -> String:
	return LABELS.get(current(), "")


static func describe() -> String:
	return PHRASES.get(current(), "")


static func is_raining() -> bool:
	return current() in ["rain", "storm"]


## Estación del año: cada 30 días de juego cambia (el mundo empieza en primavera).
static func season() -> String:
	return SEASONS[int(WorldClock.absolute_minutes() / (1440.0 * 30.0)) % 4]


## Temperatura aproximada (°C): estación, hora del día y tiempo.
static func temperature() -> float:
	var base: float = {"primavera": 17.0, "verano": 26.0, "otoño": 14.0, "invierno": 6.0}[season()]
	var h := WorldClock.hour()
	base += sin((h - 9.0) / 24.0 * TAU) * 5.0
	if is_raining():
		base -= 3.0
	if current() == "wind":
		base -= 2.0
	return base

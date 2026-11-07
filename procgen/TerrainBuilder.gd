class_name TerrainBuilder
extends RefCounted
## Construye el terreno de un lugar a partir de su definición (bioma + semilla).
## Determinista: la misma definición produce siempre el mismo terreno, así que volver a un
## lugar no necesita a la IA ni guardar mallas, solo la definición.

const SIZE := 160.0       # metros de lado
const RES := 80           # celdas por lado
const FLAT_RADIUS := 14.0 # zona llana en el centro, donde aparece el jugador

## low/high: color del suelo según la altura; amp: altura del relieve; fog: color de la niebla.
const BIOMES := {
	"temperate": {"low": "#4f7a3a", "high": "#8a9a5b", "amp": 7.0, "fog": "#b9c9d6"},
	"desert": {"low": "#d9b26f", "high": "#b9824a", "amp": 6.0, "fog": "#e8cfa0"},
	"ice": {"low": "#dfeef5", "high": "#9fc2d6", "amp": 8.0, "fog": "#e4f0f7"},
	"jungle": {"low": "#2f5a2a", "high": "#4d7d36", "amp": 9.0, "fog": "#9fbf9a"},
	"ocean": {"low": "#b8a676", "high": "#e3cf9c", "amp": 4.5, "fog": "#a9c8d8"},
	"volcanic": {"low": "#2a2220", "high": "#7a2e1c", "amp": 14.0, "fog": "#5a3a33"},
	"crystal": {"low": "#5c4b8a", "high": "#a7e0f0", "amp": 11.0, "fog": "#b9a9e0"},
	"barren": {"low": "#8a5a3c", "high": "#c48a5a", "amp": 6.0, "fog": "#c9956a"},
	"urban": {"low": "#5a5a60", "high": "#7a7a80", "amp": 1.5, "fog": "#9a9aa0"},
	"void": {"low": "#101018", "high": "#3a2f5a", "amp": 10.0, "fog": "#1a1a2a"},
}


static func palette(biome: String) -> Dictionary:
	return BIOMES.get(biome, BIOMES["barren"])


## Devuelve { node: el terreno (ChunkTerrain: sin bordes, se genera a tu alrededor al moverte),
## height_at: Callable(x, z) -> float }. El centro (SIZE) es llano donde apareces y es lo que se
## decora a mano; más lejos el relieve crece hasta montañas.
static func build(definition: Dictionary) -> Dictionary:
	var biome := str(definition.get("biome", "barren"))
	var pal := palette(biome)
	var noise := FastNoiseLite.new()
	noise.seed = int(definition.get("seed", 1))
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var big := FastNoiseLite.new()
	big.seed = int(definition.get("seed", 1)) + 17
	big.frequency = 0.0025
	big.fractal_octaves = 3
	var amp: float = pal.amp
	var ocean := biome == "ocean"
	var height_at := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length()
		var flat := smoothstep(FLAT_RADIUS * 0.5, FLAT_RADIUS * 2.0, d)
		var h := noise.get_noise_2d(x, z) * amp * flat
		# Lejos, montañas (o, en un mundo océano, islas y mar abierto)
		var far := smoothstep(SIZE * 0.6, SIZE * 2.5, d)
		var m := big.get_noise_2d(x, z)
		if ocean:
			h = lerpf(h, -6.0 + maxf(m - 0.25, 0.0) * 40.0, far)
		else:
			h += (m * 0.5 + 0.5) * amp * 4.0 * far
		return h
	var low := Color(pal.low)
	var high := Color(pal.high)
	var t := ChunkTerrain.new()
	t.name = "Terreno"
	t.height_fn = height_at
	t.color_fn = func(_x: float, _z: float, h: float) -> Color:
		return low.lerp(high, clampf(h / (amp * 2.0) * 0.5 + 0.5, 0.0, 1.0))
	t.material = Decor.ground_material()
	t.props_exclude = Rect2(-SIZE / 2.0 - 4.0, -SIZE / 2.0 - 4.0, SIZE + 8.0, SIZE + 8.0)  # el centro lo decora PropsBuilder
	t.prop_fn = ChunkTerrain.nature_chooser(biome)
	t.prop_builder = ChunkTerrain.nature_placer(biome)
	if ocean:
		t.water_level = -0.45
	return {"node": t, "height_at": height_at, "limit": INF, "chunked": true}

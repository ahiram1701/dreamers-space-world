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


## Devuelve { node: StaticBody3D con malla y colisión, height_at: Callable(x, z) -> float }.
static func build(definition: Dictionary) -> Dictionary:
	var pal := palette(definition.get("biome", "barren"))
	var noise := FastNoiseLite.new()
	noise.seed = int(definition.get("seed", 1))
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var amp: float = pal.amp
	var height_at := func(x: float, z: float) -> float:
		var flat := smoothstep(FLAT_RADIUS * 0.5, FLAT_RADIUS * 2.0, Vector2(x, z).length())
		return noise.get_noise_2d(x, z) * amp * flat

	var low := Color(pal.low)
	var high := Color(pal.high)
	var step := SIZE / RES
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RES:
		for i in RES:
			var x0 := -SIZE / 2.0 + i * step
			var z0 := -SIZE / 2.0 + j * step
			var quad := [Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0, z0 + step), Vector2(x0 + step, z0 + step)]
			for k in [0, 1, 2, 2, 1, 3]:
				var p: Vector2 = quad[k]
				var h: float = height_at.call(p.x, p.y)
				st.set_color(low.lerp(high, clampf(h / amp * 0.5 + 0.5, 0.0, 1.0)))
				st.add_vertex(Vector3(p.x, h, p.y))
	st.generate_normals()
	var mesh := st.commit()

	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Decor.ground_material()
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	return {"node": body, "height_at": height_at}

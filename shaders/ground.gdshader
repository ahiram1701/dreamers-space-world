shader_type spatial;
// Suelo: el color base viene de los vértices (bioma, arena, caminos) y aquí se le añade
// variación a dos escalas, oscurecimiento en pendientes y un poco de brillo de roca.
render_mode cull_back;

uniform float variation = 0.18;
uniform float slope_dark = 0.35;
uniform vec4 rock_color : source_color = vec4(0.42, 0.40, 0.38, 1.0);
uniform float bump = 0.35;  // relieve fino (piedrecitas, terrones) sin texturas
global uniform float wetness;  // 0 seco … 1 empapado (la lluvia, desde EnvironmentFX)

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Un triángulo degenerado (dos vértices iguales) deja la normal a cero; normalizarla da NaN,
	// y un solo píxel NaN el resplandor (glow) lo convierte en una mancha blanca enorme: eran los
	// «destellos» que se veían de noche en el campo y en la orilla (el agua refleja lo de debajo).
	if (dot(NORMAL, NORMAL) < 1e-8) {
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float detail(vec2 p) {
	return noise(p * 3.0) * 0.6 + noise(p * 9.0) * 0.4;
}

void fragment() {
	float n = noise(world_pos.xz * 0.08) * 0.6 + noise(world_pos.xz * 0.6) * 0.3 + noise(world_pos.xz * 3.0) * 0.1;
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));  // los colores de vértice vienen en sRGB
	vec3 col = base * (1.0 - variation + n * variation * 2.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(0.35, 0.65, slope);
	col = mix(col, rock_color.rgb * (0.8 + n * 0.4), rock);
	col *= 1.0 - slope * slope_dark;
	// Relieve fino: la normal se inclina con el ruido (se desvanece de lejos, donde haría ruido)
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(25.0, 60.0, dist);
	float e = 0.05;
	float d0 = detail(world_pos.xz);
	vec2 grad = vec2(detail(world_pos.xz + vec2(e, 0.0)) - d0, detail(world_pos.xz + vec2(0.0, e)) - d0) / e;
	vec3 wn = normalize(world_normal - vec3(grad.x, 0.0, grad.y) * bump * 0.12 * fade * (1.0 + rock));
	// Mojado: la tierra se oscurece, brilla más; en lo llano y bajo se forman charcos
	float wet = clamp(wetness, 0.0, 1.0);
	float flat_ground = 1.0 - smoothstep(0.04, 0.18, slope);
	// (en el césped el agua se cuela entre la hierba: charcos solo en tierra, arena y asfalto)
	float grassy = smoothstep(0.0, 0.06, base.g - max(base.r, base.b));
	float puddle = smoothstep(0.64, 0.74, 1.0 - noise(world_pos.xz * 0.35)) * flat_ground * smoothstep(0.45, 0.9, wet) * (1.0 - grassy);
	col *= 1.0 - wet * 0.32;
	col = mix(col, col * 0.6, puddle);
	wn = normalize(mix(wn, world_normal, puddle));  // el agua del charco es lisa
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.45, wet), 0.06, puddle);
	SPECULAR = mix(0.5, 0.65, wet);
}

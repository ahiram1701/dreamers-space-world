shader_type spatial;
// Suelo: el color base viene de los vértices (bioma, arena, caminos) y aquí se le añade
// variación a dos escalas, oscurecimiento en pendientes y un poco de brillo de roca.
render_mode cull_back;

uniform float variation = 0.18;
uniform float slope_dark = 0.35;
uniform vec4 rock_color : source_color = vec4(0.42, 0.40, 0.38, 1.0);

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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = noise(world_pos.xz * 0.08) * 0.6 + noise(world_pos.xz * 0.6) * 0.3 + noise(world_pos.xz * 3.0) * 0.1;
	vec3 base = pow(COLOR.rgb, vec3(2.2));  // los colores de vértice vienen en sRGB
	vec3 col = base * (1.0 - variation + n * variation * 2.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	col = mix(col, rock_color.rgb * (0.8 + n * 0.4), smoothstep(0.35, 0.65, slope));
	col *= 1.0 - slope * slope_dark;
	ALBEDO = col;
	ROUGHNESS = 0.92;
}

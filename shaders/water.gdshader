shader_type spatial;
// Agua con olas (suma de ondas de Gerstner), fresnel, reflejo del cielo y espuma donde toca
// la orilla (se calcula con la profundidad de la escena).
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.16, 0.55, 0.62, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.17, 0.30, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float wave_height = 0.22;
uniform float wave_speed = 0.8;
uniform float foam_width = 0.45;  // solo una línea fina donde el agua toca la orilla
uniform float clarity = 6.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float ripple_strength = 0.18;
global uniform float rain;   // 0..1: lo que llueve ahora (anillos de gotas)
global uniform vec2 wind;    // m/s: el viento riza el agua

varying float crest;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float ripples(vec2 p, float t) {
	return noise(p * 1.3 + vec2(t * 0.35, t * 0.2)) * 0.6 + noise(p * 3.1 - vec2(t * 0.5, -t * 0.3)) * 0.4;
}
// Anillos de gotas de lluvia: cada celda tiene su gota que cae a su ritmo y abre un círculo
vec2 rain_rings(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = p * (k == 0 ? 1.6 : 2.3) + float(k) * 7.31;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		vec2 c = (vec2(hash(cell), hash(cell + 3.7)) - 0.5) * 0.5;
		float ph = fract(t * 1.1 + hash(cell + 11.0));
		vec2 dv = f - c;
		float d = length(dv);
		float r = ph * 0.45;
		float ring = sin(clamp((d - r) * 40.0, -3.14159, 3.14159)) * (1.0 - smoothstep(0.0, 0.08, abs(d - r))) * (1.0 - ph);
		g += (d > 0.001 ? dv / d : vec2(0.0)) * ring;
	}
	return g;
}

vec3 gerstner(vec2 p, vec2 dir, float steep, float len, float t) {
	float k = 6.28318 / len;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	vec3 o = gerstner(p, vec2(1.0, 0.3), 0.18, 14.0, t)
		+ gerstner(p, vec2(0.6, 1.0), 0.14, 8.0, t)
		+ gerstner(p, vec2(-0.4, 0.8), 0.10, 4.5, t);
	VERTEX += o * wave_height / 0.35;
	crest = o.y;
	// Normal aproximada por diferencias
	// Normal por diferencias, con las tres olas (antes solo dos: la pequeña no se notaba al sol)
	float e = 0.3;
	float k = wave_height / 0.35;
	float hx = (gerstner(p + vec2(e, 0.0), vec2(1.0, 0.3), 0.18, 14.0, t) + gerstner(p + vec2(e, 0.0), vec2(0.6, 1.0), 0.14, 8.0, t) + gerstner(p + vec2(e, 0.0), vec2(-0.4, 0.8), 0.10, 4.5, t)).y * k;
	float hz = (gerstner(p + vec2(0.0, e), vec2(1.0, 0.3), 0.18, 14.0, t) + gerstner(p + vec2(0.0, e), vec2(0.6, 1.0), 0.14, 8.0, t) + gerstner(p + vec2(0.0, e), vec2(-0.4, 0.8), 0.10, 4.5, t)).y * k;
	float h0 = o.y * k;
	NORMAL = normalize(vec3(h0 - hx, e, h0 - hz));
}

void fragment() {
	// Rizado fino (más con viento) y anillos de lluvia: inclinan la normal en el mundo
	float t = TIME * wave_speed;
	float ee = 0.08;
	float wind_k = 0.6 + min(length(wind), 15.0) * 0.08;
	float r0 = ripples(world_pos.xz, t);
	vec2 rg = vec2(ripples(world_pos.xz + vec2(ee, 0.0), t) - r0, ripples(world_pos.xz + vec2(0.0, ee), t) - r0) / ee;
	vec2 tilt = rg * ripple_strength * 0.25 * wind_k;
	tilt += rain_rings(world_pos.xz, TIME) * clamp(rain, 0.0, 1.0) * 0.35;
	float fade = 1.0 - smoothstep(20.0, 70.0, length(VERTEX));  // de lejos no: haría ruido
	vec3 tilt_view = (VIEW_MATRIX * vec4(tilt.x, 0.0, tilt.y, 0.0)).xyz * fade;
	NORMAL = normalize(NORMAL - tilt_view);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp(-world.z - (-VERTEX.z), 0.0, 100.0);
	float deep = clamp(water_depth / clarity, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, deep);
	// Lo que hay debajo se ve un poco en la orilla
	vec3 under = textureLod(screen_tex, SCREEN_UV + NORMAL.xz * 0.01, 1.0).rgb;
	col = mix(under * shallow_color.rgb * 1.4, col, clamp(deep * 1.6 + 0.35, 0.0, 1.0));
	// Espuma: una línea fina en la orilla y algo en las crestas. Antes (más ancha y casi blanca)
	// en el agua poco profunda se veían manchas blancas grandes que brillaban como destellos.
	float foam = (1.0 - smoothstep(0.0, foam_width, water_depth)) * 0.7;
	foam += smoothstep(0.22, 0.38, crest) * 0.18;
	// La espuma late con la posición EN EL MUNDO (antes usaba la de la cámara: al moverte, la orilla
	// parpadeaba en blanco) y suave, sin llegar a blanco puro.
	foam *= 0.75 + 0.25 * sin(TIME * 1.4 + world_pos.x * 0.7 + world_pos.z * 0.5);
	ALBEDO = mix(col, foam_color.rgb * 0.72, clamp(foam, 0.0, 0.6));
	// Algo menos espejo: los puntos de luz (farolas, luna) ya no saltan como destellos en cada ola
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// Fresnel: de frente se ve el fondo; rasante, el agua es un espejo del cielo
	ROUGHNESS = mix(0.28, 0.12, fres) + clamp(rain, 0.0, 1.0) * 0.1;
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.55, fres);
	ALPHA = clamp(0.82 + fres * 0.18 + foam * 0.2, 0.0, 1.0);
}

shader_type sky;
// Cielo del espacio: estrellas (con tamaños y colores distintos), una franja de Vía Láctea y
// nebulosas suaves. Todo procedural, sin texturas.

uniform vec3 nebula_a : source_color = vec3(0.32, 0.12, 0.45);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.22, 0.38);
uniform float star_density = 0.9;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 stars(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash(cell);
	if (h < threshold) {
		return vec3(0.0);
	}
	vec3 center = cell + vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3));
	float d = length(p - center);
	float b = smoothstep(0.35, 0.0, d) * (h - threshold) / (1.0 - threshold);
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.85, 0.7), hash(cell + 9.1));
	return tint * b * 3.0;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Vía Láctea: una banda inclinada
	float band = exp(-pow(dot(dir, normalize(vec3(0.3, 1.0, 0.2))) * 3.2, 2.0));
	float neb = fbm(dir * 3.0) * fbm(dir * 6.0 + 4.0);
	vec3 col = mix(nebula_b, nebula_a, fbm(dir * 2.0 + 9.0)) * neb * 0.55;
	col += vec3(0.55, 0.5, 0.6) * band * fbm(dir * 18.0) * 0.18;
	col += stars(dir, 160.0, 1.0 - 0.06 * star_density);
	col += stars(dir, 420.0, 1.0 - (0.05 + band * 0.12) * star_density) * 0.7;
	COLOR = col;
}

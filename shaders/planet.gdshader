shader_type spatial;
// Planeta visto desde el espacio: continentes o bandas (gigante gaseoso), casquetes y un borde
// de atmósfera que brilla del lado del sol.

uniform vec3 color_a : source_color = vec3(0.2, 0.45, 0.75);
uniform vec3 color_b : source_color = vec3(0.3, 0.55, 0.25);
uniform vec3 color_c : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 atmosphere : source_color = vec3(0.45, 0.7, 1.0);
uniform float banded = 0.0;      // 1: gigante gaseoso
uniform float land = 0.45;       // cuánto es tierra (color_b) frente a color_a
uniform float seed = 0.0;

varying vec3 local_n;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1 + seed);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_n = normalize(VERTEX);
}

void fragment() {
	vec3 n = local_n;
	vec3 col;
	if (banded > 0.5) {
		float b = n.y * 6.0 + fbm(n * 3.0) * 1.6;
		col = mix(color_a, color_b, 0.5 + 0.5 * sin(b * 3.14159));
		col = mix(col, color_c, smoothstep(0.55, 0.9, fbm(n * 5.0 + vec3(b))) * 0.35);
	} else {
		float h = fbm(n * 2.6);
		col = mix(color_a, color_b, smoothstep(land - 0.03, land + 0.03, h));
		col = mix(col, color_c, smoothstep(0.82, 0.9, abs(n.y)));          // casquetes
		col = mix(col, color_c, smoothstep(0.6, 0.75, fbm(n * 7.0 + 13.0)) * 0.45);  // nubes
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = atmosphere * rim * 0.9;
}

shader_type canvas_item;
// Fondo del menú: anochecer sobre el mar, estrellas que titilan y el faro de Bahía de las Horas
// con su haz girando. Todo procedural (sin imágenes).

uniform vec2 aspect = vec2(1.7778, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect.x, uv.y);
	float horizon = 0.68;
	// Cielo: de azul noche arriba a naranja en el horizonte
	vec3 top = vec3(0.02, 0.03, 0.08);
	vec3 mid = vec3(0.12, 0.13, 0.30);
	vec3 low = vec3(0.85, 0.42, 0.26);
	float t = clamp(uv.y / horizon, 0.0, 1.0);
	vec3 col = mix(top, mid, smoothstep(0.0, 0.7, t));
	col = mix(col, low, smoothstep(0.75, 1.0, t) * 0.85);
	// Estrellas
	vec2 cell = floor(p * 140.0);
	float star = step(0.996, hash(cell)) * (0.5 + 0.5 * sin(TIME * (1.0 + hash(cell + 3.0) * 3.0) + hash(cell) * 30.0));
	col += vec3(star) * (1.0 - smoothstep(0.2, 0.62, uv.y));
	// Mar: oscuro con reflejos que se mueven
	if (uv.y > horizon) {
		float d = (uv.y - horizon) / (1.0 - horizon);
		col = mix(vec3(0.10, 0.08, 0.16), vec3(0.01, 0.02, 0.05), d);
		float wave = sin(p.x * 40.0 + TIME * 1.3 + d * 60.0) * sin(p.x * 13.0 - TIME * 0.7);
		col += low * 0.35 * smoothstep(0.6, 1.0, wave) * (1.0 - d) * smoothstep(0.6, 0.0, abs(uv.x - 0.72));
	}
	// Promontorio y faro (silueta) a la derecha
	float lx = 0.78 * aspect.x;
	float hill = horizon - 0.035 * exp(-pow((p.x - lx) * 3.5, 2.0));
	float tower = step(abs(p.x - lx), mix(0.012, 0.008, (horizon - uv.y) / 0.2)) * step(horizon - 0.24, uv.y);
	if (uv.y > hill || tower > 0.5) {
		col = vec3(0.015, 0.015, 0.03);
	}
	// Haz del faro girando (y la lámpara)
	vec2 lamp = vec2(lx, horizon - 0.245);
	vec2 dv = p - lamp;
	float ang = atan(dv.y, dv.x);
	float beam_dir = TIME * 0.9;
	float beam = pow(max(cos(ang - beam_dir), 0.0), 60.0) * smoothstep(1.4, 0.0, length(dv)) * (0.5 + 0.5 * sin(beam_dir));
	col += vec3(1.0, 0.93, 0.7) * beam * 0.55 * step(uv.y, horizon);
	col += vec3(1.0, 0.9, 0.6) * smoothstep(0.012, 0.0, length(dv)) * 1.5;
	// Viñeta
	col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.3, 2.0);
	COLOR = vec4(col, 1.0);
}

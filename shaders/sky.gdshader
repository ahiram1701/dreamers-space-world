shader_type sky;
// Cielo con nubes. Mismos colores que antes (los mueve EnvironmentFX según la hora y el tiempo,
// y El Despertar los anima), más lo que da realismo:
//  - dispersión alrededor del sol (el halo blanco de mediodía; el resplandor naranja del ocaso
//    que se abre por el horizonte del lado del sol);
//  - disco solar con borde suave que las nubes tapan;
//  - una capa de nubes (ruido fbm proyectado en un plano alto) que cubre según el tiempo que
//    hace, se ilumina por el lado del sol y avanza con el viento (cloud_offset, desde GDScript:
//    sin TIME, así el reflejo del cielo no se recalcula en cada fotograma).

uniform vec4 sky_top_color : source_color = vec4(0.25, 0.42, 0.68, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.65, 0.76, 0.88, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.6, 0.66, 0.72, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.12, 0.13, 0.12, 1.0);
uniform float sky_curve : hint_range(0.01, 1.0) = 0.15;
uniform float sun_angle_max = 20.0;      // grados: hasta dónde llega el halo
uniform float sun_disk_size = 0.55;      // grados: radio aparente del sol
uniform float sun_disk_energy = 1.6;
uniform float halo_strength = 0.35;
uniform vec4 sunset_color : source_color = vec4(1.0, 0.55, 0.28, 1.0);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.2;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.55, 0.6, 0.68, 1.0);
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_scale = 0.9;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) {
			break;
		}
		v += a * noise(p);
		p = rot * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		float c = 1.0 - acos(clamp(h, 0.0, 1.0)) / (PI * 0.5);
		col = mix(sky_horizon_color.rgb, sky_top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	} else {
		col = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, clamp(-h * 5.0, 0.0, 1.0));
	}

	float sun_cos = -1.0;
	float sun_up = 0.0;
	vec3 sun_col = vec3(1.0);
	if (LIGHT0_ENABLED) {
		sun_cos = dot(LIGHT0_DIRECTION, d);
		sun_up = LIGHT0_DIRECTION.y;
		sun_col = LIGHT0_COLOR;
		float toward = max(sun_cos, 0.0);
		float low = 1.0 - clamp(sun_up * 3.5, 0.0, 1.0);  // 1 con el sol en el horizonte
		// Ocaso: el horizonte arde del lado del sol y se apaga hacia el otro lado
		float band = pow(1.0 - clamp(abs(h), 0.0, 1.0), 6.0);
		col = mix(col, sunset_color.rgb * (0.6 + 0.4 * toward), band * low * (0.25 + 0.75 * pow(toward, 2.0)) * 0.85);
		// Halo (dispersión de Mie): fuerte hacia el sol
		float spread = cos(radians(clamp(sun_angle_max, 1.0, 89.0)));
		float halo = smoothstep(spread, 1.0, sun_cos);
		col += sun_col * (halo * halo * halo_strength + pow(toward, 64.0) * 0.25) * min(LIGHT0_ENERGY, 1.5);
	}

	// Nubes: un plano alto visto desde abajo, que se pierde en el horizonte
	if (h > 0.0 && cloud_cover > 0.01) {
		vec2 uv = d.xz / (h + 0.12) * cloud_scale + cloud_offset;
		int oct = AT_CUBEMAP_PASS ? 3 : 5;
		float n = fbm(uv, oct);
		float edge = 1.0 - cloud_cover;
		float dens = smoothstep(edge * 0.75 + 0.1, edge * 0.75 + 0.42, n) * smoothstep(0.0, 0.14, h);
		// Más espesas cuanto más cubierto: con todo cerrado, un manto continuo
		dens = max(dens, smoothstep(0.75, 1.0, cloud_cover) * smoothstep(0.0, 0.1, h) * (0.7 + 0.3 * n));
		// Luz: la cara que mira al sol, más clara; el núcleo denso, en sombra; el borde fino brilla a contraluz
		float thick = smoothstep(0.3, 0.85, n);
		vec3 lit = mix(cloud_color.rgb, cloud_shadow_color.rgb, thick * (0.55 + cloud_cover * 0.4));
		float rim = pow(max(sun_cos, 0.0), 12.0) * (1.0 - thick) * 0.6;
		lit += sun_col * rim * min(LIGHT0_ENABLED ? LIGHT0_ENERGY : 0.0, 1.2);
		col = mix(col, lit, clamp(dens, 0.0, 0.97));
		sun_cos = mix(sun_cos, -1.0, clamp(dens * 1.4, 0.0, 1.0));  // la nube tapa el disco
	}

	// Disco del sol
	if (LIGHT0_ENABLED && h > -0.02) {
		float r = radians(sun_disk_size);
		float a = acos(clamp(sun_cos, -1.0, 1.0));
		float disk = 1.0 - smoothstep(r * 0.75, r, a);
		col += sun_col * disk * sun_disk_energy * min(LIGHT0_ENERGY, 1.5);
	}
	COLOR = max(col, vec3(0.0));  // nunca negativo ni NaN (el resplandor lo convertiría en manchas)
}

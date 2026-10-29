shader_type spatial;
// Agua con olas (suma de ondas de Gerstner), fresnel, reflejo del cielo y espuma donde toca
// la orilla (se calcula con la profundidad de la escena).
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.16, 0.55, 0.62, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.17, 0.30, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float wave_height = 0.22;
uniform float wave_speed = 0.8;
uniform float foam_width = 1.4;
uniform float clarity = 6.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying float crest;

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
	float t = TIME * wave_speed;
	vec3 o = gerstner(p, vec2(1.0, 0.3), 0.18, 14.0, t)
		+ gerstner(p, vec2(0.6, 1.0), 0.14, 8.0, t)
		+ gerstner(p, vec2(-0.4, 0.8), 0.10, 4.5, t);
	VERTEX += o * wave_height / 0.35;
	crest = o.y;
	// Normal aproximada por diferencias
	float e = 0.4;
	float hx = (gerstner(p + vec2(e, 0.0), vec2(1.0, 0.3), 0.18, 14.0, t) + gerstner(p + vec2(e, 0.0), vec2(0.6, 1.0), 0.14, 8.0, t)).y;
	float hz = (gerstner(p + vec2(0.0, e), vec2(1.0, 0.3), 0.18, 14.0, t) + gerstner(p + vec2(0.0, e), vec2(0.6, 1.0), 0.14, 8.0, t)).y;
	float h0 = (gerstner(p, vec2(1.0, 0.3), 0.18, 14.0, t) + gerstner(p, vec2(0.6, 1.0), 0.14, 8.0, t)).y;
	NORMAL = normalize(vec3(h0 - hx, e, h0 - hz));
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp(-world.z - (-VERTEX.z), 0.0, 100.0);
	float deep = clamp(water_depth / clarity, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, deep);
	// Lo que hay debajo se ve un poco en la orilla
	vec3 under = textureLod(screen_tex, SCREEN_UV + NORMAL.xz * 0.01, 1.0).rgb;
	col = mix(under * shallow_color.rgb * 1.4, col, clamp(deep * 1.6 + 0.35, 0.0, 1.0));
	float foam = 1.0 - smoothstep(0.0, foam_width, water_depth);
	foam += smoothstep(0.18, 0.35, crest) * 0.35;
	foam *= 0.6 + 0.4 * sin(TIME * 2.0 + VERTEX.x * 0.7 + VERTEX.z * 0.5);
	ALBEDO = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALPHA = clamp(0.82 + fres * 0.18 + foam * 0.2, 0.0, 1.0);
}

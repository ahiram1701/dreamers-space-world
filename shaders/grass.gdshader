shader_type spatial;
// Briznas de hierba (MultiMesh): se mecen con el viento y se oscurecen en la base.
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec4 tip_color : source_color = vec4(0.55, 0.68, 0.30, 1.0);
uniform vec4 base_color : source_color = vec4(0.18, 0.30, 0.12, 1.0);
uniform float wind_strength = 0.08;
global uniform vec2 wind;  // m/s, el viento de Weather (lo pone EnvironmentFX)

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;   // la punta (UV.y = 0) se mueve, la base no
	float speed = length(wind);
	vec2 dir = speed > 0.01 ? wind / speed : vec2(0.8, 0.4);
	// Ráfagas que recorren el prado en la dirección del viento (ondas, no todo a la vez)
	float phase = dot(wp.xz, dir) * 0.35 - TIME * (1.2 + speed * 0.18);
	float gust = sin(phase) * 0.6 + sin(phase * 0.37 + wp.x * 0.11) * 0.4;
	float sway = sin(TIME * 2.3 + wp.x * 0.5 + wp.z * 0.3) * 0.25;  // temblor propio de cada brizna
	float amount = wind_strength * (0.35 + min(speed, 18.0) * 0.12);
	float lean = min(speed, 18.0) * 0.012;  // con viento fuerte, inclinada hacia donde sopla
	vec2 off = dir * (lean + (gust * 0.5 + 0.5) * amount) + vec2(-dir.y, dir.x) * sway * amount;
	// El desplazamiento es en el mundo: se pasa al espacio de cada mata (que está girada)
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(off.x, 0.0, off.y) * h * h;
	COLOR = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 col = mix(tip_color.rgb, base_color.rgb, UV.y) * (0.85 + COLOR.r * 0.3);
	ALBEDO = col;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
	ROUGHNESS = 0.9;
}

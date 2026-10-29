shader_type spatial;
// Briznas de hierba (MultiMesh): se mecen con el viento y se oscurecen en la base.
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec4 tip_color : source_color = vec4(0.55, 0.68, 0.30, 1.0);
uniform vec4 base_color : source_color = vec4(0.18, 0.30, 0.12, 1.0);
uniform float wind_strength = 0.08;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;   // la punta (UV.y = 0) se mueve, la base no
	float w = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.25) + sin(TIME * 0.9 + wp.x * 0.11) * 0.6;
	VERTEX.x += w * wind_strength * h;
	VERTEX.z += w * wind_strength * 0.5 * h;
	COLOR = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 col = mix(tip_color.rgb, base_color.rgb, UV.y) * (0.85 + COLOR.r * 0.3);
	ALBEDO = col;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
	ROUGHNESS = 0.9;
}

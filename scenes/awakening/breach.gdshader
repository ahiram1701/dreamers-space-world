shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// La brecha: una lente gravitatoria. Refracta lo que hay detrás, lo corre al rojo en el
// centro (dilatación temporal) y brilla en el borde (efecto Fresnel).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.07;
uniform vec4 rim_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec2 wobble = vec2(sin(TIME * 3.0 + UV.y * 24.0), cos(TIME * 2.3 + UV.x * 24.0));
	vec2 offset = (NORMAL.xy * (1.0 - fresnel) + wobble * 0.15) * strength;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offset, 1.5).rgb;
	behind = mix(behind, behind * vec3(1.3, 0.75, 0.65), (1.0 - fresnel) * 0.7);
	ALBEDO = behind + rim_color.rgb * fresnel * 2.5;
	ALPHA = 1.0;
}

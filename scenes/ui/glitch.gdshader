shader_type canvas_item;
// Decoherencia: con mucha inestabilidad la imagen se desplaza en franjas y los colores se separan.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float rand(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 12.0);
	float band = step(1.0 - intensity * 0.18, rand(vec2(t, floor(uv.y * 40.0))));
	uv.x += band * (rand(vec2(t, uv.y)) - 0.5) * 0.08 * intensity;
	float shift = 0.007 * intensity;
	vec3 c = vec3(
		texture(screen_tex, uv + vec2(shift, 0.0)).r,
		texture(screen_tex, uv).g,
		texture(screen_tex, uv - vec2(shift, 0.0)).b);
	c += (rand(uv * (TIME + 1.0)) - 0.5) * 0.1 * intensity;
	COLOR = vec4(c, 1.0);
}

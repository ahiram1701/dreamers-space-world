shader_type canvas_item;
// Túnel del salto: estelas radiales que se acercan hacia el centro (el Ancla atravesando la brecha).

uniform float speed = 1.6;

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = max(length(uv), 0.001);
	float a = atan(uv.y, uv.x);
	float z = 0.18 / r + TIME * speed;
	float lane = floor(a * 48.0 / 6.2831);
	float streak = smoothstep(0.8, 1.0, fract(sin(lane * 91.7 + floor(z * 3.0) * 13.1) * 4375.5)) * fract(z * 3.0);
	vec3 col = mix(vec3(0.02, 0.03, 0.09), vec3(0.45, 0.85, 1.0), streak);
	col += vec3(0.6, 0.9, 1.0) * smoothstep(0.1, 0.0, r);
	col *= smoothstep(0.0, 0.2, r) * 0.9 + 0.1;
	COLOR = vec4(col, 1.0);
}

shader_type canvas_item;
// Bordes oscuros y algo borrosos de cansancio (la intensidad la da el modulate del nodo).

void fragment() {
	float d = length(UV - vec2(0.5)) * 1.45;
	float v = smoothstep(0.45, 1.05, d);
	COLOR = vec4(0.0, 0.0, 0.02, v * 0.85);
}

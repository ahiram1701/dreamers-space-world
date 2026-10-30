shader_type spatial;
// Tapa invisible dentro de una barca: no pinta nada, solo escribe profundidad. Se dibuja antes que
// el agua (render_priority más bajo), así el agua que queda por debajo no pasa la prueba de
// profundidad y el interior del casco se ve seco.
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix, shadows_disabled;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}

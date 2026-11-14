shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cart Slop GP: thin rising light wisps above the aurora speed zone. One quad
// per wisp, one shared material, all motion from TIME. No particles and no
// per-frame script work, so a track can instance as many pads as it likes.

uniform vec4 tint : source_color = vec4(0.28, 0.70, 1.00, 1.0);
uniform float intensity : hint_range(0.0, 1.5) = 0.22;
uniform float rise_speed : hint_range(0.0, 2.0) = 0.4;
uniform float sway_amount : hint_range(0.0, 0.4) = 0.11;
uniform float core_width : hint_range(0.02, 0.3) = 0.10;

void fragment() {
	float t = TIME;
	float h = 1.0 - UV.y; // 0.0 at the ground, 1.0 at the top

	// Curving sway, strongest near the top, so the wisp reads as drifting light
	// rather than a painted stroke or a pole.
	float sway = sin(h * 3.4 + t * 0.62) * sway_amount
			+ sin(h * 6.2 - t * 1.05) * sway_amount * 0.4;
	float lane = UV.x + sway * (0.35 + 0.65 * h);

	// Soft gaussian core; no texture, no loop, one exp per pixel.
	float core = exp(-pow((lane - 0.5) / core_width, 2.0));

	// Brightest just above the road, fading out well before the quad's top edge
	// so the card never shows a cut-off.
	float envelope = smoothstep(0.0, 0.10, h) * (1.0 - smoothstep(0.22, 0.88, h));

	// Brightness nodes travel upward, so the wisp looks like it is rising.
	float rising = 0.58 + 0.42 * sin(h * 8.0 - t * rise_speed * TAU);
	float flicker = 0.86 + 0.14 * sin(t * 2.1 + UV.x * 9.0);

	ALBEDO = tint.rgb;
	ALPHA = clamp(core * envelope * rising * flicker * intensity, 0.0, 0.85);
}

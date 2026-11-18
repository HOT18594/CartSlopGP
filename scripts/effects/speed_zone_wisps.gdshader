shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cart Slop GP: rising aurora light wisps flanking the holographic speed zone.
// Vertical gradient from vivid cyan at road level to electric violet aloft.

uniform vec4 tint : source_color = vec4(0.08, 0.78, 1.00, 1.0);
uniform vec4 top_tint : source_color = vec4(0.78, 0.34, 1.00, 1.0);
uniform vec4 crest_tint : source_color = vec4(0.62, 1.00, 1.00, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.52;
uniform float rise_speed : hint_range(0.0, 3.0) = 0.78;
uniform float sway_amount : hint_range(0.0, 0.4) = 0.13;
uniform float core_width : hint_range(0.02, 0.3) = 0.12;

void fragment() {
	float t = TIME;
	float h = 1.0 - UV.y; // 0.0 at the ground, 1.0 at the top

	// Curving aurora ribbon sway, strongest near the top.
	float sway = sin(h * 3.8 + t * 1.15) * sway_amount
			+ sin(h * 7.0 - t * 1.85) * sway_amount * 0.42;
	float lane = UV.x + sway * (0.30 + 0.70 * h);

	// Soft gaussian glow + crisp hot inner filament.
	float dist = (lane - 0.5) / core_width;
	float core = exp(-dist * dist);
	float filament = exp(-dist * dist * 3.8);

	// Bright near the road, tapering cleanly before the quad's top edge.
	float envelope = smoothstep(0.0, 0.09, h) * (1.0 - smoothstep(0.30, 0.92, h));

	// Upward-travelling plasma nodes.
	float rising = 0.62 + 0.38 * sin(h * 8.5 - t * rise_speed * TAU);
	float flicker = 0.88 + 0.12 * sin(t * 2.8 + UV.x * 9.0);

	vec3 grad = mix(tint.rgb, top_tint.rgb, smoothstep(0.10, 0.82, h));
	vec3 color = mix(grad, crest_tint.rgb, filament * (1.0 - h * 0.65) * 0.65);

	ALBEDO = color * (0.95 + 0.35 * clamp(intensity / 0.52, 0.0, 2.5));
	ALPHA = clamp((core * 0.82 + filament * 0.38) * envelope * rising * flicker * intensity, 0.0, 0.92);
}

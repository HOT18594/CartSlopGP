shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Cart Slop GP boost pad: dark plate, glowing rim and scrolling chevrons.
uniform vec4 plate_color : source_color = vec4(0.05, 0.12, 0.28, 0.55);
uniform vec4 rim_color : source_color = vec4(0.22, 0.84, 0.94, 1.0);
uniform vec4 arrow_color : source_color = vec4(1.0, 0.82, 0.18, 1.0);
uniform float scroll_speed = 1.6;
uniform float glow : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float rim = 1.0 - smoothstep(0.026, 0.052, edge);

	float warp = abs(uv.x - 0.5) * 0.55;
	float band = fract(uv.y * 2.0 - warp - TIME * scroll_speed);
	float chev = 1.0 - smoothstep(0.05, 0.11, abs(band - 0.5));
	chev *= 1.0 - rim;

	vec3 col = plate_color.rgb;
	col = mix(col, rim_color.rgb * glow, rim);
	col = mix(col, arrow_color.rgb * glow, chev);

	ALBEDO = col;
	ALPHA = max(max(plate_color.a, rim), chev);
}

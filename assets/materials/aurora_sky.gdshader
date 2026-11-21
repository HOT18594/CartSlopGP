shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec3 color_low : source_color = vec3(0.14, 1.0, 0.56);
uniform vec3 color_mid : source_color = vec3(0.16, 0.88, 1.0);
uniform vec3 color_high : source_color = vec3(0.58, 0.24, 1.0);
uniform float speed = 0.42;
uniform float intensity = 1.65;
uniform float phase_offset = 0.0;

void vertex() {
	// Gentle horizontal ribbon wave in the sky
	float wave = sin(UV.x * 11.0 + TIME * speed + phase_offset) * 14.0
		+ cos(UV.x * 21.0 - TIME * speed * 0.7 + phase_offset) * 6.5;
	VERTEX.z += wave * (0.35 + 0.65 * UV.y);
}

void fragment() {
	float t = TIME * speed + phase_offset;
	// Vertical shimmering aurora rays
	float ray_a = 0.5 + 0.5 * sin(UV.x * 38.0 + t * 1.4 + sin(UV.x * 9.0 - t * 0.6) * 2.4);
	float ray_b = 0.5 + 0.5 * sin(UV.x * 74.0 - t * 2.1 + cos(UV.x * 15.0 + t) * 1.8);
	float streaks = pow(mix(ray_a, ray_b, 0.42), 1.65);

	// Soft vertical curtain envelope: crisp glowing lower edge, airy feathered top
	float lower_fade = smoothstep(0.0, 0.16, UV.y);
	float upper_fade = pow(1.0 - smoothstep(0.18, 1.0, UV.y), 1.45);
	float edge_fade = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));

	// Vertical aurora color gradient: emerald base -> turquoise body -> violet crown
	vec3 col = mix(color_low, color_mid, smoothstep(0.08, 0.48, UV.y));
	col = mix(col, color_high, smoothstep(0.42, 0.92, UV.y));

	float alpha = lower_fade * upper_fade * edge_fade * (0.38 + 0.62 * streaks);
	ALBEDO = col * intensity * (0.75 + 0.55 * streaks);
	ALPHA = clamp(alpha, 0.0, 0.92);
}

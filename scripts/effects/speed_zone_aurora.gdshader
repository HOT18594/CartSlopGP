shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cart Slop GP: high-contrast arcade speed pad with a deep navy energy bed,
// 3 forward-rushing neon cyan-gold chevron waves and glowing lateral rails.
// Pops vividly on bright snow, desert sand, concrete, and dark asphalt.

uniform vec4 deep_color : source_color = vec4(0.320, 0.075, 0.015, 1.0); // deep molten ember bed
uniform vec4 glow_color : source_color = vec4(1.000, 0.460, 0.050, 1.0); // vivid blazing orange
uniform vec4 crest_color : source_color = vec4(1.000, 0.960, 0.560, 1.0); // solar yellow-white crest
uniform vec4 edge_color : source_color = vec4(1.000, 0.740, 0.120, 1.0); // hot amber rail glow
uniform float intensity : hint_range(0.0, 5.0) = 2.6;
uniform float pulse_speed : hint_range(0.0, 4.0) = 1.05;
uniform float drift_speed : hint_range(0.0, 1.0) = 0.16;
uniform float curtain_speed : hint_range(0.0, 4.0) = 0.85;
uniform float chevron_speed : hint_range(0.0, 6.0) = 2.65;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 smooth_f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, smooth_f.x), mix(c, d, smooth_f.x), smooth_f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// Godot QuadMesh UV.y = 0.0 is local +Y. After the scene's -90 deg X
	// rotation that is world +Z (entry), so UV.y = 1.0 is the -Z boost exit.
	float forward_uv = uv.y;
	float abs_x = abs(uv.x - 0.5) * 2.0;

	// Sleek elliptical capsule falloff so ends feather smoothly with zero box cut.
	vec2 offset = (uv - vec2(0.5)) * 2.0;
	float ellip = 1.0 - smoothstep(0.48, 1.04, length(offset * vec2(0.88, 0.98)));
	float end_fade = smoothstep(0.0, 0.15, uv.y) * smoothstep(1.0, 0.85, uv.y);
	float side_fade = 1.0 - smoothstep(0.88, 1.0, abs_x);
	float falloff = clamp(ellip * 0.82 + end_fade * side_fade * 0.36, 0.0, 1.0);

	// Flowing plasma aurora curtains warped by two-octave noise.
	vec2 drift = vec2(t * drift_speed, -t * drift_speed * 1.45);
	float low = value_noise(vec2(uv.x * 3.8, forward_uv * 2.2) + drift);
	float high = value_noise(vec2(uv.x * 8.2, forward_uv * 4.0) - drift * 1.9);
	float warp = (low - 0.5) * 0.56 + (high - 0.5) * 0.22;

	float ribbon_a = sin((uv.x + warp * 1.05) * 18.0 + t * curtain_speed);
	float ribbon_b = sin((uv.x - warp * 0.85) * 10.5 - t * curtain_speed * 0.72 + 1.7);
	float ribbon_c = sin((uv.x + warp * 0.55) * 28.0 + t * curtain_speed * 1.55 + 0.6);
	float bands = ribbon_a * 0.50 + ribbon_b * 0.34 + ribbon_c * 0.16;
	float curtain = smoothstep(0.18, 0.82, bands * 0.5 + 0.5);

	// Forward plasma shimmer rushing toward -Z.
	float flow = sin(forward_uv * 6.2 - t * 2.8 + low * 4.2) * 0.5 + 0.5;
	float shimmer = 0.78 + 0.22 * flow;

	// 3 crisp, luminous forward-scrolling speed chevrons pointing toward -Z.
	float lane_mask = (1.0 - smoothstep(0.68, 0.88, abs_x)) * end_fade;
	float chev_coord = (forward_uv + abs_x * 0.34 + warp * 0.03) * 3.0 - t * chevron_speed;
	float chev_f = fract(chev_coord);
	float chev_wake = smoothstep(0.16, 0.66, chev_f) * smoothstep(0.90, 0.66, chev_f);
	float chev_core = exp(-pow((chev_f - 0.66) / 0.095, 2.0));
	float chevron = (chev_wake * 0.75 + chev_core * 1.15) * lane_mask;

	// High-contrast holographic edge rails at x ~ 0.08 and x ~ 0.92.
	float rail_dist = abs(abs(uv.x - 0.5) - 0.43);
	float rail_pulse = 0.75 + 0.25 * sin(forward_uv * 11.0 - t * chevron_speed * 2.8);
	float rail_core = exp(-pow(rail_dist / 0.017, 2.0)) * end_fade;
	float rail_glow = exp(-pow(rail_dist / 0.048, 2.0)) * end_fade * rail_pulse;
	float edge_aura = exp(-pow(rail_dist / 0.090, 2.0)) * end_fade;

	// Compose deep navy energy bed + cyan plasma + golden-white chevrons.
	vec3 bed = deep_color.rgb * (0.48 + 0.45 * curtain) * shimmer;
	vec3 plasma = mix(bed, glow_color.rgb * 0.85, curtain * 0.55);
	plasma = mix(plasma, edge_color.rgb, edge_aura * (0.45 + 0.25 * sin(t * 2.4 + forward_uv * 5.0)));

	vec3 chev_col = mix(glow_color.rgb, crest_color.rgb, clamp(chev_core * 0.92 + 0.18, 0.0, 1.0));
	vec3 rail_col = mix(glow_color.rgb, crest_color.rgb, clamp(rail_core * 0.85 + 0.2, 0.0, 1.0))
			+ edge_color.rgb * edge_aura * 0.38;

	float surge_boost = max(intensity - 2.6, 0.0) * 0.65;
	vec3 color = plasma
			+ chev_col * chevron * (1.35 + surge_boost)
			+ rail_col * (rail_glow * 1.05 + rail_core * 1.35);
	color *= (0.85 + 0.25 * clamp(intensity / 2.6, 0.0, 2.0));

	float pulse = 0.94 + 0.06 * sin(t * pulse_speed * TAU);
	float bed_alpha = falloff * (0.76 + 0.14 * curtain);
	float fx_alpha = clamp(chevron * 0.85 + rail_glow * 0.65 + rail_core * 0.55, 0.0, 1.0);
	float alpha = max(bed_alpha, fx_alpha) * clamp(intensity / 2.2, 0.6, 1.3) * pulse;

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 0.95);
}

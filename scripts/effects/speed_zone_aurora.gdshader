shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cart Slop GP: holographic arcade aurora speed zone with 3 forward-rushing
// chevron waves and glowing lateral rails. Unmistakable from 100 m away on
// tarmac, dirt, and bright glacier ice.

uniform vec4 deep_color : source_color = vec4(0.039, 0.133, 0.659, 1.0); // #0a22a8
uniform vec4 glow_color : source_color = vec4(0.078, 0.722, 1.000, 1.0); // #14b8ff
uniform vec4 crest_color : source_color = vec4(0.580, 1.000, 1.000, 1.0); // #94ffff
uniform vec4 edge_color : source_color = vec4(0.847, 0.361, 1.000, 1.0); // #d85cff
uniform float intensity : hint_range(0.0, 4.0) = 1.9;
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.85;
uniform float drift_speed : hint_range(0.0, 1.0) = 0.12;
uniform float curtain_speed : hint_range(0.0, 4.0) = 0.65;
uniform float chevron_speed : hint_range(0.0, 6.0) = 2.15;

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

	// 3 soft, luminous forward-scrolling speed chevrons pointing toward -Z.
	float lane_mask = (1.0 - smoothstep(0.64, 0.86, abs_x)) * end_fade;
	float chev_coord = (forward_uv + abs_x * 0.28 + warp * 0.05) * 3.0 - t * chevron_speed;
	float chev_f = fract(chev_coord);
	float chev_wake = smoothstep(0.14, 0.68, chev_f) * smoothstep(0.88, 0.68, chev_f);
	float chev_core = exp(-pow((chev_f - 0.68) / 0.092, 2.0));
	float chevron = (chev_wake * 0.68 + chev_core * 0.96) * lane_mask;

	// Sleek holographic edge rails at x ~ 0.08 and x ~ 0.92 (abs(uv.x - 0.5) = 0.42).
	float rail_dist = abs(abs(uv.x - 0.5) - 0.42);
	float rail_pulse = 0.72 + 0.28 * sin(forward_uv * 10.0 - t * chevron_speed * 2.6);
	float rail_core = exp(-pow(rail_dist / 0.015, 2.0)) * end_fade;
	float rail_glow = exp(-pow(rail_dist / 0.045, 2.0)) * end_fade * rail_pulse;
	float edge_aura = exp(-pow(rail_dist / 0.085, 2.0)) * end_fade;

	// Compose electric indigo -> vivid cyan -> neon aqua-white + magenta edge shimmer.
	vec3 plasma = mix(deep_color.rgb, glow_color.rgb, curtain);
	plasma = mix(plasma, crest_color.rgb, pow(curtain, 3.0) * 0.52);
	plasma = mix(plasma, edge_color.rgb, edge_aura * (0.42 + 0.26 * sin(t * 2.4 + forward_uv * 5.0)));
	plasma *= shimmer;

	vec3 chev_col = mix(glow_color.rgb, crest_color.rgb, clamp(chev_core * 0.85 + 0.25, 0.0, 1.0));
	vec3 rail_col = mix(glow_color.rgb, crest_color.rgb, clamp(rail_core * 0.9 + 0.2, 0.0, 1.0))
			+ edge_color.rgb * edge_aura * 0.35;

	float surge_boost = max(intensity - 1.9, 0.0) * 0.55;
	vec3 color = plasma * (0.65 + 0.45 * curtain)
			+ chev_col * chevron * (1.28 + surge_boost)
			+ rail_col * (rail_glow * 0.95 + rail_core * 1.15);
	color *= (0.78 + 0.28 * clamp(intensity / 1.9, 0.0, 2.0));

	float pulse = 0.92 + 0.08 * sin(t * pulse_speed * TAU);
	float field_alpha = falloff * (0.30 + 0.52 * curtain)
			+ chevron * 0.62
			+ rail_glow * 0.58
			+ rail_core * 0.42;
	float alpha = field_alpha * (intensity / 1.9) * pulse;

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 0.90);
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cart Slop GP: aurora speed zone. A translucent ground field of soft blue-cyan
// curtains that drift and breathe over the road. Every pad in the world shares
// this one material and one compiled shader; all motion comes from TIME, so
// nothing is animated or allocated from script.

uniform vec4 deep_color : source_color = vec4(0.02, 0.08, 0.55, 1.0);
uniform vec4 glow_color : source_color = vec4(0.08, 0.42, 1.00, 1.0);
uniform vec4 crest_color : source_color = vec4(0.32, 0.86, 1.00, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.9;
uniform float pulse_speed : hint_range(0.0, 2.0) = 0.5;
uniform float drift_speed : hint_range(0.0, 0.5) = 0.05;
uniform float curtain_speed : hint_range(0.0, 2.0) = 0.22;

// Two-octave value noise, cheap on purpose: no texture fetch, no loop, so the
// mobile renderer sees a handful of instructions per pixel on a small quad.
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

	// Soft elliptical falloff: the field ends in a glow, never a rectangle.
	vec2 offset = (uv - vec2(0.5)) * 2.0;
	float falloff = 1.0 - smoothstep(0.42, 1.05, length(offset * vec2(0.94, 1.0)));
	falloff *= falloff;

	// Low-frequency noise bends the curtains so they breathe instead of scroll.
	vec2 drift = vec2(t * drift_speed, -t * drift_speed * 0.62);
	float low = value_noise(uv * vec2(3.4, 1.7) + drift);
	float high = value_noise(uv * vec2(7.5, 3.1) - drift * 1.8);
	float warp = (low - 0.5) * 0.62 + (high - 0.5) * 0.22;

	// Vertical curtains: narrow light ribbons sliding across the field plus one
	// fine fold, all warped by the noise. Nothing has a hard edge, so the pad
	// never reads as paint, but the ribbons stay distinct from the dark gaps.
	float ribbon_a = sin((uv.x + warp * 1.1) * 18.0 + t * curtain_speed);
	float ribbon_b = sin((uv.x - warp * 0.9) * 9.5 - t * curtain_speed * 0.62 + 1.9);
	float ribbon_c = sin((uv.x + warp * 0.6) * 30.0 + t * curtain_speed * 1.5 + 0.7);
	float bands = ribbon_a * 0.52 + ribbon_b * 0.33 + ribbon_c * 0.15;
	float curtain = smoothstep(0.22, 0.80, bands * 0.5 + 0.5);

	// Slow energy travelling along the pad plus soft lengthwise breakup, so the
	// ribbons breathe instead of reading as uniform stripes.
	float flow = sin(uv.y * 4.6 - t * 0.5 + low * 5.0) * 0.5 + 0.5;
	float shimmer = 0.72 + 0.28 * flow;
	float length_var = mix(0.62, 1.0, smoothstep(0.15, 0.85, low * 0.6 + high * 0.4));

	vec3 color = mix(deep_color.rgb, glow_color.rgb, curtain);
	color = mix(color, crest_color.rgb, pow(curtain, 4.0) * 0.55);
	color *= shimmer;

	float pulse = 0.88 + 0.12 * sin(t * pulse_speed * TAU);
	float alpha = falloff * (0.34 + 0.95 * curtain) * length_var * intensity * pulse;

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 0.55);
}

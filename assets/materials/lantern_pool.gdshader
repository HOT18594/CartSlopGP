shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Soft radial warm lantern glow pool projected onto the ground beneath lanterns.
uniform vec4 pool_color : source_color = vec4(1.0, 0.68, 0.20, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.15;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	float core = exp(-r * r * 3.4);
	float halo = smoothstep(1.0, 0.08, r);
	float glow = (core * 0.65 + halo * halo * 0.45) * intensity;
	ALBEDO = pool_color.rgb * glow;
	ALPHA = clamp(glow * 0.68, 0.0, 0.78);
}

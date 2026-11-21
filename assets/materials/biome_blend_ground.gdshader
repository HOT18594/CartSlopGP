shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Cart Slop GP: Stylized Fluid Multi-Region Ground Shader
// Blends smoothly between vertex-colored terrain/floor regions with soft
// organic multi-octave FBM noise and subtle stylized ground grain — zero
// sharp boxy transitions between grass, dirt, sand, snow, ice, or stone!

uniform float noise_scale : hint_range(0.005, 0.25) = 0.045;
uniform float detail_scale : hint_range(0.05, 1.0) = 0.22;
uniform float blend_strength : hint_range(0.0, 0.35) = 0.14;
uniform float grain_strength : hint_range(0.0, 0.12) = 0.045;
uniform vec4 tint_a : source_color = vec4(0.95, 1.0, 0.90, 1.0);
uniform vec4 tint_b : source_color = vec4(1.05, 0.97, 0.88, 1.0);
uniform float roughness_val : hint_range(0.2, 1.0) = 0.86;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p = p * 2.07 + vec2(13.7, 29.3);
		amp *= 0.48;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = v_world_pos.xz;
	float macro_n = fbm(wp * noise_scale);
	float micro_n = vnoise(wp * detail_scale);
	float fine_n = vnoise(wp * (detail_scale * 3.1));

	// Smooth organic biome colour modulation & micro-grain on top of vertex blend.
	vec3 base = COLOR.rgb;
	vec3 patch_tint = mix(tint_a.rgb, tint_b.rgb, smoothstep(0.25, 0.78, macro_n));
	float grain = (micro_n * 0.65 + fine_n * 0.35 - 0.5) * 2.0 * grain_strength;
	vec3 col = base * mix(vec3(1.0), patch_tint, blend_strength * 3.5) + vec3(grain);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness_val + (micro_n - 0.5) * 0.08, 0.2, 0.98);
	METALLIC = 0.0;
}

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cart Slop GP: procedural tyre-mark ribbon (WS3).
//
// The ribbon geometry is a cheap two-vertex-wide strip; everything that makes a
// mark read as a real tyre is done here in the fragment shader, so one wheel
// still costs exactly one draw call and no tread texture asset:
//
//   UV.x = 0..1 across the tyre, UV.y = distance travelled along the mark (m).
//   COLOR.rgb = per-vehicle rubber tint, COLOR.a = fade.
//
// Four styles are authored: 0 slick (racing), 1 street (sipes + centre groove),
// 2 offroad (chunky staggered blocks) and 3 caster (two thin shopping-cart
// streaks). Everything uses only sin/fract/exp/hash: no textures, no compute,
// no derivatives that WebGL2 lacks, so the Compatibility renderer runs it.

uniform int tread_style : hint_range(0, 3) = 1;
uniform float tread_period : hint_range(0.05, 2.0) = 0.34;
uniform float tread_contrast : hint_range(0.0, 1.0) = 0.35;
uniform float edge_soft : hint_range(0.02, 0.45) = 0.16;
uniform float grit_strength : hint_range(0.0, 1.0) = 0.10;

// Deterministic 1D hash for the per-block grain (no noise texture needed).
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	float across = clamp(UV.x, 0.0, 1.0);
	float along = max(UV.y, 0.0);

	// Soft longitudinal edges: a tyre mark has a pressure falloff, not a cut.
	float edge = smoothstep(0.0, edge_soft, across)
			* smoothstep(1.0, 1.0 - edge_soft, across);

	float pattern = 1.0;
	float shade = 1.0;

	if (tread_style == 0) {
		// Racing slick: near-solid, a faint polished centre wear band.
		float wear = exp(-pow((across - 0.5) / 0.19, 2.0));
		shade = 0.84 + 0.16 * wear;
	} else if (tread_style == 1) {
		// Street tyre: repeating lateral sipes and a centre water groove.
		float s = fract(along / tread_period + across * 0.05);
		float sipe = smoothstep(0.40, 0.46, s) * smoothstep(0.63, 0.56, s);
		float groove = smoothstep(0.055, 0.0, abs(across - 0.5));
		float rounded = smoothstep(0.06, 0.14, across) * smoothstep(0.94, 0.86, across);
		pattern = mix(1.0, 1.0 - tread_contrast, sipe * rounded);
		pattern *= 1.0 - groove * 0.50;
		shade = 0.90 + 0.10 * (1.0 - sipe);
	} else if (tread_style == 2) {
		// Offroad tyre: two staggered columns of chunky blocks.
		float row = floor(along / (tread_period * 1.7));
		float stagger = mod(row, 2.0) * 0.5;
		float col = fract(across * 2.0 + stagger);
		float r = fract(along / (tread_period * 1.7));
		float block = smoothstep(0.12, 0.20, r) * smoothstep(0.92, 0.84, r)
				* smoothstep(0.08, 0.16, col) * smoothstep(0.92, 0.84, col);
		pattern = mix(1.0 - tread_contrast, 1.0, block);
		shade = 0.78 + 0.22 * block;
	} else {
		// Shopping-cart caster: two narrow streaks with a hollow centre, plus a
		// little caster-wheel wobble and grit so it does not read as one line.
		float centre = smoothstep(0.24, 0.34, across) * smoothstep(0.76, 0.66, across);
		pattern = 1.0 - centre;
		float wobble = sin(along * 7.0) * 0.02;
		pattern *= smoothstep(0.0, 0.08, abs(across - 0.5 + wobble));
		shade = 0.88;
	}

	// Fine blocky grain: a mark is rubber + grit, never flat plastic. The hash
	// is evaluated on a quantised lattice so it stays stable as the mark fades.
	float grain = 1.0 - grit_strength * hash11(
			floor(along * 24.0) + floor(across * 13.0) * 7.0);

	ALBEDO = COLOR.rgb * shade * grain;
	ALPHA = clamp(COLOR.a * pattern * edge, 0.0, 1.0);
}

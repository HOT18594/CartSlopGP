shader_type canvas_item;

// Clips any TextureRect / preview image into a crisp anti-aliased slanted
// parallelogram with optional hover sheen and subtle ink outline.
uniform float skew_uv : hint_range(0.0, 0.25) = 0.075;
uniform float border_px : hint_range(0.0, 8.0) = 2.5;
uniform vec4 border_color : source_color = vec4(0.11, 0.11, 0.22, 1.0);
uniform float sheen_pos : hint_range(-0.5, 1.6) = 2.0;

void fragment() {
	vec2 uv = UV;
	// Top edge shifts right by skew_uv; bottom edge sits at 0..(1 - skew_uv).
	float left_edge = (1.0 - uv.y) * skew_uv;
	float right_edge = 1.0 - uv.y * skew_uv;

	vec2 px = max(fwidth(uv), vec2(0.001));
	float d_left = (uv.x - left_edge) / px.x;
	float d_right = (right_edge - uv.x) / px.x;
	float d_top = uv.y / px.y;
	float d_bot = (1.0 - uv.y) / px.y;
	float dist = min(min(d_left, d_right), min(d_top, d_bot));

	float mask = smoothstep(-0.75, 0.75, dist);
	if (mask <= 0.001) {
		discard;
	}

	vec4 tex = texture(TEXTURE, uv) * COLOR;
	// Optional animated diagonal sheen sweep across the clipped preview
	float diag = uv.x + (1.0 - uv.y) * 0.35;
	float band = exp(-pow((diag - sheen_pos) / 0.08, 2.0)) * 0.22;
	tex.rgb += vec3(band);

	// Crisp border rim along the slanted parallelogram silhouette
	float rim = 1.0 - smoothstep(border_px - 0.7, border_px + 0.7, dist);
	vec3 final_rgb = mix(tex.rgb, border_color.rgb, rim * border_color.a);
	COLOR = vec4(final_rgb, tex.a * mask);
}

shader_type spatial;
// Inverted-hull cartoon outline. The mesh is pushed out along its normals and
// only the back faces are drawn, so a dark rim appears around the silhouette.
// Cheap enough for the Mobile renderer (no screen-space pass, no depth read).
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.1176, 0.1059, 0.2275, 1.0);
uniform float thickness = 0.02;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

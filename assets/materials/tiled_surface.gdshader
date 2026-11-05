shader_type spatial;
render_mode cull_disabled;

// Tileable ground / road surface for the Meadow Loop minigame.
// repeat_enable is explicit so the imported texture wraps regardless of the
// texture importer's repeat setting.
uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float uv_scale = 1.0;

void fragment() {
	ALBEDO = texture(albedo_tex, UV * uv_scale).rgb * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

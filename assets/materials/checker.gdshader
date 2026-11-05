shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Simple painted checkerboard for start/finish lines and trim strips.
uniform vec4 light_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 dark_color : source_color = vec4(0.118, 0.106, 0.227, 1.0);
uniform vec2 cells = vec2(16.0, 2.0);

void fragment() {
	vec2 cell = floor(UV * cells);
	float checker = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(light_color.rgb, dark_color.rgb, checker);
}

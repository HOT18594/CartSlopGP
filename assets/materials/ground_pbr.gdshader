shader_type spatial;
render_mode cull_disabled;

// Tileable CC0 Poly Haven PBR ground / road. repeat_enable is explicit so
// wrapping does not depend on the texture importer's repeat setting.
// The normal map is used both as a roughness/detail source and to fake fine
// bump in the albedo, which avoids needing per-vertex tangents on the huge
// flat ground plane.

uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D rough_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float uv_scale = 1.0;
uniform float detail_strength = 0.16;
uniform float macro_variation = 0.07;
uniform float roughness_min = 0.55;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 base = texture(albedo_tex, uv).rgb * tint;
	vec3 n = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	// Cheap bump: brighten/darken by the normal-map slope.
	base *= 1.0 + (n.x + n.y) * detail_strength;
	// Wide, soft colour drift so a 1.4 km plane does not read as one flat tile.
	float macro = sin(v_world.x * 0.031) * sin(v_world.z * 0.037)
		+ 0.5 * sin(v_world.x * 0.013 + v_world.z * 0.021);
	base *= 1.0 + macro * macro_variation;
	ALBEDO = max(base, vec3(0.0));
	ROUGHNESS = clamp(texture(rough_tex, uv).r, roughness_min, 1.0);
	SPECULAR = 0.08;
}

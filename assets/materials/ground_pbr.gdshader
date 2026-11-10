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
uniform float track_strength = 0.0; // 0 = off; road sets ~0.12
uniform bool use_vertex_color = false; // terrain tint (grass / road / bowl)

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 base = texture(albedo_tex, uv).rgb * tint;
	if (use_vertex_color) {
		// Vertex colours carry the zone palette (grass, road, bowl, dirt).
		// Multiplying keeps the texture detail instead of flattening the mesh.
		base *= COLOR.rgb;
	}
	vec3 n = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	// Cheap bump: brighten/darken by the normal-map slope.
	base *= 1.0 + (n.x + n.y) * detail_strength;
	// Wide, soft colour drift so a 1.4 km plane does not read as one flat tile.
	float macro = sin(v_world.x * 0.031) * sin(v_world.z * 0.037)
		+ 0.5 * sin(v_world.x * 0.013 + v_world.z * 0.021);
	base *= 1.0 + macro * macro_variation;
	// Two worn wheel bands down the road. UV.x runs across the ribbon, so this
	// follows every corner without any extra geometry.
	if (track_strength > 0.0) {
		float across = fract(UV.x);
		float left = 1.0 - smoothstep(0.0, 0.075, abs(across - 0.28));
		float right = 1.0 - smoothstep(0.0, 0.075, abs(across - 0.72));
		base *= 1.0 - track_strength * (left + right);
	}
	ALBEDO = max(base, vec3(0.0));
	ROUGHNESS = clamp(texture(rough_tex, uv).r, roughness_min, 1.0);
	SPECULAR = 0.08;
}

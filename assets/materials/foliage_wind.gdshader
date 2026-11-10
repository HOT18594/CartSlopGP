shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Alpha-cutout foliage card (leaves, fronds, grass) with two-sided lighting,
// gusting wind and a push-away deformation where the kart drives through.
// One material is shared by every MultiMesh; per-instance phase comes from
// MODEL_MATRIX so thousands of cards never sway in lockstep.

uniform sampler2D card_tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float alpha_cutoff = 0.42;
uniform float sway_height = 8.0;      // local Y at which sway reaches full strength
uniform float wind_strength = 0.28;
uniform float wind_speed = 1.15;
uniform float phase_offset = 0.0;
uniform vec3 kart_position = vec3(0.0, -1000.0, 0.0);
uniform float bend_radius = 5.0;
uniform float bend_strength = 0.85;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.13 + origin.z * 0.09 + phase_offset;
	float t = TIME * wind_speed + phase;
	float h = clamp(VERTEX.y / max(sway_height, 0.01), 0.0, 1.0);
	h *= h;
	float gust = sin(t) * 0.65 + sin(t * 1.83 + 1.7) * 0.35;
	VERTEX.x += gust * wind_strength * h;
	VERTEX.z += cos(t * 0.77 + phase) * wind_strength * 0.7 * h;

	vec3 away = origin - kart_position;
	away.y = 0.0;
	float d = length(away);
	if (d < bend_radius && d > 0.001) {
		float push = 1.0 - d / bend_radius;
		vec3 world_push = normalize(away) * push * push * bend_strength * h;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(world_push, 0.0)).xyz;
	}
}

void fragment() {
	vec4 texel = texture(card_tex, UV);
	// Alpha scissor (rather than discard) so the shadow/depth pass cuts the
	// same leaf silhouette - otherwise every card casts a square shadow.
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ALBEDO = texel.rgb * tint;
	ROUGHNESS = 0.88;
	SPECULAR = 0.04;
}

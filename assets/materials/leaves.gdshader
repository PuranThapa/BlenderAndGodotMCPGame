// Tree foliage: photo leaf-cluster atlas on cards. Alpha-scissor cut-outs,
// two-sided with the crown-outward normals kept on both faces, translucent
// back-lighting, and a gentle height-weighted wind sway.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.45;
uniform float translucency = 0.55;
uniform float wind_strength = 0.05;
uniform float tree_height = 8.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / tree_height, 0.0, 1.2);
	float t = TIME;
	float sway = sin(t * 1.3 + wp.x * 0.15 + wp.z * 0.1) * 0.6 + sin(t * 2.7 + wp.x * 0.9 + wp.y * 0.7) * 0.4;
	VERTEX.x += sway * wind_strength * h;
	VERTEX.z += cos(t * 1.1 + wp.z * 0.2 + wp.y * 0.5) * wind_strength * 0.6 * h;
	VERTEX.y += sin(t * 3.3 + wp.x + wp.z) * wind_strength * 0.25 * h;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	// Mipmaps average alpha toward the transparent background, which would
	// make distant trees go thin; boost alpha with the mip level to compensate.
	vec2 tsize = vec2(textureSize(albedo_tex, 0));
	vec2 dx = dFdx(UV * tsize);
	vec2 dy = dFdy(UV * tsize);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALBEDO = c.rgb * tint;
	ALPHA = clamp(c.a * (1.0 + lod * 0.28), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = c.rgb * tint * translucency;
	// Two-sided: Godot flips NORMAL on back faces; undo it so both sides keep
	// the crown-outward normal and the canopy shades as one soft volume.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

// Procedural roof tiles for the gable PrismMesh roofs. Sloped faces get rows
// of staggered tiles with shadowed lower edges; the vertical gable-end
// triangles take the house's wall colour instead.
shader_type spatial;

uniform vec3 tile_color : source_color = vec3(0.30, 0.30, 0.32);
uniform vec3 gable_color : source_color = vec3(0.85, 0.80, 0.70);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (abs(wnrm.y) < 0.15) {
		ALBEDO = gable_color;
		ROUGHNESS = 0.9;
	} else {
		// Distance along the ridge = the horizontal axis the normal doesn't face.
		float along = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
		float row_f = wpos.y / 0.16;
		float row = floor(row_f);
		float f = fract(row_f);
		float col_f = along / 0.28 + mod(row, 2.0) * 0.5;
		float cell = floor(col_f);
		float detail = clamp(1.6 - length(fwidth(vec2(col_f, row_f))) * 5.0, 0.0, 1.0);
		float gap = step(fract(col_f), 0.04) * detail;
		float edge = mix(1.0, mix(0.62, 1.0, smoothstep(0.0, 0.25, f)), detail);
		float v = 1.0 + (hash(vec2(cell, row)) - 0.5) * 0.22 * detail;
		ALBEDO = tile_color * edge * v * (1.0 - gap * 0.35);
		ROUGHNESS = 0.82;
	}
}

// Procedural building facade, mapped in world space so any box wall works.
// pattern: 0 = brick (running bond), 1 = painted clapboard siding, 2 = render/stucco.
shader_type spatial;

uniform int pattern = 0;
uniform vec3 base_color : source_color = vec3(0.56, 0.29, 0.22);
uniform vec3 mortar_color : source_color = vec3(0.70, 0.68, 0.63);
uniform float roughness_value = 0.9;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.x > n.z ? wpos.zy : wpos.xy;
	if (n.y > 0.7) {
		uv = wpos.xz;
	}
	// Large-scale weathering so walls don't look flat.
	float grime = 0.92 + 0.08 * vnoise(uv * 0.7);
	vec3 col = base_color;
	float rough = roughness_value;
	if (pattern == 0) {
		vec2 b = uv / vec2(0.225, 0.075);
		float row = floor(b.y);
		b.x += mod(row, 2.0) * 0.5;
		vec2 cell = floor(b);
		vec2 f = fract(b);
		// Fade fine detail as bricks shrink on screen to avoid moire.
		float detail = clamp(1.6 - length(fwidth(b)) * 5.0, 0.0, 1.0);
		float mortar = max(step(f.x, 0.045), step(f.y, 0.13)) * detail;
		float v = (hash(cell) * 0.28 - 0.14) * detail;
		col = base_color * (1.0 + v) * (0.93 + 0.07 * vnoise(uv * 40.0));
		col = mix(col, mortar_color, mortar);
		// Distant walls average to brick + some mortar rather than flickering.
		col = mix(mix(base_color, mortar_color, 0.18), col, detail);
		rough = mix(rough, 0.97, mortar);
	} else if (pattern == 1) {
		float y = uv.y / 0.19;
		float f = fract(y);
		// Each board's lower edge overlaps the one below: a soft shadow line.
		float shade = mix(0.74, 1.0, smoothstep(0.0, 0.22, f));
		col = base_color * shade * (0.96 + 0.04 * vnoise(vec2(uv.x * 1.5, floor(y) * 7.0)));
		rough = 0.75;
	} else {
		col = base_color * (0.9 + 0.1 * vnoise(uv * 3.0)) * (0.95 + 0.05 * vnoise(uv * 35.0));
	}
	ALBEDO = col * grime;
	ROUGHNESS = rough;
}

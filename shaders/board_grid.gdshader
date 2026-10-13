shader_type spatial;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = mat3(MODEL_MATRIX) * NORMAL;
}

void fragment() {
	vec3 base = vec3(0.36, 0.39, 0.43);
	if (world_normal.y > 0.5) {
		vec2 cells = world_position.xz + vec2(15.0);
		vec2 edge = abs(fract(cells + 0.5) - 0.5);
		vec2 pixel_width = max(fwidth(cells), vec2(0.001));
		vec2 lines = 1.0 - smoothstep(vec2(0.012), vec2(0.012) + pixel_width, edge);
		float grid = max(lines.x, lines.y);
		vec2 major_cells = cells / 5.0;
		vec2 major_edge = abs(fract(major_cells + 0.5) - 0.5);
		vec2 major_lines = 1.0 - smoothstep(vec2(0.005), vec2(0.005) + fwidth(major_cells), major_edge);
		float major = max(major_lines.x, major_lines.y);
		base = mix(base, vec3(0.13, 0.16, 0.20), max(grid * 0.6, major * 0.9));
	}
	ALBEDO = base;
	ROUGHNESS = 0.85;
}

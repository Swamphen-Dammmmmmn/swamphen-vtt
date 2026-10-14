uniform vec4 surface_color : source_color = vec4(0.3, 0.5, 0.8, 1.0);
uniform float surface_roughness = 0.85;
uniform float grain_strength = 0.0;
uniform float surface_metallic = 0.0;
uniform float edge_strength = 0.0;
uniform float opacity = 1.0;
uniform vec3 face_axis = vec3(0.0, 0.0, 1.0);
varying vec3 local_position;
varying float side_surface;
float grain(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
void vertex() {
	local_position = VERTEX;
	side_surface = 1.0 - abs(dot(normalize(NORMAL), normalize(face_axis)));
}
void fragment() {
	float edge = smoothstep(0.4, 0.8, side_surface) * edge_strength;
	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	vec3 cell = floor(local_position * 350.0);
	float texture_grain = grain(cell) - 0.5;
	vec3 micro_normal = vec3(grain(cell + 7.0), grain(cell + 19.0), grain(cell + 41.0)) - 0.5;
	NORMAL = normalize(NORMAL + micro_normal * grain_strength * 0.20);
	vec3 tint = mix(surface_color.rgb, mix(surface_color.rgb, vec3(0.9, 0.95, 1.0), 0.25), edge);
	ALBEDO = clamp(tint * (1.0 + texture_grain * grain_strength * 0.10), vec3(0), vec3(1));
	ROUGHNESS = clamp(surface_roughness + edge * 0.06 + texture_grain * grain_strength * 0.06, 0.0, 1.0);
	SPECULAR = 0.5 + edge_strength * 0.05;
	METALLIC = surface_metallic;
#ifdef SURFACE_TRANSPARENT
	ALPHA = clamp(opacity + edge * 0.16 + grazing * edge_strength * 0.22, 0.0, 1.0);
#endif
}

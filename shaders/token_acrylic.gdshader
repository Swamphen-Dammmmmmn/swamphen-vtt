shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 plate_color : source_color = vec4(0.945, 0.969, 0.98, 1.0);
uniform float opacity : hint_range(0.0, 0.6) = 0.10;
uniform float surface_roughness : hint_range(0.05, 0.8) = 0.60;
varying float side_surface;

void vertex() {
	// Geometry normals, independent of component rotation and camera angle.
	side_surface = 1.0 - abs(NORMAL.z);
}

void fragment() {
	float edge = smoothstep(0.4, 0.8, side_surface);
	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = mix(plate_color.rgb, mix(plate_color.rgb, vec3(0.9, 0.95, 1.0), 0.25), edge);
	METALLIC = 0.0;
	SPECULAR = 0.55;
	ROUGHNESS = clamp(surface_roughness + edge * 0.06, 0.05, 0.85);
	ALPHA = clamp(opacity + edge * 0.16 + grazing * 0.22, 0.0, 0.78);
}

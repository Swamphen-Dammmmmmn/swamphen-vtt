shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;

#include "res://shaders/grass_wind.gdshaderinc"

uniform vec4 grass_color : source_color = vec4(0.25, 0.72, 0.35, 1.0);
uniform float softness = 0.55;
uniform float wind_time = 0.0;
uniform float wind_direction = 35.0;
uniform float wind_strength = 0.8;
uniform float gust_strength = 0.6;
uniform float gust_frequency = 0.18;
uniform float wave_width_feet = 30.0;
uniform float wave_speed_feet = 8.0;
uniform float sway_period = 1.0;
uniform float sway_amplitude = 0.51;
uniform float distant_width = 1.5;
uniform bool coverage_enabled = false;
uniform sampler2D coverage_mask : filter_linear, repeat_disable;
uniform vec2 coverage_origin = vec2(0.0);
uniform vec2 coverage_size = vec2(1.0);
varying float root_coverage;
varying float blade_height;
varying float blade_tint;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 upright = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 1.0)).xyz - root;
	float height = max(length(upright), 0.001);
	root_coverage = coverage_enabled ? texture(coverage_mask,(root.xz-coverage_origin)/coverage_size).r : 1.0;
	float t = UV.y;
	float weight = t * t;
	float angle = radians(wind_direction);
	vec2 wind = vec2(sin(angle), cos(angle));
	vec2 side = vec2(wind.y, -wind.x);
	float gust = grass_wind_gust(root.xz, wind_time, wind_direction, gust_frequency, wave_width_feet, wave_speed_feet);
	float phase = grass_wind_phase(root.xz, wind_time, wind_direction, 1.0 / max(sway_period, 0.1), wave_speed_feet);
	phase += (INSTANCE_CUSTOM.r - 0.5) * 0.25;
	float ripple = sin(wind_time * 2.4 + INSTANCE_CUSTOM.r * TAU + dot(root.xz, wind) * 0.8);
	float swing = sin(phase);
	// Continuous asymmetric cycle: +1 downwind, -0.375 upwind, crossing upright.
	float asymmetric = swing * 0.6875 + swing * swing * 0.3125;
	float boost = 1.0 + max(swing, 0.0) * gust_strength * gust * 0.5;
	float bend = clamp(sway_amplitude * asymmetric * boost * wind_strength * softness * INSTANCE_CUSTOM.b, -0.6, 1.1);
	float side_sway = sway_amplitude * (sin(phase + 0.6) * 0.10 + ripple * 0.028);
	vec2 displacement = wind * bend + side * side_sway * wind_strength * softness;
	// Static individual lean remains even when wind is zero; roots stay anchored.
	displacement += vec2(sin(INSTANCE_CUSTOM.r * TAU), cos(INSTANCE_CUSTOM.r * TAU)) * 0.025;
	float distance_to_camera = distance(root, CAMERA_POSITION_WORLD);
	float widen = mix(1.0, distant_width, smoothstep(8.0, 30.0, distance_to_camera));
	// Widen across the blade only; root and height do not move with camera distance.
	VERTEX += MODEL_MATRIX[0].xyz * (UV.x - 0.5) * (widen - 1.0);
	VERTEX.xz += displacement * height * weight;
	VERTEX.y -= min(dot(displacement, displacement) * 0.25, 0.35) * height * weight;
	vec3 width_axis = normalize(MODEL_MATRIX[0].xyz);
	vec3 tangent = normalize(upright + vec3(displacement.x, 0.0, displacement.y) * height * 2.0 * t);
	NORMAL = normalize(cross(width_axis, tangent));
	float amount = 1.0 - smoothstep(30.0, 70.0, distance_to_camera);
	float presence = smoothstep(INSTANCE_CUSTOM.a - 0.04, INSTANCE_CUSTOM.a + 0.04, amount);
	VERTEX = root + (VERTEX - root) * presence * step(0.015,root_coverage);
	blade_height = t;
	blade_tint = INSTANCE_CUSTOM.g;
}

void fragment() {
	if (root_coverage < 0.015) { discard; }
	vec3 face_normal = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 upward = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Both faces receive mostly upward lighting, with a little bending response.
	NORMAL = normalize(mix(face_normal, upward, 0.85));
	float shading = mix(0.94, 1.03, blade_height) * mix(0.97, 1.04, blade_tint);
	ALBEDO = clamp(grass_color.rgb * shading, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}

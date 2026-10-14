shader_type spatial;
render_mode diffuse_burley;

uniform vec4 stone_color : source_color = vec4(0.49, 0.52, 0.52, 1.0);
uniform float variation : hint_range(0.0, 0.5) = 0.12;
uniform float surface_roughness : hint_range(0.3, 1.0) = 0.88;
uniform float seed = 1.0;
varying vec3 stone_position;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33 + seed * 0.001);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	stone_position = VERTEX;
}

void fragment() {
	float patches = noise3(stone_position * 1.9 + vec3(seed * 0.013));
	float grains = noise3(stone_position * 36.0);
	float shade = 1.0 + (patches - 0.5) * variation * 1.5 + (grains - 0.5) * variation * 0.16;
	ALBEDO = clamp(stone_color.rgb * shade, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(surface_roughness + (grains - 0.5) * 0.04, 0.3, 1.0);
	METALLIC = 0.0;
}

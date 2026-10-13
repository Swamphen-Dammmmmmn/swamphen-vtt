shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/grass_wind.gdshaderinc"

uniform sampler2DArray detail_masks : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D macro_mask : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_microstructure : repeat_enable, filter_linear_mipmap_anisotropic;
#include "res://shaders/sand_surface.gdshaderinc"

uniform bool sand_surface = false;
uniform float patch_strength = 0.35;
uniform float grain_normal = 0.18;
uniform float glint_strength = 0.55;
uniform float glint_density = 0.18;
uniform vec4 base_color : source_color = vec4(0.25, 0.68, 0.32, 1.0);
uniform float contrast : hint_range(0.0, 1.0) = 0.5;
// One Godot world unit = five feet. Offset is in platform-local world units.
uniform float texture_feet : hint_range(2.0, 30.0) = 10.0;
uniform vec2 ground_offset = vec2(0.0);
uniform uint pattern_seed = 1u;
uniform bool varied = true;
uniform int single_variant : hint_range(0, 3) = 0;
uniform float grain_strength = 0.10;
uniform bool ground_wind_enabled = false;
uniform float wind_time = 0.0;
uniform float wind_direction = 35.0;
uniform float wind_strength = 0.8;
uniform float gust_strength = 0.6;
uniform float gust_frequency = 0.18;
uniform float wave_width_feet = 30.0;
uniform float wave_speed_feet = 8.0;
uniform float sway_period = 1.0;
uniform float sway_amplitude = 0.51;
uniform float softness = 0.55;
uniform float ground_wave_strength = 0.07;
uniform float relief_feet = 0.0;
uniform float ripple_strength = 0.0;
varying vec2 ground_position;

float sand_height(vec2 p) {
 vec2 q=p+ground_offset;
 float seed=float(pattern_seed % 97u)/97.0;
 vec3 broad=textureLod(macro_mask,q/41.0+vec2(seed,0.37),0.0).rgb;
 // Only broad undulations displace the mesh. Fine ripples are shading normals.
 float edge=1.0-smoothstep(5.5,8.0,max(abs(p.x),abs(p.y)));
 float reserve=smoothstep(0.6,2.6,length(p))*(1.0-smoothstep(3.4,6.4,p.y));
 return relief_feet/5.0*(0.55+(broad.r-0.5)*0.65+(broad.g-0.5)*0.2)*edge*reserve;
}

varying vec3 ground_axis_x;
varying vec3 ground_axis_z;

varying vec3 ground_world_position;

uint mix_bits(uint value) {
	value = (value ^ (value >> 16u)) * 2246822519u;
	value = (value ^ (value >> 13u)) * 3266489917u;
	return value ^ (value >> 16u);
}

vec3 patch_sample(vec2 cell, vec2 uv, vec2 dx, vec2 dy) {
	ivec2 signed_cell = ivec2(cell);
	uint hash = mix_bits(uint(signed_cell.x) * 73856093u ^ uint(signed_cell.y) * 19349663u ^ pattern_seed);
	vec2 offset = vec2(float((hash >> 8u) & 255u), float((hash >> 16u) & 255u)) / 256.0;
	// Mirror both coordinates; use identical transformations on explicit derivatives.
	vec2 flip = vec2((hash & 4u) == 0u ? 1.0 : -1.0, (hash & 8u) == 0u ? 1.0 : -1.0);
	return textureGrad(detail_masks, vec3(uv * flip + offset, float(hash & 3u)), dx * flip, dy * flip).rgb;
}

void vertex() {
	ground_position = VERTEX.xz + ground_offset;
	ground_axis_x = normalize((MODELVIEW_MATRIX*vec4(1.0,0.0,0.0,0.0)).xyz);
	ground_axis_z = normalize((MODELVIEW_MATRIX*vec4(0.0,0.0,1.0,0.0)).xyz);
 if (relief_feet > 0.0) {
  vec2 p = VERTEX.xz;
  VERTEX.y += sand_height(p);
  float e = 0.015;
  NORMAL = normalize(vec3((sand_height(p-vec2(e,0.0))-sand_height(p+vec2(e,0.0)))/(2.0*e), 1.0, (sand_height(p-vec2(0.0,e))-sand_height(p+vec2(0.0,e)))/(2.0*e)));
 }

	ground_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = ground_position * (5.0 / max(texture_feet, 0.1));
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec3 detail;
	if (varied) {
		// Patch distribution is independent of the five-foot game grid.
		vec2 distribution = ground_position / 3.73;
		vec2 cell = floor(distribution);
		vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(distribution));
		vec3 a = patch_sample(cell, uv, dx, dy);
		vec3 b = patch_sample(cell + vec2(1.0, 0.0), uv, dx, dy);
		vec3 c = patch_sample(cell + vec2(0.0, 1.0), uv, dx, dy);
		vec3 d = patch_sample(cell + vec2(1.0), uv, dx, dy);
		detail = mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
	} else {
		detail = textureGrad(detail_masks, vec3(uv, float(single_variant)), dx, dy).rgb;
	}
	vec3 broad = texture(macro_mask, ground_position / 43.7 + vec2(float(pattern_seed % 97u) / 97.0)).rgb;
	float tonal = (detail.g - 0.5) * 0.12 + (broad.r - 0.5) * 0.22 + (broad.b - 0.5) * 0.07;
	float flecks = detail.r * grain_strength - detail.b * grain_strength * 0.65;
	vec3 color = base_color.rgb * (1.0 + contrast * (tonal + flecks));
	ROUGHNESS = 0.92;
	SPECULAR = 0.5;
	if (sand_surface) {
  vec3 fields = sand_fields(ground_position,float(pattern_seed % 97u)/97.0);
  color = sand_surface_color(base_color.rgb,detail,fields,contrast,grain_strength,patch_strength);
  float phase = sand_ripple_phase(ground_position,fields);
  float ripple_aa = 1.0-smoothstep(0.5,2.5,fwidth(phase));
  NORMAL = sand_grain_normal(NORMAL,VERTEX,sin(phase)*sand_ripple_coverage(fields),ripple_strength*3.0*ripple_aa);
  vec4 micro = sand_micro_sample(ground_position,float(pattern_seed % 97u)/97.0);
  float visibility = sand_micro_visibility(ground_position,distance(ground_world_position,CAMERA_POSITION_WORLD));
  color = sand_near_color(color,ground_position,float(pattern_seed % 97u)/97.0,visibility);
  float crystal = sand_crystals(micro,glint_density,visibility);
  NORMAL = sand_facet_normal(NORMAL,ground_axis_x,ground_axis_z,micro,grain_normal*visibility+crystal*glint_strength*0.65);
  ROUGHNESS = sand_material_roughness(micro,visibility,crystal,glint_strength);
  SPECULAR = 0.4;

 }
 // Tiny warm/cool shifts retain color variation without baking lighting.
	if (!sand_surface) color += vec3(0.012, 0.008, -0.009) * (broad.g - 0.5) * contrast;
	if (ground_wind_enabled) {
		float gust = grass_wind_gust(ground_world_position.xz, wind_time, wind_direction, gust_frequency, wave_width_feet, wave_speed_feet);
		float phase = grass_wind_phase(ground_world_position.xz, wind_time, wind_direction, 1.0 / max(sway_period, 0.1), wave_speed_feet);
		float far_amount = smoothstep(10.0, 35.0, distance(ground_world_position, CAMERA_POSITION_WORLD));
		float flow = sin(phase) * 0.25 + (gust - 0.4) * gust_strength * 0.7;
		float response = clamp(sway_amplitude / 0.36, 0.0, 2.0) * clamp(softness, 0.0, 1.5);
		float modulation = clamp(flow * ground_wave_strength * wind_strength * response * far_amount * (0.75 + broad.g * 0.5), -0.08, 0.08);
		color *= 1.0 + modulation;
	}
	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	METALLIC = 0.0;
}

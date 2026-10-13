shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D shore_mask : filter_linear, repeat_disable;
uniform vec4 beach_color : source_color;
#include "res://shaders/water_surface.gdshaderinc"

uniform sampler2D cover_mask : filter_linear, repeat_disable;
uniform sampler2DArray grass_masks : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray sand_masks : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_microstructure : repeat_enable, filter_linear_mipmap_anisotropic;
#include "res://shaders/sand_surface.gdshaderinc"

uniform float sand_patch_strength = 0.35;
uniform float sand_grain_strength = 0.18;
uniform float sand_glint_strength = 0.55;
uniform float sand_glint_density = 0.18;
uniform float sand_ripple_strength = 0.055;
uniform bool independent_sand_details = false;
uniform float beach_grain_feet = 6.0;
uniform float beach_color_strength = 0.7;
uniform float beach_patch_strength = 0.35;
uniform float beach_grain_strength = 0.18;
uniform float beach_glint_strength = 0.55;
uniform float beach_glint_density = 0.18;
uniform float beach_ripple_strength = 0.055;
uniform vec2 area_size = vec2(16.0);
uniform vec2 shore_texel = vec2(0.0052083333);
uniform float top_scene_height = 0.002;
#include "res://shaders/grass_wind.gdshaderinc"
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
uniform float sand_seed_offset = 0.010309;
uniform vec4 grass_color : source_color;
uniform vec4 sand_color : source_color;
uniform vec2 area_origin = vec2(18.0,-8.0);
varying vec2 floor_position;
varying vec3 floor_axis_x;
varying vec3 floor_axis_z;

void vertex() {
	floor_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
	floor_axis_x = normalize((MODELVIEW_MATRIX*vec4(1.0,0.0,0.0,0.0)).xyz);
	floor_axis_z = normalize((MODELVIEW_MATRIX*vec4(0.0,0.0,1.0,0.0)).xyz);
}

void fragment() {
	vec2 uv = (floor_position-area_origin)/area_size;
	vec4 weights = texture(cover_mask,uv);
	weights /= max(dot(weights,vec4(1.0)),0.0001);
	float cover = weights.r;
	vec2 detail_uv = floor_position*0.5;
	vec2 dx = dFdx(detail_uv);
	vec2 dy = dFdy(detail_uv);
	vec3 broad = texture(macro_mask,floor_position/43.7).rgb;
	vec2 patch_uv = floor_position/3.73;
	vec2 cell = floor(patch_uv);
	vec2 weight = smoothstep(vec2(0.0),vec2(1.0),fract(patch_uv));
	vec3 grass_detail = vec3(0.0);
	vec3 sand_detail = vec3(0.0);
	for (int z=0; z<2; z++) {
		for (int x=0; x<2; x++) {
			vec2 c = cell+vec2(float(x),float(z));
			float hash = fract(sin(dot(c,vec2(127.1,311.7)))*43758.5453);
			float layer = floor(hash*4.0);
			vec2 shift = vec2(hash,fract(hash*17.37));
			float amount = (x==0?1.0-weight.x:weight.x)*(z==0?1.0-weight.y:weight.y);
			grass_detail += textureGrad(grass_masks,vec3(detail_uv+shift,layer),dx,dy).rgb*amount;
			sand_detail += textureGrad(sand_masks,vec3(detail_uv+shift,layer),dx,dy).rgb*amount;
		}
	}
	float tone = (broad.r-0.5)*0.22+(broad.b-0.5)*0.07;
	vec3 grass = grass_color.rgb*(1.0+0.65*(tone+(grass_detail.g-0.5)*0.12+grass_detail.r*0.24-grass_detail.b*0.156));
	if (ground_wind_enabled) {
	 float gust=grass_wind_gust(floor_position,wind_time,wind_direction,gust_frequency,wave_width_feet,wave_speed_feet);
	 float phase=grass_wind_phase(floor_position,wind_time,wind_direction,1.0/max(sway_period,0.1),wave_speed_feet);
	 float wave=sin(phase)*ground_wave_strength*wind_strength*(0.5+gust*gust_strength);
	 float far_mix=smoothstep(8.0,30.0,distance(vec3(floor_position.x,top_scene_height,floor_position.y),CAMERA_POSITION_WORLD));
	 grass *= 1.0+wave*far_mix;
	}
	vec3 fields = sand_fields(floor_position,sand_seed_offset);
	float beach_mix = weights.b/max(weights.g+weights.b,0.0001);
	float details_mix=independent_sand_details?beach_mix:0.0;
	float grain_feet=mix(sand_grain_feet,beach_grain_feet,details_mix);
	float color_strength=mix(sand_color_strength,beach_color_strength,details_mix);
	float patch_strength=mix(sand_patch_strength,beach_patch_strength,details_mix);
	float grain_strength=mix(sand_grain_strength,beach_grain_strength,details_mix);
	float glint_strength=mix(sand_glint_strength,beach_glint_strength,details_mix);
	float glint_density=mix(sand_glint_density,beach_glint_density,details_mix);
	float ripple_strength=mix(sand_ripple_strength,beach_ripple_strength,details_mix);
	vec3 sand_base = mix(sand_color.rgb,beach_color.rgb,beach_mix);
	vec3 sand = sand_surface_color(sand_base,sand_detail,fields,0.65,0.14,patch_strength);
	float sand_weight = weights.g+weights.b;
	float phase = sand_ripple_phase(floor_position,fields);
	float ripple_aa = 1.0-smoothstep(0.5,2.5,fwidth(phase));
	NORMAL = sand_grain_normal(NORMAL,VERTEX,sin(phase)*sand_ripple_coverage(fields),ripple_strength*3.0*ripple_aa*sand_weight);
	vec4 micro = sand_micro_sample_sized(floor_position,sand_seed_offset,grain_feet);
	float visibility = sand_micro_visibility_sized(floor_position,distance(vec3(floor_position.x,top_scene_height,floor_position.y),CAMERA_POSITION_WORLD),grain_feet);
	sand = sand_near_color_sized(sand,floor_position,sand_seed_offset,visibility,grain_feet,color_strength);
	float crystal = sand_crystals(micro,glint_density,visibility);
	NORMAL = sand_facet_normal(NORMAL,floor_axis_x,floor_axis_z,micro,(grain_strength*visibility+crystal*glint_strength*0.65)*sand_weight);
	float land_weight = 1.0-weights.a;
	float grass_mix = cover/max(land_weight,0.0001);
	ALBEDO = mix(sand,grass,grass_mix);
	ROUGHNESS = mix(sand_material_roughness(micro,visibility,crystal,glint_strength),0.92,grass_mix);
	SPECULAR = mix(0.4,0.5,grass_mix);
	float shore_distance = texture(shore_mask,uv).r;
	float wetness = (1.0-smoothstep(0.0,4.0,abs(shore_distance)))*sand_weight;
	ALBEDO *= 1.0-wetness*0.18;
	ROUGHNESS = mix(ROUGHNESS,0.55,wetness);
	if (weights.a>0.001) {
	 vec2 texel=shore_texel;
	 vec2 gradient=vec2(texture(shore_mask,uv+vec2(texel.x,0.0)).r-texture(shore_mask,uv-vec2(texel.x,0.0)).r,
	                    texture(shore_mask,uv+vec2(0.0,texel.y)).r-texture(shore_mask,uv-vec2(0.0,texel.y)).r);
	 vec2 world_gradient=gradient/(texel*area_size);
	 vec2 direction=world_gradient/max(length(world_gradient),0.0001);
	 vec2 feet=floor_position*5.0;
	 vec2 shore_point=feet-direction*max(shore_distance,0.0);
	 float deep=smoothstep(0.0,max(4.0,gradient_range*25.0),max(shore_distance,0.0));
	 vec3 water_color;
	 vec3 water_normal;
	 float water_roughness;
	 float water_specular;
	 shade_water(feet,deep,shore_distance,shore_point,normalize(cross(floor_axis_z,floor_axis_x)),floor_axis_x,floor_axis_z,water_color,water_normal,water_roughness,water_specular);
	 float water_mix=smoothstep(0.15,0.85,weights.a);
	 ALBEDO=mix(ALBEDO,water_color,water_mix);
	 NORMAL=normalize(mix(NORMAL,water_normal,water_mix));
	 ROUGHNESS=mix(ROUGHNESS,water_roughness,water_mix);
	 SPECULAR=mix(SPECULAR,water_specular,water_mix);
	}
	METALLIC = 0.0;
}

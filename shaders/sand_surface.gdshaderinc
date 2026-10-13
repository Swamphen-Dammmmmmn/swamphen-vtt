uniform sampler2D sand_grain_color : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float sand_grain_feet = 6.0;
uniform float sand_color_strength = 0.7;

// Both the standalone and painted sand use these fixed world-space fields.
// macro_mask is declared by the including shader; one world unit = five feet.
vec3 sand_fields(vec2 p, float seed_offset) {
	vec3 mask_mean = vec3(0.527367,0.469955,0.403140);
	vec3 medium = textureLod(macro_mask,p/11.3+vec2(seed_offset,0.37),0.0).rgb-mask_mean+vec3(0.5);
	vec3 large = textureLod(macro_mask,p/37.9+vec2(0.61,seed_offset),0.0).rgb-mask_mean+vec3(0.5);
	return vec3(mix(large.r,medium.g,0.35), medium.b, mix(medium.r,large.b,0.3));
}

vec3 sand_surface_color(vec3 base, vec3 detail, vec3 fields, float contrast_amount, float grain_amount, float patch_amount) {
	float density = mix(0.35,1.25,smoothstep(0.23,0.77,fields.y));
	float grains = (detail.r-detail.b*0.65)*grain_amount*density;
	float fine_tone = (detail.g-0.5)*0.25;
	float patches = ((fields.x-0.5)*1.7+(fields.z-0.5)*0.65)*patch_amount;
	vec3 color = base*(1.0+contrast_amount*(fine_tone+grains)+patches);
	// Subtle warm patches retain the chosen base color rather than whitening it.
	color += vec3(0.11,0.018,-0.085)*(fields.x-0.5)*patch_amount;
	return clamp(color,vec3(0.0),vec3(1.0));
}

float sand_ripple_phase(vec2 p,vec3 fields) {
	return dot(p,vec2(12.0,3.2))+fields.x*8.0+fields.z*5.0+sin(p.y*0.71+fields.y*3.0)*1.3;
}

float sand_ripple_coverage(vec3 fields) {
	float t = clamp((fields.y-0.2)/0.65,0.0,1.0);
	float envelope = t*t*t*(t*(t*6.0-15.0)+10.0);
	return mix(0.025,1.0,envelope)*(0.4+fields.z*0.6);
}

// Screen derivatives reconstruct a weak bump normal in view space.
vec3 sand_grain_normal(vec3 normal,vec3 view_position,float height,float amount) {
	vec3 dp1 = dFdx(view_position);
	vec3 dp2 = dFdy(view_position);
	vec3 r1 = cross(dp2,normal);
	vec3 r2 = cross(normal,dp1);
	float determinant = dot(dp1,r1);
	vec3 gradient = sign(determinant)*(dFdx(height)*r1+dFdy(height)*r2);
	return normalize(max(abs(determinant),0.00000001)*normal-gradient*amount*0.003);
}

// RG: grain facet slopes, B: roughness, A: crystal selection rank.
// The built-in dielectric BRDF supplies light- and view-dependent glints.
vec4 sand_micro_sample_sized(vec2 p,float seed_offset,float grain_feet) {
	return texture(sand_microstructure,p*(5.0/max(grain_feet,0.1))+vec2(seed_offset,0.61));
}
vec4 sand_micro_sample(vec2 p,float seed_offset) {
	return sand_micro_sample_sized(p,seed_offset,sand_grain_feet);
}
float sand_micro_visibility_sized(vec2 p,float camera_distance,float grain_feet) {
	vec2 uv=p*(5.0/max(grain_feet,0.1));
	float footprint=max(length(dFdx(uv)),length(dFdy(uv)));
	return (1.0-smoothstep(3.0,10.0,camera_distance))*(1.0-smoothstep(0.002,0.012,footprint));
}
float sand_micro_visibility(vec2 p,float camera_distance) {
	return sand_micro_visibility_sized(p,camera_distance,sand_grain_feet);
}
float sand_crystals(vec4 micro,float density,float visibility) {
	if (density<=0.0) return 0.0;
	return smoothstep(1.0-density,min(1.0,1.06-density),micro.a)*visibility;
}
vec3 sand_facet_normal(vec3 normal,vec3 axis_x,vec3 axis_z,vec4 micro,float amount) {
	vec2 slope=micro.rg*2.0-1.0;
	return normalize(normal+(axis_x*slope.x+axis_z*slope.y)*amount);
}
float sand_material_roughness(vec4 micro,float visibility,float crystal,float strength) {
	float matte=mix(0.92,micro.b,visibility);
	float crystal_roughness = mix(0.42,0.12,clamp(strength,0.0,1.0));
	return mix(matte,crystal_roughness,crystal*smoothstep(0.0,0.12,strength));
}

// Grain color shares the facet coordinates, but remains visible without a glint.
vec3 sand_near_color_sized(vec3 color,vec2 p,float seed_offset,float visibility,float grain_feet,float color_strength) {
	vec3 grain=texture(sand_grain_color,p*(5.0/max(grain_feet,0.1))+vec2(seed_offset,0.61)).rgb;
	float strength=color_strength*visibility;
	float tone=(grain.r-0.495132)*1.4;
	float warmth=(grain.g-0.517199)*2.0;
	vec3 tint=vec3(0.18,0.035,-0.16)*warmth;
	// Limit positive and negative variation equally before bright channels clip.
	vec3 headroom=min(color,vec3(1.0)-color);
	vec3 delta=clamp(color*(vec3(tone)+tint)*strength,-headroom,headroom);
	return color+delta;
}

vec3 sand_near_color(vec3 color,vec2 p,float seed_offset,float visibility) {
	return sand_near_color_sized(color,p,seed_offset,visibility,sand_grain_feet,sand_color_strength);
}

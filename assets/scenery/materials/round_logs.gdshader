shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 surface_color : source_color = vec4(0.596078,0.376471,0.223529,1.0);
uniform vec4 wood_reference : source_color;
uniform vec4 bark_reference : source_color = vec4(0.427451,0.396078,0.341176,1.0);
uniform bool bark_mode = false;
uniform vec4 bare_reference : source_color = vec4(0.545098,0.478431,0.396078,1.0);
uniform vec4 cut_wood_color : source_color = vec4(0.627451,0.568627,0.470588,1.0);
uniform sampler2DArray board_colors : source_color,filter_linear_mipmap_anisotropic,repeat_disable;
uniform sampler2DArray board_detail : filter_linear_mipmap_anisotropic,repeat_disable;
uniform int board_count = 64;
uniform float course_height = 0.2;
uniform float log_radius = 0.1;
uniform bool showcase_unlit = false;
uniform int showcase_layer = -1;
varying vec3 local_point;
varying vec3 local_normal;
varying vec3 world_point;
varying flat vec2 axis;
varying flat float line_seed;
varying flat float face_basis;
varying flat vec3 grain_tangent;
varying flat vec3 grain_up;

void vertex() {
	local_point = VERTEX;
	local_normal = NORMAL;
	world_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	axis = vec2(MODEL_MATRIX[3].x+MODEL_MATRIX[3].z,MODEL_MATRIX[0].x+MODEL_MATRIX[0].z);
	line_seed = floor((abs(MODEL_MATRIX[0].x)>0.5 ? MODEL_MATRIX[3].z : MODEL_MATRIX[3].x)*17.0+0.5);
	face_basis = abs(MODEL_MATRIX[0].x)>0.5 ? MODEL_MATRIX[2].z : MODEL_MATRIX[2].x;
	grain_tangent = normalize((VIEW_MATRIX*vec4(MODEL_MATRIX[0].xyz*axis.y,0.0)).xyz);
	grain_up = normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
}

void fragment() {
	float course = floor(world_point.y/course_height+0.000001);
	float across = fract(world_point.y/course_height);
	float along = axis.x+axis.y*local_point.x;
	float board_position = along/2.0+mod(course,2.0)*0.5;
	float piece = floor(board_position);
	float face = step(0.0,local_point.z*face_basis);
	float layer = mod(piece*5.0+course*7.0+floor(course/4.0)*6.0+face*8.0+line_seed*11.0,float(board_count));
	vec2 uv = vec2(fract(board_position),across);
	vec2 dx = vec2(dFdx(along)/2.0,dFdx(world_point.y)/course_height);
	vec2 dy = vec2(dFdy(along)/2.0,dFdy(world_point.y)/course_height);
	if (showcase_layer>=0) {
		layer = float(showcase_layer);
		uv = UV;
		across = UV.y;
		dx = dFdx(UV);
		dy = dFdy(UV);
	}
	vec2 half_texel = 0.5/vec2(textureSize(board_colors,0).xy);
	uv = clamp(uv,half_texel,vec2(1.0)-half_texel);
	vec3 wood = textureGrad(board_colors,vec3(uv,layer),dx,dy).rgb;
	vec3 detail = textureGrad(board_detail,vec3(uv,layer),dx,dy).rgb;
	float is_end = step(0.92,abs(normalize(local_normal).x));
	vec2 disk = vec2(local_point.z/log_radius,(across-0.5)*2.0);
	float rings = sin(length(disk*vec2(1.0,0.92))*32.0+sin(disk.y*4.0)*0.5+course*0.7);
	vec3 end_wood = cut_wood_color.rgb*(0.93+rings*0.055);
	if (!bark_mode) {
		end_wood *= wood_reference.rgb/max(bare_reference.rgb,vec3(0.001));
	}
	if (bark_mode) {
		// Retain a thin bark perimeter while keeping the cut face pale wood.
		float t = abs(across-0.5)*2.0;
		float depth = t<0.64 ? mix(1.0,0.82,t/0.64) : mix(0.82,0.32,(t-0.64)/0.36);
		float edge = max(t,abs(local_point.z)/max(log_radius*depth,0.001));
		end_wood = mix(end_wood,wood,smoothstep(0.90,0.98,edge));
	}
	if (showcase_layer>=0) { is_end=0.0; }
	wood = mix(wood,end_wood,is_end);
	float seam = 1.0-smoothstep(0.0,0.045,min(across,1.0-across));
	float butt = 1.0-smoothstep(0.0,0.003+fwidth(board_position),min(fract(board_position),1.0-fract(board_position)));
	if (showcase_layer>=0) { seam=0.0; butt=0.0; }
	vec3 reference = bark_mode ? bark_reference.rgb : wood_reference.rgb;
	ALBEDO = wood*surface_color.rgb/max(reference,vec3(0.001))*(1.0-seam*0.10)*(1.0-butt*(1.0-is_end)*0.12);
	if (bark_mode && is_end<0.5 && abs(local_normal.z)>0.1) {
		vec3 n = normalize(NORMAL);
		vec3 tangent = normalize(grain_tangent-n*dot(n,grain_tangent));
		vec3 bitangent = normalize(grain_up-n*dot(n,grain_up)-tangent*dot(tangent,grain_up));
		vec2 xy = (detail.rg*2.0-1.0)*smoothstep(0.0,0.08,min(across,1.0-across));
		NORMAL = normalize(n*sqrt(max(0.0,1.0-dot(xy,xy)))+tangent*xy.x+bitangent*xy.y);
	}
	ROUGHNESS = bark_mode ? mix(clamp(detail.b+seam*0.03,0.83,0.99),0.85,is_end) : clamp(detail.b+seam*0.03,0.74,0.97);
	SPECULAR = 0.16;
	if (showcase_unlit) { EMISSION = ALBEDO; ALBEDO = vec3(0.0); }
}

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 surface_color : source_color = vec4(0.596078, 0.376471, 0.223529, 1.0);
uniform vec4 wood_reference : source_color = vec4(0.596078, 0.376471, 0.223529, 1.0);
uniform sampler2DArray board_colors : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2DArray board_detail : filter_linear_mipmap_anisotropic, repeat_disable;
uniform int board_count = 64;
uniform int showcase_layer = -1;
uniform bool showcase_unlit = false;
uniform bool vertical_planks = false;
uniform float board_length = 1.0;
uniform float wall_length = 1.0;
uniform vec2 end_slopes = vec2(0.0);
uniform vec2 end_margins = vec2(0.0);
uniform float board_height = 0.2;
uniform float seam_half_width = 0.004;
varying vec3 world_point;
varying vec3 wall_point;
varying vec3 wall_normal;
varying flat vec2 board_axis;
varying flat float line_seed;
varying flat vec3 board_tangent;
varying flat vec3 board_bitangent;
varying flat float face_basis;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_point = VERTEX;
	wall_normal = NORMAL;
	board_axis = vec2(MODEL_MATRIX[3].x + MODEL_MATRIX[3].z, MODEL_MATRIX[0].x + MODEL_MATRIX[0].z);
	float line = abs(MODEL_MATRIX[0].x) > 0.5 ? MODEL_MATRIX[3].z : MODEL_MATRIX[3].x;
	line_seed = floor(line * 17.0 + 0.5);
	face_basis = abs(MODEL_MATRIX[0].x) > 0.5 ? MODEL_MATRIX[2].z : MODEL_MATRIX[2].x;
	vec3 canonical_axis = MODEL_MATRIX[0].xyz * board_axis.y;
	board_tangent = normalize((VIEW_MATRIX * vec4(vertical_planks ? vec3(0.0,1.0,0.0) : canonical_axis, 0.0)).xyz);
	board_bitangent = normalize((VIEW_MATRIX * vec4(vertical_planks ? canonical_axis : vec3(0.0,1.0,0.0), 0.0)).xyz);
}

void fragment() {
	// Recover the same board axis used by the actual groove geometry at mitered ends.
	float u = wall_point.x;
	if (end_margins.x > 0.0 && wall_point.x < end_margins.x) {
		u = (wall_point.x - end_slopes.x * wall_point.z) / (1.0 - end_slopes.x * wall_point.z / end_margins.x);
	} else if (end_margins.y > 0.0 && wall_point.x > wall_length - end_margins.y) {
		float k = end_slopes.y * wall_point.z / end_margins.y;
		u = (wall_point.x + k * (wall_length - end_margins.y)) / (1.0 + k);
	}
	float wall_axis = board_axis.x + board_axis.y * u;
	float along = vertical_planks ? world_point.y : wall_axis;
	float cross_axis = vertical_planks ? wall_axis : world_point.y;
	float level = cross_axis / board_height;
	float row = floor(level + 0.000001);
	float across = fract(level);
	float stagger = board_length * 0.5 * mod(row, 2.0);
	float board_position = (along + stagger) / board_length;
	float piece = floor(board_position);
	float face = step(0.0, wall_point.z * face_basis);
	// A permutation, not independent random picks: adjacent boards cannot repeat.
	float layer = mod(piece*5.0 + row*7.0 + floor(row/4.0)*6.0 + face*8.0 + line_seed*11.0, float(board_count));
	float seed = hash2(vec2(piece + line_seed*13.0, row + face*71.0));
	vec2 flip = vec2(seed > 0.5 ? -1.0 : 1.0, hash2(vec2(row+31.0,piece+line_seed)) > 0.5 ? -1.0 : 1.0);
	vec2 uv = vec2(fract(board_position), across);
	vec2 dx = vec2(dFdx(along)/board_length, dFdx(level));
	vec2 dy = vec2(dFdy(along)/board_length, dFdy(level));
	if (showcase_layer >= 0) {
		layer = float(showcase_layer);
		uv = UV;
		dx = dFdx(UV);
		dy = dFdy(UV);
		flip = vec2(1.0);
	}
	uv = (uv-0.5)*flip + 0.5;
	vec2 half_texel = 0.5/vec2(textureSize(board_colors,0).xy);
	uv = clamp(uv,half_texel,vec2(1.0)-half_texel);
	vec3 color = textureGrad(board_colors,vec3(uv,layer),dx*flip,dy*flip).rgb;
	vec3 detail = textureGrad(board_detail,vec3(uv,layer),dx*flip,dy*flip).rgb;
	float tone = showcase_layer >= 0 ? 1.0 : 0.97 + seed*0.06;
	color *= surface_color.rgb / max(wood_reference.rgb,vec3(0.001)) * tone;

	float end_distance = mod(along+stagger+board_length*0.5,board_length)-board_length*0.5;
	float edge_distance = min(across,1.0-across)*board_height;
	float seam = 1.0-smoothstep(0.0,seam_half_width*1.5+fwidth(cross_axis),edge_distance);
	float butt = 1.0-smoothstep(seam_half_width*0.12,seam_half_width+fwidth(along),abs(end_distance));
	float end_cap = (1.0-step(0.00001,min(u,wall_length-u))) * step(0.01,abs(wall_normal.x));
	float jamb = step(0.99,abs(normalize(wall_normal).x)) * step(seam_half_width*1.1,abs(end_distance));
	float end_face = max(end_cap,jamb);
	if (vertical_planks) {
		// Board ends are on wall tops, sills and lintels; jambs follow the grain.
		end_face = step(0.99,abs(normalize(wall_normal).y));
	}
	if (showcase_layer >= 0) {
		seam = 0.0;
		butt = 0.0;
		end_face = 0.0;
	}
	// End-grain is transverse and follows the board seed, including opening jambs.
	float rings = sin(length(vec2(wall_point.z*32.0,(across-0.48)*2.8))*15.0 + seed*3.0);
	color *= mix(1.0,0.91+rings*0.045,end_face);
	ALBEDO = color * (1.0-seam*0.12) * (1.0-butt*(1.0-end_face)*0.14);
	// Tiny fibre relief overlays the real groove normals, never replaces them.
	if (abs(wall_normal.z) > 0.4 && end_face < 0.5) {
		vec3 n = normalize(NORMAL);
		vec3 t = normalize(board_tangent - n*dot(n,board_tangent));
		vec3 b = normalize(board_bitangent-n*dot(n,board_bitangent)-t*dot(t,board_bitangent));
		vec2 xy = (detail.rg*2.0-1.0)*flip*(1.0-seam)*(1.0-butt);
		NORMAL = normalize(n*sqrt(max(0.0,1.0-dot(xy,xy)))+t*xy.x+b*xy.y);
	}
	ROUGHNESS = clamp(detail.b+seam*0.04,0.7,0.97);
	METALLIC = 0.0;
	SPECULAR = 0.18;
	if (showcase_unlit) {
		EMISSION = ALBEDO;
		ALBEDO = vec3(0.0);
	}
}

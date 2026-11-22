shader_type spatial;
render_mode cull_back;

uniform sampler2DArray board_colors : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray board_detail : filter_linear_mipmap, repeat_enable;
uniform vec4 surface_color : source_color = vec4(0.5451,0.4784,0.3961,1.0);
uniform vec4 wood_reference : source_color;
uniform int board_count = 64;

// UV.x = physical distance along EACH timber; UV.y = distance across it.
// COLOR.r selects an independent piece, COLOR.g identifies exposed end grain.
// COLOR.b (generator 3+) marks members longer than one board: their UVs mirror-fold
// at tile edges so the grain stays continuous instead of jumping at the repeat seam.
// Unflagged vertices (all generator 1/2 assets) sample exactly as before.
void fragment() {
	float layer = floor(COLOR.r * 255.0 + 0.5);
	vec2 raw = vec2(UV.x, UV.y / 0.2);
	vec2 mirrored = mod(floor(raw), 2.0) * step(0.5, COLOR.b);
	vec2 uv = mix(raw, 1.0 - fract(raw) + floor(raw), mirrored);
	// Derivatives of the unfolded UV keep mip selection smooth across the fold line.
	vec2 grad_x = dFdx(raw);
	vec2 grad_y = dFdy(raw);
	vec3 wood = textureGrad(board_colors,vec3(uv,mod(layer,float(board_count))),grad_x,grad_y).rgb;
	vec3 detail = textureGrad(board_detail,vec3(uv,mod(layer,float(board_count))),grad_x,grad_y).rgb;
	detail.rg = mix(detail.rg, 1.0 - detail.rg, mirrored);
	ALBEDO = clamp(wood * surface_color.rgb / max(wood_reference.rgb,vec3(0.01)),vec3(0.0),vec3(1.0));
	if (COLOR.g>0.5) {
		float rings = sin(length((UV-vec2(0.04,0.02))*vec2(65.0,90.0))+sin(UV.x*83.0)*0.22);
		ALBEDO = surface_color.rgb * (0.9+0.07*rings);
	}
	NORMAL_MAP = vec3(detail.rg,sqrt(max(0.0,1.0-dot(detail.rg*2.0-1.0,detail.rg*2.0-1.0)))*0.5+0.5);
	NORMAL_MAP_DEPTH = COLOR.g>0.5 ? 0.0 : 0.28;
	ROUGHNESS = max(0.72,detail.b);
}

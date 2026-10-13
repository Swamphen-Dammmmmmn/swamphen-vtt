shader_type spatial;
render_mode depth_prepass_alpha;

uniform sampler2D image_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 board_size = vec2(1.0);
uniform vec2 picture_size = vec2(1.0);
uniform vec2 offset_ratio = vec2(0.0);
uniform float picture_scale = 1.0;
uniform float angle = 0.0;
uniform vec4 image_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_x = false;
uniform bool flip_y = false;
uniform float opacity = 1.0;
uniform bool backing_only = false;
uniform vec4 backing_color : source_color = vec4(1.0);

void fragment() {
	vec2 point = (UV - vec2(0.5)) * board_size;
	point -= offset_ratio * board_size;
	float c = cos(angle);
	float s = sin(angle);
	point = vec2(c * point.x + s * point.y, -s * point.x + c * point.y);
	vec2 sample_uv = point / (picture_size * picture_scale) + vec2(0.5);
	if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) { discard; }
	if (flip_x) { sample_uv.x = 1.0 - sample_uv.x; }
	if (flip_y) { sample_uv.y = 1.0 - sample_uv.y; }
	sample_uv = image_region.xy + sample_uv * image_region.zw;
	vec4 color = texture(image_texture, sample_uv);
	if (color.a < 0.005) { discard; }
	ALBEDO = backing_only ? backing_color.rgb : color.rgb;
	ALPHA = color.a * opacity;
	ROUGHNESS = 0.85;
}

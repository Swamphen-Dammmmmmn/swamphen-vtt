shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
#define SURFACE_TRANSPARENT
#include "res://shaders/token_surface_effects.gdshaderinc"

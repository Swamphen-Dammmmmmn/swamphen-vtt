shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/water_surface.gdshaderinc"

uniform vec2 half_extent_feet = vec2(40.0);
varying vec2 surface_feet;
varying vec3 view_x;
varying vec3 view_z;
varying vec3 view_up;

void vertex() {
 surface_feet = VERTEX.xz * 5.0;
 view_x = normalize((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
 view_z = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
 view_up = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
 vec2 q = UV*2.0-1.0;
 vec2 warped = q+vec2(sin(q.y*3.4+q.x*1.1),sin(q.x*4.1-q.y*0.8))*0.045;
 float deep = 1.0-smoothstep(1.05-gradient_range,1.05,length(warped));
 vec2 d = abs(surface_feet)-(half_extent_feet-vec2(2.0));
 float shore_distance = -(length(max(d,vec2(0.0)))+min(max(d.x,d.y),0.0)-2.0);
 vec2 shore_point = surface_feet/max(max(abs(surface_feet.x)/half_extent_feet.x,abs(surface_feet.y)/half_extent_feet.y),0.0001);
 vec3 color;
 vec3 normal;
 float roughness;
 float specular;
 shade_water(surface_feet,deep,shore_distance,shore_point,view_up,view_x,view_z,color,normal,roughness,specular);
 ALBEDO = color;
 NORMAL = normal;
 ROUGHNESS = roughness;
 SPECULAR = specular;
}

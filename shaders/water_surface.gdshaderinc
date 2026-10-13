uniform vec4 edge_color : source_color = vec4(0.157, 0.725, 0.757, 1.0);
uniform vec4 center_color : source_color = vec4(0.027, 0.404, 0.561, 1.0);
uniform float gradient_range : hint_range(0.1, 1.0) = 0.6;
uniform float wave_strength : hint_range(0.0, 0.3) = 0.11;
uniform float wave_feet : hint_range(2.0, 20.0) = 7.0;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.6;
uniform float highlight_strength : hint_range(0.0, 0.4) = 0.14;
uniform float water_time = 0.0;
uniform float gloss : hint_range(0.0,1.0) = 0.65;
uniform bool shore_enabled = true;
uniform float shore_strength : hint_range(0.0,1.0) = 0.42;
uniform float shore_width_feet : hint_range(1.0,15.0) = 6.0;
uniform float shore_period : hint_range(1.0,10.0) = 4.0;
uniform sampler2D wave_noise : repeat_enable, filter_linear_mipmap;

// Wave surface is shared by shading and crest highlights. Noise distorts
// phase and amplitude, so the short wave bands do not form straight stripes.
float wave_height(vec2 p,float t) {
 vec3 a = texture(wave_noise,p*0.16+vec2(t*0.006,-t*0.004)).rgb;
 vec3 b = texture(wave_noise,vec2(p.y,-p.x)*0.21+vec2(-t*0.004,t*0.007)+vec2(0.31,0.67)).rgb;
 float first = sin(dot(p,vec2(0.91,0.42))*TAU-t+a.r*5.0+b.b*2.0);
 float second = sin(dot(p,vec2(-0.36,0.93))*TAU*0.73+t*0.63+b.g*5.0-a.b*2.0);
 return (first*0.65+second*0.35)*(0.6+0.4*a.g);
}

// Caller supplies depth and the actual shoreline distance in feet.
void shade_water(vec2 surface_feet,float deep,float shore_distance,vec2 shore_point,vec3 view_up,vec3 view_x,vec3 view_z,out vec3 color,out vec3 normal,out float roughness,out float specular) {

 color = mix(edge_color.rgb,center_color.rgb,deep);
 vec2 p = surface_feet/max(wave_feet,0.1);
 float t = water_time*flow_speed;
 float height = wave_height(p,t);
 float e = 0.015;
 vec2 slope = vec2(wave_height(p+vec2(e,0.0),t)-wave_height(p-vec2(e,0.0),t),
                   wave_height(p+vec2(0.0,e),t)-wave_height(p-vec2(0.0,e),t))/(2.0*e);
 float aa = 1.0-smoothstep(0.06,0.4,max(length(dFdx(p)),length(dFdy(p))));
 slope *= wave_strength*0.12*aa;
 normal = normalize(view_up-view_x*slope.x-view_z*slope.y);
 vec3 breakup = texture(wave_noise,p*0.19+vec2(t*0.004,-t*0.007)).rgb;
 float crest = smoothstep(0.60,0.86,height);
 float gate = smoothstep(0.40,0.66,breakup.b);
 float highlight = crest*gate*highlight_strength*aa;
 color = mix(color,vec3(0.61,0.86,0.88),highlight);

 if (shore_enabled && shore_strength>0.0) {
  float width = max(shore_width_feet,0.1);
  vec3 shore_noise = texture(wave_noise,shore_point/31.0+vec2(0.17,0.43)).rgb;
  vec3 foam_noise = texture(wave_noise,surface_feet/5.0+vec2(t*0.014,-t*0.009)).rgb;
  float local_clock = water_time/max(shore_period,0.1)+shore_noise.g*5.1;
  float cycle = floor(local_clock);
  float wave = 0.0;
  // Include neighbors: pulses enter and leave at zero opacity, including
  // when the integer cycle changes. No fract-based synchronized reset.
  for (int i=-1;i<=1;i++) {
   float event = cycle+float(i);
   vec3 random = fract(sin(vec3(event*17.13+2.7,event*41.71+9.3,event*73.19+4.1))*vec3(43758.5453,22578.1459,19642.3491));
   float start = event+random.x*0.45+shore_noise.r*0.12;
   float lifetime = mix(0.65,1.15,random.y)*mix(0.85,1.15,shore_noise.r);
   float age = (local_clock-start)/lifetime;
   float phase = clamp(age,0.0,1.0);
   float progress = pow(phase,mix(0.8,1.3,random.z));
   float reach = width*mix(0.72,1.0,random.x);
   float front = progress*reach+(shore_noise.b-0.5)*0.65*sin(phase*PI);
   float thickness = (0.22+foam_noise.g*0.5)*mix(0.7,1.35,random.z);
   thickness = max(thickness,fwidth(shore_distance)*0.8);
   float band = 1.0-smoothstep(thickness*0.35,thickness,abs(shore_distance-front));
   float life = smoothstep(0.0,0.16,age)*(1.0-smoothstep(0.66,1.0,age));
   // Events leave different quiet gaps, rather than persistent full rings.
   float patch = texture(wave_noise,shore_point/11.0+vec2(random.x*2.7,random.z*3.1)).b;
   float presence = smoothstep(0.34,0.63,patch);
   wave += band*life*presence*mix(0.5,0.95,random.y);
  }
  float fragments = smoothstep(0.25,0.62,foam_noise.b);
  float edge_fade = smoothstep(0.0,0.4,shore_distance)*(1.0-smoothstep(width*0.85,width,shore_distance));
  float foam = clamp(wave*fragments*edge_fade*shore_strength,0.0,0.8);
  color = mix(color,vec3(0.78,0.94,0.92),foam);
 }

 roughness = mix(0.65,0.22,gloss);
 specular = mix(0.2,0.5,gloss);
}

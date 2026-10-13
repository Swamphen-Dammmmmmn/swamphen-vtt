// Shared field for decorative blades and distant ground color, in scene space.
float grass_wind_phase(vec2 at, float clock, float direction_deg, float frequency, float speed_feet) {
	vec2 direction = vec2(sin(radians(direction_deg)), cos(radians(direction_deg)));
	return TAU * frequency * (clock - dot(at, direction) / max(speed_feet / 5.0, 0.01));
}

float grass_wind_gust(vec2 at, float clock, float direction_deg, float frequency, float width_feet, float speed_feet) {
	float safe_frequency = max(frequency, 0.01);
	float spacing = max(speed_feet / 5.0, 0.01) / safe_frequency;
	float phase = grass_wind_phase(at, clock, direction_deg, safe_frequency, speed_feet);
	float front_distance = sin(phase * 0.5) * spacing / PI;
	return exp(-pow(front_distance / max(width_feet / 5.0, 0.05), 2.0));
}

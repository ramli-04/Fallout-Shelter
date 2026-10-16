shader_type spatial;
render_mode diffuse_burley;

uniform vec2 map_size;
uniform int x_count;
uniform int y_count;
uniform float x_cuts[32];
uniform float y_cuts[32];
uniform vec4 park_bounds;
uniform vec4 reserve_bounds;
uniform int map_seed;

bool inside(vec2 point, vec4 bounds) {
	return point.x > bounds.x + 40.0 && point.y > bounds.y + 40.0
		&& point.x < bounds.z - 40.0 && point.y < bounds.w - 40.0;
}

void fragment() {
	vec2 point = UV * map_size;
	float dx = 1e10;
	float dy = 1e10;
	for (int i = 0; i < 32; i++) {
		if (i < x_count) { dx = min(dx, abs(point.x - x_cuts[i])); }
		if (i < y_count) { dy = min(dy, abs(point.y - y_cuts[i])); }
	}
	float distance_to_lane = min(dx, dy);
	bool nature = inside(point, park_bounds) || inside(point, reserve_bounds);
	vec3 color = COLOR.rgb;
	if (nature) {
		float xlo = 0.0;
		float ylo = 0.0;
		float xhi = map_size.x;
		float yhi = map_size.y;
		int xi = 0;
		int yi = 0;
		for (int i = 0; i < 32; i++) {
			if (i < x_count) {
				if (x_cuts[i] <= point.x) { xlo = x_cuts[i]; xi = i; }
				else { xhi = min(xhi, x_cuts[i]); }
			}
			if (i < y_count) {
				if (y_cuts[i] <= point.y) { ylo = y_cuts[i]; yi = i; }
				else { yhi = min(yhi, y_cuts[i]); }
			}
		}
		distance_to_lane = 1e10;
		for (int i = 0; i < 32; i++) {
			if (i < x_count) {
				vec2 midpoint = vec2(x_cuts[i], (ylo + yhi) * 0.5);
				bool curved = inside(midpoint, park_bounds) || inside(midpoint, reserve_bounds);
				float sign_value = mod(float(i + yi + map_seed), 2.0) < 0.5 ? 1.0 : -1.0;
				float bend = curved ? sin((point.y-ylo)/max(1.0,yhi-ylo)*3.14159265)*32.0*sign_value : 0.0;
				distance_to_lane = min(distance_to_lane,abs(point.x-x_cuts[i]-bend));
			}
			if (i < y_count) {
				vec2 midpoint = vec2((xlo + xhi) * 0.5,y_cuts[i]);
				bool curved = inside(midpoint, park_bounds) || inside(midpoint, reserve_bounds);
				float sign_value = mod(float(xi + i + map_seed), 2.0) < 0.5 ? 1.0 : -1.0;
				float bend = curved ? sin((point.x-xlo)/max(1.0,xhi-xlo)*3.14159265)*32.0*sign_value : 0.0;
				distance_to_lane = min(distance_to_lane,abs(point.y-y_cuts[i]-bend));
			}
		}
		float trail = 1.0 - smoothstep(6.0, 8.0, distance_to_lane);
		color = mix(color, vec3(0.60, 0.49, 0.32), trail);
	} else {
		float sidewalk = 1.0 - smoothstep(36.0, 39.0, distance_to_lane);
		float street = 1.0 - smoothstep(19.0, 21.0, distance_to_lane);
		color = mix(color, vec3(0.50, 0.51, 0.45), sidewalk);
		color = mix(color, vec3(0.15, 0.19, 0.21), street);
		bool dash = (dx < 0.9 && mod(point.y, 30.0) < 12.0)
			|| (dy < 0.9 && mod(point.x, 30.0) < 12.0);
		if (dash) { color = vec3(0.74, 0.67, 0.44); }
	}
	ALBEDO = color;
	ROUGHNESS = 0.95;
}

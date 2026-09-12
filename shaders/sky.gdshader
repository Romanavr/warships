shader_type sky;

// Layered maritime sky: graded blue, a warm haze band on the horizon and two
// drifting cumulus decks. Everything is procedural so there are no assets.

uniform vec3 zenith : source_color = vec3(0.16, 0.33, 0.52);
uniform vec3 horizon : source_color = vec3(0.72, 0.79, 0.82);
uniform vec3 ground : source_color = vec3(0.20, 0.29, 0.33);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_shadow : source_color = vec3(0.42, 0.47, 0.55);
uniform float cloud_cover = 0.46;
uniform float cloud_speed = 0.004;
uniform float haze = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		total += noise(p) * amplitude;
		p = p * 2.03 + vec2(3.1, 1.7);
		amplitude *= 0.5;
	}
	return total;
}

float deck(vec3 direction, float height, float scale, float drift, float coverage) {
	// Project the view ray onto a flat cloud layer.
	float up = max(direction.y, 0.008);
	vec2 plane = direction.xz / up * height;
	vec2 uv = plane * scale + vec2(drift, drift * 0.4);
	float density = fbm(uv);
	density = smoothstep(coverage, coverage + 0.34, density);
	// Fade the deck out as it approaches the horizon so it does not tile.
	return density * smoothstep(0.0, 0.18, direction.y);
}

void sky() {
	vec3 direction = EYEDIR;
	float up = direction.y;
	vec3 base = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.42));
	base = mix(base, ground, smoothstep(0.0, -0.12, up));
	// Warm band right on the water line.
	base = mix(base, horizon * vec3(1.06, 1.02, 0.96), haze * (1.0 - smoothstep(0.0, 0.22, abs(up))));

	float drift = TIME * cloud_speed;
	float high = deck(direction, 1.0, 0.055, drift * 0.45, cloud_cover + 0.12);
	float low = deck(direction, 1.0, 0.021, drift, cloud_cover);
	float shape = fbm(direction.xz / max(direction.y, 0.008) * 0.021 + vec2(drift, drift * 0.4));

	vec3 cloud = mix(cloud_shadow, cloud_lit, clamp(shape * 1.5, 0.0, 1.0));
	float sun_facing = clamp(dot(normalize(direction), normalize(LIGHT0_DIRECTION * -1.0)), 0.0, 1.0);
	cloud += cloud_lit * pow(sun_facing, 12.0) * 0.5 * low;

	vec3 result = mix(base, cloud, clamp(low * 0.92 + high * 0.4, 0.0, 1.0));

	if (LIGHT0_ENABLED) {
		vec3 sun_direction = -LIGHT0_DIRECTION;
		float angle = dot(direction, sun_direction);
		// Disc and a soft aureole around it.
		float disc = smoothstep(0.9993, 0.99975, angle);
		float glow = pow(clamp(angle, 0.0, 1.0), 180.0) * 0.55 + pow(clamp(angle, 0.0, 1.0), 12.0) * 0.14;
		result += LIGHT0_COLOR * (disc * 12.0 + glow) * (1.0 - low * 0.75);
	}
	COLOR = result;
}

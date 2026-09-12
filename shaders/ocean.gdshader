shader_type spatial;
render_mode specular_schlick_ggx;

// Gerstner swell for the shape, an analytic wind-wave spectrum for the surface.
// The CPU buoyancy solver in ocean.gd uses the same swell parameters and clock,
// so hulls sit on the crest that is actually drawn.

uniform float ocean_time = 0.0;
// (direction.x, direction.y, steepness, wavelength)
uniform vec4 wave_0 = vec4(1.0, 0.35, 0.066, 73.0);
uniform vec4 wave_1 = vec4(-0.42, 1.0, 0.058, 44.0);
uniform vec4 wave_2 = vec4(0.75, 0.78, 0.051, 29.0);
uniform vec4 wave_3 = vec4(-0.88, 0.40, 0.043, 19.0);
uniform vec4 wave_4 = vec4(0.28, -0.96, 0.035, 13.0);
// Islands, so the water goes turquoise and breaks into surf near land.
uniform vec4 shores[6];
uniform int shore_count = 0;
// Fuel slicks, as (x, z, radius, strength). The film is part of the water
// surface rather than a decal laid over it: it rides the same waves, damps the
// same ripples and takes the same light.
uniform vec4 slicks[12];
uniform int slick_count = 0;
uniform vec3 slick_sheen : source_color = vec3(0.47, 0.54, 0.61);
uniform vec3 slick_heavy : source_color = vec3(0.105, 0.080, 0.048);

uniform vec3 sun_travel = vec3(0.732, -0.559, -0.389);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.82);
uniform vec3 deep_tint : source_color = vec3(0.021, 0.088, 0.121);
uniform vec3 mid_tint : source_color = vec3(0.058, 0.205, 0.238);
uniform vec3 shallow_tint : source_color = vec3(0.105, 0.360, 0.352);
uniform vec3 scatter_tint : source_color = vec3(0.055, 0.225, 0.180);
uniform vec3 sky_low : source_color = vec3(0.60, 0.70, 0.76);
uniform vec3 sky_high : source_color = vec3(0.24, 0.42, 0.60);
uniform vec3 foam_tint : source_color = vec3(0.80, 0.86, 0.86);

uniform float detail_scale = 0.055;
uniform float choppiness = 1.0;
// The distant sheet uses the same shader with the swell switched off, so it
// cannot punch through the displaced near-field plane.
uniform float swell_scale = 1.0;
uniform float detail_range = 1650.0;
// Quality knobs. The wind spectrum is the single most expensive thing in this
// shader — seven octaves of gradient noise with analytic derivatives, per pixel
// — and the Compatibility renderer used by the web build cannot afford it.
uniform int wind_octaves : hint_range(2, 7) = 7;
uniform int foam_octaves : hint_range(1, 4) = 4;
uniform bool rich_slicks = true;
uniform float glitter_strength = 9.0;
uniform vec2 wind = vec2(0.86, 0.5);

varying vec3 world_pos;
varying vec3 wave_normal;
varying float crest;
varying float jacobian;

// --------------------------------------------------------------------------- //
// Gradient noise with analytic derivatives (value in x, d/dx and d/dy in yz)
// --------------------------------------------------------------------------- //

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

vec3 noised(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = hash2(i);
	vec2 gb = hash2(i + vec2(1.0, 0.0));
	vec2 gc = hash2(i + vec2(0.0, 1.0));
	vec2 gd = hash2(i + vec2(1.0, 1.0));
	float va = dot(ga, f);
	float vb = dot(gb, f - vec2(1.0, 0.0));
	float vc = dot(gc, f - vec2(0.0, 1.0));
	float vd = dot(gd, f - vec2(1.0, 1.0));
	float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd);
	vec2 derivative = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
		+ du * (u.yx * (va - vb - vc + vd) + vec2(vb, vc) - va);
	return vec3(value, derivative);
}

float fbm(vec2 p, int octaves) {
	float total = 0.0;
	float amplitude = 0.5;
	mat2 rot = mat2(vec2(0.86, 0.51), vec2(-0.51, 0.86));
	for (int i = 0; i < octaves; i++) {
		total += noised(p).x * amplitude;
		p = rot * p * 2.07;
		amplitude *= 0.5;
	}
	return total * 0.5 + 0.5;
}

// Slope of the wind-wave spectrum. Each octave drifts a little faster than the
// last and is rotated so the sheet never lines up into a visible grid.
vec2 wind_slope(vec2 p, float t, float lod) {
	vec2 slope = vec2(0.0);
	float amplitude = 1.0;
	float frequency = 1.0;
	mat2 rot = mat2(vec2(0.86, 0.51), vec2(-0.51, 0.86));
	mat2 frame = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	vec2 q = p;
	for (int i = 0; i < wind_octaves; i++) {
		// Drop the finest octaves with distance so the horizon does not crawl.
		float fade = clamp(lod * float(wind_octaves) - float(i) + 2.2, 0.0, 1.0);
		if (fade > 0.002) {
			vec2 drift = wind * t * (0.22 + float(i) * 0.16) * frequency;
			vec3 n = noised(q - drift);
			slope += (n.yz * frame) * amplitude * frequency * fade;
		}
		q = rot * q * 2.07;
		frame = rot * frame;
		amplitude *= 0.52;
		frequency *= 2.07;
	}
	return slope * 0.075;
}

// --------------------------------------------------------------------------- //
// Swell
// --------------------------------------------------------------------------- //

void gerstner(vec2 p, vec4 w, float t, inout vec3 offset, inout vec3 tangent,
		inout vec3 binormal, inout vec3 fold) {
	float k = 6.2831853 / w.w;
	float c = sqrt(9.81 / k);
	vec2 d = normalize(w.xy);
	float a = w.z / k;
	float f = k * (dot(d, p) - c * t);
	float cf = cos(f);
	float sf = sin(f);
	offset += vec3(d.x * a * cf, a * sf, d.y * a * cf);
	tangent += vec3(-d.x * d.x * w.z * sf, d.x * w.z * cf, -d.x * d.y * w.z * sf);
	binormal += vec3(-d.x * d.y * w.z * sf, d.y * w.z * cf, -d.y * d.y * w.z * sf);
	// Horizontal compression terms, for the Jacobian that marks breaking crests.
	fold += vec3(d.x * d.x, d.y * d.y, d.x * d.y) * (-w.z * sf);
}

float shoreline(vec2 p) {
	float result = 0.0;
	for (int i = 0; i < shore_count; i++) {
		float distance = length(p - shores[i].xy) - shores[i].z;
		result = max(result, 1.0 - smoothstep(0.0, 46.0, distance));
	}
	return result;
}

// How much fuel film covers this point, from the slicks the world has pushed in.
float slick_cover(vec2 p) {
	float result = 0.0;
	for (int i = 0; i < slick_count; i++) {
		float reach = max(slicks[i].z, 1.0);
		float distance = length(p - slicks[i].xy) / reach;
		result = max(result, (1.0 - smoothstep(0.55, 1.05, distance)) * slicks[i].w);
	}
	return result;
}

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 offset = vec3(0.0);
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 fold = vec3(0.0);
	gerstner(point.xz, wave_0, ocean_time, offset, tangent, binormal, fold);
	gerstner(point.xz, wave_1, ocean_time, offset, tangent, binormal, fold);
	gerstner(point.xz, wave_2, ocean_time, offset, tangent, binormal, fold);
	gerstner(point.xz, wave_3, ocean_time, offset, tangent, binormal, fold);
	gerstner(point.xz, wave_4, ocean_time, offset, tangent, binormal, fold);
	offset *= swell_scale;
	VERTEX += offset;
	world_pos = point + offset;
	wave_normal = normalize(cross(binormal, tangent));
	crest = offset.y;
	jacobian = (1.0 + fold.x) * (1.0 + fold.y) - fold.z * fold.z;
}

void fragment() {
	float eye_distance = length(world_pos - CAMERA_POSITION_WORLD);
	float lod = clamp(1.0 - eye_distance / detail_range, 0.0, 1.0);
	lod *= lod;

	vec2 p = world_pos.xz;
	vec2 slope = wind_slope(p * detail_scale, ocean_time, lod) * choppiness;
	vec3 normal = normalize(wave_normal + vec3(-slope.x, 0.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);

	vec3 eye = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 light = -normalize(sun_travel);
	float shore = shoreline(p);

	// Breaking crests: where the swell folds in on itself, streaked with a
	// drifting noise so the foam has structure instead of blotches.
	float foam_noise = fbm(p * 0.16 - wind * ocean_time * 0.09, foam_octaves);
	float fold_foam = smoothstep(0.76, 0.52, jacobian);
	float crest_foam = fold_foam * smoothstep(0.42, 0.78, foam_noise + fold_foam * 0.3);
	float wash = sin(shore * 13.0 - ocean_time * 1.6) * 0.5 + 0.5;
	float surf = smoothstep(0.40, 0.96, shore) * (0.42 + wash * 0.58);
	surf *= smoothstep(0.2, 0.62, foam_noise + 0.28);
	float foam = clamp(crest_foam + surf, 0.0, 1.0);

	// --- fuel slick, folded into the water itself ----------------------------
	float oil = slick_cover(p);
	float film = 0.0;
	if (oil > 0.003) {
		// One domain-warped evaluation shapes every slick at once, so the
		// footprints break into meandering ribbons with frayed edges instead of
		// reading as discs.
		vec2 base = p * 0.055;
		// Domain warping costs two more fbm evaluations on every slick pixel.
		// Worth it on the desktop; the first thing to go everywhere else.
		vec2 warped = base;
		if (rich_slicks) {
			warped += (vec2(fbm(base * 1.25, 3), fbm(base * 1.25 + 7.3, 3)) - 0.5) * 3.2;
		}
		float shape = fbm(warped * 1.05, foam_octaves);
		// A narrow band either side of an isoline: that is what makes ribbons
		// rather than a disc with texture painted inside it.
		float ribbon = 1.0 - abs(shape - 0.47) * 7.5;
		oil = clamp(oil * smoothstep(0.02, 0.68, ribbon), 0.0, 1.0);
		film = rich_slicks
			? clamp((fbm(warped * 3.1 + 2.0, 3) - 0.28) * 2.0, 0.0, 1.0) * oil
			: oil * 0.5;
		// A film damps the short waves: that flattening is the strongest cue
		// that there is oil on the water at all.
		normal = normalize(mix(normal, wave_normal, oil * 0.94));
		NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
		foam *= 1.0 - oil * 0.9;
	}

	// Water body colour. Real water is dark; almost all of its brightness is
	// reflected sky, so drive it with Fresnel rather than a light albedo.
	float fresnel = clamp(pow(1.0 - clamp(dot(normal, eye), 0.0, 1.0), 5.0), 0.0, 1.0);
	fresnel = mix(0.05, 1.0, fresnel);
	vec3 sky = mix(sky_low, sky_high, clamp(reflect(-eye, normal).y * 1.6, 0.0, 1.0));
	vec3 body = mix(deep_tint, mid_tint, clamp(crest * 0.22 + 0.6, 0.0, 1.0));
	body = mix(body, shallow_tint, smoothstep(0.0, 0.85, shore));
	// Light scattering up through the back of a lifted crest.
	float back_light = pow(clamp(dot(eye, -light) * 0.5 + 0.5, 0.0, 1.0), 3.0);
	body += scatter_tint * back_light * smoothstep(0.15, 1.3, crest) * (1.0 - shore * 0.5);

	// Keep the shallows turquoise instead of letting the sky reflection bury them.
	vec3 water = mix(body, sky, fresnel * 0.9 * (1.0 - shore * 0.6));
	// Thin-film interference, in the band of thickness where it actually occurs.
	if (oil > 0.003) {
		float facing_oil = clamp(dot(normal, normalize(CAMERA_POSITION_WORLD - world_pos)), 0.45, 1.0);
		float path = mix(190.0, 1120.0, film) * mix(1.0, 1.25, 1.0 - facing_oil);
		vec3 spectral = 0.5 + 0.5 * cos(6.2831853 * path / vec3(660.0, 545.0, 452.0));
		spectral = mix(vec3(dot(spectral, vec3(0.333))), spectral, 0.42);
		float banded = smoothstep(0.18, 0.48, film) * (1.0 - smoothstep(0.70, 0.94, film));
		float heavy = smoothstep(0.84, 0.99, film);
		vec3 sheen = mix(slick_sheen, spectral, 0.07 + banded * 0.17);
		water = mix(water, mix(sheen, slick_heavy * (0.9 + spectral * 0.25), heavy), oil * 0.82);
	}

	ALBEDO = mix(water, foam_tint, foam);

	// Sun glitter: a very tight lobe riding the fine wind-wave normals. This is
	// the sparkle a smooth normal map can never produce.
	vec3 half_vector = normalize(light + eye);
	float tightness = mix(220.0, 1400.0, lod);
	float glitter = pow(max(dot(normal, half_vector), 0.0), tightness);
	glitter *= glitter_strength * (1.0 - foam) * smoothstep(0.0, 0.12, light.y * -1.0 + 1.0);
	EMISSION = sun_color * glitter;

	METALLIC = 0.0;
	SPECULAR = 0.55;
	// Glassy where the film lies, so it mirrors the sky and reads as calm water.
	ROUGHNESS = mix(mix(mix(0.045, 0.22, 1.0 - lod), 0.018, oil), 0.85, foam);
	BACKLIGHT = scatter_tint * 0.5 * (1.0 - foam);
	AO = mix(1.0, 0.9, smoothstep(0.55, 1.0, shore) * (1.0 - foam));
	AO_LIGHT_AFFECT = 0.3;
}

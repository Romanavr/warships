class_name Vfx
extends RefCounted
## Procedural effect assets: sprite textures, particle materials and the
## factory functions that build fire, smoke, sparks, splashes and tracers.
## Nothing here is imported — every texture is generated on first use.

static var _soft: Texture2D
static var _smoke: Texture2D
static var _flame: Texture2D
static var _spark: Texture2D
static var _streak: Texture2D
## Tracer meshes and materials, keyed by the shape asked for. There are exactly
## three tracers in the game — the shell, the rocket and the CIWS round — but
## this used to build a fresh BoxMesh, QuadMesh and two StandardMaterial3Ds for
## *every round fired*. A new material is a new shader variant and a new uniform
## buffer, which the Compatibility renderer pays for on the spot, and a CIWS
## burst is dozens of rounds a second. That was the stutter on gunfire.
static var _tracer_parts: Dictionary = {}
static var _lick: Texture2D

# --------------------------------------------------------------------------- #
# Textures
# --------------------------------------------------------------------------- #

static func soft() -> Texture2D:
	## Round falloff. Muzzle flashes, glows, light bloom.
	if _soft != null:
		return _soft
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var uv := Vector2(float(x) / 63.0, float(y) / 63.0) * 2.0 - Vector2.ONE
			var falloff := clampf(1.0 - uv.length(), 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, pow(falloff, 2.1)))
	_soft = ImageTexture.create_from_image(image)
	return _soft

static func smoke() -> Texture2D:
	## Irregular cloud with a soft edge, so puffs never read as spheres.
	if _smoke != null:
		return _smoke
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 49
	noise.frequency = 0.022
	noise.fractal_octaves = 5
	for y in range(128):
		for x in range(128):
			var uv := Vector2(float(x) / 127.0, float(y) / 127.0) * 2.0 - Vector2.ONE
			var density: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var edge := clampf(1.0 - uv.length() / (0.62 + density * 0.42), 0.0, 1.0)
			var alpha := pow(edge, 1.35) * (0.3 + density * 0.7)
			var shade := 0.72 + density * 0.28
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	_smoke = ImageTexture.create_from_image(image)
	return _smoke

static func flame() -> Texture2D:
	## Hot core with a ragged, wispy boundary.
	if _flame != null:
		return _flame
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 12
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	for y in range(96):
		for x in range(96):
			var uv := Vector2(float(x) / 95.0, float(y) / 95.0) * 2.0 - Vector2.ONE
			var wisp: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var radius: float = uv.length() * (0.78 + wisp * 0.5)
			var alpha := clampf(1.0 - radius, 0.0, 1.0)
			alpha = pow(alpha, 1.1) * (0.45 + wisp * 0.55)
			var core := clampf(1.0 - uv.length() * 1.9, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.55 + core * 0.45, 0.25 + core * 0.7, alpha))
	_flame = ImageTexture.create_from_image(image)
	return _flame

static func lick() -> Texture2D:
	## A single tongue of flame: wide and solid at the root, tapering into a
	## ragged wisp. Stretched along its velocity this reads as fire, where a
	## round blob only ever reads as a puff.
	if _lick != null:
		return _lick
	var image := Image.create(48, 96, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.055
	noise.fractal_octaves = 3
	for y in range(96):
		for x in range(48):
			var v := float(y) / 95.0                       # 0 root, 1 tip
			var u := absf(float(x) / 47.0 * 2.0 - 1.0)
			# The tongue narrows and frays toward the tip.
			var width: float = (1.0 - pow(v, 0.75)) * 0.95
			var wisp: float = noise.get_noise_2d(float(x), float(y) * 0.6) * 0.5 + 0.5
			width *= 0.55 + wisp * 0.75
			var body := clampf(1.0 - u / maxf(width, 0.001), 0.0, 1.0)
			var alpha := pow(body, 1.25) * (1.0 - pow(v, 2.2))
			var heat := clampf(1.0 - v * 1.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.5 + heat * 0.5, 0.18 + heat * 0.7, alpha))
	_lick = ImageTexture.create_from_image(image)
	return _lick

static func spark() -> Texture2D:
	## Tiny hot point with a short halo.
	if _spark != null:
		return _spark
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var uv := Vector2(float(x) / 31.0, float(y) / 31.0) * 2.0 - Vector2.ONE
			var distance := uv.length()
			var core := clampf(1.0 - distance * 3.2, 0.0, 1.0)
			var halo := clampf(1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, clampf(core + pow(halo, 3.0) * 0.55, 0.0, 1.0)))
	_spark = ImageTexture.create_from_image(image)
	return _spark

static func streak() -> Texture2D:
	## Tracer glow: hot at one end, feathered into a tail at the other.
	if _streak != null:
		return _streak
	var image := Image.create(16, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(16):
			var v := float(y) / 63.0
			var u := absf(float(x) / 15.0 * 2.0 - 1.0)
			var along := pow(clampf(1.0 - v, 0.0, 1.0), 2.2)
			var across := pow(clampf(1.0 - u, 0.0, 1.0), 1.8)
			image.set_pixel(x, y, Color(1, 1, 1, along * across))
	_streak = ImageTexture.create_from_image(image)
	return _streak

# --------------------------------------------------------------------------- #
# Materials
# --------------------------------------------------------------------------- #

static func additive(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	return material

static func particle_material(texture: Texture2D, add: bool, lit: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without this the billboard discards the per-particle scale and every
	# particle renders at the bare quad size.
	material.billboard_keep_scale = true
	material.particles_anim_h_frames = 1
	material.particles_anim_v_frames = 1
	material.particles_anim_loop = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	if add:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if lit:
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		material.roughness = 1.0
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	else:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

static func aligned_material(texture: Texture2D, add: bool) -> StandardMaterial3D:
	## For emitters using transform_align: the particle transform already faces
	## the camera and points along velocity, so no billboard mode here.
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if add:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return material

static func ramp(stops: Array) -> GradientTexture1D:
	## stops: [[offset, Color], ...]. HDR so hot colours bloom through the glow.
	## A fresh Gradient already owns two points, so reuse those and insert the
	## rest — assigning the offset and colour arrays separately can desync them.
	var gradient := Gradient.new()
	gradient.set_offset(0, float(stops[0][0]))
	gradient.set_color(0, stops[0][1])
	gradient.set_offset(1, float(stops[stops.size() - 1][0]))
	gradient.set_color(1, stops[stops.size() - 1][1])
	for index in range(1, stops.size() - 1):
		gradient.add_point(float(stops[index][0]), stops[index][1])
	var texture := GradientTexture1D.new()
	texture.use_hdr = true
	texture.gradient = gradient
	texture.width = 128
	return texture

static func curve(points: Array) -> CurveTexture:
	var shape := Curve.new()
	shape.min_value = 0.0
	shape.max_value = 1.0
	for point: Array in points:
		shape.add_point(Vector2(float(point[0]), float(point[1])))
	var texture := CurveTexture.new()
	texture.curve = shape
	return texture

# --------------------------------------------------------------------------- #
# Emitters
# --------------------------------------------------------------------------- #

## Whether this renderer can afford the full effect budget. Alpha-blended
## particles are paid for in overdraw, and the Compatibility renderer used by
## the web build pays far more for it than the deferred one.
static func rich() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

static func make_particles(amount: int, lifetime: float, mesh_material: Material,
		process: ParticleProcessMaterial, quad_size: float = 1.0, stretch: float = 1.0) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	# Half the particles everywhere off the deferred path. Each one is a
	# transparent quad and the cost is in how many of them overlap.
	particles.amount = maxi(1, amount if rich() else int(ceil(amount * 0.5)))
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.process_material = process
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size * stretch)
	particles.draw_pass_1 = quad
	particles.material_override = mesh_material
	return particles

## How many one-shot bursts may be alive at once. A sinking hull throws a lot
## of them in the same frame, and the spike that causes is the stutter you feel
## rather than the average frame time.
const EFFECT_BUDGET: int = 64
## Test hook: -1 uses the constant above.
static var EFFECT_BUDGET_OVERRIDE: int = -1
static var live_bursts: int = 0

static func one_shot(parent: Node3D, point: Vector3, particles: GPUParticles3D, hold: float) -> GPUParticles3D:
	# Counts emitters, not nodes: wreckage and foam decals share this parent and
	# must not starve explosions out of existence.
	var budget: int = EFFECT_BUDGET_OVERRIDE if EFFECT_BUDGET_OVERRIDE >= 0 else (
		EFFECT_BUDGET if rich() else 22)
	if live_bursts >= budget:
		particles.queue_free()
		return null
	live_bursts += 1
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.set_script(preload("res://scripts/one_shot_particles.gd"))
	particles.set("ttl", particles.lifetime + hold)
	particles.set("counted", true)
	parent.add_child(particles)
	particles.global_position = point
	particles.emitting = true
	return particles

# --- fire ---------------------------------------------------------------- #

static func fire_core(power: float, upward: float) -> ParticleProcessMaterial:
	## The bright base of a flame: small, fast and very short lived.
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.3 * power
	process.direction = Vector3.UP
	process.spread = 14.0
	process.initial_velocity_max = upward
	process.initial_velocity_min = upward * 0.55
	process.gravity = Vector3(0, 3.0, 0)
	process.damping_max = 4.0
	process.damping_min = 2.0
	process.scale_max = 1.3 * power
	process.scale_min = 0.7 * power
	process.scale_curve = curve([[0.0, 0.5], [0.25, 1.0], [1.0, 0.3]])
	process.angle_max = 180.0
	process.angle_min = -180.0
	process.angular_velocity_max = 120.0
	process.angular_velocity_min = -120.0
	process.color_ramp = ramp([
		[0.0, Color(5.5, 4.4, 2.6, 1.0)],
		[0.25, Color(4.2, 2.2, 0.7, 1.0)],
		[0.6, Color(2.2, 0.75, 0.15, 0.75)],
		[1.0, Color(0.5, 0.12, 0.02, 0.0)]])
	return process

static func fire_body(power: float, upward: float) -> ParticleProcessMaterial:
	## The opaque part of a flame. Additive alone blows out against a bright sky
	## and gives fire no mass; this pass supplies the body and the dark edges,
	## with the additive layers riding on top of it.
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.42 * power
	process.direction = Vector3.UP
	process.spread = 17.0
	process.initial_velocity_max = upward
	process.initial_velocity_min = upward * 0.4
	process.gravity = Vector3(0, 4.0, 0)
	process.damping_max = 1.6
	process.damping_min = 0.4
	process.scale_max = 1.5 * power
	process.scale_min = 0.75 * power
	process.scale_curve = curve([[0.0, 0.4], [0.3, 1.0], [1.0, 0.35]])
	process.color_ramp = ramp([
		[0.0, Color(1.35, 0.62, 0.14, 0.85)],
		[0.3, Color(0.85, 0.30, 0.05, 0.85)],
		[0.66, Color(0.28, 0.09, 0.03, 0.6)],
		[1.0, Color(0.08, 0.05, 0.05, 0.0)]])
	return process

static func fire_process(power: float, upward: float = 5.0) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.55 * power
	process.direction = Vector3.UP
	process.spread = 26.0
	process.initial_velocity_max = upward
	process.initial_velocity_min = upward * 0.5
	process.gravity = Vector3(0, 2.2, 0)
	process.damping_max = 2.6
	process.damping_min = 1.2
	process.scale_max = 2.4 * power
	process.scale_min = 1.1 * power
	process.scale_curve = curve([[0.0, 0.35], [0.3, 1.0], [1.0, 0.55]])
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -70.0
	process.angular_velocity_max = 70.0
	# Godot's particle turbulence scatters these emitters to nothing at this
	# scale; the noise in the sprite plus per-particle spin carries the motion.
	process.turbulence_enabled = false
	process.color_ramp = ramp([
		[0.0, Color(3.0, 1.9, 0.8, 0.95)],
		[0.16, Color(2.4, 1.0, 0.22, 1.0)],
		[0.42, Color(1.35, 0.36, 0.06, 0.8)],
		[0.72, Color(0.42, 0.10, 0.02, 0.35)],
		[1.0, Color(0.10, 0.03, 0.01, 0.0)]])
	return process

static func smoke_process(power: float, rise: float, drift: Vector3, dark: bool) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8 * power
	process.direction = Vector3.UP
	process.spread = 34.0
	process.initial_velocity_max = rise
	process.initial_velocity_min = rise * 0.55
	process.gravity = drift
	process.damping_max = 1.7
	process.damping_min = 0.7
	process.scale_max = 2.1 * power
	process.scale_min = 1.05 * power
	process.scale_curve = curve([[0.0, 0.25], [0.45, 0.75], [1.0, 1.0]])
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -26.0
	process.angular_velocity_max = 26.0
	process.turbulence_enabled = false
	if dark:
		process.color_ramp = ramp([
			[0.0, Color(1.10, 0.52, 0.18, 0.0)],
			[0.05, Color(0.62, 0.34, 0.18, 0.95)],
			[0.18, Color(0.27, 0.24, 0.22, 1.0)],
			[0.45, Color(0.19, 0.19, 0.20, 0.92)],
			[1.0, Color(0.28, 0.30, 0.32, 0.0)]])
	else:
		process.color_ramp = ramp([
			[0.0, Color(0.95, 0.95, 0.93, 0.0)],
			[0.1, Color(0.82, 0.84, 0.83, 0.75)],
			[0.5, Color(0.70, 0.73, 0.74, 0.5)],
			[1.0, Color(0.65, 0.69, 0.71, 0.0)]])
	return process

static func spark_process(power: float, speed: float, gravity: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35 * power
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_max = speed
	process.initial_velocity_min = speed * 0.25
	process.gravity = Vector3(0, -gravity, 0)
	process.damping_max = 2.4
	process.damping_min = 0.6
	process.scale_max = 0.65 * power
	process.scale_min = 0.25 * power
	process.scale_curve = curve([[0.0, 1.0], [0.75, 0.7], [1.0, 0.0]])
	process.color_ramp = ramp([
		[0.0, Color(4.0, 3.0, 1.6, 1.0)],
		[0.25, Color(3.0, 1.3, 0.3, 1.0)],
		[0.7, Color(1.4, 0.35, 0.05, 0.8)],
		[1.0, Color(0.4, 0.08, 0.02, 0.0)]])
	return process

# --------------------------------------------------------------------------- #
# Tracers
# --------------------------------------------------------------------------- #

static func release() -> void:
	## Drop the cached meshes and materials. The audio bank had this same
	## problem: a static cache outliving the object database shows up as leaked
	## instances at exit.
	_tracer_parts.clear()

static func tracer_parts(length: float, width: float, core_color: Color,
		glow_color: Color, glow_width: float) -> Dictionary:
	## The meshes and materials for one kind of tracer, built once and shared by
	## every round of that kind thereafter.
	var key := "%.2f|%.3f|%s|%s|%.2f" % [length, width, core_color, glow_color, glow_width]
	if _tracer_parts.has(key):
		return _tracer_parts[key]
	var box := BoxMesh.new()
	box.size = Vector3(width, width, length)
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = core_color
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(glow_width, length * 1.35)
	var glow_material := additive(streak())
	glow_material.albedo_color = glow_color
	glow_material.vertex_color_use_as_albedo = false
	_tracer_parts[key] = {"box": box, "core": core_material,
		"quad": quad, "glow": glow_material}
	return _tracer_parts[key]

static func tracer(parent: Node3D, length: float, width: float, core_color: Color,
		glow_color: Color, glow_width: float) -> void:
	## A hot core that stays visible head-on, wrapped in a pair of crossed
	## additive glow strips so the round reads as a streak from any angle.
	var parts := tracer_parts(length, width, core_color, glow_color, glow_width)
	var core := MeshInstance3D.new()
	core.mesh = parts["box"]
	core.material_override = parts["core"]
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(core)
	for index in range(2):
		var strip := MeshInstance3D.new()
		strip.mesh = parts["quad"]
		strip.material_override = parts["glow"]
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(strip)
		var basis := Basis(Vector3.RIGHT, -PI * 0.5)
		if index == 1:
			basis = Basis(Vector3.BACK, PI * 0.5) * basis
		strip.transform = Transform3D(basis, Vector3(0, 0, length * 0.1))

static func flash(parent: Node3D, point: Vector3, size: float, color: Color,
		duration: float, light_energy: float) -> void:
	## Muzzle or impact flash: an additive billboard plus a very short light.
	var node := Node3D.new()
	node.set_script(preload("res://scripts/one_shot_particles.gd"))
	node.set("ttl", duration + 0.2)
	parent.add_child(node)
	node.global_position = point
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	sprite.mesh = quad
	var material := additive(soft())
	material.albedo_color = color
	material.vertex_color_use_as_albedo = false
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.material_override = material
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(sprite)
	var light: OmniLight3D = null
	if light_energy > 0.0:
		light = OmniLight3D.new()
		light.light_color = Color(color.r, color.g, color.b)
		light.light_energy = light_energy
		light.omni_range = size * 3.0
		light.shadow_enabled = false
		node.add_child(light)
	var tween := node.create_tween()
	tween.tween_property(sprite, "scale", Vector3.ONE * 1.9, duration)
	tween.parallel().tween_property(material, "albedo_color", Color(color.r, color.g, color.b, 0.0), duration)
	if light != null:
		tween.parallel().tween_property(light, "light_energy", 0.0, duration * 0.7)

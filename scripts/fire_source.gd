class_name FireSource
extends Node3D
## A burning compartment. Four layers, each doing one job: a white-hot core at
## the seat of the fire, tongues of flame stretched along their own velocity,
## embers carried up in the column, and the smoke above it. Particle counts stay
## small — alpha blending is paid for in overdraw and a hull can burn in three
## places at once.

var base: GPUParticles3D
var body: GPUParticles3D
var core: GPUParticles3D
var licks: GPUParticles3D
var embers: GPUParticles3D
var smoke: GPUParticles3D
var glow: OmniLight3D
var intensity: float = 0.0
var scale_factor: float = 1.0
var flicker: float = 0.0

## Whether this renderer can afford the full six-layer fire.
##
## Alpha-blended particles are paid for in overdraw, and the Compatibility
## renderer the web build uses pays far more for it than the deferred one: on an
## overloaded sector the fires alone were the difference between 29 fps and 145.
## The cheap build keeps the seat of the fire, the hot core and the smoke column
## — the three layers that carry the read — and drops the rest.
static func rich() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func _ready() -> void:
	# A low, wide seat of fire hugging the deck, under everything else.
	var base_process := Vfx.fire_body(1.25 * scale_factor, 1.8)
	base_process.spread = 62.0
	base_process.gravity = Vector3(0, 0.8, 0)
	base_process.scale_curve = Vfx.curve([[0.0, 0.55], [0.4, 1.0], [1.0, 0.6]])
	base = Vfx.make_particles(9, 0.72, Vfx.particle_material(Vfx.flame(), false),
		base_process, 2.5 * scale_factor)
	base.visibility_aabb = AABB(Vector3(-9, -4, -9), Vector3(18, 14, 18))
	add_child(base)

	# The body of the flame: alpha blended, so the fire has mass and an edge.
	var body_process := Vfx.fire_body(0.85 * scale_factor, 7.0)
	body = Vfx.make_particles(15, 0.85, Vfx.aligned_material(Vfx.lick(), false),
		body_process, 1.6 * scale_factor, 2.3)
	body.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	body.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 30, 24))
	add_child(body)

	core = Vfx.make_particles(12, 0.38, Vfx.particle_material(Vfx.flame(), true),
		Vfx.fire_core(0.8 * scale_factor, 6.0), 1.4 * scale_factor)
	core.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 20, 16))
	add_child(core)

	# Tongues of flame: aligned to their own velocity and billboarded, so they
	# rise as stretched licks rather than tumbling blobs.
	var lick_process := Vfx.fire_process(0.75 * scale_factor, 9.0)
	lick_process.spread = 12.0
	lick_process.gravity = Vector3(0, 5.0, 0)
	lick_process.damping_max = 1.2
	lick_process.damping_min = 0.3
	lick_process.angular_velocity_max = 0.0
	lick_process.angular_velocity_min = 0.0
	lick_process.scale_curve = Vfx.curve([[0.0, 0.45], [0.28, 1.0], [1.0, 0.25]])
	licks = Vfx.make_particles(18, 0.8, Vfx.aligned_material(Vfx.lick(), true),
		lick_process, 1.5 * scale_factor, 2.6)
	licks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	licks.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 30, 24))
	add_child(licks)
	licks.emitting = rich()
	licks.visible = rich()
	body.emitting = rich()
	body.visible = rich()

	var ember_process := Vfx.spark_process(0.5 * scale_factor, 5.0, -6.0)
	ember_process.direction = Vector3.UP
	ember_process.spread = 30.0
	ember_process.damping_max = 0.6
	ember_process.damping_min = 0.1
	embers = Vfx.make_particles(14, 1.7, Vfx.particle_material(Vfx.spark(), true),
		ember_process, 0.5 * scale_factor)
	embers.visibility_aabb = AABB(Vector3(-14, -4, -14), Vector3(28, 40, 28))
	add_child(embers)
	embers.emitting = rich()
	embers.visible = rich()

	smoke = Vfx.make_particles(26 if rich() else 14, 4.5, Vfx.particle_material(Vfx.smoke(), false, true),
		Vfx.smoke_process(1.15 * scale_factor, 8.0, Vector3(1.6, 0.5, 0.5), true), 3.2 * scale_factor)
	smoke.visibility_aabb = AABB(Vector3(-40, -8, -40), Vector3(80, 70, 80))
	add_child(smoke)

	glow = OmniLight3D.new()
	glow.light_color = Color("ff8a3c")
	glow.omni_range = 17.0 * scale_factor
	glow.shadow_enabled = false
	# Forward lighting costs per light per fragment, and a burning sector can
	# have a dozen of these. The deferred build hardly notices; this one does.
	glow.visible = rich()
	add_child(glow)
	set_intensity(0.0)

func layers() -> Array[GPUParticles3D]:
	if not rich():
		return [base, core, smoke]
	return [base, body, core, licks, embers, smoke]

func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	var alive := intensity > 0.03
	var ratio := clampf(0.28 + intensity * 0.72, 0.05, 1.0)
	for layer in layers():
		layer.emitting = alive
		if alive:
			layer.amount_ratio = ratio

func _process(delta: float) -> void:
	flicker += delta * 13.0
	# Two detuned oscillators so the light never settles into a visible pulse.
	var wobble := 0.62 + 0.38 * sin(flicker) * sin(flicker * 0.41 + 1.1)
	glow.light_energy = intensity * 5.4 * wobble * scale_factor

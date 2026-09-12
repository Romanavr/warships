extends Node3D
## One-shot detonation: white-hot flash, a rolling fireball, ejected embers,
## ballistic debris and a smoke column that outlives all of it.
var world: Node3D
var power: float = 1.0
var age: float = 0.0
var flash: OmniLight3D
var smoke_emitted: bool = false

func _ready() -> void:
	flash = OmniLight3D.new()
	flash.light_color = Color("ffcf9c")
	flash.light_energy = 26.0 * power
	flash.omni_range = 62.0 * power
	flash.shadow_enabled = false
	add_child(flash)

	# Ignition: a very brief bright core before the fireball rolls out.
	var core_material := Vfx.additive(Vfx.soft())
	var core := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 5.5 * power
	core.mesh = quad
	core_material.albedo_color = Color(2.6, 2.1, 1.5, 1.0)
	core_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	core_material.vertex_color_use_as_albedo = false
	core.material_override = core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var fade := create_tween()
	fade.tween_property(core, "scale", Vector3.ONE * 2.2, 0.28)
	fade.parallel().tween_property(core_material, "albedo_color", Color(0.6, 0.15, 0.02, 0.0), 0.28)

	# Fireball.
	var fireball := Vfx.fire_process(0.85 * power, 12.0 * power)
	fireball.initial_velocity_min = 5.0 * power
	fireball.spread = 62.0
	fireball.gravity = Vector3(0, 5.0, 0)
	fireball.damping_min = 6.0
	fireball.damping_max = 12.0
	fireball.scale_curve = Vfx.curve([[0.0, 0.3], [0.35, 1.0], [1.0, 0.85]])
	Vfx.one_shot(world.effects, global_position,
		Vfx.make_particles(int(16 * power) + 8, 0.95,
			Vfx.particle_material(Vfx.flame(), true), fireball, 4.0 * power), 0.4)

	# Embers thrown clear of the fireball.
	Vfx.one_shot(world.effects, global_position,
		Vfx.make_particles(int(22 * power) + 10, 1.7,
			Vfx.particle_material(Vfx.spark(), true),
			Vfx.spark_process(power, 24.0 * power, 14.0), 1.1 * power), 0.4)

	world.debris(global_position, int(10 * power) + 2, 2.0 * power)

func _process(delta: float) -> void:
	age += delta
	flash.light_energy = 26.0 * power * exp(-age * 11.0)
	if age > 0.16 and not smoke_emitted:
		smoke_emitted = true
		var column := Vfx.smoke_process(1.1 * power, 9.5 * power, Vector3(1.6, 0.7, 0.6), true)
		column.spread = 55.0
		column.scale_curve = Vfx.curve([[0.0, 0.3], [0.5, 0.8], [1.0, 1.0]])
		Vfx.one_shot(world.effects, global_position,
			Vfx.make_particles(int(10 * power) + 5, 4.6,
				Vfx.particle_material(Vfx.smoke(), false, true), column, 4.2 * power), 0.5)
	if age > 1.2:
		queue_free()

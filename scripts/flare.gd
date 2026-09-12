extends Node3D
var world: Node3D
var aircraft: CombatHelicopter
var burst_id: int = 0
var velocity := Vector3.ZERO
var age: float = 0
var trail_clock: float = 0

func _ready() -> void:
	add_to_group("flares")
	var mesh := NavalGeometry.box(self, Vector3.ONE * 0.3, Vector3.ZERO, Color(3.0, 2.4, 1.4))
	mesh.material_override = NavalGeometry.material(Color(3.0, 2.4, 1.4), true)
	var burn := Vfx.fire_process(0.35, 2.5)
	burn.gravity = Vector3(0, 1.5, 0)
	burn.color_ramp = Vfx.ramp([
		[0.0, Color(4.0, 3.4, 2.4, 1.0)],
		[0.3, Color(3.0, 1.8, 0.6, 0.9)],
		[1.0, Color(0.8, 0.25, 0.05, 0.0)]])
	var fire := Vfx.make_particles(24, 0.65, Vfx.particle_material(Vfx.flame(), true), burn, 2.0)
	add_child(fire)
	fire.emitting = true
	var glow := OmniLight3D.new()
	glow.light_color = Color("ffd08a")
	glow.light_energy = 8.0
	glow.omni_range = 34.0
	glow.shadow_enabled = false
	add_child(glow)

func _physics_process(delta: float) -> void:
	age += delta
	velocity.y -= delta * 4
	position += velocity * delta
	trail_clock += delta
	if trail_clock > 0.14:
		trail_clock = 0
		world.smoke_puff(position, 0.3, 2.4, Vector3.UP * 0.3, Color(0.78, 0.79, 0.76, 0.45), 0.35)
	if age > 3.8:
		queue_free()

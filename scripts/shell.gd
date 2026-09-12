extends Node3D
## Swept segment collision avoids tunneling at high projectile speeds.
const SPEED: float = 230.0
const GRAVITY: float = 2.0
var velocity := Vector3.ZERO
var exclusions: Array[RID] = []
var world: Node3D
var age: float = 0.0
var damage: float = 64.0
var by_player: bool = false
var is_rocket: bool = false
var trail: GPUParticles3D

func _ready() -> void:
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = false
	add_child(lamp)
	if is_rocket:
		# A rocket is its own flare: short hot tracer, a motor plume, and a fat
		# smoke trail hanging in the air behind it.
		Vfx.tracer(self, 5.0, 0.26, Color(3.6, 2.6, 1.2), Color(2.0, 0.8, 0.2, 0.6), 2.6)
		lamp.light_color = Color("ff9a45")
		lamp.light_energy = 5.0
		lamp.omni_range = 30.0
		var flame := Vfx.fire_core(0.42, 3.5)
		flame.direction = Vector3.BACK
		flame.spread = 14.0
		flame.gravity = Vector3.ZERO
		flame.damping_max = 9.0
		flame.damping_min = 4.0
		var plume := Vfx.make_particles(14, 0.2, Vfx.particle_material(Vfx.flame(), true), flame, 1.6)
		add_child(plume)
		plume.position = Vector3(0, 0, 1.4)
		plume.emitting = true
		var smoke := Vfx.smoke_process(0.72, 0.8, Vector3(0.3, 0.5, 0.15), false)
		smoke.spread = 20.0
		smoke.initial_velocity_max = 1.6
		smoke.initial_velocity_min = 0.0
		smoke.damping_max = 0.5
		smoke.damping_min = 0.1
		smoke.scale_curve = Vfx.curve([[0.0, 0.3], [0.4, 0.8], [1.0, 1.0]])
		trail = Vfx.make_particles(80, 3.2, Vfx.particle_material(Vfx.smoke(), false, true), smoke, 2.6)
		trail.visibility_aabb = AABB(Vector3(-120, -60, -120), Vector3(240, 120, 240))
		add_child(trail)
		trail.position = Vector3(0, 0, 1.7)
		trail.emitting = true
		return
	Vfx.tracer(self, 11.0, 0.34, Color(3.2, 2.4, 1.15), Color(1.7, 0.62, 0.16, 0.55), 3.6)
	lamp.light_color = Color("ffb762")
	lamp.light_energy = 3.2
	lamp.omni_range = 26.0

func finish() -> void:
	## Let the laid smoke drift on after the round is gone.
	if is_instance_valid(trail) and is_instance_valid(world) and is_instance_valid(world.effects):
		trail.emitting = false
		var where := trail.global_transform
		remove_child(trail)
		trail.set_script(preload("res://scripts/one_shot_particles.gd"))
		trail.set("ttl", trail.lifetime + 0.5)
		world.effects.add_child(trail)
		trail.global_transform = where
	queue_free()

func launch(origin: Vector3, target: Vector3, ignored: Array[RID]) -> void:
	global_position = origin
	exclusions = ignored
	var flight_time := maxf(origin.distance_to(target) / SPEED, 0.01)
	velocity = (target - origin) / flight_time
	velocity.y += 0.5 * GRAVITY * flight_time
	look_at(position + velocity)

func _physics_process(delta: float) -> void:
	age += delta
	var next := global_position + velocity * delta + Vector3.DOWN * GRAVITY * delta * delta * 0.5
	velocity.y -= GRAVITY * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, 3, exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Node = hit.collider
		if collider.has_meta("boat"):
			var boat: Node3D = collider.get_meta("boat")
			# Counted here and not in `report_hit`, which every CIWS round also
			# goes through: rounds on target has to be the same population as
			# rounds fired, or accuracy is a ratio between two different things.
			if by_player and not is_rocket:
				world.tally.landed += 1
			boat.take_hit(String(collider.get_meta("section")), damage, hit.position, by_player)
		world.impact(hit.position, 0.5)
		world.explosion(hit.position, 0.22)
		finish()
		return
	global_position = next
	if next.y < world.ocean.height_at(next):
		world.splash(Vector3(next.x, world.ocean.height_at(next), next.z), 2.2 if not is_rocket else 1.3)
		finish()
	elif age > 4.0:
		finish()

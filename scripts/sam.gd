extends Node3D
## Short-range IR missile. Flares can seduce the seeker; radar missiles are not modeled.
var world: Node3D
var source: Node3D
var target: Node3D
var velocity := Vector3.UP * 35
var age: float = 0.0
var detonated: bool = false
var intercept_health: float = 24.0
var exclusions: Array[RID] = []
var trail_clock: float = 0
var considered_bursts: Array[int] = []
var seeker_decoyed: bool = false
var plume: GPUParticles3D
var trail: GPUParticles3D

func _ready() -> void:
	add_to_group("guided_missiles")
	add_to_group("sam_missiles")
	var model := NavalGeometry.box(self, Vector3(0.22, 0.22, 2), Vector3.ZERO, Color("deded0"))
	model.material_override = NavalGeometry.material(Color("deded0"), true)
	build_plume()
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("missile", self)
	add_child(area)
	var shape := SphereShape3D.new()
	shape.radius = 1.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)

func build_plume() -> void:
	var flame := Vfx.fire_process(0.3, 1.6)
	flame.direction = Vector3.BACK
	flame.spread = 10.0
	flame.initial_velocity_min = 1.5
	flame.initial_velocity_max = 5.0
	flame.gravity = Vector3.ZERO
	flame.damping_min = 6.0
	flame.damping_max = 12.0
	plume = Vfx.make_particles(14, 0.2, Vfx.particle_material(Vfx.flame(), true), flame, 1.5)
	add_child(plume)
	plume.position = Vector3(0, 0, 1.3)
	plume.emitting = true
	var smoke := Vfx.smoke_process(0.4, 0.5, Vector3(0.4, 0.3, 0.2), false)
	smoke.spread = 18.0
	smoke.initial_velocity_min = 0.0
	smoke.initial_velocity_max = 1.0
	smoke.damping_min = 0.1
	smoke.damping_max = 0.4
	trail = Vfx.make_particles(110, 4.6, Vfx.particle_material(Vfx.smoke(), false, true), smoke, 2.6)
	add_child(trail)
	trail.visibility_aabb = AABB(Vector3(-400, -200, -400), Vector3(800, 400, 800))
	trail.position = Vector3(0, 0, 1.5)
	trail.emitting = true

func launch(origin: Vector3, aircraft: CombatHelicopter, ship: Node3D) -> void:
	position = origin
	source = ship
	target = aircraft
	exclusions = ship.colliders.duplicate()

func consider_flare(flare: Node3D, random_roll: float) -> bool:
	if seeker_decoyed or not is_instance_valid(target) or not (target is CombatHelicopter):
		return false
	if flare.aircraft != target or considered_bursts.has(flare.burst_id):
		return false
	if flare.position.distance_to(position) > 300:
		return false
	considered_bursts.append(flare.burst_id)
	if random_roll < 0.55:
		target = flare
		seeker_decoyed = true
		world.sam_decoyed += 1
		return true
	return false

func _physics_process(delta: float) -> void:
	if detonated:
		return
	age += delta
	if is_instance_valid(target) and target is CombatHelicopter and not target.destroyed:
		for flare in get_tree().get_nodes_in_group("flares"):
			if consider_flare(flare, randf()):
				break
	if is_instance_valid(target) and age > 0.35:
		var aim: Vector3 = target.position
		if target is CombatHelicopter:
			aim += target.velocity * minf(position.distance_to(aim) / 150.0, 0.8)
		var desired := position.direction_to(aim)
		var current := velocity.normalized()
		var angle := current.angle_to(desired)
		velocity = current.slerp(desired, minf(1, 2.0 * delta / maxf(0.001, angle))).normalized() * move_toward(velocity.length(), 150, delta * 100)
	else:
		velocity += Vector3.DOWN * delta * 6
	var next := position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(position, next, 11, exclusions)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var aircraft: CombatHelicopter = (hit.collider.get_meta("aircraft") if hit.collider.has_meta("aircraft") else null)
		detonate(hit.position, aircraft)
		return
	position = next
	if is_instance_valid(target) and position.distance_to(target.position) < 6:
		detonate(position, target if target is CombatHelicopter else null)
		return
	if velocity.length_squared() > 0.1:
		look_at(position + velocity, Vector3.FORWARD if absf(velocity.normalized().y) > 0.95 else Vector3.UP)
	if age > 11 or position.y < world.ocean.height_at(position):
		detonate(position, null)

func detonate(point: Vector3, aircraft: CombatHelicopter) -> void:
	if detonated:
		return
	detonated = true
	if is_instance_valid(trail) and is_instance_valid(world) and is_instance_valid(world.effects):
		trail.emitting = false
		var where := trail.global_transform
		remove_child(trail)
		trail.set_script(preload("res://scripts/one_shot_particles.gd"))
		trail.set("ttl", trail.lifetime + 0.5)
		world.effects.add_child(trail)
		trail.global_transform = where
	world.explosion(point, 0.45)
	if is_instance_valid(aircraft):
		aircraft.take_damage(80, is_instance_valid(source) and source.manual)
	queue_free()

func take_interception_damage(amount: float) -> void:
	intercept_health -= amount
	if intercept_health <= 0:
		world.missiles_intercepted += 1
		detonate(position, null)

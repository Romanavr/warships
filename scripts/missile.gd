extends Node3D
## Stylized guided missile: boost, low cruise, then terminal homing.
const SPEED: float = 90.0
const TURN_RATE: float = 2.6
var world: Node3D
var target: PatrolBoat
var source: Node3D
var warhead_damage: float = 290.0
var exclusions: Array[RID] = []
var velocity := Vector3.ZERO
var age: float = 0.0
var trail_clock: float = 0.0
var last_trail := Vector3.ZERO
var detonated: bool = false
var by_player: bool = false
## Guidance, and how long the seeker has been looking at rock instead of a ship.
var guiding: bool = true
var masked: float = 0.0
var intercept_health: float = 48.0
var exhaust: MeshInstance3D
var plume: GPUParticles3D
var trail: GPUParticles3D

func _ready() -> void:
	add_to_group("guided_missiles")
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("missile", self)
	add_child(area)
	var shape := SphereShape3D.new()
	shape.radius = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	var body := NavalGeometry.cylinder(self, 0.22, 0.12, 2.5, Vector3.ZERO, Color("d3d5c7"), 10)
	body.rotation.x = PI / 2
	NavalGeometry.box(self, Vector3(1.25, 0.07, 0.55), Vector3(0, 0, 0.7), Color("778683"))
	NavalGeometry.box(self, Vector3(0.07, 1.1, 0.55), Vector3(0, 0, 0.7), Color("778683"))
	exhaust = NavalGeometry.cylinder(self, 0.04, 0.2, 1.5, Vector3(0, 0, 1.9), Color("ffb76b"), 8)
	exhaust.rotation.x = PI / 2
	var material := NavalGeometry.material(Color("ffddac"), true)
	material.emission_enabled = true
	material.emission = Color("ff983f")
	material.emission_energy_multiplier = 5.0
	exhaust.material_override = material
	build_plume(1.0)

func build_plume(scale_factor: float) -> void:
	## Continuous world-space exhaust: a short hot plume laying down a long
	## smoke trail that hangs in the air behind the missile.
	var flame := Vfx.fire_process(0.4 * scale_factor, 2.0)
	flame.direction = Vector3.BACK
	flame.spread = 12.0
	flame.initial_velocity_min = 2.0
	flame.initial_velocity_max = 7.0
	flame.gravity = Vector3.ZERO
	flame.damping_min = 6.0
	flame.damping_max = 12.0
	plume = Vfx.make_particles(24, 0.3, Vfx.particle_material(Vfx.flame(), true), flame, 2.6 * scale_factor)
	add_child(plume)
	plume.position = Vector3(0, 0, 1.9 * scale_factor)
	plume.emitting = true
	var smoke := Vfx.smoke_process(0.55 * scale_factor, 0.7, Vector3(0.5, 0.35, 0.2), false)
	smoke.spread = 22.0
	smoke.initial_velocity_min = 0.0
	smoke.initial_velocity_max = 1.4
	smoke.damping_min = 0.1
	smoke.damping_max = 0.5
	smoke.scale_curve = Vfx.curve([[0.0, 0.25], [0.4, 0.7], [1.0, 1.0]])
	trail = Vfx.make_particles(150, 6.0, Vfx.particle_material(Vfx.smoke(), false, true), smoke, 3.2 * scale_factor)
	add_child(trail)
	trail.visibility_aabb = AABB(Vector3(-400, -200, -400), Vector3(800, 400, 800))
	trail.position = Vector3(0, 0, 2.2 * scale_factor)
	trail.emitting = true
	var glow := OmniLight3D.new()
	glow.light_color = Color("ffa24a")
	glow.light_energy = 4.5
	glow.omni_range = 34.0
	glow.shadow_enabled = false
	add_child(glow)
	glow.position = Vector3(0, 0, 2.0 * scale_factor)

func detach_trail() -> void:
	## Let the laid smoke drift after the missile is gone.
	if not is_instance_valid(trail):
		return
	trail.emitting = false
	if not is_instance_valid(world) or not is_instance_valid(world.effects):
		return
	var transform := trail.global_transform
	remove_child(trail)
	trail.set_script(preload("res://scripts/one_shot_particles.gd"))
	trail.set("ttl", trail.lifetime + 0.5)
	world.effects.add_child(trail)
	trail.global_transform = transform

func launch(origin: Vector3, boat: PatrolBoat, shooter: Node3D) -> void:
	global_position = origin
	target = boat
	source = shooter
	by_player = shooter.manual
	exclusions = shooter.colliders.duplicate()
	velocity = -shooter.basis.z * 50 if shooter.is_in_group("aircraft") else Vector3.UP * 28.0
	last_trail = origin
	look_at(position + velocity, Vector3.FORWARD if absf(velocity.normalized().y) > 0.95 else Vector3.UP)

func _physics_process(delta: float) -> void:
	if detonated:
		return
	age += delta
	check_masking(delta)
	if not is_instance_valid(target) or target.sunk or not guiding:
		velocity = velocity.move_toward(Vector3(velocity.x, -22, velocity.z), delta * 25)
	elif age > 0.65:
		var goal := target.visuals.to_global(Vector3(0, 2.5, 0))
		var distance := global_position.distance_to(goal)
		goal -= target.basis.z * target.speed * minf(distance / SPEED, 1.5)
		if distance > 38:
			goal.y = world.ocean.height_at(goal) + 6.5
		var desired := (goal - global_position).normalized()
		var current := velocity.normalized()
		var angle := current.angle_to(desired)
		var weight := minf(1.0, TURN_RATE * delta / maxf(angle, 0.001))
		velocity = current.slerp(desired, weight).normalized() * move_toward(velocity.length(), SPEED, delta * 42)
	else:
		velocity += velocity.normalized() * delta * 30
	var next := global_position + velocity * delta
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(global_position, next, 3, exclusions))
	if not hit.is_empty():
		var victim: PatrolBoat = (hit.collider.get_meta("boat") if hit.collider.has_meta("boat") else null)
		detonate(hit.position, victim)
		return
	global_position = next
	if velocity.length_squared() > 0.01:
		look_at(position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.FORWARD)
	exhaust.scale.y = 0.8 + sin(age * 60) * 0.18
	if next.y < world.ocean.height_at(next):
		detonate(next, null)
	elif age > 24.0:
		detonate(next, null)

## How long the seeker will hold a track it cannot see before giving up on it.
const MASK_GRACE: float = 0.55

func check_masking(delta: float) -> void:
	## A sea-skimmer flies at six metres and looks along its own nose. Put an
	## island between it and the ship and there is nothing for the seeker to
	## look at — so it loses the track, goes ballistic and hits the rock.
	##
	## This is the one thing that makes the islands terrain rather than scenery.
	## Guns already respect them (`clear_shot` raycasts through layer 2); until
	## now missiles flew straight past a headland as if it were painted on.
	if not guiding or age < 0.65 or not is_instance_valid(target) or target.sunk:
		return
	# Layer 2 only: another hull in the way is not masking, it is a different
	# target, and the flight raycast below already deals with hitting it.
	var goal: Vector3 = target.visuals.to_global(Vector3(0, 2.5, 0))
	var blocked := not get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(global_position, goal, 2)).is_empty()
	masked = masked + delta if blocked else 0.0
	if masked < MASK_GRACE:
		return
	# A seeker does not give up the instant the picture flickers; a wave crest or
	# a moment of geometry should not throw the missile away.
	guiding = false
	if world != null:
		world.report("%s / seeker lost the track — terrain masking"
			% ("Vampire" if not by_player else "Missile"))

func detonate(point: Vector3, victim: PatrolBoat) -> void:
	if detonated:
		return
	detonated = true
	if by_player and is_instance_valid(victim):
		world.tally.missile_hits += 1
	detach_trail()
	world.explosion(point, 1.0)
	if is_instance_valid(victim) and not victim.sunk:
		victim.take_blast(point, warhead_damage, by_player)
	elif point.y < world.ocean.height_at(point) + 2:
		world.splash(point, 2.5)
	queue_free()

func take_interception_damage(amount: float) -> void:
	if detonated:
		return
	intercept_health -= amount
	world.burst(position, Color("ffdfa0"), 2, 0.18)
	if intercept_health <= 0:
		detonated = true
		detach_trail()
		if is_instance_valid(source) and source.has_method("note_interception"):
			source.note_interception()
		world.missiles_intercepted += 1
		world.explosion(position, 0.35)
		world.report("CIWS / incoming missile destroyed")
		queue_free()

class_name CombatHelicopter
extends Node3D
## Original silhouettes inspired by the requested aircraft, with fictional tuning.
var world: Node3D
var manual := false
var selection: MeshInstance3D
var sunk: bool:
	get:
		return destroyed
var has_move_order := false
var explicit_target := false
var destination := Vector3.ZERO
var flight_height := 45.0
var team: int = 0
var variant: String = "Apache"
var callsign: String = "APACHE"
var health: float = 150.0
var maximum_health: float = 150.0
var destroyed: bool = false
var rockets: int = 8
var flare_packs: int = 3
var flare_cooldown: float = 0.0
var flare_generation: int = 0
var rocket_cooldown: float = 0.0
var velocity := Vector3.ZERO
var colliders: Array[RID] = []
var target: Node3D
var air_missiles: int = 2
var cannon_rounds: int = 120
var air_stores: Array[MeshInstance3D] = []
var air_cooldown: float = 0.0
var cannon_cooldown: float = 0.0
var fall_clock: float = 0.0
var home := Vector3.ZERO
var task: String = "ESCORT"
var rotor: Node3D
var tail_rotor: Node3D
var blades: Node3D
var rotor_disc: MeshInstance3D
var canopy: Node3D
var boom: Node3D
var blade_count: int = 4
var blade_reach: float = 5.1
var seats: Array[Vector3] = []
var burning := false
var mounts: Array[Node3D] = []
var age: float = 0.0
var evade_until: float = 0.0

func _ready() -> void:
	add_to_group("aircraft")
	home = position
	maximum_health = 190.0 if variant == "Hind" else 150.0
	health = maximum_health
	build_model()
	scale = Vector3.ONE * 1.5
	selection = NavalGeometry.ring(self, 11, Color("8ce0c8"), 0.12)
	selection.visible = false
	selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.set_meta("aircraft", self)
	add_child(area)
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 9)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	colliders.append(area.get_rid())

func build_model() -> void:
	var model := HelicopterModel.build(self, team, variant)
	mounts.assign(model["mounts"])
	air_stores.assign(model["air_stores"])
	rotor = model["rotor"]
	tail_rotor = model["tail_rotor"]
	blades = model["blades"]
	rotor_disc = model["disc"]
	boom = model["boom"]
	canopy = model["canopy"]
	blade_count = model["blade_count"]
	blade_reach = model["blade_reach"]
	seats.assign(model["seats"])

func is_combat_capable() -> bool:
	return not destroyed and (rockets > 0 or air_missiles > 0 or cannon_rounds > 0)

func holding_fire() -> bool:
	## Ours, under AI, while the mission says our side is not engaging aircraft.
	## Once the player takes the controls the hold is theirs to ignore.
	return team == 0 and not manual and world != null and world.air_hold

func _physics_process(delta: float) -> void:
	age += delta
	if not destroyed:
		rotor.rotation.y += delta * 34
		tail_rotor.rotation.y += delta * 62
	if destroyed:
		velocity.y -= delta * 9.8
		velocity.x *= 1.0 - delta * 0.3
		velocity.z *= 1.0 - delta * 0.3
		position += velocity * delta
		# With the head shed, the airframe has nothing holding it: it rolls off
		# and spins about the tail boom the way an unloaded rotorcraft does.
		rotation.z += delta * 1.5
		rotation.y += delta * 2.6
		rotation.x = lerpf(rotation.x, 0.7, delta * 0.5)
		fall_clock += delta
		if fall_clock > 0.06:
			fall_clock = 0.0
			world.smoke_puff(to_global(Vector3(0, 0.3, 1.5)), 1.5, 2.6,
				Vector3.UP * 1.5, Color(0.1, 0.1, 0.11, 0.7), 2.4)
			world.smoke_puff(to_global(Vector3(0, 0.3, 0.5)), 0.9, 0.5,
				Vector3.UP * 3.0, Color(1.0, 0.55, 0.16, 0.9), 1.6)
		if position.y < world.ocean.height_at(position):
			world.explosion(position, 1.4)
			world.splash(position, 2.5)
			world.oil_slick(position, 16.0)
			queue_free()
		return
	flare_cooldown = maxf(0, flare_cooldown - delta)
	rocket_cooldown = maxf(0, rocket_cooldown - delta)
	air_cooldown = maxf(0, air_cooldown - delta)
	cannon_cooldown = maxf(0, cannon_cooldown - delta)
	if manual:
		process_manual(delta)
		return
	if holding_fire():
		# Told to stand off. The duel in level three is the player's to fight,
		# and an AI Shaheen shot the gunship down during the four lines of
		# dialogue that hand over the cockpit — the level's whole set piece,
		# resolved by someone else while the player read about it.
		explicit_target = false
		target = null
	elif not explicit_target or not is_instance_valid(target) or not target.is_combat_capable():
		explicit_target = false
		target = choose_target()
	# Friendly aircraft keep station on the ship they are covering, so "no
	# orders" means escorting rather than loitering over an empty spawn point.
	if team == 0 and is_instance_valid(world.player_ship) and not world.player_ship.sunk:
		home = world.player_ship.position + Vector3(-60, 0, 45).rotated(Vector3.UP, world.player_ship.rotation.y)
	task = "ESCORT"
	if not is_combat_capable():
		task = "WINCHESTER"
	elif is_instance_valid(target):
		task = ("ENGAGING " + target.callsign) if explicit_target else ("ATTACKING " + target.callsign)
	var desired := home - position
	if is_instance_valid(target) and is_combat_capable():
		desired = target.position - position
		desired.y = 0
		var distance := desired.length()
		if distance < (180 if target is CombatHelicopter else 320):
			desired = Vector3(desired.z, 0, -desired.x)
		if age < evade_until:
			desired = Vector3(-desired.z, 0, desired.x)
		# No guided anti-ship rounds aboard: to hurt a ship this aircraft has to
		# come inside rocket range and wear the return fire.
		if target is PatrolBoat and distance < 420 and rockets > 0 and rocket_cooldown <= 0:
			rockets -= 1
			rocket_cooldown = 0.65
			world.fire_rocket(mounts[rockets % 4].global_position, target.visuals.to_global(Vector3(0, 3, 0)), colliders)
		if target is CombatHelicopter:
			var origin := to_global(Vector3(0, -1, -5))
			if distance < 900 and air_missiles > 0 and air_cooldown <= 0:
				air_stores[2 - air_missiles].visible = false
				air_missiles -= 1
				air_cooldown = 7.0
				var missile = load("res://scripts/sam.gd").new()
				missile.world = world
				world.projectiles.add_child(missile)
				missile.launch(origin, target, self)
				missile.velocity = -basis.z * 65
			if distance < 330 and cannon_rounds > 0 and cannon_cooldown <= 0:
				var aim: Vector3 = target.position + target.velocity * distance / 650.0
				if (-basis.z).dot(position.direction_to(aim)) > 0.6:
					cannon_rounds -= 1
					cannon_cooldown = 0.10
					world.fire_ciws(origin, aim, colliders, true, false)
	if has_move_order:
		desired = destination - position
		desired.y = 0
		if desired.length() < 15:
			desired = Vector3.ZERO
		else:
			desired = desired.normalized() * minf(1, desired.length() / 90)
	if desired.length() > 0.01:
		desired.y = 0
		var next_velocity := desired.normalized() * (minf(1, desired.length()) if has_move_order else 1.0) * (52 if variant == "Apache" else 46)
		if not is_combat_capable():
			next_velocity *= 0.7
		velocity = velocity.move_toward(next_velocity, delta * 18)
		var heading := atan2(-velocity.x, -velocity.z)
		rotation.y = rotate_toward(rotation.y, heading, delta * 0.8)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 22)
	position += velocity * delta
	position.y = lerpf(position.y, flight_height + sin(age * 0.3) * 2, delta)
	for sam in get_tree().get_nodes_in_group("sam_missiles"):
		if sam.target == self and sam.position.distance_to(position) < 350:
			deploy_flares()
			break

func deploy_flares() -> bool:
	if destroyed or flare_packs <= 0 or flare_cooldown > 0:
		return false
	flare_packs -= 1
	flare_cooldown = 6.0
	flare_generation += 1
	evade_until = age + 3.5
	world.deploy_flares(self, flare_generation)
	return true

func take_supplies_repair() -> String:
	health = minf(maximum_health, health + maximum_health * 0.5)
	flare_packs = mini(3, flare_packs + 1)
	return "Airframe patched"

func take_supplies_ordnance() -> String:
	var before := rockets
	rockets = mini(8, rockets + 4)
	cannon_rounds = mini(120, cannon_rounds + 60)
	var loaded := 0
	for slot in range(air_stores.size()):
		if air_missiles >= 2:
			break
		if not air_stores[slot].visible:
			air_stores[slot].visible = true
			air_missiles += 1
			loaded += 1
	if loaded > 0:
		return "%d rocket%s and %d air-to-air" % [rockets - before, "" if rockets - before == 1 else "s", loaded]
	return "Rockets and cannon reloaded"

func take_damage(amount: float, by_player: bool = false) -> void:
	if destroyed:
		return
	health = maxf(0, health - amount)
	var lost := health <= 0
	world.report_hit(position, amount, lost, by_player)
	if lost:
		world.report_module_lost(position, "aircraft down", team == 0)
	if manual:
		world.report_player_damage(amount)
	if lost:
		destroyed = true
		break_up()
		world.report(callsign + " / aircraft lost")

func break_up() -> void:
	## The aircraft comes apart the way one actually does: the head sheds its
	## blades, which autorotate away flat; the canopy is blown clear; and the
	## crew go out on the rails and come down under silk. None of it damages
	## anything — the kill was scored before any of this ran.
	world.explosion(to_global(Vector3(0, 0.3, 0.2)), 1.0)
	world.camera_shake = minf(1.0, world.camera_shake + 0.28)
	shed_blades()
	shear_tail()
	jettison_canopy()
	eject_crew()
	world.debris(to_global(Vector3(0, 0, 0)), 10, 1.5)
	world.cooling_sparks(to_global(Vector3(0, 0.2, 0.6)), 1.1)
	velocity += Vector3(randf_range(-6, 6), 4.0, randf_range(-6, 6))

func shed_blades() -> void:
	if is_instance_valid(rotor_disc):
		rotor_disc.visible = false
	if not is_instance_valid(blades):
		return
	blades.visible = false
	var hub: Transform3D = rotor.global_transform
	world.explosion(hub.origin, 0.5)
	for index in range(blade_count):
		var angle := TAU * float(index) / blade_count + rotor.rotation.y
		var out := (hub.basis * Vector3(sin(angle), 0, cos(angle))).normalized()
		var wreck = load("res://scripts/wreckage.gd").new()
		wreck.world = world
		world.effects.add_child(wreck)
		wreck.global_transform = Transform3D(hub.basis.rotated(hub.basis.y.normalized(), angle),
			hub.origin + out * blade_reach * 0.5 * scale.x)
		var piece := NavalGeometry.Builder.new()
		piece.beam(Vector3(0, 0, -blade_reach * 0.5 * scale.x), Vector2(0.34, 0.09) * scale.x,
			Vector3(0, -0.1, blade_reach * 0.5 * scale.x), Vector2(0.3, 0.07) * scale.x,
			Color("222a2c"))
		piece.commit(wreck, NavalGeometry.steel(Color.WHITE, 0.55, 0.15, true, 0.25), "Blade")
		# Thrown off tangentially at rotor tip speed, still turning in its own
		# plane: that spin is what keeps it up.
		var tangent := out.cross(Vector3.UP).normalized()
		wreck.velocity = out * randf_range(16, 26) + tangent * randf_range(-9, 9) + velocity * 0.4
		wreck.velocity.y += randf_range(2.0, 7.0)
		wreck.spin = Vector3(randf_range(-0.4, 0.4), randf_range(7.0, 11.0), randf_range(-0.4, 0.4))
		wreck.lift = 0.78
		wreck.smoking = false

func shear_tail() -> void:
	## With the head gone there is nothing left to balance the tail rotor, and
	## the boom goes at its weakest point — just aft of the cabin. It takes the
	## fin, the stabilisers and the tail rotor with it, still turning.
	if not is_instance_valid(boom) or not boom.visible:
		return
	var joint: Vector3 = boom.global_position
	var wreck = load("res://scripts/wreckage.gd").new()
	wreck.world = world
	world.effects.add_child(wreck)
	wreck.global_transform = boom.global_transform
	var copy: Node3D = boom.duplicate()
	wreck.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	boom.visible = false
	world.explosion(joint, 0.55)
	world.cooling_sparks(joint, 0.9)
	# Thrown sideways and tumbling about its long axis: the tail rotor is still
	# driving it when the drive shaft parts.
	var sideways := basis.x * randf_range(-1.0, 1.0)
	wreck.velocity = (basis.z * randf_range(6, 11) + sideways * randf_range(6, 12)
		+ basis.y * randf_range(1, 5) + velocity * 0.7)
	wreck.spin = Vector3(randf_range(-1.4, 1.4), randf_range(-3.4, 3.4), randf_range(-4.5, 4.5))
	wreck.lift = 0.2

func jettison_canopy() -> void:
	## Glazing goes before the seats do, or the crew would go through it.
	if not is_instance_valid(canopy) or not canopy.visible:
		return
	var wreck = load("res://scripts/wreckage.gd").new()
	wreck.world = world
	world.effects.add_child(wreck)
	wreck.global_transform = canopy.global_transform
	var copy: Node3D = canopy.duplicate()
	wreck.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	canopy.visible = false
	# Up and back over the rotor mast, clear of the seats.
	wreck.velocity = (basis.y * randf_range(11, 15) + basis.z * randf_range(8, 13)
		+ velocity * 0.6)
	wreck.spin = Vector3(randf_range(2.5, 4.5), randf_range(-2, 2), randf_range(-2, 2))
	wreck.lift = 0.45
	wreck.smoking = false
	world.cooling_sparks(canopy.global_position, 0.6)

func eject_crew() -> void:
	## Both stations fire, staggered, so they read as a sequence and the seats
	## do not climb out on top of each other.
	for index in range(seats.size()):
		var pad: Node3D = load("res://scripts/ejection.gd").new()
		pad.world = world
		world.effects.add_child(pad)
		pad.global_position = to_global(seats[index])
		pad.rotation.y = rotation.y
		# Rails are raked back, so the seat leaves up and slightly aft.
		pad.velocity = (basis.y * randf_range(11, 14) + basis.z * randf_range(3, 6)
			+ velocity * 0.5 + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
		pad.spin = Vector3(randf_range(-1.2, 1.2), randf_range(-2, 2), randf_range(-1.2, 1.2))
		# Stagger by delaying the second seat one boost-length worth of arc.
		pad.age = -0.22 * index
		world.smoke_puff(pad.global_position, 0.9, 0.9, Vector3.UP * 4.0,
			Color(0.95, 0.95, 0.92, 0.8), 1.4)

func choose_target() -> Node3D:
	var best: Node3D
	var best_score := -INF
	for candidate in world.boats + get_tree().get_nodes_in_group("aircraft"):
		if candidate.team == team:
			continue
		if not candidate.is_combat_capable() and not (candidate is PatrolBoat and candidate.can_engage_air()):
			continue
		var air := candidate is CombatHelicopter
		if air and air_missiles == 0 and cannon_rounds == 0:
			continue
		if not air and rockets == 0:
			continue
		var distance: float = position.distance_to(candidate.position)
		var score := 1200.0 - distance
		if air:
			score += 220.0
			if candidate.target == self:
				score += 250.0
		elif candidate.can_engage_air():
			score += 160.0
		if candidate == target:
			score += 130.0
		if score > best_score:
			best_score = score
			best = candidate
	return best

func order_move(point: Vector3) -> void:
	destination = point
	has_move_order = true
	explicit_target = false

func order_attack(unit: Node3D) -> void:
	if unit.team == team or unit.sunk:
		return
	target = unit
	explicit_target = true
	has_move_order = false

func fire_guided(unit: Node3D) -> bool:
	if not is_instance_valid(unit) or unit.team == team or unit.sunk or destroyed:
		return false
	if manual and not world.cleared("missile"):
		world.refuse("missile", "Air-to-air is not cleared")
		return false
	var distance := position.distance_to(unit.position)
	if unit is CombatHelicopter and air_missiles > 0 and air_cooldown <= 0 and distance < 900:
		var origin := to_global(Vector3(0, -1, -5))
		air_stores[2 - air_missiles].visible = false
		air_missiles -= 1
		air_cooldown = 7
		var missile = load("res://scripts/sam.gd").new()
		missile.world = world
		world.projectiles.add_child(missile)
		missile.launch(origin, unit, self)
		missile.velocity = -basis.z.normalized() * 65
		return true
	return false

func process_manual(delta: float) -> void:
	## Arcade flight: heading comes from yaw alone, so pitch and roll are free
	## to lean into the turn without steering the aircraft.
	var turn := Input.get_axis("starboard", "port")
	rotation.y += turn * delta * 1.7
	var forward := Input.get_axis("astern", "ahead")
	var top: float = 52.0 if variant == "Apache" else 46.0
	var heading := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	velocity = velocity.move_toward(heading * forward * top, delta * 44.0)
	position += velocity * delta
	position.x = clampf(position.x, -1800, 1800)
	position.z = clampf(position.z, -1800, 1800)
	var climb := Input.get_axis("descend", "climb")
	flight_height = clampf(flight_height + climb * delta * 30.0, 14.0, 170.0)
	position.y = lerpf(position.y, flight_height, minf(1, delta * 3.0))
	rotation.z = lerp_angle(rotation.z, -turn * 0.38, minf(1, delta * 4.0))
	rotation.x = lerp_angle(rotation.x, forward * 0.13, minf(1, delta * 3.0))
	if Input.is_action_pressed("fire") and not world.pointer_over_ui():
		fire_player_weapon()
	for sam in get_tree().get_nodes_in_group("sam_missiles"):
		if sam.target == self and sam.position.distance_to(position) < 350:
			deploy_flares()
			break

func fire_player_weapon() -> void:
	var contact: Node3D = world.locked_target
	var muzzle := to_global(Vector3(0, -1.4, -6.5))
	# Aircraft in the reticle get the cannon; anything else gets rockets, and
	# the cannon strafes once the pods are empty.
	if contact is CombatHelicopter and is_instance_valid(contact) and not contact.destroyed:
		var reach := position.distance_to(contact.position)
		if reach < 480.0 and cannon_rounds > 0 and cannon_cooldown <= 0:
			cannon_rounds -= 1
			cannon_cooldown = 0.07
			world.fire_ciws(muzzle, contact.position + contact.velocity * reach / 650.0, colliders, true, true)
			return
	var aim: Vector3 = world.mouse_on_sea(2.0)
	if rockets > 0 and not world.cleared("rocket"):
		world.refuse("rocket", "Rockets are not cleared")
	elif rockets > 0 and rocket_cooldown <= 0:
		if position.distance_to(aim) < 640.0:
			rockets -= 1
			rocket_cooldown = 0.32
			world.fire_rocket(mounts[rockets % 4].global_position, aim, colliders, true)
	elif cannon_rounds > 0 and cannon_cooldown <= 0:
		if position.distance_to(aim) < 420.0:
			cannon_rounds -= 1
			cannon_cooldown = 0.07
			world.fire_ciws(muzzle, aim, colliders, false, true)

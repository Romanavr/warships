extends TestHarness
var failures: int = 0


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		push_error("FAIL: " + message)
		failures += 1

func run() -> void:
	seed(72)
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for initial_aircraft in get_nodes_in_group("aircraft"):
		initial_aircraft.free()
	world.set_physics_process(false)
	var player: PatrolBoat = world.boats[0]
	var ally: PatrolBoat = world.boats[1]
	var enemy: PatrolBoat = world.boats[2]
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
	player.position = Vector3(0, 0, 65)
	enemy.position = Vector3(0, 0, -65)
	await physics_frame
	check(PatrolBoat.RELOAD >= 3, "Gun cadence is slower than the original rapid fire")
	check(not player.launch_missile(ally), "Friendly targets cannot be missile-locked")
	check(player.launch_missile(enemy), "Valid target launches a missile")
	check(player.missile_ammo == 3, "A launch consumes exactly one missile")
	check(not player.cell_loaded[0] and is_instance_valid(player.cell_lids[0]), "Fired cell opens while its physical launcher remains")
	check(not player.launch_missile(enemy), "Reload prevents an immediate second launch")
	var missile = world.projectiles.get_child(0)
	var peak := 0.0
	for frame in range(720):
		await physics_frame
		if not is_instance_valid(missile):
			break
		peak = maxf(peak, missile.position.y)
	check(peak > 8, "Missile climbs during launch before its terminal approach")
	check(enemy.hull_fraction() < 1, "Guidance and swept collision deliver damage to the target")
	check(not enemy.sunk, "One missile does not erase a healthy corvette")
	enemy.begin_sinking(true)
	check(world.destruction_count == 1, "Destruction event fires exactly once")
	enemy.begin_sinking(true)
	enemy.take_blast(enemy.position, 200)
	check(world.destruction_count == 1, "Repeated hits cannot duplicate a destruction event")
	check(world.effects.get_child_count() > 20, "Missile leaves a persistent trail and layered blast effects")
	# A lost target must not leave a permanent missile or phantom hit.
	player.missile_cooldown = 0
	var lost: PatrolBoat = world.spawn_boat(1, Vector3(40, 0, -100), "LOST TARGET")
	lost.set_physics_process(false)
	player.launch_missile(lost)
	lost.sunk = true
	for frame in range(1500):
		await physics_frame
	check(world.projectiles.get_child_count() == 0, "Lost-target missiles expire cleanly")
	check(lost.hull_fraction() == 1, "Lost target receives no ghost damage")
	# Waves freeze when the simulation clock freezes, and boats sample that surface.
	var height: float = world.ocean.height_at(player.position)
	world.ocean.set_clock(2.0)
	check(absf(world.ocean.height_at(player.position) - height) > 0.01, "Wave surface changes with simulation time")
	for frame in range(240):
		player.update_buoyancy(1.0 / 60)
	check(absf(player.position.y - world.ocean.height_at(player.position)) < 0.08, "Boat buoyancy follows rendered wave height")
	var frozen: float = world.ocean.height_at(player.position)
	await process_frame
	check(world.ocean.height_at(player.position) == frozen, "Wave clock remains deterministic without a simulation tick")
	print("MISSILE RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)

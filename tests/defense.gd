extends TestHarness
func run() -> void:
	seed(22)
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for initial_aircraft in get_nodes_in_group("aircraft"):
		initial_aircraft.free()
	world.set_physics_process(false)
	var defender: PatrolBoat = world.boats[0]
	var attacker: PatrolBoat = world.boats[2]
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
	world.boats[1].position = Vector3(-900, 0, 800)
	world.boats[3].position = Vector3(900, 0, -800)
	defender.position = Vector3(0, 0, 200)
	attacker.position = Vector3(0, 0, -400)
	defender.rotation.y = PI
	attacker.rotation.y = PI
	attacker.missile_cooldown = 0
	await physics_frame
	attacker.launch_missile(defender)
	for frame in range(1200):
		defender.process_ciws(1.0 / 60)
		await physics_frame
		if world.missiles_intercepted > 0 or defender.hull_fraction() < 1:
			break
	var passed: bool = world.missiles_intercepted > 0 and defender.ciws_ammo < 120 and defender.hull_fraction() == 1
	print("DEFENSE: intercepted=%d ammo=%d hull=%.2f enemy_launches=%d" % [
		world.missiles_intercepted, defender.ciws_ammo, defender.hull_fraction(), world.enemy_missiles_launched])
	quit(0 if passed else 1)

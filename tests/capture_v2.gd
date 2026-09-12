extends TestHarness
## Capture a real missile impact, then explicitly stage sinking to inspect wreck effects.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

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
	world.direct_control = false
	world.camera_focus = Vector3(0, 0, -40)
	world.camera_distance = 280
	world.camera_pitch = 22
	world.camera_yaw = -0.65
	var player: PatrolBoat = world.boats[0]
	var enemy: PatrolBoat = world.boats[2]
	player.position = Vector3(0, 0, 40)
	enemy.position = Vector3(12, 0, -70)
	world.boats[1].position = Vector3(-90, 0, 75)
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
	await physics_frame
	player.launch_missile(enemy)
	for frame in range(35):
		for boat: PatrolBoat in world.boats:
			boat.update_buoyancy(1.0 / 60)
		await physics_frame
	await save_frame("missile-flight.png")
	var hit := false
	for frame in range(600):
		await physics_frame
		if enemy.hull_fraction() < 1:
			hit = true
			break
	if not hit:
		push_error("Visual check: missile did not hit")
		quit(1)
		return
	enemy.set_physics_process(true)
	await create_timer(0.12).timeout
	await save_frame("missile-impact.png")
	enemy.begin_sinking(true)
	await create_timer(1.0).timeout
	await save_frame("missile-wreck.png")
	# Let her go down and spread the slick.
	world.camera_distance = 190
	world.camera_pitch = 34
	await create_timer(14.0).timeout
	await save_frame("missile-oil.png")
	print("VISUAL: flight, real impact, and staged wreck captured")
	quit()

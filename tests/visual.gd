extends TestHarness
## A reproducible damaged-boat render for manual visual inspection.

func run() -> void:
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for initial_aircraft in get_nodes_in_group("aircraft"):
		initial_aircraft.free()
	world.direct_control = false
	world.camera_focus = Vector3(0, 0, 0)
	world.camera_distance = 90
	world.camera_pitch = 45
	var player: PatrolBoat = world.boats[0]
	player.position = Vector3(-12, 0, 3)
	player.rotation.y = 0.5
	var enemy: PatrolBoat = world.boats[2]
	enemy.position = Vector3(20, 0, -10)
	enemy.rotation.y = -0.7
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
	player.take_hit("stern", 100, player.position)
	player.flooding = 0.35
	enemy.take_hit("bow", 100, enemy.position)
	enemy.take_hit("mid", 45, enemy.position)
	for frame in range(90):
		if frame % 12 == 0:
			world.smoke(player.to_global(Vector3(0, 2, 6)), 0.8)
			world.smoke(enemy.to_global(Vector3(0, 2, -6)), 0.9)
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/damage-preview.png")
	quit()

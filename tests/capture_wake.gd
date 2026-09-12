extends TestHarness
## Ships under way, to check wakes and the fleet at tactical range.

func run() -> void:
	seed(3)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	var player: PatrolBoat = world.boats[0]
	var tern: PatrolBoat = world.boats[1]
	player.position = Vector3(-40, 0, 260)
	tern.position = Vector3(60, 0, 300)
	world.boats[2].position = Vector3(30, 0, -220)
	world.boats[3].position = Vector3(210, 0, -300)
	world.select_boat(player)
	world.camera_focus = Vector3(0, 0, 60)
	world.camera_distance = 300
	world.camera_pitch = 34
	world.camera_yaw = -0.15
	await create_timer(14.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/fleet-underway.png")
	print("WAKE CAPTURE OK")
	quit()

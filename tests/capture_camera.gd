extends TestHarness
## Direct-control camera: the view should lead ahead of the ship at speed.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(5)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for aircraft in get_nodes_in_group("aircraft"):
		aircraft.queue_free()
	var player: PatrolBoat = world.boats[0]
	world.boats[1].position = Vector3(-120, 0, 420)
	world.boats[2].position = Vector3(90, 0, -560)
	world.boats[3].position = Vector3(320, 0, -680)
	player.position = Vector3(0, 0, 420)
	player.rotation.y = PI
	world.select_boat(player)
	world.direct_control = true
	world.camera_distance = 130
	world.camera_pitch = 26
	world.camera_yaw = PI
	# Centre the pointer so only the travel lead is in play.
	Input.warp_mouse(root.get_visible_rect().size * 0.5)

	# Stationary reference.
	player.throttle = 0.0
	await create_timer(1.5).timeout
	Input.warp_mouse(root.get_visible_rect().size * 0.5)
	await save_frame("camera-stopped.png")

	# Under way: the ship should sit back in frame with sea opening ahead.
	for tick in range(600):
		player.throttle = 1.0
		player.speed = move_toward(player.speed, player.loadout.speed, 0.2)
		Input.warp_mouse(root.get_visible_rect().size * 0.5)
		await physics_frame
	await save_frame("camera-underway.png")
	print("CAMERA CAPTURE OK lead=", world.camera_lead.length(), " speed=", player.speed)
	quit()

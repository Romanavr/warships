extends TestHarness
## Clean elevation and quarter views of one hull, for art review.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(4)
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for aircraft in get_nodes_in_group("aircraft"):
		aircraft.queue_free()
	world.hud.visible = false
	var ship: PatrolBoat = world.boats[0]
	var small: PatrolBoat = world.boats[1]
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
		boat.selection.visible = false
		boat.position = Vector3(0, -3000, 0)
	ship.position = Vector3.ZERO
	ship.rotation.y = 0.0
	small.position = Vector3(0, 0, 70)
	small.rotation.y = 0.0
	await physics_frame
	ship.update_buoyancy(1.0)
	world.camera_distance = 72
	world.camera_pitch = 6
	world.camera_yaw = 1.5708
	world.camera_focus = Vector3(0, 4, 0)
	await create_timer(0.7).timeout
	await save_frame("model-side.png")
	world.camera_pitch = 26
	world.camera_yaw = 2.5
	world.camera_distance = 66
	await create_timer(0.4).timeout
	await save_frame("model-quarter.png")
	world.camera_pitch = 20
	world.camera_yaw = -0.55
	world.camera_distance = 58
	world.camera_focus = Vector3(0, 4, -8)
	await create_timer(0.4).timeout
	await save_frame("model-bow.png")
	ship.position = Vector3(0, -3000, 0)
	small.position = Vector3.ZERO
	small.update_buoyancy(1.0)
	world.camera_focus = Vector3(0, 2, 0)
	world.camera_distance = 40
	world.camera_pitch = 15
	world.camera_yaw = 2.3
	await create_timer(0.4).timeout
	await save_frame("model-tern.png")
	print("MODEL CAPTURE OK")
	quit()

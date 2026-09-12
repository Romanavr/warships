extends TestHarness
## Close views of both helicopter variants.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(9)
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	world.hud.visible = false
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
		boat.selection.visible = false
		boat.position = Vector3(0, -3000, 0)
	var aircraft: Array = get_nodes_in_group("aircraft")
	for index in range(aircraft.size()):
		var craft = aircraft[index]
		craft.set_physics_process(false)
		craft.selection.visible = false
		craft.position = Vector3(index * 26 - 13, 34, 0)
		craft.set_process(false)
		craft.rotation = Vector3(0.05, 0.5, -0.12)
	world.direct_control = true
	world.selected = aircraft[0]
	aircraft[0].manual = false
	world.camera_focus = Vector3(0, 34, 0)
	world.camera_distance = 44
	world.camera_pitch = 12
	world.camera_yaw = 2.4
	await create_timer(1.0).timeout
	await save_frame("air-preview.png")
	world.camera_focus = Vector3(13, 34, 0)
	world.selected = aircraft[1] if aircraft.size() > 1 else aircraft[0]
	world.camera_distance = 22
	world.camera_pitch = 6
	world.camera_yaw = 1.1
	await create_timer(0.4).timeout
	await save_frame("air-closeup.png")
	print("AIR CAPTURE OK")
	quit()

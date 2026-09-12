extends TestHarness
## A gunship coming apart: blades away, canopy gone, crew under silk.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(11)
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
		aircraft[index].position = Vector3(0, -3000, 0)
		aircraft[index].set_physics_process(false)
	var victim = aircraft[0]
	victim.position = Vector3(0, 78, 0)
	victim.selection.visible = false
	victim.rotation = Vector3(0.02, 0.4, -0.1)
	victim.velocity = Vector3(14, 0, 6)
	victim.set_physics_process(true)
	# Drive the camera by hand: the follow logic lets go of a unit the moment it
	# is destroyed, which is exactly the stretch this capture is about.
	world.set_process(false)
	await create_timer(0.6).timeout
	victim.take_damage(9999.0)
	for shot: Array in [[0.3, "breakup-1.png"], [0.8, "breakup-2.png"], [1.6, "breakup-3.png"], [2.8, "breakup-4.png"]]:
		await create_timer(float(shot[0])).timeout
		aim(world, Vector3(6, 76, 4), 62.0)
		await save_frame(String(shot[1]))
	await create_timer(2.0).timeout
	aim(world, Vector3(10, 78, 6), 66.0)
	await save_frame("breakup-5.png")
	await create_timer(3.0).timeout
	aim(world, Vector3(14, 62, 8), 72.0)
	await save_frame("breakup-6.png")
	quit()

func aim(world, focus: Vector3, distance: float) -> void:
	world.camera_focus = focus
	world.ocean.position = Vector3(snappedf(focus.x, 100), 0, snappedf(focus.z, 100))
	world.camera.position = focus + Vector3(sin(2.2) * 0.94, 0.28, cos(2.2) * 0.94) * distance
	world.camera.look_at(focus)

extends TestHarness
## The instrument panel with the gunship under the player's hands.
func run() -> void:
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for unit in world.all_units():
		unit.set_physics_process(false)
	var heli: CombatHelicopter = get_nodes_in_group("aircraft")[0]
	world.take_control(heli)
	world.camera_distance = 100
	world.camera_focus = heli.position
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/helicopter-controls.png")
	world.hud.details = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/helicopter-systems.png")
	print("CONTROLS CAPTURE OK")
	quit()

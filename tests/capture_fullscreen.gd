extends TestHarness
## A frame at the real display resolution, downsampled for review. This is what
## the game actually looks like on the machine it is played on.

func run() -> void:
	seed(17)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	var ship: PatrolBoat = world.player_ship
	ship.manual = false
	world.wave_clock = 0.05
	await create_timer(1.0).timeout
	for boat: PatrolBoat in world.boats:
		if boat.team == 1:
			boat.position = ship.position + Vector3(randf_range(-90, 90), 0, -260)
	for id: String in ["mid", "engine"]:
		ship.systems[id].fire = 0.9
	ship.update_fires()
	world.camera_distance = 150
	world.camera_pitch = 26
	await create_timer(6.0).timeout
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var size := shot.get_size()
	shot.resize(1600, int(1600.0 * float(size.y) / float(size.x)), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	shot.save_png("res://artifacts/fullscreen-retina.png")
	print("FULLSCREEN CAPTURE window=%s  scale3d=%.3f  (3D renders at the window's pixel count)" % [
		DisplayServer.window_get_size(), root.scaling_3d_scale])
	quit()

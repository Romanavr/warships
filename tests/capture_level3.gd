extends TestHarness
## Walks level three to the scripted shoot-down and photographs it, so the kill
## and the camera can be judged rather than guessed at.

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
	world.begin_level(2)
	# Let the opening beats run and the gunships arrive.
	var guard := 0
	while guard < 60 * 60 and not (world.selected is CombatHelicopter):
		guard += 1
		world.wave_clock = 0.0
		await physics_frame
	print("cockpit at step %d" % world.campaign.step)
	# Win the air fight so the script moves to the shoot-down.
	for craft in get_nodes_in_group("aircraft"):
		if craft.team == 1:
			craft.take_damage(99999.0)
	guard = 0
	while guard < 60 * 90 and world.cutaway.is_empty():
		guard += 1
		world.wave_clock = 0.0
		await physics_frame
	print("cutaway open, tracking %d, hold=%s" % [world.cutaway.size(), world.cutaway_hold])
	var shots := 0
	var frames := 0
	while frames < 60 * 26 and shots < 9:
		frames += 1
		world.wave_clock = 0.0
		await physics_frame
		if frames % 90 == 0:
			shots += 1
			var air: Node3D = world.player_air
			var state := "gone"
			if is_instance_valid(air):
				state = "destroyed" if air.destroyed else "flying"
			print("  t=%4.1fs  air=%-10s cutaway=%d  dist=%.0f" % [
				frames / 60.0, state, world.cutaway.size(),
				world.camera.position.distance_to(world.camera_focus)])
			await save_frame("level3-%d.png" % shots)
	print("LEVEL3 CAPTURE OK")
	quit()

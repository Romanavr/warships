extends TestHarness
## Frame-time probe with the sector deliberately overloaded: several hulls
## burning, smoke everywhere, ordnance in the air.

func run() -> void:
	seed(3)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	var ship: PatrolBoat = world.player_ship
	ship.manual = false
	for boat: PatrolBoat in world.boats:
		boat.position = ship.position + Vector3(randf_range(-160, 160), 0, randf_range(-160, 160))
		for id: String in boat.systems:
			boat.systems[id].fire = 0.9
			boat.systems[id].health = boat.systems[id].maximum * 0.35
	world.camera_distance = 170
	world.camera_pitch = 28
	# Sink two hulls as well, so the oil shader is in the measurement.
	for boat: PatrolBoat in world.boats:
		if boat != ship and boat.team == 1:
			boat.begin_sinking(true)
	# Let it settle, then sample.
	for warm in range(600):
		await process_frame
	var frames := 0
	var worst := 0.0
	var total := 0.0
	var started := Time.get_ticks_usec()
	for tick in range(240):
		var mark := Time.get_ticks_usec()
		await process_frame
		var span := float(Time.get_ticks_usec() - mark) / 1000.0
		total += span
		worst = maxf(worst, span)
		frames += 1
	var effects: int = world.effects.get_child_count()
	print("PERF frames=%d avg=%.2f ms worst=%.2f ms fps=%.0f effect_nodes=%d wall=%.1f s" % [
		frames, total / frames, worst, 1000.0 / (total / frames), effects,
		float(Time.get_ticks_usec() - started) / 1000000.0])
	quit()

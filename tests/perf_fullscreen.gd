extends TestHarness
## Frame-time probe at the real display resolution, fullscreen, with the sector
## deliberately overloaded. This is the number that matters on a Retina panel:
## a 1280x800 window is under a seventh of the pixels.

func run() -> void:
	seed(3)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
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
	for boat: PatrolBoat in world.boats:
		if boat != ship and boat.team == 1:
			boat.begin_sinking(true)
	world.camera_distance = 150
	world.camera_pitch = 28
	for warm in range(420):
		await process_frame
	# Every frame time is kept, not just the largest. A single worst-of-300 is
	# dominated by whatever the operating system was doing during one of them —
	# it cannot tell a game that stutters from a game that had one hiccup, and
	# those want completely different answers.
	var spans: Array[float] = []
	var total := 0.0
	for tick in range(300):
		var mark := Time.get_ticks_usec()
		await process_frame
		var span := float(Time.get_ticks_usec() - mark) / 1000.0
		total += span
		spans.append(span)
	var frames: int = spans.size()
	var order := spans.duplicate()
	order.sort()
	var at := func(share: float) -> float:
		return order[clampi(int(float(frames) * share), 0, frames - 1)]
	var worst: float = order[frames - 1]
	var worst_at := spans.find(worst)
	# How many frames actually missed the 60 fps budget is the number that says
	# whether the player would feel anything.
	var over := 0
	for span: float in spans:
		if span > 16.7:
			over += 1
	var view: Vector2i = root.get_texture().get_size()
	print("  window=%s  screen=%s  screen_scale=%.2f  content_scale=%.2f  stretch=%d  hidpi=%s" % [
		DisplayServer.window_get_size(), DisplayServer.screen_get_size(),
		DisplayServer.screen_get_scale(), root.content_scale_factor,
		root.content_scale_mode, ProjectSettings.get_setting("display/window/dpi/allow_hidpi")])
	var pixels := Vector2(view) * root.scaling_3d_scale
	print("FULLSCREEN root=%dx%d  3D=%dx%d (%.1f Mpx)  scale3d=%.2f  avg=%.2f ms  fps=%.0f" % [
		view.x, view.y, int(pixels.x), int(pixels.y),
		pixels.x * pixels.y / 1000000.0, root.scaling_3d_scale,
		total / frames, 1000.0 / (total / frames)])
	print("FRAMES p50=%.2f  p95=%.2f  p99=%.2f  worst=%.2f ms (frame %d of %d)  over 16.7 ms: %d" % [
		at.call(0.50), at.call(0.95), at.call(0.99), worst, worst_at, frames, over])
	quit()

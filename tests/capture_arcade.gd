extends TestHarness
## Campaign shots: the wave banner, a gunnery exchange and the gunship view.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(17)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	var ship: PatrolBoat = world.player_ship
	ship.manual = false
	world.wave_clock = 0.05
	await create_timer(1.2).timeout
	await save_frame("arcade-wave.png")
	# Close the range and let the guns work.
	for boat: PatrolBoat in world.boats:
		if boat.team == 1:
			boat.position = ship.position + Vector3(randf_range(-120, 120), 0, -300)
	world.camera_distance = 175
	world.camera_pitch = 24
	await create_timer(9.0).timeout
	await save_frame("arcade-battle.png")
	# And the gunship's own view.
	world.swap_control()
	world.player_air.manual = false
	world.camera_distance = 95
	world.camera_pitch = 18
	await create_timer(3.0).timeout
	await save_frame("arcade-gunship.png")
	# Radar, crates and off-screen contact arrows.
	world.swap_control()
	for boat: PatrolBoat in world.boats:
		if boat.team == 1:
			boat.position = ship.position + Vector3(900, 0, 260)
	world.camera_distance = 130
	world.camera_pitch = 30
	await create_timer(1.2).timeout
	await save_frame("arcade-radar.png")
	# Burning ship with the damage-control readout live.
	for id: String in ["mid", "engine", "gun"]:
		ship.systems[id].fire = 0.95
		ship.systems[id].health = ship.systems[id].maximum * 0.45
	ship.update_fires()
	ship.cell_loaded[0] = false
	ship.sam_ammo = 2
	world.camera_distance = 95
	world.camera_pitch = 20
	world.camera_yaw = 1.2
	# Knock a mount out so the callout and damage number are both in frame.
	world.locked_target = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and not boat.sunk:
			boat.position = ship.position + Vector3(70, 0, -110)
			world.locked_target = boat
			break
	await create_timer(3.2).timeout
	if is_instance_valid(world.locked_target):
		world.locked_target.take_hit("ciws", 9999.0, world.locked_target.visuals.to_global(Vector3(0, 7, 13)), true)
		world.locked_target.take_hit("mid", 74.0, world.locked_target.visuals.to_global(Vector3(2, 4, 0)), true)
	# And one of ours, so both callout styles are in the same frame.
	ship.damage_system("radar", 9999.0)
	ship.flooding = 0.4
	world.hud.raise_vampire()
	await create_timer(0.35).timeout
	await save_frame("arcade-fire.png")
	print("ARCADE CAPTURE OK wave=", world.wave_index + 1, " hostiles=", world.hostiles_remaining())
	quit()

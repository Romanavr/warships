extends TestHarness
## Effect review: gunfire and tracers, a burning ship, and a fresh detonation.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(21)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	world.hud.visible = false
	for aircraft in get_nodes_in_group("aircraft"):
		aircraft.queue_free()
	var player: PatrolBoat = world.boats[0]
	var enemy: PatrolBoat = world.boats[2]
	world.boats[1].position = Vector3(0, -3000, 0)
	world.boats[3].position = Vector3(0, -3000, 0)
	player.position = Vector3(-70, 0, 190)
	player.rotation.y = -0.35
	enemy.position = Vector3(60, 0, -120)
	enemy.rotation.y = PI
	for boat: PatrolBoat in world.boats:
		boat.selection.visible = false

	# --- gunfire: tracers in flight and a muzzle flash ---
	world.camera_focus = Vector3(-40, 0, 120)
	world.camera_distance = 150
	world.camera_pitch = 16
	world.camera_yaw = 0.6
	await create_timer(2.5).timeout
	for shot in range(3):
		player.cooldown = 0.0
		player.aft_cooldown = 0.0
		player.shoot(enemy.visuals.to_global(Vector3(0, 3, 0)))
		await create_timer(0.06).timeout
	await create_timer(0.09).timeout
	await save_frame("effects-gunfire.png")

	# --- CIWS stream ---
	world.camera_focus = player.position
	world.camera_distance = 95
	world.camera_pitch = 12
	world.camera_yaw = 1.9
	for shot in range(14):
		var muzzle: Vector3 = player.ciws_turret.to_global(Vector3(0, 0.8, -3.3))
		world.fire_ciws(muzzle, muzzle + Vector3(-70, 26, -120), player.colliders, true)
		await create_timer(0.03).timeout
	await save_frame("effects-ciws.png")

	# --- burning ship ---
	for id: String in ["mid", "bridge", "engine", "stern"]:
		enemy.systems[id].fire = 0.95
		enemy.systems[id].health = enemy.systems[id].maximum * 0.3
	enemy.update_fires()
	world.camera_focus = enemy.position
	world.camera_distance = 120
	world.camera_pitch = 18
	world.camera_yaw = 0.2
	await create_timer(4.0).timeout
	await save_frame("effects-fire.png")

	# --- detonation ---
	world.explosion(enemy.visuals.to_global(Vector3(0, 4, -6)), 1.6)
	await create_timer(0.35).timeout
	await save_frame("effects-blast.png")
	await create_timer(1.6).timeout
	await save_frame("effects-blast-smoke.png")
	# --- shell striking a target: impact, marker and damage number ---
	world.hud.visible = true
	enemy.repair()
	enemy.position = player.position + Vector3(60, 0, -95)
	player.manual = true
	world.selected = player
	world.locked_target = enemy
	world.camera_focus = (player.position + enemy.position) * 0.5
	world.camera_distance = 110
	world.camera_pitch = 26
	world.camera_yaw = 0.4
	await create_timer(0.9).timeout
	Input.warp_mouse(world.camera.unproject_position(enemy.visuals.to_global(Vector3(0, 4, 0))))
	await physics_frame
	enemy.take_hit("bridge", 92.0, enemy.visuals.to_global(Vector3(0, 6, -6)), true)
	enemy.take_hit("mid", 64.0, enemy.visuals.to_global(Vector3(3, 3, 4)), true)
	await create_timer(0.1).timeout
	await save_frame("effects-hit.png")
	print("EFFECTS CAPTURE OK")
	quit()

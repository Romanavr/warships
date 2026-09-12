extends TestHarness
## Running lights and the two authored airframes.
##
## The lights are built from the hull's module boxes rather than typed in, so
## the assertions here are about position: a sidelight on the wrong side of the
## centreline is a mistake nobody notices from a screenshot at 150 m.
var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func save_frame(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(31)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	await physics_frame
	var ship: PatrolBoat = world.player_ship
	ship.manual = false

	# --- lights are fitted, and on the right sides ---------------------------- #
	for boat: PatrolBoat in world.boats:
		check(is_instance_valid(boat.beacon), "%s carries an anti-collision beacon" % boat.callsign)
		check(boat.visuals.has_meta("navigation_lights"),
			"%s carries running lights" % boat.callsign)
	var lights: MeshInstance3D = ship.visuals.get_meta("navigation_lights")
	# Red to port is negative x on this hull, green to starboard positive. Read
	# it back off the committed mesh so the test fails if the boxes are swapped.
	var faces: PackedVector3Array = lights.mesh.get_faces()
	var colours := lights.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var points := lights.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var reddest := 0.0
	var greenest := 0.0
	for index in range(points.size()):
		var tint: Color = colours[index]
		if tint.r > 0.8 and tint.g < 0.4:
			reddest += points[index].x
		elif tint.g > 0.8 and tint.r < 0.4:
			greenest += points[index].x
	check(reddest < 0.0, "The red sidelight is to port")
	check(greenest > 0.0, "The green sidelight is to starboard")
	check(faces.size() > 0, "The lights mesh has geometry")

	# --- the beacon flashes rather than sitting on -------------------------- #
	var seen_on := false
	var seen_off := false
	for frame in range(140):
		await physics_frame
		if ship.beacon.visible:
			seen_on = true
		else:
			seen_off = true
	check(seen_on and seen_off, "The beacon flashes")
	world.camera_distance = 68
	world.camera_pitch = 10
	world.camera_yaw = 1.15
	for frame in range(20):
		await process_frame
	await save_frame("lights-ship.png")

	# And goes out with the ship.
	ship.begin_sinking(false)
	await physics_frame
	await physics_frame
	check(not ship.beacon.visible, "A sinking hull shows no beacon")
	check(not (ship.visuals.get_meta("navigation_lights") as MeshInstance3D).visible,
		"A sinking hull shows no running lights")

	# --- the airframes are on the right sides -------------------------------- #
	var ours: CombatHelicopter = null
	var theirs: CombatHelicopter = null
	for craft in world.get_tree().get_nodes_in_group("aircraft"):
		if craft.team == 0:
			ours = craft
		else:
			theirs = craft
	check(ours != null and ours.variant == "Hind", "We fly the Hind")
	check(theirs != null and theirs.variant == "Apache", "They fly the Apache")
	check(ours != null and ours.blade_count == 5, "The Hind sheds five blades, got %d"
		% (ours.blade_count if ours != null else -1))
	check(theirs != null and theirs.blade_count == 4, "The Apache sheds four blades, got %d"
		% (theirs.blade_count if theirs != null else -1))
	check(ours != null and String(ours.callsign).begins_with("SHAHEEN"),
		"Our aircraft answers to its own name")

	# Both airframes, side by side and clear of the toolbar, so the swap can be
	# checked by eye and not only by the variant string.
	world.hud.visible = false
	world.take_control(ours)
	ours.position = ship.position + Vector3(-18, 40, -150)
	ours.flight_height = ours.position.y
	ours.rotation.y = 2.6
	theirs.position = ours.position + Vector3(34, 0, 6)
	theirs.flight_height = theirs.position.y
	theirs.rotation.y = 2.6
	world.camera_distance = 40
	world.camera_pitch = 4
	world.camera_yaw = 1.0
	for frame in range(24):
		await process_frame
	await save_frame("lights-air.png")
	world.hud.visible = true

	# Blades actually leave the aircraft when it dies.
	var before: int = world.effects.get_child_count()
	theirs.take_damage(9999.0)
	await physics_frame
	check(world.effects.get_child_count() > before + 4,
		"Breaking up throws wreckage, got %d pieces" % (world.effects.get_child_count() - before))

	print("LIGHTS RESULT: %d failures" % failures)
	quit(1 if failures else 0)

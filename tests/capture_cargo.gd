extends TestHarness
## The cargo ship, and the one invariant that decides whether the training level
## can be finished at all: a shell aimed at the engine room has to reach it.
var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func save_frame(filename: String) -> void:
	## Headless has no frames to capture; the assertions above are the point of
	## this script and they run either way.
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(6)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for boat: PatrolBoat in world.boats:
		boat.position = Vector3(0, -3000, 0)
		boat.set_physics_process(false)
	for craft in get_nodes_in_group("aircraft"):
		craft.position = Vector3(0, -3000, 0)
		craft.set_physics_process(false)
	var trader: PatrolBoat = world.spawn_boat(1, Vector3(0, 0, 0), "MV MERIDIAN", false,
		load("res://ships/trader.tres"))
	trader.set_physics_process(false)
	trader.selection.visible = false
	await physics_frame
	await physics_frame

	# --- the contract PatrolBoat relies on ----------------------------------- #
	check(trader.noncombatant, "The trader is flagged as a noncombatant")
	check(trader.systems.size() == 13, "Every canonical module id is present, stubbed or real")
	check(not trader.is_combat_capable(), "She is not a threat")
	check(trader.turret == null and trader.barrel == null, "No gun mounts at all")
	check(trader.operational("engine") and trader.operational("bridge"), "Engine room and bridge are live")
	check(not trader.operational("gun"), "Stubbed modules read as destroyed")

	# --- the hittability invariant ------------------------------------------- #
	# Shells and the pointer both take the FIRST box a ray meets and read its
	# "section" meta. If the engine room sat inside the stern hull box, no shot
	# could ever land on it and the level would be unwinnable.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var wanted := {"engine": Vector3(0, 11.0, 29), "bridge": Vector3(0, 11.5, 21)}
	for id: String in wanted:
		var aim: Vector3 = trader.visuals.to_global(wanted[id])
		var hits := {}
		# Rake it the way a gun would: from several bearings, flat and slightly down.
		for bearing: float in [-0.9, -0.45, 0.0, 0.45, 0.9]:
			var offset := Vector3(sin(bearing), 0.10, cos(bearing)) * 300.0
			var query := PhysicsRayQueryParameters3D.create(aim + offset, aim, 1)
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and hit.collider.has_meta("section"):
				hits[hit.collider.get_meta("section")] = true
		check(hits.has(id), "%s is reachable by gunfire, hit %s" % [id, str(hits.keys())])

	# --- damage behaviour ----------------------------------------------------- #
	trader.damage_system("engine", 999.0)
	check(not trader.operational("engine"), "The engine room can be destroyed")
	check(not trader.sunk, "Losing the engine room does not sink her")
	trader.cease_fire()
	var before: float = trader.hull_fraction()
	trader.take_hit("mid", 400.0, trader.position)
	trader.take_blast(trader.position, 400.0)
	check(trader.hull_fraction() == before, "Under a cease-fire nothing reaches her")

	# --- and what she looks like ---------------------------------------------- #
	trader.protected = false
	trader.systems["engine"].health = trader.systems["engine"].maximum
	trader.revive_module("engine")
	world.set_process(false)
	for shot: Array in [[Vector3(96, 26, 96), "cargo-quarter.png", Vector3(0, 6, 2)],
			[Vector3(4, 14, 132), "cargo-beam.png", Vector3(0, 6, 2)],
			[Vector3(-118, 34, -42), "cargo-bow.png", Vector3(0, 6, 2)],
			[Vector3(46, 22, 62), "cargo-aft.png", Vector3(0, 11, 26)]]:
		world.camera.position = shot[0]
		world.camera.look_at(shot[2])
		world.ocean.position = Vector3.ZERO
		await save_frame(String(shot[1]))
	print("CARGO RESULT: %d failures" % failures)
	quit(1 if failures else 0)

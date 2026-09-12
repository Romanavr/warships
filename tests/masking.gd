extends TestHarness
## Islands as cover, and the partial replenishment between levels.
##
## Both are gameplay rules with no visual tell of their own, so they are the kind
## of thing that can quietly stop working and only show up as the game feeling
## slightly wrong months later.
var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func run() -> void:
	seed(5)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	await physics_frame
	var ship: PatrolBoat = world.player_ship
	ship.manual = false

	# --- an island between two hulls breaks the line ------------------------- #
	var hostile: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 1:
			hostile = boat
	check(hostile != null, "There is a hostile to be masked from")
	# Clear water first: put them either side of an empty patch.
	ship.position = Vector3(0, 0, 600)
	hostile.position = Vector3(0, 0, -600)
	await physics_frame
	check(world.line_of_sight(ship, hostile), "Across open water they can see each other")
	# Now drop a headland squarely between them.
	world.add_island(Vector3(0, 0, 0), 160.0, 70.0)
	await physics_frame
	await physics_frame
	check(not world.line_of_sight(ship, hostile), "An island between them breaks the line")
	check(not world.line_of_sight(hostile, ship), "and it breaks it both ways")

	# --- a seeker that cannot see the ship loses the track ------------------- #
	var launched: PatrolBoat = hostile
	launched.missile_cooldown = 0.0
	launched.cell_loaded = [true, true, true, true]
	check(not launched.should_launch_at(ship),
		"The AI does not spend a missile it could never guide")
	# Fire one anyway, straight at a target it cannot see, and watch it give up.
	world.fire_missile(launched.position + Vector3(0, 6, 0), ship, launched)
	await physics_frame
	var missile: Node3D = null
	for child in world.projectiles.get_children():
		if child.has_method("check_masking"):
			missile = child
	check(missile != null, "The missile is away")
	check(missile.guiding, "and it starts out guiding")
	var gave_up := false
	for frame in range(360):
		await physics_frame
		if not is_instance_valid(missile):
			break
		if not missile.guiding:
			gave_up = true
			break
	check(gave_up, "The seeker loses the track behind the island")

	# --- replenishment ------------------------------------------------------- #
	# The policy the campaign actually runs: a full repair between levels.
	check(Campaign.REPLENISH == 1.0, "The campaign replenishes to full")
	var wreck := func() -> void:
		for id: String in ship.systems:
			if ship.offline_by_design.has(id):
				continue
			ship.systems[id].health = 0.0
		ship.flooding = 0.6
	wreck.call()
	ship.repair(Campaign.REPLENISH)
	check(ship.hull_fraction() > 0.99, "A wrecked hull comes back whole, at %d%%"
		% int(round(ship.hull_fraction() * 100.0)))
	check(ship.operational("gun") and ship.operational("engine"),
		"with every mount working again")
	check(ship.flooding == 0.0, "and the flooding pumped out")

	# The mechanism underneath it, which the campaign does not currently use but
	# which any level can ask for by naming a fraction. Worth keeping honest: the
	# fraction is what is *added* to each system, not the level it is repaired
	# to, so a wreck and a scratch come back differently.
	wreck.call()
	ship.repair(0.6)
	check(absf(ship.hull_fraction() - 0.6) < 0.02,
		"A partial repair adds its share, leaving %d%%" % int(round(ship.hull_fraction() * 100.0)))
	check(ship.operational("gun"), "and never leaves a mount unusable")
	ship.systems["gun"].health = ship.systems["gun"].maximum * 0.8
	ship.repair(0.6)
	check(ship.systems["gun"].fraction() > 0.99,
		"while a lightly damaged mount comes back to full")
	print("MASKING RESULT: %d failures" % failures)
	quit(1 if failures else 0)

extends TestHarness
## Two things that are only visible over time: escorts holding station without
## running into anything, and the duel being a real one-level mode.
var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func run() -> void:
	seed(11)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	await physics_frame
	var ship: PatrolBoat = world.player_ship
	ship.manual = false
	# Empty sea. This test is about whether escorts can hold a station without
	# hitting anything; leaving the sandbox's hostiles in means an escort can
	# also just be shot, and then the test reports a collision failure for a
	# perfectly ordinary death.
	for unit in world.all_units():
		if unit.team == 1:
			if unit is PatrolBoat:
				world.boats.erase(unit)
			unit.queue_free()
	await physics_frame

	# --- station keeping ------------------------------------------------------ #
	var escorts: Array[PatrolBoat] = []
	for index in range(2):
		var mate: PatrolBoat = world.spawn_boat(0, ship.position + Vector3(260 + index * 90, 0, 320),
			"PEYKAAP / %02d" % (index + 1), true)
		mate.station_on = ship
		mate.station_offset = Campaign.STATIONS[index]
		escorts.append(mate)
	# Stations have to sit outside the separation the avoidance rule enforces,
	# or the escort is shoved off the spot it is trying to hold, forever.
	for post: Vector3 in Campaign.STATIONS:
		check(post.length() > 95.0, "A station is outside the avoidance radius, at %d m"
			% int(post.length()))
		check(post.length() < ship.loadout.ciws_range,
			"and inside the close-in gun's reach, at %d m" % int(post.length()))
	check(Campaign.STATIONS[0].distance_to(Campaign.STATIONS[1]) > 95.0,
		"The two stations are clear of each other")

	# Let them form up while the ship is under way, then watch them hold.
	ship.has_move_order = true
	ship.destination = ship.position + Vector3(-900, 0, -1400)
	var closest := 9999.0
	var furthest := 0.0
	var settled := false
	for frame in range(60 * 70):
		await physics_frame
		if ship.position.distance_to(ship.destination) < 120.0:
			ship.destination = ship.position + Vector3(randf_range(-900, 900), 0, randf_range(-900, 900))
		var formed := true
		for mate: PatrolBoat in escorts:
			if mate.position.distance_to(ship.position) > 210.0:
				formed = false
		if formed:
			settled = true
		if not settled:
			continue
		# Once formed up, nothing may touch: not the escorts and the ship, and
		# not the escorts and each other.
		for mate: PatrolBoat in escorts:
			var gap: float = mate.position.distance_to(ship.position)
			closest = minf(closest, gap)
			furthest = maxf(furthest, gap)
		closest = minf(closest, escorts[0].position.distance_to(escorts[1].position))
	check(settled, "The escorts form up on the ship")
	check(closest > 40.0, "and never come closer than a hull length, closest %d m" % int(closest))
	check(furthest < ship.loadout.ciws_range * 1.6,
		"and stay under the umbrella while she manoeuvres, furthest %d m" % int(furthest))
	for mate: PatrolBoat in escorts:
		check(not mate.sunk, "%s is still afloat" % mate.callsign)

	# --- the duel is its own mode --------------------------------------------- #
	check(Campaign.duel().size() == 1, "The duel is one level")
	var solo := Campaign.new(world, Campaign.duel())
	check(solo.count() == 1 and solo.table.size() == 1, "and the run plays that table")
	check(Campaign.new(world).count() == Campaign.levels().size(),
		"while the default is still the campaign")
	print("ESCORT RESULT: %d failures" % failures)
	quit(1 if failures else 0)

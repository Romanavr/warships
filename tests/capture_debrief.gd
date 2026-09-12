extends TestHarness
## The card that goes up between levels.
##
## The point of it is that playing a level well and merely surviving it should
## not look the same, so the assertions are about the figures being real: they
## count what the player did, they stop when the level does, and they start over
## for the next one.
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
	seed(9)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	await physics_frame
	for frame in range(3):
		await process_frame
	var hud = world.hud
	var ship: PatrolBoat = world.player_ship
	ship.manual = false
	check(not hud.debrief_showing(), "No card during a fight")

	# --- the figures are counted, not invented ------------------------------- #
	world.tally.reset(world.elapsed)
	var victim: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 1:
			victim = boat
	check(victim != null, "There is something to shoot at")
	for shot in range(10):
		world.fire_shell(ship.position + Vector3(0, 6, 0), victim.position, ship.colliders, true)
	check(world.tally.shells == 10, "Rounds fired are counted, got %d" % world.tally.shells)
	# Two hits out of ten is 20%, which the card should call wild rather than good.
	for hit in range(2):
		world.tally.landed += 1
	check(world.tally.landed == 2, "Rounds on target are counted, got %d" % world.tally.landed)
	# Rounds on target has to be the same population as rounds fired. Every CIWS
	# round reports a hit too, and counting those made accuracy a ratio between
	# two different things — it could pass 100%.
	world.report_hit(victim.position, 40.0, false, true)
	check(world.tally.landed == 2, "A CIWS strike is not a round on target, got %d"
		% world.tally.landed)
	check(absf(world.tally.accuracy() - 0.2) < 0.001, "Accuracy is hits over rounds")
	check(world.tally.rating() == "SHOOTING WILD", "and it is judged, got " + world.tally.rating())
	# Only theirs count: knocking a mount off our own hull is not an achievement.
	world.report_module_lost(victim.position, "Forward gun", false)
	world.report_module_lost(ship.position, "Search radar", true)
	check(world.tally.modules == 1, "Only their modules count, got %d" % world.tally.modules)
	world.report_player_damage(55.0)
	check(absf(world.tally.taken - 55.0) < 0.01, "Damage taken is counted")
	victim.begin_sinking(false)
	check(world.tally.sunk == 1, "A hostile on the bottom is counted, got %d" % world.tally.sunk)
	# Sinking is counted once, at the one call every route to the bottom ends at.
	victim.begin_sinking(false)
	check(world.tally.sunk == 1, "and counted only once, got %d" % world.tally.sunk)

	# --- the card goes up, with the level's own figures ---------------------- #
	var before: Tally = world.tally
	world.close_tally(0)
	check(world.debrief == before, "The card shows the level that just ended")
	check(world.tally != before and world.tally.shells == 0,
		"and the next level starts from zero")
	check(world.debrief.seconds >= 0.0, "The clock stopped")
	world.wave_state = "cleared"
	check(hud.debrief_showing(), "The card is up between levels")
	for frame in range(4):
		await process_frame
	await save_frame("debrief-cleared.png")

	# A lost level gets one too, in its own colour.
	world.mission_state = "failed"
	world.wave_state = "over"
	check(hud.debrief_showing(), "A lost level is debriefed as well")
	for frame in range(4):
		await process_frame
	await save_frame("debrief-lost.png")
	print("DEBRIEF RESULT: %d failures" % failures)
	quit(1 if failures else 0)

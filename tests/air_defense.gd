extends TestHarness
var failures := 0
func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
func run() -> void:
	seed(39)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for initial_aircraft in get_nodes_in_group("aircraft"):
		initial_aircraft.free()
	world.set_physics_process(false)
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
	var ship: PatrolBoat = world.boats[0]
	ship.position = Vector3(0, 0, 0)
	var aircraft: CombatHelicopter = world.spawn_helicopter(1)
	aircraft.set_physics_process(false)
	aircraft.position = Vector3(0, 60, -250)
	await physics_frame
	ship.sam_cooldown = 0
	ship.process_sam(0.016)
	check(ship.sam_ammo == 3 and world.sams_launched == 1, "SAM fires from a finite ship magazine")
	for frame in range(480):
		await physics_frame
		if aircraft.health < aircraft.maximum_health:
			break
	check(aircraft.health < aircraft.maximum_health, "Guided SAM damages a helicopter without flares")
	check(not aircraft.destroyed, "A single SAM does not instantly erase a healthy Hind")
	check(aircraft.deploy_flares(), "Helicopter deploys a flare burst")
	check(aircraft.flare_packs == 2 and not aircraft.deploy_flares(), "Flares have limited packs and cooldown")
	var sam = load("res://scripts/sam.gd").new()
	sam.world = world
	world.projectiles.add_child(sam)
	sam.launch(aircraft.position + Vector3(0, -10, 50), aircraft, ship)
	var flare = get_nodes_in_group("flares")[0]
	check(sam.consider_flare(flare, 0.0), "IR seeker can be diverted to a matching flare")
	check(sam.target == flare and sam.seeker_decoyed, "Decoy changes the actual guidance target")
	var before := aircraft.health
	for frame in range(780):
		await physics_frame
	check(aircraft.health == before, "Decoyed missile causes no ghost aircraft damage")
	# Live CIWS rounds hit an aircraft, but each hit is much weaker than a missile hit.
	aircraft.health = aircraft.maximum_health
	aircraft.position = Vector3(0, 10, -90)
	await physics_frame
	for frame in range(90):
		ship.process_ciws(1.0 / 60)
		await physics_frame
	check(aircraft.health > aircraft.maximum_health * 0.6, "A short CIWS burst cannot instantly kill a helicopter")
	check(ship.ciws_ammo < 120, "Anti-air CIWS consumes its limited ammunition")
	# Gunships carry no guided anti-ship rounds any more: they have to close to
	# rocket range, and the pods run dry.
	check(not ("missiles" in aircraft), "Helicopters carry no guided anti-ship missiles")
	aircraft.position = Vector3(120, 55, -180)
	aircraft.rocket_cooldown = 0
	aircraft.set_physics_process(true)
	var launched: int = world.missiles_launched
	var pods: int = aircraft.rockets
	for frame in range(240):
		await physics_frame
	check(aircraft.rockets < pods, "Enemy helicopter attacks ships with its finite rocket pods")
	check(world.missiles_launched == launched, "No guided rounds are launched from the air")
	print("AIR RESULT: %d failures" % failures)
	quit(1 if failures else 0)

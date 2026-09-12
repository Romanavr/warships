extends TestHarness
## The readouts the player actually reads: the designated-target panel, the
## minimap, the compact condition strip and the target bracket out in the world.
##
## Half of this is a capture and half is a regression test, because the failures
## that matter here are geometric. Two panels overlapping, or a panel reaching
## into the middle of the screen where the pointer lives, is not something the
## other suites can see and not something a play session reliably notices either.
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
	seed(23)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	# layout() runs from _process, so the rects are all zero until a frame has
	# actually been drawn. Reading them any earlier makes every geometric
	# assertion below pass against nothing.
	await physics_frame
	for frame in range(3):
		await process_frame
	var hud = world.hud
	var ship: PatrolBoat = world.player_ship
	ship.manual = false

	# --- layout ------------------------------------------------------------- #
	var named := {
		"mission": hud.mission_rect, "status": hud.status_rect, "wing": hud.wing_rect,
		"weapons": hud.weapon_rect, "minimap": hud.minimap_rect,
		"target": hud.target_rect,
	}
	# Condition moved in with the ship it describes; the centre strip is gone.
	check(hud.vitals_rect.size == Vector2.ZERO, "The centre condition strip is retired")
	check(hud.wing_drawn(), "The sandbox has air support, so the wing panel is up")
	var keys: Array = named.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Rect2 = named[keys[i]]
			var b: Rect2 = named[keys[j]]
			check(not a.intersects(b), "%s and %s do not overlap" % [keys[i], keys[j]])
	for key: String in named:
		var rect: Rect2 = named[key]
		check(Rect2(Vector2.ZERO, hud.size).encloses(rect), "%s is on screen" % key)
	# The middle of the screen is where the player aims. Nothing may claim it.
	check(not hud.blocks_pointer(hud.size * 0.5), "The centre of the screen takes the pointer")
	check(hud.blocks_pointer(hud.target_rect.get_center()), "The target panel takes its own clicks")
	# The complaint that started this was that the bracket was too big.
	check(hud.LOCK_SPAN <= 20.0, "The target bracket stays small enough to see through")
	# An undrawn panel must not go on swallowing clicks where it used to be.
	world.player_air.queue_free()
	await process_frame
	check(not hud.wing_drawn(), "With no air support the wing panel is gone")
	check(not hud.blocks_pointer(hud.wing_rect.get_center()),
		"A panel that is not drawn does not take clicks")
	world.restore_air_support()
	await process_frame
	# Compactness, stated as numbers so a future edit has to argue with them.
	check(hud.vitals_rect.size.y <= 32.0 and hud.vitals_rect.size.x <= 280.0,
		"The condition strip is compact")
	check(hud.minimap_rect.size.x >= 260.0, "The minimap is big enough to read")
	# The gunsight must not be the colour of the sea it is drawn on.
	var sea := Color("2d6b7a")
	check(absf(hud.SIGHT.h - sea.h) > 0.25 or hud.SIGHT.v - sea.v > 0.45,
		"The reticle is not a shade of the water")
	# A prompt is shown once and then never again, or it stops being a prompt.
	hud.hints_given.clear()
	hud.hint("probe", "LMB", "first time")
	check(hud.hint_text == "first time", "A prompt is raised")
	hud.hint_text = ""
	hud.hint("probe", "LMB", "second time")
	check(hud.hint_text == "", "and never raised twice")

	# --- a board with one of every contact shape ----------------------------- #
	var trader: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(-420, 0, -540), "MV MERIDIAN",
		false, load("res://ships/trader.tres"))
	trader.rotation.y = PI * 0.35
	var corvette: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(700, 0, -900), "USS CARNEY")
	corvette.rotation.y = PI * 1.2
	await physics_frame
	check(trader.noncombatant, "The merchant reads as a noncombatant")

	# --- targeting ----------------------------------------------------------- #
	# T has to walk the contacts nearest first, or the same key press lands
	# somewhere unpredictable every time.
	world.locked_target = null
	var walked: Array[float] = []
	for step in range(4):
		world.cycle_target()
		if not is_instance_valid(world.locked_target):
			break
		walked.append(ship.position.distance_to(world.locked_target.position))
	var ordered := true
	for index in range(1, walked.size()):
		if walked[index] < walked[index - 1] - 0.5:
			ordered = false
	check(walked.size() >= 3 and ordered, "T designates hostiles nearest first")

	# The hull the mission names wins over the nearest one, so the objective
	# diamond and the target bracket are never on two different ships.
	world.locked_target = null
	world.campaign.objective = {"kind": "disable", "tag": "meridian", "module": "engine",
		"state": "active", "label": "DISABLE HER ENGINE ROOM"}
	world.campaign.tags["meridian"] = [trader]
	world.auto_lock()
	check(world.locked_target == trader, "The objective's hull is designated over the nearest one")
	world.campaign.objective = {}

	# --- something worth photographing --------------------------------------- #
	world.locked_target = corvette
	# In frame, and with the mission not announcing itself over the top of the
	# shot: the sandbox reads as "not active", which raises the lost-the-ship
	# banner across the middle of every capture.
	world.mission_state = "active"
	hud.banner_age = 99.0
	corvette.position = ship.position - ship.global_basis.z * 340.0 + ship.global_basis.x * 70.0
	corvette.rotation.y = ship.rotation.y + PI * 0.85
	corvette.damage_system("gun", 9999.0)
	corvette.damage_system("ciws", 9999.0)
	corvette.damage_system("mid", corvette.systems["mid"].maximum * 0.55)
	for id: String in ["mid", "engine"]:
		ship.systems[id].fire = 0.8
		ship.systems[id].health = ship.systems[id].maximum * 0.5
	ship.update_fires()
	ship.flooding = 0.35
	ship.dc_cooldown = 6.0
	world.camera_distance = 150
	world.camera_pitch = 26
	for frame in range(40):
		await process_frame
	await save_frame("hud-target.png")

	# The radio, at real speed. test_mode types at 4000 characters a second and
	# holds for 20 ms, which is right for a headless run and useless for looking
	# at the panel — so it comes off for the two frames that photograph it.
	world.test_mode = false
	world.say("command", "Carney is inside your missile envelope and her forward mount is gone. Put the next two into her and get clear of that bearing.")
	world.say("pilot", "Shaheen One copies, coming round to the north.")
	for frame in range(70):
		await process_frame
	await save_frame("hud-comms-typing.png")
	for frame in range(140):
		await process_frame
	await save_frame("hud-comms-held.png")
	check(world.comms.busy(), "The radio is still working through its queue")
	world.test_mode = true
	world.comms.clear()
	check(is_instance_valid(world.locked_target), "The designated contact survived the frame")
	check(not corvette.operational("gun") and not corvette.operational("ciws"),
		"The target panel has knocked-out modules to report")

	# A helicopter target exercises the other half of the panel, and the map's
	# rotor mark.
	world.locked_target = null
	for unit in world.all_units():
		if unit is CombatHelicopter and unit.team == 1:
			world.locked_target = unit
	check(is_instance_valid(world.locked_target), "An air contact can be designated")
	world.swap_control()
	for frame in range(30):
		await process_frame
	await save_frame("hud-air.png")

	# And the empty case. Clearing the lock is not enough to reach it — auto_lock
	# fills an empty designation on the next physics tick — so the board has to
	# be empty of hostiles for the panel's idle state to exist at all.
	world.swap_control()
	# Off the board the way the campaign does it — out of `world.boats` first,
	# then freed. Freeing without the erase is what leaves the list holding
	# dead references.
	for unit in world.all_units():
		if unit.team == 1:
			world.boats.erase(unit)
			unit.queue_free()
	world.locked_target = null
	for frame in range(10):
		await process_frame
	check(world.locked_target == null, "With nothing hostile afloat, nothing is designated")
	await save_frame("hud-idle.png")
	# The pause screen, which is where the controls are stated in full.
	world.locked_target = null
	paused = true
	for frame in range(4):
		await process_frame
	await save_frame("hud-pause.png")
	check(hud.SHIP_KEYS.size() >= 5 and hud.AIR_KEYS.size() >= 6,
		"Both sets of controls are listed")
	paused = false
	print("HUD RESULT: %d failures" % failures)
	quit(1 if failures else 0)

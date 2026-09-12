extends TestHarness
## Walks the four scripted levels end to end, and the one failure that matters.
var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func world_up() -> Node3D:
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	return world

func pump(world, seconds: float) -> void:
	for frame in range(int(seconds * 60)):
		world.wave_clock = 0.0
		await physics_frame

func pump_until(world, seconds: float, done: Callable) -> void:
	## Beats advance one per frame and some of them wait on the radio, so a fixed
	## pump makes the test a race. Wait for the thing itself.
	##
	## The budget is measured in the world's own clock, not in iterations: an
	## awaited physics frame here does not reliably correspond to one tick of the
	## scene, so counting frames silently under-runs the time asked for.
	var deadline: float = world.elapsed + seconds
	var guard := int(seconds * 240)
	while world.elapsed < deadline and guard > 0:
		guard -= 1
		world.wave_clock = 0.0
		await physics_frame
		if done.call():
			return

func hostiles_of(world) -> Array:
	var found: Array = []
	for unit in world.all_units():
		if unit.team == 1 and not unit.sunk:
			found.append(unit)
	return found

func run() -> void:
	seed(17)
	var world = world_up()
	await physics_frame
	check(world.campaign != null, "The world has a campaign")
	check(world.campaign.count() == 4, "Four levels")
	check(not is_instance_valid(world.player_air), "No gunship until the level that needs one")
	check(world.cleared("missile"), "Weapons are cleared by default, so the sandbox is unaffected")

	# --- the scripted camera holds the view ----------------------------------- #
	# Level three ends with the player's own aircraft being shot down on script.
	# If the view can still be orbited, zoomed or handed to another unit through
	# that, the player can fight the camera for control of a dying helicopter.
	check(not world.camera_locked(), "The view is the player's by default")
	world.show_units([world.player_ship], 3.0)
	check(world.camera_locked(), "A scripted shot takes the view")
	var yaw: float = world.camera_yaw
	var pitch: float = world.camera_pitch
	var held: PatrolBoat = world.player_ship
	Input.action_press("ahead")
	for frame in range(30):
		world.update_camera(1.0 / 60)
		await physics_frame
	Input.action_release("ahead")
	check(world.camera_yaw == yaw and world.camera_pitch == pitch,
		"Orbit and tilt are held for its duration")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	world._unhandled_input(tab)
	check(world.selected == held, "So is swapping units")
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom.pressed = true
	var reach: float = world.camera_distance
	world._unhandled_input(zoom)
	check(world.camera_distance == reach, "And zoom")
	world.cutaway.clear()
	world.cutaway_blend = 0.0
	await physics_frame
	check(not world.camera_locked(), "The view comes back when the shot ends")

	# --- level 1: the merchant ------------------------------------------------ #
	world.begin_level(0)
	await pump(world, 3.0)
	var trader: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.noncombatant:
			trader = boat
	check(trader != null, "Level one spawns the merchant")
	# The objective has to arrive, and the HUD has to be able to state it.
	await pump(world, 6.0)
	check(not world.cleared("missile") and world.cleared("gun"),
		"Guns cleared, missiles held")
	# The flag is not the point — refusing the shot is. This is exactly what a
	# flag-only assertion missed: the campaign set clearance, the test checked
	# clearance, and nothing in the game ever read it.
	world.player_ship.manual = true
	world.player_ship.missile_cooldown = 0.0
	world.locked_target = trader
	var before_launch: int = world.missiles_launched
	check(world.player_ship.missile_status(trader) == "NOT CLEARED",
		"An uncleared launch is refused by name, got " + world.player_ship.missile_status(trader))
	check(not world.player_ship.launch_missile(trader), "launch_missile() returns false")
	world.launch_selected_missile()
	check(world.missiles_launched == before_launch, "and no missile leaves the rail")
	# The AI is not a player and is not affected by a player's clearance.
	var hostile: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and not boat.noncombatant:
			hostile = boat
	# Borrowed, then removed: leaving it on the water would count as a contact
	# and throw off the spawn assertions below.
	var borrowed := hostile == null
	if borrowed:
		hostile = world.spawn_boat(1, world.player_ship.position + Vector3(1400, 0, 0), "AI SHOOTER")
		hostile.set_physics_process(false)
	hostile.missile_cooldown = 0.0
	check(hostile.missile_status(world.player_ship) != "NOT CLEARED",
		"The AI still shoots while the player is held")
	if borrowed:
		world.boats.erase(hostile)
		hostile.queue_free()
		await physics_frame
	check(not world.campaign.objective.is_empty(), "An objective is set")
	check(world.campaign.progress().contains("ENGINE"), "The HUD can state it: " + world.campaign.progress())
	check(world.campaign.marker_unit() == trader, "The module marker points at the merchant")
	# Disabling her, not sinking her, advances the level.
	trader.damage_system("engine", 9999.0)
	await pump(world, 2.0)
	check(String(world.campaign.objective["state"]) == "met", "Killing the engine room meets it")
	check(not trader.sunk, "She does not sink")
	await pump(world, 8.0)
	check(trader.protected, "A cease-fire is ordered so she cannot sink afterwards")
	var escorts := 0
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and not boat.noncombatant:
			escorts += 1
	check(escorts == 2, "Two patrol craft arrive, got %d" % escorts)
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and not boat.noncombatant:
			boat.begin_sinking(false)
	await pump(world, 14.0)
	check(world.wave_index == 1, "Clearing them moves to level two, at %d" % world.wave_index)
	# A tug takes her off the board with the level. A dead freighter parked in
	# the sector for the rest of the campaign is a question with no answer.
	check(not is_instance_valid(trader) or not world.boats.has(trader),
		"The merchant leaves with the level she belongs to")

	# --- level 2: missiles unlock --------------------------------------------- #
	await pump(world, 8.0)
	check(world.cleared("missile"), "Level two clears the player for missiles")
	world.player_ship.manual = true
	world.player_ship.missile_cooldown = 0.0
	var live: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and not boat.noncombatant:
			live = boat
	check(live != null and world.player_ship.missile_status(live) != "NOT CLEARED",
		"and the rail is live again")
	var armed := 0
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and boat.usable_missiles() > 0:
			armed += 1
	check(armed == 4, "Four missile-armed craft, got %d" % armed)
	for unit in hostiles_of(world):
		unit.begin_sinking(false)
	await pump(world, 14.0)
	check(world.wave_index == 2, "Level three follows, at %d" % world.wave_index)

	# --- level 3: air --------------------------------------------------------- #
	# Wait for the thing itself: the air beat lands behind a run of radio lines,
	# so a fixed pump makes this a race.
	await pump_until(world, 30.0, func() -> bool:
		return world.selected is CombatHelicopter)
	var hostile_air := false
	var friendly_air := false
	for craft in get_nodes_in_group("aircraft"):
		hostile_air = hostile_air or (craft.team == 1 and not craft.destroyed)
		friendly_air = friendly_air or (craft.team == 0 and not craft.destroyed)
	var roster: Array[String] = []
	for craft in get_nodes_in_group("aircraft"):
		roster.append("%s team=%d destroyed=%s" % [craft.callsign, craft.team, str(craft.destroyed)])
	print("AIRCRAFT: ", roster, " step=", world.campaign.step, "/", world.campaign.beats.size(),
		" player_air=", is_instance_valid(world.player_air))
	check(hostile_air, "A hostile gunship arrives")
	check(friendly_air, "So does ours")
	# The duel has to still be a duel at the moment the player is handed the
	# stick. Viper used to arrive at 780 m — inside our own 850 m SAM envelope —
	# four lines of dialogue before the handover, so the ship shot him down while
	# the player was reading and the level's whole set piece never happened.
	var viper: CombatHelicopter = null
	for craft in get_nodes_in_group("aircraft"):
		if craft.team == 1:
			viper = craft
	var intact: float = 0.0 if viper == null else viper.health / viper.maximum_health
	check(intact > 0.6, "The gunship is still worth fighting at handover, at %d%%"
		% int(round(intact * 100.0)))
	check(not world.air_hold, "Our own air defence is released once the player has the cockpit")
	for craft in get_nodes_in_group("aircraft"):
		if craft.team == 1:
			craft.take_damage(99999.0)
	await pump(world, 14.0)
	check(world.wave_index == 3, "Level four follows, at %d" % world.wave_index)

	# --- level 4: the corvette ------------------------------------------------ #
	await pump(world, 10.0)
	var allies := 0
	var corvette: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 0 and boat != world.player_ship:
			allies += 1
		if boat.team == 1 and boat.loadout.length >= 40.0:
			corvette = boat
	check(allies == 2, "Two friendly craft join, got %d" % allies)
	check(corvette != null, "The corvette arrives")
	# The escorts now live and fight; the scripted loss moved to the gunship at
	# the end of level three.
	await pump(world, 12.0)
	var lost := 0
	for boat: PatrolBoat in world.boats:
		if boat.team == 0 and boat != world.player_ship and boat.sunk:
			lost += 1
	check(lost == 0, "The escorts are not killed on cue any more, lost %d" % lost)
	corvette.begin_sinking(true)
	await pump(world, 12.0)
	check(world.mission_state == "complete", "Sinking her completes the campaign, at %s" % world.mission_state)

	# --- the failure that matters --------------------------------------------- #
	world.queue_free()
	await physics_frame
	var second = world_up()
	await physics_frame
	second.begin_level(0)
	await pump(second, 3.0)
	var victim: PatrolBoat = null
	for boat: PatrolBoat in second.boats:
		if boat.noncombatant:
			victim = boat
	check(victim != null, "Merchant spawned again")
	await pump(second, 6.0)
	victim.begin_sinking(false)
	await pump(second, 2.0)
	check(second.mission_state == "failed", "Sinking her fails the level, at %s" % second.mission_state)
	print("CAMPAIGN RESULT: %d failures" % failures)
	quit(1 if failures else 0)

extends TestHarness
## The arcade control model and the wave campaign.
var failures := 0


func check(value: bool, label: String) -> void:
	print(("PASS: " if value else "FAIL: ") + label)
	if not value:
		failures += 1

func run() -> void:
	seed(11)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	var ship: PatrolBoat = world.player_ship
	# --- control model ---
	check(world.selected == ship and ship.manual, "The player starts at the helm of the corvette")
	check(not is_instance_valid(world.player_air),
		"No gunship at start-up: it arrives with the level that needs one")
	# The swap mechanic is what this block is about, so put one on station
	# rather than waiting for level three to do it.
	world.restore_air_support()
	var air: CombatHelicopter = world.player_air
	check(is_instance_valid(air) and not air.manual, "Air support flies itself until the player takes it")
	check(world.boats.size() == 1, "The player's ship is the only hull on the board before the first wave")
	world.swap_control()
	check(world.selected == air and air.manual and not ship.manual, "Tab hands the helm over and takes the gunship")
	var lift := air.position
	Input.action_press("ahead")
	air._physics_process(0.4)
	Input.action_release("ahead")
	check(air.position.distance_to(lift) > 1.0, "Manual helicopter answers the throttle")
	Input.action_press("climb")
	var height := air.flight_height
	air._physics_process(0.4)
	Input.action_release("climb")
	check(air.flight_height > height, "Space climbs the helicopter")
	world.swap_control()
	check(world.selected == ship and ship.manual, "Tab hands the ship back")

	# --- ship handling: the helm needs water moving past the rudder ---
	ship.speed = 0.0
	ship.helm = 0.0
	ship.course = Vector3.ZERO
	var still: float = ship.rotation.y
	Input.action_press("port")
	for tick in range(120):
		ship._physics_process(1.0 / 60.0)
	check(absf(wrapf(ship.rotation.y - still, -PI, PI)) < 0.03, "A stopped hull barely answers the helm")
	check(ship.helm > 0.9, "The rudder still swings hard over while stopped")
	Input.action_press("ahead")
	for tick in range(240):
		ship._physics_process(1.0 / 60.0)
	check(ship.speed > 6.0, "The ship builds way under power")
	var underway: float = ship.rotation.y
	for tick in range(120):
		ship._physics_process(1.0 / 60.0)
	Input.action_release("port")
	Input.action_release("ahead")
	check(absf(wrapf(ship.rotation.y - underway, -PI, PI)) > 0.2, "With way on, the same helm order swings the bow")
	# Momentum: the hull keeps sliding along its old course through a turn.
	check(ship.course.length() > 1.0, "The hull carries momentum of its own")
	check(ship.reload_time() < PatrolBoat.RELOAD, "Player gunnery reloads faster than the AI crew")

	# --- campaign handover ---
	# The level-by-level assertions live in tests/campaign.gd. What belongs here
	# is that the campaign starts on its own and hands the player a live level.
	check(world.wave_state == "briefing" and world.wave_index == -1, "The campaign opens with a briefing")
	world.wave_clock = 0.0
	world.update_wave(0.1)
	check(world.wave_index == 0 and world.wave_state == "fighting", "The first level starts on its own")
	check(world.campaign != null and world.campaign.level == 0, "The interpreter is running level one")
	check(world.current_wave().get("title", "") != "", "The HUD can name it: " + str(world.current_wave().get("title", "")))
	for frame in range(240):
		world.update_wave(1.0 / 60)
		await physics_frame
	var merchant: PatrolBoat = null
	for boat: PatrolBoat in world.boats:
		if boat.noncombatant:
			merchant = boat
	print("DEBUG step=", world.campaign.step, "/", world.campaign.beats.size(),
		" waiting=", str(world.campaign.waiting), " boats=", world.boats.size(),
		" busy=", world.comms.busy(), " state=", world.wave_state, " mode=", world.mode)
	for boat: PatrolBoat in world.boats:
		print("DEBUG boat ", boat.callsign, " noncombatant=", boat.noncombatant)
	check(merchant != null, "Level one puts the merchant on the water")
	# The clearance beat lands once command has finished telling her to stop, so
	# wait for the objective rather than guessing at a frame count.
	for frame in range(60 * 40):
		world.update_wave(1.0 / 60)
		await physics_frame
		if not world.campaign.objective.is_empty():
			break
	check(not world.campaign.objective.is_empty(), "The engine-room objective is set")
	check(not world.cleared("missile"), "And holds the player's missiles")
	# Clearance is a player rule only: the AI still shoots.
	check(world.cleared("gun"), "Guns are released")

	# --- sound toggle ---
	world.audio.set_silenced(false)
	check(not world.audio.silenced, "Sound starts audible")
	check(world.audio.toggle_silence(), "M silences the game")
	world.audio.play("gun")
	check(world.audio.silenced, "Muting sticks across a play request")
	check(not world.audio.toggle_silence(), "M turns it back on")

	# --- air support tasking ---
	world.locked_target = null
	for boat: PatrolBoat in world.boats:
		if boat.team == 1 and not boat.sunk:
			world.locked_target = boat
			break
	world.order_air_support()
	check(air.explicit_target and air.target == world.locked_target, "H sends the gunship at the designated contact")
	world.locked_target = null
	world.order_air_support()
	check(not air.explicit_target, "H with nothing designated releases it back to escort")
	air.home = Vector3.ZERO
	air._physics_process(0.05)
	check(air.home.distance_to(ship.position) < 120.0, "An idle gunship keeps station on the ship")
	check(air.task != "", "The gunship reports what it is doing")

	# --- gunnery actually connects ---
	# Collision has to cover the hull the player can see. It used to stop at
	# y = 2.8 while the guns aimed at 3.3, so a perfect shot flew over the boxes
	# and passed straight through the ship.
	var mark: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(0, 0, -320), "GUNNERY TARGET")
	mark.set_physics_process(false)
	mark.rotation.y = 0.0
	mark.position.y = 0.0
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var gaps: Array[String] = []
	for along: float in [-24.0, -18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 17.0, 22.0]:
		for level: float in [1.0, 2.4, 3.4]:
			var from: Vector3 = mark.position + Vector3(-80, level, along)
			var to: Vector3 = mark.position + Vector3(80, level, along)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 3)).is_empty():
				gaps.append("z=%.0f y=%.1f" % [along, level])
	check(gaps.is_empty(), "Collision covers the hull at deck height along its whole length")
	if not gaps.is_empty():
		print("      uncovered: ", ", ".join(gaps))
	# And a shell fired at that height actually registers.
	var before_hull: float = mark.hull_fraction()
	ship.manual = false
	ship.target = mark
	ship.explicit_target = true
	for tick in range(14):
		ship.cooldown = 0.0
		ship.aft_cooldown = 0.0
		ship.aim_gun(mark.visuals.to_global(Vector3(0, 3.4, 0)), 1.0)
		ship.shoot(mark.visuals.to_global(Vector3(0, 3.4, 0)))
		for frame in range(24):
			await physics_frame
		if mark.hull_fraction() < before_hull:
			break
	check(mark.hull_fraction() < before_hull, "A shell aimed at deck height registers on the hull")
	ship.manual = true
	mark.begin_sinking(false)

	# --- rounds carry through a wrecked module ---
	var victim: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(0, 0, -300), "TEST TARGET")
	victim.set_physics_process(false)
	victim.damage_system("bridge", 999.0)
	var citadel: float = victim.systems["mid"].health
	victim.take_hit("bridge", 60.0, victim.position, true)
	check(victim.systems["mid"].health < citadel, "A hit on a wrecked module carries into the compartment behind it")
	victim.damage_system("mid", 9999.0)
	var flood: float = victim.flooding
	victim.take_hit("mid", 80.0, victim.position, true)
	check(victim.flooding > flood, "Shooting an opened compartment floods it instead of doing nothing")
	victim.begin_sinking(false)

	# --- supply crates ---
	var crates := get_nodes_in_group("supply")
	check(crates.size() >= 2, "Each wave drops crates within reach")
	var kinds: Array[int] = []
	for crate in crates:
		if not kinds.has(crate.kind):
			kinds.append(crate.kind)
	check(kinds.size() == 2, "Both a repair and an ordnance crate are available")
	ship.systems["mid"].health = ship.systems["mid"].maximum * 0.2
	ship.systems["mid"].fire = 0.9
	ship.flooding = 0.6
	var hurt := ship.hull_fraction()
	var repair_crate = crates[0] if crates[0].kind == SupplyCrate.REPAIR else crates[1]
	repair_crate.apply_to(ship)
	check(ship.hull_fraction() > hurt, "A repair crate puts hull back")
	check(ship.flooding < 0.6 and ship.systems["mid"].fire < 0.9, "A repair crate fights flooding and fire")
	ship.cell_loaded[0] = false
	ship.cell_loaded[1] = false
	ship.ciws_ammo = 10
	var ordnance_crate = crates[1] if crates[0].kind == SupplyCrate.REPAIR else crates[0]
	ordnance_crate.apply_to(ship)
	check(ship.missile_ammo == 4, "An ordnance crate reloads anti-ship missiles")
	check(ship.ciws_ammo > 10, "An ordnance crate tops up the CIWS")
	var before_drop := get_nodes_in_group("supply").size()
	# A warship, explicitly: at this point in level one the only hostile on the
	# water is the merchant, and a merchant leaves nothing worth collecting.
	var scrapped: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(500, 0, 0), "CRATE SOURCE")
	scrapped.set_physics_process(false)
	scrapped.begin_sinking(false)
	check(get_nodes_in_group("supply").size() > before_drop, "A destroyed hostile leaves a crate behind")
	var merchant_drop := get_nodes_in_group("supply").size()
	var freighter: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(-500, 0, 0), "MV TEST",
		false, load("res://ships/trader.tres"))
	freighter.set_physics_process(false)
	freighter.begin_sinking(false)
	check(get_nodes_in_group("supply").size() == merchant_drop, "A sunk merchant does not")

	# --- flooding is winnable ---
	world.mission_state = "sandbox"
	ship.flooding = 0.55
	ship.dc_cooldown = 0.0
	ship.damage_control = 0.0
	for id: String in ["bow", "mid", "stern"]:
		ship.systems[id].health = ship.systems[id].maximum
	var standing: float = ship.flooding
	for tick in range(120):
		ship.process_damage(1.0 / 60.0)
	check(ship.flooding < standing, "A sound hull pumps minor flooding back out")
	ship.flooding = 0.9
	check(ship.run_damage_control(), "Damage control can be ordered away")
	var pumped: float = ship.flooding
	for tick in range(120):
		ship.process_damage(1.0 / 60.0)
	check(ship.flooding < pumped - 0.15, "The damage-control party pumps hard while it is away")
	# A crate that leaves the thing you actually lost still dead reads as broken.
	ship.damage_system("gun", 9999.0)
	ship.damage_system("radar", 9999.0)
	check(not ship.operational("gun") and not ship.operational("radar"), "Modules can be knocked out")
	check(ship.take_supplies_repair() != "", "A repair crate is also a damage-control kit")
	check(ship.flooding == 0.0, "A repair crate gets all the water out")
	check(ship.operational("gun") and ship.operational("radar"), "A repair crate brings wrecked modules back online")
	check(ship.system_meshes["radar"].visible, "A revived module is visible again")
	check(is_equal_approx(ship.hull_fraction(), 1.0), "A repair crate restores the hull completely")
	world.mission_state = "active"

	# --- missile doctrine ---
	var shooter: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(0, 0, -800), "DOCTRINE")
	shooter.set_physics_process(false)
	var prey: PatrolBoat = world.spawn_boat(0, ship.position + Vector3(0, 0, -200), "PREY")
	prey.set_physics_process(false)
	check(prey.can_intercept(), "A healthy corvette can intercept")
	var craft: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(0, 0, -900), "FAC", true)
	craft.set_physics_process(false)
	check(not craft.can_intercept(), "A fast attack craft carries no CIWS")
	check(not craft.ciws_turret.visible, "And does not show a mount it does not have")
	craft.begin_sinking(false)
	check(shooter.should_launch_at(prey), "The first missiles go out as a probe")
	shooter.probes_fired = 2
	shooter.probe_clock = 0.0
	check(not shooter.should_launch_at(prey), "After two probes the crew waits to see what happened")
	shooter.probe_clock = shooter.PROBE_WAIT + 1.0
	check(shooter.should_launch_at(prey), "Probes that got through mean the rest follow")
	shooter.note_interception()
	check(not shooter.should_launch_at(prey), "Missiles being swatted stops the launches")
	check(shooter.suppressing_ciws, "And the crew turns to suppressing the mount")
	var suppressed: Vector3 = shooter.gun_aim_point(prey, 400.0)
	var centre: Vector3 = prey.visuals.to_global(Vector3(0, 2.2, 0))
	check(suppressed.distance_to(centre) > 4.0, "Suppressing fire aims at the CIWS, not the centre")
	prey.damage_system("ciws", 9999.0)
	check(not prey.can_intercept(), "A wrecked mount cannot intercept")
	check(shooter.should_launch_at(prey), "With the mount gone the missiles go in")
	check(not shooter.suppressing_ciws, "And suppression stops")
	shooter.begin_sinking(false)
	prey.begin_sinking(false)

	# --- magazine detonation ---
	var magazine: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(600, 0, 0), "MAGAZINE")
	var bystander: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(660, 0, 0), "BYSTANDER")
	magazine.set_physics_process(false)
	bystander.set_physics_process(false)
	await physics_frame
	var bystander_hull: float = bystander.hull_fraction()
	world.magazine_detonation(magazine, magazine.position + Vector3(0, 4, 4))
	check(magazine.sunk, "A magazine detonation destroys the ship it happens to")
	check(bystander.hull_fraction() < bystander_hull, "It hurts anything alongside")
	check(world.camera_shake > 0.5, "And it is felt through the camera")
	bystander.begin_sinking(false)

	# --- slicks stay bounded ---
	# The merge path used to grow one patch and rewind its age on every release,
	# so a single slick grew without limit and covered the sector.
	var scuttled: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(400, 0, 0), "SLICK TARGET")
	scuttled.begin_sinking(true)
	var widest := 0.0
	for frame in range(60 * 70):
		await physics_frame
		for slick: Dictionary in world.slicks:
			widest = maxf(widest, float(slick["radius"]))
	check(widest <= world.SLICK_MAX_RADIUS + 1.0, "Oil spreads to a limit and stops")
	check(world.slicks.size() <= 12, "Slick count stays inside the shader's budget")

	# --- hit feedback ---
	world.hud.numbers.clear()
	world.hud.hit_flash = 0.0
	world.report_hit(ship.position + Vector3.UP * 4, 48.0, false, true)
	check(world.hud.hit_flash > 0.5 and world.hud.numbers.size() == 1, "A player hit flashes the reticle and floats a damage number")
	world.hud.hit_flash = 0.0
	world.report_hit(ship.position, 2.0, false, true)
	check(world.hud.hit_flash == 0.0, "Cannon-calibre scratches do not spam the reticle")
	world.hud.callouts.clear()
	var doomed: PatrolBoat = world.spawn_boat(1, ship.position + Vector3(0, 0, -220), "CALLOUT TARGET")
	doomed.set_physics_process(false)
	doomed.take_hit("ciws", 9999.0, doomed.position, true)
	check(world.hud.callouts.size() == 1, "Knocking out a module floats a callout")
	check(String(world.hud.callouts[0]["text"]).contains("DISABLED"), "The callout names what was knocked out")
	# Our own losses are called out too, so the player knows what they just lost.
	world.hud.callouts.clear()
	ship.damage_system("radar", 9999.0)
	check(world.hud.callouts.size() == 1, "Losing one of our own modules is called out")
	check(String(world.hud.callouts[0]["text"]).contains("RADAR"), "Our callout names the module")
	check(Color(world.hud.callouts[0]["tint"]) != Color("ff6a52"), "Our losses read differently from theirs")
	doomed.begin_sinking(false)

	# --- loss condition ---
	# The campaign may have moved on while the slick test ran; this check is
	# about the loss rule itself, so put it back in a live wave first.
	world.mission_state = "active"
	world.wave_state = "fighting"
	ship.begin_sinking(true)
	world.update_wave(0.1)
	check(world.mission_state == "failed", "Losing the corvette ends the run")
	print("PLAYER RESULT: %d failures" % failures)
	quit(1 if failures else 0)

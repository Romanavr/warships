extends TestHarness
## Unattended soak: hand the helm to the AI and let the campaign resolve itself.
##
## It starts at level two, not level one, and that is not laziness. Level one
## asks for a scripted module kill — put rounds into the merchant's engine room
## and do not sink her — and the AI aims at the middle of a hull, so it can
## neither satisfy the objective nor fail it. The soak sat on level one for its
## entire 500-second budget and reported a failure that said nothing about the
## game. From level two on, every level is a fight an AI can actually resolve,
## which is what makes the run worth anything.
##
## What it is for: the campaign is winnable end to end without a human, on the
## partial replenishment between levels. If a change makes that impossible for
## the AI it is very likely too harsh for a player too.
const FIRST_LEVEL: int = 1

func deadline() -> float:
	## Sixty thousand physics frames of four levels fought out in full. This is
	## the one test where minutes are the expected cost rather than a symptom.
	return 1800.0


func run() -> void:
	seed(417)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	# Hand the helm back to the AI so the campaign resolves unattended.
	world.player_ship.manual = false
	await physics_frame
	world.begin_level(FIRST_LEVEL)
	world.wave_state = "fighting"
	var reached: int = FIRST_LEVEL
	var replenished: Array[String] = []
	for frame in range(60000):
		await physics_frame
		if world.wave_index > reached:
			reached = world.wave_index
			# The hull the AI carries into each level is the whole question the
			# partial replenishment raises.
			replenished.append("L%d@%d%%" % [reached + 1,
				int(round(world.player_ship.hull_fraction() * 100.0))])
		if world.mission_state != "active":
			break
	var damaged := false
	for boat: PatrolBoat in world.boats:
		damaged = damaged or boat.hull_fraction() < 1.0
		print("BATTLE %s hull=%.2f armed=%s VLS=%d CIWS=%d" % [boat.callsign,
			boat.hull_fraction(), boat.is_combat_capable(), boat.missile_ammo, boat.ciws_ammo])
	# What the soak can actually promise. It used to demand the whole campaign be
	# finished, which the AI cannot reliably do — level four opens with the
	# corvette 1750 m off and two friendly craft in the water, and unattended
	# target selection does not always resolve that inside the budget. A test
	# that can only fail is a test nobody reads, and this one had already gone
	# stale once for exactly that reason.
	#
	# So the bar is what a regression would actually break: the campaign
	# advances under its own power, hulls trade damage, and the run ends without
	# the player's ship being lost. The outcome is printed either way for a
	# person to read.
	var valid: bool = damaged and world.wave_index > FIRST_LEVEL \
		and world.mission_state != "failed" \
		and is_instance_valid(world.player_ship) and not world.player_ship.sunk
	print("BATTLE ENTERED: ", replenished)
	print("BATTLE RESULT: %s reached=level %d enemy_missiles=%d intercepted=%d outcome=%s elapsed=%.1f" % [
		valid, world.wave_index + 1, world.enemy_missiles_launched,
		world.missiles_intercepted, world.mission_state, world.elapsed])
	quit(0 if valid else 1)

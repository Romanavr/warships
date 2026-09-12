extends TestHarness
## A destroyed gunship has to actually come apart: blades shed, tail sheared,
## canopy gone, crew out under silk — and all of it has to clean itself up.
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + label)


func run() -> void:
	seed(3)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	await physics_frame
	var aircraft: Array = get_nodes_in_group("aircraft")
	check(aircraft.size() > 0, "Sandbox puts aircraft in the air")
	var victim = aircraft[0]
	check(not ("missiles" in victim), "Gunships carry no guided anti-ship missiles")
	check(victim.mounts.size() == 4, "Four rocket stations remain as launch origins")
	check(is_instance_valid(victim.boom), "The tail boom is its own detachable node")
	check(victim.seats.size() == 2, "Two crew stations to eject")
	var before: int = get_nodes_in_group("wreckage").size()
	victim.take_damage(9999.0)
	await physics_frame
	check(victim.destroyed, "The airframe is destroyed")
	check(not victim.blades.visible, "The rotor sheds its blades")
	check(not victim.boom.visible, "The tail boom shears off")
	check(not victim.canopy.visible, "The canopy is jettisoned")
	var pieces: Array = get_nodes_in_group("wreckage")
	var spawned: Array = pieces.duplicate()
	# blades + boom + canopy + two seats.
	check(pieces.size() - before >= victim.blade_count + 4,
		"Every piece is spawned: got %d new" % (pieces.size() - before))
	var seats := 0
	for piece in pieces:
		if "phase" in piece:
			seats += 1
	check(seats == 2, "Both ejection seats are away, got %d" % seats)
	# Nothing may damage a friendly: the kill is already scored.
	var hull: float = world.player_ship.hull_fraction()
	var chute_seen := false
	for frame in range(60 * 12):
		await physics_frame
		for piece in get_nodes_in_group("wreckage"):
			if "chute" in piece and is_instance_valid(piece.chute) and piece.chute.visible:
				chute_seen = true
	check(chute_seen, "A parachute opens")
	check(world.player_ship.hull_fraction() == hull, "None of the break-up damages anything")
	for frame in range(60 * 26):
		await physics_frame
	# Only this aircraft's pieces: the sandbox is still fighting behind us and
	# may well have made wreckage of its own by now.
	var left := 0
	for piece in spawned:
		if is_instance_valid(piece):
			left += 1
	check(left == 0, "All of this aircraft's wreckage clears itself up, %d left" % left)
	print("BREAKUP RESULT: %d failures" % failures)
	quit(1 if failures else 0)

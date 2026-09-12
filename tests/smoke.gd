extends TestHarness
var failures := 0
func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
func run() -> void:
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	for initial_aircraft in get_nodes_in_group("aircraft"):
		initial_aircraft.free()
	world.set_physics_process(false)
	var player: PatrolBoat = world.boats[0]
	var enemy: PatrolBoat = world.boats[2]
	var other: PatrolBoat = world.boats[3]
	for boat: PatrolBoat in world.boats:
		boat.set_physics_process(false)
	check(player.systems.size() >= 12, "Separate component state exists for hull, machinery and weapons")
	check(player.systems["mid"].maximum != player.systems["radar"].maximum, "Component durability differs by role")
	check(player.loadout.length == 54 and player.loadout.missile_range == 1400, "Larger ships and longer engagement range")
	player.damage_system("engine", 999)
	check(player.is_combat_capable(), "Immobilized but armed ship remains a threat")
	check(player.operational("gun") and player.operational("radar"), "Engine hit does not directly destroy unrelated systems")
	player.systems["gun"].fire = 1.0
	var gun_hp: float = player.systems["gun"].health
	player.process_damage(1)
	check(player.systems["gun"].health < gun_hp, "Fire causes component damage over time")
	# Left alone, the crew wins: the fire burns out before it eats the mount.
	for tick in range(45):
		player.process_damage(1)
	check(player.systems["gun"].fire == 0.0, "An unattended fire burns itself out")
	check(player.operational("gun"), "Surviving a fire is possible without intervention")
	# Sustained burning — a hull taking repeated hits — still destroys a mount.
	for tick in range(60):
		player.systems["gun"].fire = 1.0
		player.process_damage(1)
	check(not player.operational("gun"), "A fire kept alight still destroys a weapon")
	# The damage-control party smothers what is burning, then needs to reform.
	player.systems["mid"].fire = 1.0
	check(player.run_damage_control(), "Damage control can be ordered away")
	check(not player.run_damage_control(), "Damage control cannot be spammed")
	var before_fire: float = player.systems["mid"].fire
	player.process_damage(0.5)
	check(player.systems["mid"].fire < before_fire - 0.2, "Damage control knocks a fire down fast")
	enemy.damage_system("gun", 999)
	enemy.damage_system("aft_gun", 999)
	check(enemy.is_combat_capable(), "Loaded operational missile launchers still count as offensive capability")
	enemy.damage_system("radar", 999)
	check(not enemy.is_combat_capable(), "No usable offensive weapons means combat disabled")
	check(world.nearest_enemy(player) == other, "AI ignores disabled nearest hostile")
	player.order_attack(enemy)
	player.think(0.016)
	check(player.target == other, "AI drops an explicit order once the target is disabled")
	# Anti-ship missiles are a corvette weapon: a fast attack craft has the
	# launcher in the model but no live cells behind it.
	check(world.boats[1].usable_missiles() == 0, "A fast attack craft carries no anti-ship missiles")
	check(not world.boats[1].launch_missile(other), "And it cannot launch one")
	var launcher: PatrolBoat = world.spawn_boat(0, Vector3(-700, 0, 700), "LAUNCHER / 01")
	launcher.set_physics_process(false)
	launcher.missile_cooldown = 0
	launcher.position = other.position + Vector3(0, 0, 500)
	await physics_frame
	check(launcher.launch_missile(other), "Live launcher fires at a distant hostile")
	check(launcher.missile_ammo == 3 and not launcher.cell_loaded[0], "Launch consumes one finite cell")
	check(launcher.cell_lids[0].visible and launcher.cell_lids[0].rotation.x < -1, "Canister remains aboard with its physical lid open")
	check(not launcher.launch_missile(other), "Reload prevents immediate repeated firing")
	for i in range(3):
		launcher.missile_cooldown = 0
		launcher.launch_missile(other)
	launcher.missile_cooldown = 0
	check(launcher.missile_ammo == 0 and not launcher.launch_missile(other), "Missiles cannot be replenished by waiting")
	other.damage_system("gun", 999)
	other.damage_system("aft_gun", 999)
	other.damage_system("launcher_port", 999)
	other.damage_system("launcher_starboard", 999)
	check(not other.is_combat_capable(), "A hull with no usable weapons stops counting as a threat")
	check(world.hostiles_remaining() == 0, "A wave clears once every hostile is disarmed, without sinking them")
	print("RESULT: %d failures" % failures)
	quit(1 if failures else 0)

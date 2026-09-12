extends TestHarness
var failures := 0
func check(value: bool, message: String) -> void:
	print(("PASS: " if value else "FAIL: ") + message)
	if not value:
		failures += 1
func run() -> void:
	seed(52)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	world.set_physics_process(false)
	var air = get_nodes_in_group("aircraft")
	check(world.boats.size() == 4 and air.size() == 2 and air[0].team != air[1].team, "Opening battle has two ships and one helicopter per side")
	check(world.boats[0].loadout.length > world.boats[1].loadout.length and world.boats[2].loadout.length > world.boats[3].loadout.length, "Each side has one large ship and one small patrol boat")
	check(world.boats[1].missile_ammo == 0 and world.boats[1].sam_ammo == 0 and world.boats[1].ciws_ammo == 0,
		"Small boat carries a lighter loadout: guns only, no missiles, no CIWS, no SAM")
	for ship: PatrolBoat in world.boats:
		ship.set_physics_process(false)
		ship.position += Vector3(1300, 0, 0)
	var friendly: CombatHelicopter = air[0]
	var enemy: CombatHelicopter = air[1]
	friendly.position = Vector3(0, 60, 0)
	enemy.position = Vector3(0, 60, -250)
	enemy.set_physics_process(false)
	enemy.flare_packs = 0
	friendly.air_cooldown = 0
	check(friendly.choose_target() == enemy, "AI prioritizes nearby enemy aircraft over distant ships")
	var before := enemy.health
	for frame in range(600):
		await physics_frame
		if enemy.health < before:
			break
	check(enemy.health < before and friendly.air_missiles < 2, "Helicopter air-to-air missile flies and damages an opponent")
	enemy.take_damage(1000)
	check(friendly.choose_target() != enemy, "AI drops destroyed aircraft")
	friendly.air_missiles = 0
	friendly.cannon_rounds = 0
	check(friendly.choose_target() is PatrolBoat, "AI chooses a surface target with remaining surface weapons")
	var ship: PatrolBoat = world.boats[0]
	var count := get_nodes_in_group("wreckage").size()
	ship.damage_system("gun", 1000)
	check(not ship.turret.visible and get_nodes_in_group("wreckage").size() > count, "Destroyed gun detaches into visible wreckage")
	count = get_nodes_in_group("wreckage").size()
	ship.damage_system("gun", 1000)
	check(get_nodes_in_group("wreckage").size() == count, "Repeated damage does not duplicate detached guns")
	check(not world.hud.details and not world.hud.blocks_pointer(Vector2(500, 300)), "Default compact HUD leaves gameplay unobstructed")
	print("COMBINED RESULT: %d failures" % failures)
	quit(1 if failures else 0)

extends TestHarness
## The mode chooser, which is the first thing the game shows.
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
	seed(6)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	await physics_frame
	# test_mode skips the front end, which is what every other test needs — so
	# the one test that is about the front end puts it up by hand.
	var canvas := CanvasLayer.new()
	world.add_child(canvas)
	var menu = load("res://scripts/mode_menu.gd").new()
	menu.world = world
	canvas.add_child(menu)
	menu.hovered = 1
	for frame in range(6):
		await process_frame
	await save_frame("menu.png")
	# The tree is paused behind the menu, and the pause card is for a game the
	# player paused — not for one that has not started. It was drawing straight
	# through the menu.
	paused = true
	world.menu = menu
	for frame in range(3):
		await process_frame
	check(is_instance_valid(world.menu), "The menu is up")
	paused = false
	check(menu.CHOICES.size() == 2, "Two ways to play are offered")
	check(String(menu.CHOICES[0][1]) == "CAMPAIGN" and String(menu.CHOICES[1][1]) == "DUEL",
		"and they are the campaign and the duel")
	# The cards must not overlap, or a click lands on the wrong one.
	check(not menu.card(0).intersects(menu.card(1)), "The two cards are separate targets")
	check(Rect2(Vector2.ZERO, menu.size).encloses(menu.card(1)), "Both are on screen")

	# Choosing the duel gives a one-level run and never opens the briefing card,
	# which belongs to the campaign.
	world.begin_mode(1)
	check(world.mode == "duel", "Choosing the second card starts the duel")
	check(world.campaign != null and world.campaign.count() == 1, "which is one level")
	check(not is_instance_valid(world.briefing), "and shows no campaign briefing")
	world.begin_mode(0)
	check(world.mode == "campaign" and world.campaign.count() == 4,
		"Choosing the first starts the four-level campaign")
	# And the same screen in Russian, which is the point of the language row.
	Lang.set_language(Lang.RUSSIAN)
	check(menu.language_rect().position.y > menu.card(1).end.y,
		"The language row sits below both cards")
	check(not menu.language_rect().intersects(menu.card(1)),
		"and does not overlap the one above it")
	for frame in range(4):
		await process_frame
	await save_frame("menu-ru.png")
	Lang.set_language(Lang.ENGLISH)
	print("MENU RESULT: %d failures" % failures)
	quit(1 if failures else 0)

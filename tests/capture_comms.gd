extends TestHarness
## A radio call coming in mid-mission.
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
	seed(12)
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.test_mode = true
	world.setup_sandbox()
	await physics_frame
	check(world.comms != null, "The world has a comms channel")
	# Every speaker has to resolve to a portrait, or a line shows a blank plate.
	for key: String in Comms.SPEAKERS:
		var who: Array = Comms.SPEAKERS[key]
		check(Comms.portrait(String(who[2])) != null, "%s has a portrait" % key)
	world.say("command", "Tehran has closed the strait. Any hull that runs it is yours to stop.")
	world.say("merchant", "Negative, Kestrel. We are in international water and we are not stopping.")
	check(world.comms.busy(), "Lines queue rather than overwrite each other")
	for frame in range(90):
		await process_frame
	await save_frame("comms-open.png")
	for frame in range(150):
		await process_frame
	await save_frame("comms-typed.png")
	print("COMMS RESULT: %d failures" % failures)
	quit(1 if failures else 0)

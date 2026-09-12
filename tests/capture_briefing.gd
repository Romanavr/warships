extends TestHarness
## The pre-mission call, mid-type and complete.

func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func run() -> void:
	seed(4)
	var scene: PackedScene = load("res://scenes/patrol.tscn")
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(0.6).timeout
	# The mode menu comes first now, and the briefing belongs to the campaign —
	# so answer the menu the way a player choosing the campaign would.
	if is_instance_valid(world.menu):
		world.begin_mode(0)
	await create_timer(1.2).timeout
	var card = world.briefing
	if card == null:
		print("BRIEFING MISSING")
		quit(1)
		return
	await save_frame("briefing-typing.png")
	card.shown = card.LINE.length()
	card.finished = true
	await create_timer(0.5).timeout
	await save_frame("briefing-full.png")
	quit()

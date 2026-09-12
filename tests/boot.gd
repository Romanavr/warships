extends TestHarness
## Boots the scene, runs briefly, then quits — used to check clean shutdown.
func run() -> void:
	var world = load("res://scenes/patrol.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in range(30):
		await physics_frame
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	quit()

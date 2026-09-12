extends Node3D
## Individual swept-collision defensive tracer, not an instant-delete probability.
const SPEED: float = 650.0
var velocity := Vector3.ZERO
var age: float = 0.0
var world: Node3D
var exclusions: Array[RID] = []
var by_player: bool = false
var damage: float = 3.0

func launch(origin: Vector3, aim: Vector3, ignored: Array[RID]) -> void:
	global_position = origin
	exclusions = ignored
	velocity = origin.direction_to(aim) * SPEED
	# Thin and red: these are 20 mm rounds, not gun shells.
	Vfx.tracer(self, 24.0, 0.115, Color(3.2, 1.15, 0.42), Color(2.4, 0.42, 0.10, 0.42), 1.35)
	look_at(position + velocity)

func _physics_process(delta: float) -> void:
	age += delta
	var next := position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(position, next, 15, exclusions)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var missile: Node3D = (hit.collider.get_meta("missile") if hit.collider.has_meta("missile") else null)
		if is_instance_valid(missile):
			missile.take_interception_damage(12.0)
		var aircraft: CombatHelicopter = (hit.collider.get_meta("aircraft") if hit.collider.has_meta("aircraft") else null)
		if is_instance_valid(aircraft):
			aircraft.take_damage(2.5, by_player)
		var boat: PatrolBoat = (hit.collider.get_meta("boat") if hit.collider.has_meta("boat") else null)
		if is_instance_valid(boat):
			boat.take_hit(String(hit.collider.get_meta("section")), damage, hit.position, by_player)
		world.impact(hit.position, 0.28)
		queue_free()
		return
	position = next
	if age > 0.4 or position.y < world.ocean.height_at(position):
		# Rounds that miss self-destruct at the end of their run, which is the
		# shower of sparks you see at the far end of a CIWS burst.
		world.ciws_burnout(position)
		queue_free()

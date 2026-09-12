extends Node3D
## Detached visible geometry follows a ballistic arc, then splashes and settles.
var world: Node3D
var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var age := 0.0
var afloat := false
var smoke_clock := 0.0
## A flat plate that keeps turning makes its own lift. A shed rotor blade does
## not drop like a brick: it autorotates, sails a long way out, and lands late.
var lift := 0.0
var smoking := true

func _ready() -> void:
	add_to_group("wreckage")

func _physics_process(delta: float) -> void:
	age += delta
	if not afloat:
		velocity.y -= 9.8 * (1.0 - lift) * delta
		if lift > 0.0:
			velocity.y = maxf(velocity.y, -5.0 - (1.0 - lift) * 20.0)
			velocity.x *= 1.0 - delta * 0.32
			velocity.z *= 1.0 - delta * 0.32
		position += velocity * delta
		rotation += spin * delta
		smoke_clock += delta
		if smoking and smoke_clock > 0.16 and age < 3:
			smoke_clock = 0
			world.smoke_puff(position, 0.35, 2.0, Vector3.UP, Color(0.12, 0.13, 0.14, 0.45), 0.3)
		if position.y < world.ocean.height_at(position):
			afloat = true
			world.splash(position, 1.2)
			velocity *= 0.12
	else:
		position += Vector3(velocity.x, 0, velocity.z) * delta
		position.y = world.ocean.height_at(position) - maxf(0, age - 8) * 0.3
		rotation += spin * delta * 0.05
	if age > 24:
		queue_free()

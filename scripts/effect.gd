extends Node3D
## Finite visual effects; owned by the scene so restart clears all of them.
var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var lifetime: float = 1.0
var age: float = 0.0
var gravity: float = 0.0
var grow: float = 0.0
var fade_material: StandardMaterial3D
var fade_alpha: float = 1.0
var heat_decay: float = 0.0
var water: OceanSurface
var follow_water: bool = false

func _process(delta: float) -> void:
	age += delta
	velocity.y -= gravity * delta
	position += velocity * delta
	if follow_water and is_instance_valid(water):
		position.y = water.height_at(position) + 0.15
	rotation += spin * delta
	scale += Vector3.ONE * grow * delta
	if fade_material != null:
		fade_material.albedo_color.a = fade_alpha * clampf((lifetime - age) / (lifetime * 0.55), 0, 1)
		if heat_decay > 0:
			fade_material.emission_energy_multiplier = maxf(0, fade_material.emission_energy_multiplier - heat_decay * delta)
	elif age > lifetime * 0.7:
		scale *= maxf(0.01, 1.0 - delta * 3.0)
	if age >= lifetime:
		queue_free()

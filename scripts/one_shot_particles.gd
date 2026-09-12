extends Node3D
## A burst that cleans itself up once its last particle has died. Used for both
## GPUParticles3D bursts and short-lived sprite flashes.
var ttl: float = 2.0
var counted: bool = false

func _process(delta: float) -> void:
	ttl -= delta
	if ttl <= 0.0:
		queue_free()

func _exit_tree() -> void:
	if counted:
		counted = false
		Vfx.live_bursts = maxi(0, Vfx.live_bursts - 1)

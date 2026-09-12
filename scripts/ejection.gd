extends Node3D
## An ejection seat and its parachute, from the moment the canopy goes to the
## moment the crew hit the water. Purely cosmetic: nothing here is a target,
## does damage, or is read by the game. The kill was already scored when the
## airframe died — this is what the player watches on the way down.

var world: Node3D
var velocity := Vector3.ZERO
var age := 0.0
var phase := "boost"
var spin := Vector3.ZERO
var sway := 0.0
var sway_phase := 0.0
var seat: Node3D
var chute: Node3D
var rigging: Node3D
var trail_clock := 0.0
var settled := 0.0

const BOOST_TIME: float = 0.55   ## Rocket motor burn.
const COAST_TIME: float = 0.85   ## Seat-man separation, then freefall.
const BLOOM_TIME: float = 0.55   ## Canopy filling with air.
const DESCENT: float = 5.5       ## Terminal rate under a full canopy.

func _ready() -> void:
	add_to_group("wreckage")
	build()

func build() -> void:
	var flight := Color("2a2f24")
	var helmet := Color("d8d4c6")
	var frame := Color("343b33")
	# --- the seat: rails, bucket, headbox, and a slumped figure in it -------- #
	seat = Node3D.new()
	add_child(seat)
	var shell := NavalGeometry.Builder.new()
	shell.box(Vector3(0, 0.0, 0.14), Vector3(0.52, 0.72, 0.12), frame)          # back
	shell.box(Vector3(0, -0.34, -0.06), Vector3(0.52, 0.12, 0.46), frame)       # pan
	shell.box(Vector3(0, 0.46, 0.12), Vector3(0.42, 0.24, 0.2), frame)          # headbox
	for side: float in [-1.0, 1.0]:
		shell.box(Vector3(side * 0.3, 0.02, 0.16), Vector3(0.06, 0.86, 0.1), frame.darkened(0.2))
	# Rocket pack under the pan — this is what is smoking on the way up.
	shell.cylinder(Vector3(0, -0.44, 0.16), 0.12, 0.12, 0.34, Color("1b1f1c"), 8,
		Basis(Vector3.RIGHT, PI * 0.5))
	shell.commit(seat, NavalGeometry.steel(Color.WHITE, 0.62, 0.24, true, 0.35), "Seat")
	var crew := NavalGeometry.Builder.new()
	crew.box(Vector3(0, 0.02, -0.04), Vector3(0.36, 0.54, 0.24), flight)        # torso
	crew.dome(Vector3(0, 0.3, -0.04), 0.15, 0.18, helmet, 10, 3)                # helmet
	crew.box(Vector3(0, 0.34, -0.16), Vector3(0.16, 0.1, 0.06), Color("11171a")) # visor
	for side: float in [-1.0, 1.0]:
		crew.tube(Vector3(side * 0.2, 0.12, -0.06), Vector3(side * 0.26, -0.2, -0.18), 0.06, flight)
		crew.tube(Vector3(side * 0.11, -0.28, -0.1), Vector3(side * 0.13, -0.34, -0.42), 0.08, flight)
		crew.tube(Vector3(side * 0.13, -0.34, -0.42), Vector3(side * 0.13, -0.6, -0.36), 0.07, flight)
	crew.commit(seat, NavalGeometry.steel(Color.WHITE, 0.78, 0.05, true, 0.3), "Crew")

	# --- the canopy, gored, hidden until it blooms --------------------------- #
	chute = Node3D.new()
	add_child(chute)
	chute.position = Vector3(0, 3.1, 0)
	chute.visible = false
	var silk := NavalGeometry.Builder.new()
	var gores := 12
	var radius := 3.1
	var height := 1.55
	for gore in range(gores):
		# International orange against off-white, but muted: at this palette a
		# saturated red-and-white canopy reads as a beach parasol.
		var tint := Color("c0562f") if gore % 2 == 0 else Color("cfc9b8")
		tint = tint.darkened(0.06 * float(gore % 3))
		for ring in range(4):
			var a0: float = PI * 0.5 * float(ring) / 4.0
			var a1: float = PI * 0.5 * float(ring + 1) / 4.0
			var t0 := TAU * float(gore) / gores
			var t1 := TAU * float(gore + 1) / gores
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair: Array in [[a0, t0], [a0, t1], [a1, t1], [a1, t0]]:
				# A canopy is not a hemisphere: it bulges near the skirt and
				# flattens over the vent, so the profile is eased, not circular.
				var lift: float = sin(float(pair[0])) 
				var out: float = cos(float(pair[0]) * 0.86)
				var offset := Vector3(out * sin(float(pair[1])) * radius, lift * height,
					out * cos(float(pair[1])) * radius)
				points.append(offset)
				normals.append(offset.normalized())
			silk.smooth_quad(points[0], points[1], points[2], points[3],
				normals[0], normals[1], normals[2], normals[3], tint, tint, tint, tint)
	var cloth := NavalGeometry.material(Color.WHITE)
	cloth.vertex_color_use_as_albedo = true
	cloth.vertex_color_is_srgb = true
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 0.95
	silk.commit(chute, cloth, "Canopy")
	# Shroud lines run from the skirt down to the harness.
	rigging = Node3D.new()
	chute.add_child(rigging)
	var lines := NavalGeometry.Builder.new()
	for line in range(10):
		var angle := TAU * float(line) / 10.0
		# Lines converge on the risers a little above the harness, not on a point.
		lines.tube(Vector3(sin(angle) * radius * 0.96, 0.02, cos(angle) * radius * 0.96),
			Vector3(sin(angle) * 0.16, -2.7, cos(angle) * 0.16), 0.016, Color("d0ccc0"), 4)
	lines.tube(Vector3(0, -2.7, 0), Vector3(0, -3.1, 0), 0.035, Color("c6c2b6"), 5)
	lines.commit(rigging, NavalGeometry.material(Color("cfcbbf")), "Lines")

func _physics_process(delta: float) -> void:
	age += delta
	match phase:
		"boost":
			# Straight up the rails, trailing the rocket motor.
			position += velocity * delta
			velocity.y += 9.0 * delta
			velocity *= 1.0 - delta * 0.5
			rotation += spin * delta * 0.3
			trail_clock += delta
			if trail_clock > 0.035:
				trail_clock = 0.0
				world.smoke_puff(global_position, 0.5, 1.6, Vector3.UP * 2.0,
					Color(0.72, 0.72, 0.7, 0.5), 0.9)
			if age > BOOST_TIME:
				phase = "coast"
				world.cooling_sparks(global_position, 0.5)
		"coast":
			velocity.y -= 9.8 * delta
			velocity *= 1.0 - delta * 0.35
			position += velocity * delta
			rotation += spin * delta
			if age > BOOST_TIME + COAST_TIME:
				phase = "bloom"
				chute.visible = true
				chute.scale = Vector3(0.22, 0.5, 0.22)
				spin = Vector3.ZERO
				rotation = Vector3.ZERO
		"bloom":
			# The canopy snaps open and the fall arrests hard.
			var t: float = clampf((age - BOOST_TIME - COAST_TIME) / BLOOM_TIME, 0.0, 1.0)
			var swell: float = ease(t, 0.35)
			chute.scale = Vector3(lerpf(0.22, 1.0, swell), lerpf(0.5, 1.0, swell),
				lerpf(0.22, 1.0, swell))
			velocity.y = lerpf(velocity.y, -DESCENT, delta * 5.0)
			velocity.x = lerpf(velocity.x, world.OIL_DRIFT.x * 3.0, delta * 2.0)
			velocity.z = lerpf(velocity.z, world.OIL_DRIFT.z * 3.0, delta * 2.0)
			position += velocity * delta
			if t >= 1.0:
				phase = "descent"
				sway = 0.5
		"descent":
			# A canopy under load swings; the swing decays as it settles.
			sway_phase += delta * 1.6
			sway = maxf(0.06, sway - delta * 0.08)
			position += velocity * delta
			position.x += sin(sway_phase) * sway * delta * 9.0
			position.z += cos(sway_phase * 0.8) * sway * delta * 7.0
			rotation.y += delta * 0.4
			rotation.z = sin(sway_phase) * sway * 0.35
			rotation.x = cos(sway_phase * 0.8) * sway * 0.25
			if position.y < world.ocean.height_at(position) + 0.8:
				phase = "down"
				world.splash(position, 0.7)
		"down":
			# Silk collapses onto the water and sinks with the seat.
			settled += delta
			position.y = world.ocean.height_at(position) - settled * 0.25
			chute.scale = Vector3(lerpf(chute.scale.x, 1.5, delta * 1.5),
				maxf(0.04, chute.scale.y - delta * 1.4), lerpf(chute.scale.z, 1.5, delta * 1.5))
			chute.position.y = lerpf(chute.position.y, 0.25, delta * 1.4)
			if settled > 9.0:
				queue_free()

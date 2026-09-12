class_name SupplyCrate
extends Node3D
## An airdropped container bobbing on the swell. Drive over it to take it.
## Repair crates put hull and airframe back; ordnance crates reload missiles.

const REPAIR: int = 0
const ORDNANCE: int = 1
const RADIUS: float = 34.0
const LIFETIME: float = 95.0
## Deliberately not from the HUD palette. A crate is a thing in the world to go
## and get, and it should not be wearing a colour that means a state somewhere.
const REPAIR_GREEN := Color("52e06a")
const ORDNANCE_ORANGE := Color("ff8a2b")

var world: Node3D
var kind: int = REPAIR
var age: float = 0.0
var collected: bool = false
var ring: MeshInstance3D
var halo: MeshInstance3D
var beam: MeshInstance3D
var spin: Node3D

func _ready() -> void:
	add_to_group("supply")
	# A medic's green and an ordnance orange. The amber the ordnance crate used
	# to wear was the same caution colour the HUD gives a merchant and a
	# flooding compartment, so the one crate that reloads your missiles read as
	# a warning; and the repair crate's mint was the hull colour, which made it
	# a piece of your own ship lying in the water.
	var tint := REPAIR_GREEN if kind == REPAIR else ORDNANCE_ORANGE
	spin = Node3D.new()
	add_child(spin)
	var builder := NavalGeometry.Builder.new()
	# Floating pallet with a lidded container on top.
	builder.slab(Vector3(0, 0, 0), Vector2(4.6, 4.6), Vector3(0, 0.5, 0), Vector2(4.2, 4.2), Color("6b6252"))
	builder.slab(Vector3(0, 0.5, 0), Vector2(3.6, 3.6), Vector3(0, 2.6, 0), Vector2(3.3, 3.3), Color("4d5a58"))
	builder.slab(Vector3(0, 2.6, 0), Vector2(3.8, 3.8), Vector3(0, 2.9, 0), Vector2(3.6, 3.6), Color("39443f"))
	for side: float in [-1.0, 1.0]:
		builder.box(Vector3(side * 1.75, 1.5, 0), Vector3(0.16, 1.9, 3.0), Color("2a3336"))
	builder.commit(spin, NavalGeometry.steel(Color.WHITE, 0.62, 0.18, true, 0.22), "Crate")
	# Painted on the lid: a wrench for the repair crate, a rocket for ordnance.
	# A cross and a stack of chevrons are both just "a marking"; these say what
	# is in the box from the height the player actually looks at it.
	var mark := NavalGeometry.Builder.new()
	if kind == REPAIR:
		# Spanner: shaft, and an open jaw at each end.
		mark.box(Vector3(0, 2.92, 0), Vector3(0.62, 0.08, 2.5), tint)
		for end: float in [-1.0, 1.0]:
			mark.box(Vector3(0, 2.92, end * 1.42), Vector3(1.5, 0.08, 0.62), tint)
			for side: float in [-1.0, 1.0]:
				mark.box(Vector3(side * 0.58, 2.92, end * 1.05), Vector3(0.34, 0.08, 0.62), tint)
			# The bite out of the jaw is what makes it a spanner and not a cross.
			mark.box(Vector3(0, 2.93, end * 1.5), Vector3(0.5, 0.08, 0.34), Color("39443f"))
	else:
		# Rocket: nose, body, and a fin either side of the nozzle.
		mark.box(Vector3(0, 2.92, 0.1), Vector3(0.85, 0.08, 2.0), tint)
		mark.slab(Vector3(0, 2.92, -0.9), Vector2(0.85, 0.08), Vector3(0, 2.92, -1.6), Vector2(0.12, 0.08), tint)
		for side: float in [-1.0, 1.0]:
			mark.box(Vector3(side * 0.82, 2.92, 0.95), Vector3(0.8, 0.08, 0.75), tint)
		mark.box(Vector3(0, 2.92, 1.42), Vector3(1.15, 0.08, 0.3), tint)
	mark.commit(spin, NavalGeometry.lamp(), "Marking")
	# A light column so the crate is findable from the tactical camera.
	var column := NavalGeometry.Builder.new()
	column.cylinder(Vector3(0, 15.0, 0), 0.55, 0.2, 30.0, Color(tint.r * 1.6, tint.g * 1.6, tint.b * 1.6, 0.5), 8)
	beam = column.commit(self, beam_material(tint), "Beacon")
	ring = NavalGeometry.ring(self, 9.0, tint, 0.22)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == ORDNANCE:
		# A second ring turning the other way, and a hotter lamp. Ordnance
		# should read as the volatile one from across the water — geometry
		# rather than particles, because these sit around for ninety seconds
		# and a browser pays for every one of them.
		halo = NavalGeometry.ring(self, 6.2, Color("ffcf7a"), 0.16)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := OmniLight3D.new()
	lamp.light_color = tint
	lamp.light_energy = 4.5 if kind == ORDNANCE else 3.0
	lamp.omni_range = 26.0 if kind == ORDNANCE else 22.0
	lamp.shadow_enabled = false
	add_child(lamp)

func beam_material(tint: Color) -> StandardMaterial3D:
	var material := NavalGeometry.material(tint, true)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func label() -> String:
	return "REPAIR" if kind == REPAIR else "ORDNANCE"

func _physics_process(delta: float) -> void:
	if collected:
		return
	age += delta
	position.y = world.ocean.height_at(position) + 0.2 + sin(age * 1.6) * 0.25
	spin.rotation.y += delta * 0.5
	ring.rotation.y -= delta * 0.9
	ring.scale = Vector3.ONE * (1.0 + sin(age * 2.2) * 0.06)
	if is_instance_valid(halo):
		# Counter-rotating and beating faster than the outer ring, so ordnance
		# reads as agitated where repair reads as steady.
		halo.rotation.y += delta * 1.9
		halo.scale = Vector3.ONE * (1.0 + sin(age * 5.4) * 0.12)
		halo.position.y = 0.4 + sin(age * 3.1) * 0.5
	# Fade the beacon out over the last few seconds rather than blinking away.
	var left := LIFETIME - age
	beam.visible = left > 0.0 and fmod(left, 1.0) > 0.25 if left < 12.0 else true
	for unit in world.all_units():
		if unit.team != 0 or not unit.manual or unit.sunk:
			continue
		if unit.position.distance_to(position) < RADIUS:
			apply_to(unit)
			return
	if age > LIFETIME:
		queue_free()

func apply_to(unit: Node3D) -> void:
	collected = true
	var message := ""
	if kind == REPAIR:
		message = unit.take_supplies_repair()
	else:
		message = unit.take_supplies_ordnance()
	world.collect_crate(self, message)
	queue_free()

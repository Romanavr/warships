class_name HelicopterModel
extends RefCounted
## Two original gunship airframes from one parts kit. The heavy variant follows
## the Mi-24 layout — stepped tandem bubbles over a troop cabin, anhedral stub
## wings on heavy pylons, a five-blade head and a port-side tail rotor. The
## light variant is a slimmer tandem-seat machine. Fictional tuning throughout.

# z, half-width, bottom y, top y — the fuselage is lofted through these.
const HIND_STATIONS := [
	[-6.30, 0.24, -0.30, 0.10],
	[-5.85, 0.46, -0.62, 0.42],
	[-5.10, 0.62, -0.78, 0.74],
	[-4.20, 0.72, -0.86, 0.92],
	[-3.30, 0.80, -0.92, 1.30],
	[-2.10, 0.92, -0.98, 1.46],
	[-0.60, 1.02, -1.02, 1.52],
	[1.10, 1.00, -0.98, 1.48],
	[2.30, 0.74, -0.66, 1.16],
	[3.40, 0.50, -0.42, 0.86],
	[4.60, 0.36, -0.26, 0.68],
	[5.80, 0.28, -0.16, 0.58],
]
const LIGHT_STATIONS := [
	[-6.10, 0.18, -0.26, 0.08],
	[-5.60, 0.34, -0.52, 0.34],
	[-4.90, 0.44, -0.64, 0.62],
	[-4.00, 0.50, -0.70, 0.82],
	[-3.10, 0.56, -0.74, 1.12],
	[-2.00, 0.62, -0.78, 1.26],
	[-0.60, 0.66, -0.80, 1.30],
	[1.00, 0.62, -0.74, 1.24],
	[2.20, 0.48, -0.54, 0.98],
	[3.40, 0.36, -0.36, 0.76],
	[4.60, 0.27, -0.22, 0.62],
	[5.80, 0.21, -0.14, 0.54],
]

static func loft_body(builder: NavalGeometry.Builder, stations: Array, paint: Color,
		origin: Vector3 = Vector3.ZERO) -> void:
	for index in range(stations.size() - 1):
		var a: Array = stations[index]
		var b: Array = stations[index + 1]
		builder.beam(
			Vector3(0, (a[2] + a[3]) * 0.5, a[0]) - origin, Vector2(a[1] * 2.0, a[3] - a[2]),
			Vector3(0, (b[2] + b[3]) * 0.5, b[0]) - origin, Vector2(b[1] * 2.0, b[3] - b[2]),
			paint)

## An authored airframe per variant, and how many main-rotor blades it carries.
## Anything without one, or whose file is missing, falls back to the procedural
## build below.
##
## The count has to be stated here because it cannot be read back off the model:
## the build script welds the blades into one mesh so the rotor costs one draw
## call, and a welded rotor cannot say how many blades went into it. Losing that
## number is not cosmetic — `shed_blades()` iterates it, so a rotor that reports
## zero throws nothing off when the aircraft dies.
const AIRFRAMES := {
	"Hind": {"path": "res://assets/models/mi24.glb", "blades": 5},
	"Apache": {"path": "res://assets/models/apache.glb", "blades": 4},
}

static func node_named(root: Node, name: String) -> Node:
	if root.name == name:
		return root
	for child in root.get_children():
		var found := node_named(child, name)
		if found != null:
			return found
	return null

static func build_imported(craft: Node3D, team: int, path: String, blades: int) -> Dictionary:
	## The break-up code tears these apart on death — blades shed, the boom
	## shears, the canopy goes, the crew eject — so the airframe has to arrive
	## already grouped into those assemblies. A missing one means falling back
	## rather than losing the effect silently.
	var scene: PackedScene = load(path)
	if scene == null:
		return {}
	var frame := scene.instantiate()
	craft.add_child(frame)
	var wanted := ["Rotor", "TailRotor", "Blades", "Canopy", "Boom"]
	var nodes: Dictionary = {}
	for name: String in wanted + ["Mount0", "Mount1", "Mount2", "Mount3",
			"AirStore0", "AirStore1"]:
		var found := node_named(frame, name)
		if found == null:
			push_warning("%s is missing '%s'; using the procedural airframe" % [path, name])
			frame.queue_free()
			return {}
		nodes[name] = found
	if team != 0:
		tint(frame)
	var mounts: Array[Node3D] = []
	for index in range(4):
		mounts.append(nodes["Mount%d" % index])
	var stores: Array[MeshInstance3D] = []
	for index in range(2):
		stores.append(nodes["AirStore%d" % index])
	return {
		"mounts": mounts, "air_stores": stores,
		"rotor": nodes["Rotor"], "tail_rotor": nodes["TailRotor"],
		"blades": nodes["Blades"], "disc": null, "canopy": nodes["Canopy"],
		"boom": nodes["Boom"], "blade_count": blades,
		"blade_reach": blade_reach(nodes["Blades"]),
		"seats": [Vector3(0, 0.9, -4.9), Vector3(0, 1.6, -3.4)],
	}

static func blade_reach(blades: Node3D) -> float:
	## How far a shed blade should be built, taken from the model rather than
	## guessed — the two airframes do not carry the same rotor.
	var reach := 0.0
	for child in blades.get_children():
		if child is MeshInstance3D and child.mesh != null:
			reach = maxf(reach, child.mesh.get_aabb().size.length() * 0.5)
	return maxf(reach, 4.0)

static func tint(node: Node) -> void:
	## Hostile airframes wear the same warm wash the hostile hulls do.
	if node is MeshInstance3D:
		var wash := StandardMaterial3D.new()
		wash.albedo_color = Color(0.66, 0.68, 0.46, 1.0)
		wash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wash.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		(node as MeshInstance3D).material_overlay = wash
	for child in node.get_children():
		tint(child)

static func build(craft: Node3D, team: int, variant: String) -> Dictionary:
	var airframe: Dictionary = AIRFRAMES.get(variant, {})
	var authored := String(airframe.get("path", ""))
	if authored != "" and ResourceLoader.exists(authored):
		var imported := build_imported(craft, team, authored, int(airframe.get("blades", 4)))
		if not imported.is_empty():
			return imported
	return build_procedural(craft, team, variant)

static func build_procedural(craft: Node3D, team: int, variant: String) -> Dictionary:
	var heavy := variant != "Apache"
	var paint := Color("46523f") if heavy else Color("3f4b46")
	if team == 0:
		paint = Color("3d4a44") if heavy else Color("3a4640")
	else:
		paint = Color("55573a") if heavy else Color("5a5540")
	var shade := paint.darkened(0.22)
	var dark := Color("1b2124")
	var metal := Color("70776f")
	var canopy := Color("0d181b")

	var hull := NavalGeometry.Builder.new()
	var trim := NavalGeometry.Builder.new()
	var glass := NavalGeometry.Builder.new()
	var lights := NavalGeometry.Builder.new()
	var result := {"mounts": [], "air_stores": []}

	var stations: Array = HIND_STATIONS if heavy else LIGHT_STATIONS
	# The boom is built on its own node from its own station range, so it can
	# shear off in one piece the way a real one does. The ranges share a station
	# so there is no seam while it is still attached.
	var cut: int = stations.size() - 4
	var boom_root := Vector3(0, 0, float(stations[cut][0]))
	var boom := Node3D.new()
	craft.add_child(boom)
	boom.position = boom_root
	result["boom"] = boom
	var boom_hull := NavalGeometry.Builder.new()
	var boom_trim := NavalGeometry.Builder.new()
	loft_body(hull, stations.slice(0, cut + 1), paint)
	loft_body(boom_hull, stations.slice(cut), paint, boom_root)
	var span: float = 2.9 if heavy else 2.3
	var deck: float = 1.52 if heavy else 1.30

	# --- stepped tandem canopies -------------------------------------------- #
	if heavy:
		# Gunner bubble, low and forward.
		glass.beam(Vector3(0, 0.44, -5.55), Vector2(0.78, 0.60), Vector3(0, 0.62, -4.90), Vector2(1.10, 0.78), canopy)
		glass.beam(Vector3(0, 0.62, -4.90), Vector2(1.10, 0.78), Vector3(0, 0.80, -4.15), Vector2(1.24, 0.84), canopy)
		# Pilot bubble, stepped up behind it.
		glass.beam(Vector3(0, 1.12, -4.05), Vector2(1.22, 0.82), Vector3(0, 1.22, -3.30), Vector2(1.42, 0.92), canopy)
		glass.beam(Vector3(0, 1.22, -3.30), Vector2(1.42, 0.92), Vector3(0, 1.20, -2.55), Vector2(1.36, 0.80), canopy)
		trim.box(Vector3(0, 0.86, -4.12), Vector3(1.28, 0.12, 0.12), shade)
		trim.box(Vector3(0, 1.64, -3.40), Vector3(1.3, 0.1, 0.1), shade)
		# Cabin portholes down each side.
		for side: float in [-1.0, 1.0]:
			for index in range(3):
				glass.box(Vector3(side * 1.0, 0.42, -1.3 + index * 1.0), Vector3(0.1, 0.44, 0.58), canopy)
	else:
		glass.beam(Vector3(0, 0.38, -5.40), Vector2(0.58, 0.54), Vector3(0, 0.62, -4.65), Vector2(0.80, 0.74), canopy)
		glass.beam(Vector3(0, 0.98, -4.15), Vector2(0.90, 0.78), Vector3(0, 1.06, -3.25), Vector2(1.04, 0.84), canopy)
		trim.box(Vector3(0, 0.74, -4.40), Vector3(0.94, 0.1, 0.12), shade)

	# --- nose: chin gun turret and sensors ---------------------------------- #
	var chin := Vector3(0, -0.92, -5.55)
	trim.cylinder(chin, 0.34, 0.30, 0.42, dark, 12)
	trim.dome(chin + Vector3(0, -0.2, 0), 0.32, 0.26, dark, 12, 3)
	# Four-barrel gatling under the nose.
	for index in range(4):
		var angle := TAU * float(index) / 4.0
		trim.cylinder(chin + Vector3(sin(angle) * 0.08, -0.06 + cos(angle) * 0.08, -0.75),
			0.05, 0.05, 1.1, Color("141a1c"), 6, Basis(Vector3.RIGHT, PI * 0.5))
	trim.dome(Vector3(0.34, -0.55, -6.05), 0.22, 0.24, Color("1d2529"), 10, 3)
	trim.dome(Vector3(-0.34, -0.55, -6.05), 0.22, 0.24, Color("1d2529"), 10, 3)
	trim.tube(Vector3(0, -0.1, -6.3), Vector3(0, -0.05, -7.05), 0.035, metal, 4)

	# --- engine deck ---------------------------------------------------------#
	var deck_z: float = -0.3 if heavy else -0.5
	for side: float in [-1.0, 1.0]:
		var nacelle := Vector3(side * (0.44 if heavy else 0.36), deck + 0.30, deck_z)
		hull.beam(nacelle + Vector3(0, 0, -1.25), Vector2(0.72, 0.68),
			nacelle + Vector3(0, 0.02, 1.35), Vector2(0.66, 0.62), shade)
		# Dust-filter intake up front, exhaust angled out the back.
		trim.cylinder(nacelle + Vector3(0, 0.06, -1.35), 0.3, 0.26, 0.34, dark, 12,
			Basis(Vector3.RIGHT, PI * 0.5))
		trim.cylinder(nacelle + Vector3(side * 0.16, 0.06, 1.5), 0.26, 0.3, 0.5, Color("23282a"), 12,
			Basis(Vector3.UP, side * 0.4) * Basis(Vector3.RIGHT, PI * 0.5))
	if heavy:
		# Spine fairing between the engines.
		hull.beam(Vector3(0, deck + 0.26, -1.6), Vector2(0.9, 0.5), Vector3(0, deck + 0.24, 1.5), Vector2(0.8, 0.46), shade)

	# --- main rotor ----------------------------------------------------------#
	var mast := Vector3(0, deck + (0.62 if heavy else 0.54), deck_z + 0.1)
	trim.cylinder(mast + Vector3(0, 0.18, 0), 0.24, 0.2, 0.8, metal.darkened(0.2), 10)
	var rotor := Node3D.new()
	craft.add_child(rotor)
	rotor.position = mast + Vector3(0, 0.68, 0)
	var head := NavalGeometry.Builder.new()
	head.cylinder(Vector3(0, -0.1, 0), 0.34, 0.3, 0.32, Color("4a534e"), 12)
	head.dome(Vector3(0, 0.06, 0), 0.3, 0.26, Color("57605a"), 12, 3)
	var blade_count := 5 if heavy else 4
	for index in range(blade_count):
		var spin := Basis(Vector3.UP, TAU * float(index) / blade_count)
		head.box(spin * Vector3(0, 0.02, -0.55), Vector3(0.14, 0.12, 0.7), Color("39423e"), spin)
		head.cylinder(spin * Vector3(0, 0.02, -0.95), 0.07, 0.07, 0.7, Color("2f3835"), 6,
			spin * Basis(Vector3.RIGHT, PI * 0.5))
	head.commit(rotor, NavalGeometry.steel(Color.WHITE, 0.45, 0.45, true, 0.4), "Head")
	var blades := NavalGeometry.Builder.new()
	var reach: float = 5.7 if heavy else 5.1
	for index in range(blade_count):
		var spin := Basis(Vector3.UP, TAU * float(index) / blade_count)
		# Slight coning droop, squared tip.
		blades.beam(spin * Vector3(0, 0.0, -1.2) + Vector3(0, 0, 0), Vector2(0.34, 0.09),
			spin * Vector3(0, -0.12, -reach), Vector2(0.30, 0.07), Color("222a2c"))
		blades.box(spin * Vector3(0, -0.12, -reach), Vector3(0.3, 0.07, 0.18), Color("b0a898"), spin)
	result["blades"] = blades.commit(rotor, NavalGeometry.steel(Color.WHITE, 0.55, 0.15, true, 0.25), "Blades")
	result["blade_count"] = blade_count
	result["blade_reach"] = reach
	# A faint disc so the rotor reads as turning rather than strobing.
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = reach * 0.98
	disc_mesh.bottom_radius = reach * 0.98
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 32
	disc_mesh.rings = 0
	disc.mesh = disc_mesh
	var haze := StandardMaterial3D.new()
	haze.albedo_color = Color(0.72, 0.74, 0.72, 0.09)
	haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	haze.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = haze
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	craft.add_child(disc)
	disc.position = rotor.position - Vector3(0, 0.06, 0)
	result["disc"] = disc

	# --- stub wings, anhedral, with pylons ----------------------------------- #
	var wing_root := Vector3(0, -0.25 if heavy else -0.35, 0.1)
	var droop: float = 0.55 if heavy else 0.3
	for side: float in [-1.0, 1.0]:
		var tip := wing_root + Vector3(side * span, -droop, 0.15)
		hull.beam(wing_root + Vector3(side * 0.55, -droop * 0.19, 0), Vector2(2.1, 0.46),
			tip, Vector2(1.45, 0.34), paint)
		# End plate on the heavy wing.
		if heavy:
			hull.beam(tip + Vector3(0, -0.22, 0), Vector2(0.95, 0.1), tip + Vector3(0, 0.34, 0), Vector2(0.7, 0.1), shade)
		# Rocket pod on the outer pylon.
		var pod := tip + Vector3(-side * 0.42, -0.34, -0.1)
		trim.cylinder(pod, 0.34, 0.34, 2.0, shade, 12, Basis(Vector3.RIGHT, PI * 0.5))
		trim.cylinder(pod + Vector3(0, 0, -1.02), 0.31, 0.31, 0.08, Color("10161a"), 12, Basis(Vector3.RIGHT, PI * 0.5))
		trim.box(pod + Vector3(0, 0.4, 0.1), Vector3(0.12, 0.5, 1.1), shade)
		# Guided anti-ship rounds belong to the corvettes, so the inboard
		# stations carry a second rocket pod instead. The mounts stay: they are
		# the launch origins the rockets leave from.
		var inboard := wing_root + Vector3(side * (span * 0.42), -droop * 0.42 - 0.34, -0.1)
		trim.cylinder(inboard, 0.28, 0.28, 1.7, shade, 12, Basis(Vector3.RIGHT, PI * 0.5))
		trim.cylinder(inboard + Vector3(0, 0, -0.87), 0.25, 0.25, 0.07, Color("10161a"), 12, Basis(Vector3.RIGHT, PI * 0.5))
		trim.box(inboard + Vector3(0, 0.34, 0.1), Vector3(0.1, 0.42, 0.95), shade)
		for index in range(2):
			var mount := Node3D.new()
			craft.add_child(mount)
			mount.position = pod if index == 0 else inboard
			result["mounts"].append(mount)
		# Wingtip launch tubes.
		var rail := NavalGeometry.Builder.new()
		for tube in range(2):
			rail.cylinder(Vector3(0, float(tube) * 0.3, 0), 0.13, 0.13, 1.5, Color("6d7264"), 10,
				Basis(Vector3.RIGHT, PI * 0.5))
			rail.cylinder(Vector3(0, float(tube) * 0.3, -0.78), 0.12, 0.12, 0.07, Color("14191b"), 10,
				Basis(Vector3.RIGHT, PI * 0.5))
		var store := rail.commit(craft, NavalGeometry.steel(Color.WHITE, 0.5, 0.25, true, 0.35), "AirStore")
		store.position = tip + Vector3(side * 0.1, -0.1, -0.2)
		result["air_stores"].append(store)

	# --- tail ----------------------------------------------------------------#
	var fin_base := Vector3(0, 0.5, 5.5) - boom_root
	boom_hull.beam(fin_base + Vector3(0, 0, -0.9), Vector2(0.24, 1.5), fin_base + Vector3(0, 1.75, 0.55), Vector2(0.2, 1.15), paint)
	boom_hull.beam(fin_base + Vector3(0, -0.55, -0.5), Vector2(0.2, 0.9), fin_base + Vector3(0, -1.25, 0.35), Vector2(0.16, 0.6), shade)
	# Horizontal stabiliser.
	for side: float in [-1.0, 1.0]:
		boom_hull.beam(Vector3(side * 0.12, 0.34, 4.5) - boom_root, Vector2(0.95, 0.14),
			Vector3(side * 1.2, 0.30, 4.58) - boom_root, Vector2(0.62, 0.11), paint)
	# Tail rotor, port side on the heavy machine.
	var tail_side: float = -1.0 if heavy else 1.0
	var tail := Node3D.new()
	boom.add_child(tail)
	tail.position = fin_base + Vector3(tail_side * 0.28, 1.35, 0.2)
	tail.rotation = Vector3(0, 0, PI * 0.5)
	var tail_builder := NavalGeometry.Builder.new()
	tail_builder.cylinder(Vector3.ZERO, 0.16, 0.14, 0.26, Color("39433f"), 10)
	var tail_blades := 3 if heavy else 4
	for index in range(tail_blades):
		var spin := Basis(Vector3.UP, TAU * float(index) / tail_blades)
		tail_builder.beam(spin * Vector3(0, 0, -0.2), Vector2(0.2, 0.06),
			spin * Vector3(0, 0, -1.35), Vector2(0.17, 0.05), Color("232d30"))
	tail_builder.commit(tail, NavalGeometry.steel(Color.WHITE, 0.55, 0.15, true, 0.3), "TailRotor")

	# --- landing gear --------------------------------------------------------#
	if heavy:
		for side: float in [-1.0, 1.0]:
			var leg := Vector3(side * 1.15, -1.0, 0.9)
			hull.beam(leg + Vector3(0, 0.1, -0.7), Vector2(0.55, 0.6), leg + Vector3(0, 0.05, 0.7), Vector2(0.5, 0.55), shade)
			trim.tube(leg, leg + Vector3(side * 0.18, -0.85, 0.05), 0.08, dark, 6)
			trim.cylinder(leg + Vector3(side * 0.2, -0.95, 0.05), 0.32, 0.32, 0.24, Color("15191b"), 12,
				Basis(Vector3.FORWARD, PI * 0.5))
		trim.tube(Vector3(0, -0.8, -4.3), Vector3(0, -1.5, -4.4), 0.07, dark, 6)
		trim.cylinder(Vector3(0, -1.58, -4.4), 0.22, 0.22, 0.18, Color("15191b"), 10, Basis(Vector3.FORWARD, PI * 0.5))
	else:
		for side: float in [-1.0, 1.0]:
			trim.tube(Vector3(side * 0.6, -0.75, -0.4), Vector3(side * 1.1, -1.75, -0.2), 0.07, dark, 6)
			trim.cylinder(Vector3(side * 1.1, -1.85, -0.2), 0.28, 0.28, 0.2, Color("15191b"), 10,
				Basis(Vector3.FORWARD, PI * 0.5))
		boom_trim.tube(Vector3(0, -0.3, 4.9) - boom_root, Vector3(0, -1.0, 5.1) - boom_root, 0.055, dark, 6)
		boom_trim.cylinder(Vector3(0, -1.06, 5.1) - boom_root, 0.15, 0.15, 0.12, Color("15191b"), 8,
			Basis(Vector3.FORWARD, PI * 0.5))

	# --- aerials and lights --------------------------------------------------#
	trim.tube(Vector3(0, deck + 0.1, -2.0), Vector3(0, deck + 0.75, -2.0), 0.028, metal, 4)
	for side: float in [-1.0, 1.0]:
		trim.tube(Vector3(side * 0.6, -0.9, 1.9), Vector3(side * 0.75, -1.2, 2.6), 0.03, metal, 4)
	lights.box(Vector3(-span - 0.1, wing_root.y - droop, 0.2), Vector3(0.16, 0.14, 0.18), Color(1.0, 0.2, 0.18))
	lights.box(Vector3(span + 0.1, wing_root.y - droop, 0.2), Vector3(0.16, 0.14, 0.18), Color(0.24, 1.0, 0.45))
	lights.box(Vector3(0, deck + 0.5, 1.9), Vector3(0.14, 0.14, 0.14), Color(1.0, 0.35, 0.3))
	lights.box(Vector3(0, -1.05, -2.6), Vector3(0.14, 0.12, 0.14), Color(1.0, 0.95, 0.85))

	hull.commit(craft, NavalGeometry.steel(Color.WHITE, 0.62, 0.16, true, 0.16), "Airframe")
	trim.commit(craft, NavalGeometry.steel(Color.WHITE, 0.5, 0.35, true, 0.3), "Fittings")
	boom_hull.commit(boom, NavalGeometry.steel(Color.WHITE, 0.62, 0.16, true, 0.16), "Boom")
	if not boom_trim.is_empty():
		boom_trim.commit(boom, NavalGeometry.steel(Color.WHITE, 0.5, 0.35, true, 0.3), "BoomFittings")
	result["canopy"] = glass.commit(craft, NavalGeometry.glass(Color("0b1518")), "Canopy")
	lights.commit(craft, NavalGeometry.lamp(), "Lights")
	result["rotor"] = rotor
	result["tail_rotor"] = tail
	# Where the crew sit, so the seats go out of the right holes. Tandem on the
	# heavy machine: gunner forward and low, pilot stepped up behind.
	result["seats"] = ([Vector3(0, 0.62, -4.85), Vector3(0, 1.24, -3.55)] if heavy
		else [Vector3(0, 0.5, -5.0), Vector3(0, 1.05, -3.7)])
	return result

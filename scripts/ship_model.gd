class_name ShipModel
extends RefCounted
## Procedural corvette: a lofted hull with sheer, flare, bilge turn and a
## transom, plus an angular low-observable superstructure. Everything is
## batched into a handful of surfaces; only moving or separately damageable
## parts get their own mesh.

# z, deck half-beam, deck height, waterline half-beam, bilge half-beam, bilge y, keel y
const STATIONS := [
	[-27.0, 0.20, 5.35, 0.08, 0.06, -0.30, -0.75],
	[-25.0, 1.00, 5.10, 0.42, 0.26, -0.80, -1.35],
	[-22.0, 2.15, 4.78, 1.15, 0.72, -1.25, -1.95],
	[-18.0, 3.30, 4.42, 2.30, 1.55, -1.65, -2.45],
	[-13.5, 4.25, 4.05, 3.45, 2.60, -1.95, -2.80],
	[-9.0, 4.72, 3.78, 4.15, 3.30, -2.05, -2.95],
	[-4.0, 5.00, 3.52, 4.70, 3.90, -2.10, -3.02],
	[0.0, 5.10, 3.38, 4.95, 4.15, -2.10, -3.05],
	[4.5, 5.12, 3.28, 5.05, 4.30, -2.05, -3.02],
	[9.0, 5.08, 3.20, 5.05, 4.35, -1.98, -2.95],
	[14.0, 4.98, 3.14, 5.00, 4.35, -1.85, -2.80],
	[19.0, 4.85, 3.10, 4.90, 4.32, -1.70, -2.55],
	[23.0, 4.72, 3.10, 4.78, 4.25, -1.55, -2.25],
	[27.0, 4.58, 3.12, 4.62, 4.15, -1.40, -1.95],
]
const BOW_END := 5      # station index where the bow compartment ends
const MID_END := 9      # and the citadel

const SEGMENT_MAP := {
	0: [0, 1, 2, 3, 4, 5, 6],       # 0
	1: [1, 2],
	2: [0, 1, 6, 4, 3],
	3: [0, 1, 6, 2, 3],
	4: [5, 6, 1, 2],
	5: [0, 5, 6, 2, 3],
	6: [0, 5, 6, 4, 3, 2],
	7: [0, 1, 2],
	8: [0, 1, 2, 3, 4, 5, 6],
	9: [0, 1, 5, 6, 2, 3],
}
const SEGMENT_RECTS := [
	Rect2(0.08, 1.44, 0.84, 0.16), Rect2(0.84, 0.82, 0.16, 0.70),
	Rect2(0.84, 0.08, 0.16, 0.70), Rect2(0.08, 0.00, 0.84, 0.16),
	Rect2(0.00, 0.08, 0.16, 0.70), Rect2(0.00, 0.82, 0.16, 0.70),
	Rect2(0.08, 0.72, 0.84, 0.16),
]

# --------------------------------------------------------------------------- #
# Hull surface sampling
# --------------------------------------------------------------------------- #

static func station_at(z: float) -> Array:
	## Linear interpolation of the station table, so fittings can sit exactly
	## on the deck edge wherever they are placed.
	if z <= STATIONS[0][0]:
		return STATIONS[0]
	for index in range(STATIONS.size() - 1):
		var a: Array = STATIONS[index]
		var b: Array = STATIONS[index + 1]
		if z <= b[0]:
			var t: float = (z - a[0]) / (b[0] - a[0])
			var row: Array = []
			for column in range(7):
				row.append(lerpf(a[column], b[column], t))
			return row
	return STATIONS[STATIONS.size() - 1]

static func deck_half(z: float) -> float:
	return station_at(z)[1]

static func deck_y(z: float) -> float:
	return station_at(z)[2]

static func topside_point(z: float, y: float, side: float) -> Vector3:
	## A point on the painted topside, following the flare of the hull.
	var row := station_at(z)
	var height: float = maxf(row[2], 0.1)
	var x: float = lerpf(row[3], row[1], clampf(y / height, 0.0, 1.0))
	return Vector3(x * side, y, z)

static func section(row: Array) -> Array:
	## Nine points from the deck edge down to the keel, one half-section.
	var deck_w: float = row[1]
	var height: float = maxf(row[2], 0.1)
	var wl: float = row[3]
	var bilge: float = row[4]
	var bilge_y: float = row[5]
	var keel_y: float = row[6]
	var under: float = maxf(-bilge_y, 0.05)
	return [
		Vector2(deck_w, row[2]),
		Vector2(lerpf(wl, deck_w, 0.60), height * 0.60),
		Vector2(lerpf(wl, deck_w, clampf(1.10 / height, 0.0, 1.0)), 1.10),
		Vector2(lerpf(wl, deck_w, clampf(0.42 / height, 0.0, 1.0)), 0.42),
		Vector2(lerpf(wl, bilge, clampf(0.42 / under, 0.0, 1.0)), -0.42),
		Vector2(lerpf(wl, bilge, 0.55), bilge_y * 0.55),
		Vector2(bilge, bilge_y),
		Vector2(bilge * 0.52, lerpf(bilge_y, keel_y, 0.60)),
		Vector2(0.0, keel_y),
	]

static func plate_color(index: int, hull: Color, boot: Color, anti: Color) -> Color:
	if index <= 2:
		return hull
	if index <= 4:
		return boot
	return anti

# --------------------------------------------------------------------------- #
# Hull
# --------------------------------------------------------------------------- #

static func loft(builder: NavalGeometry.Builder, first: int, last: int,
		hull: Color, boot: Color, anti: Color, deck: Color, transom: bool) -> void:
	var grid: Array = []
	for row in STATIONS:
		var points: Array = []
		for point: Vector2 in section(row):
			points.append(Vector3(point.x, point.y, row[0]))
		grid.append(points)
	builder.smooth(7000)
	for index in range(first, last):
		for j in range(8):
			var a: Vector3 = grid[index][j]
			var b: Vector3 = grid[index + 1][j]
			var c: Vector3 = grid[index + 1][j + 1]
			var d: Vector3 = grid[index][j + 1]
			var na := _normal(grid, index, j)
			var nb := _normal(grid, index + 1, j)
			var nc := _normal(grid, index + 1, j + 1)
			var nd := _normal(grid, index, j + 1)
			var top := plate_color(j, hull, boot, anti)
			var low := plate_color(j + 1, hull, boot, anti)
			builder.smooth_quad(a, b, c, d, na, nb, nc, nd, top, top, low, low)
			var ma := Vector3(-a.x, a.y, a.z)
			var mb := Vector3(-b.x, b.y, b.z)
			var mc := Vector3(-c.x, c.y, c.z)
			var md := Vector3(-d.x, d.y, d.z)
			builder.smooth_quad(ma, md, mc, mb,
				Vector3(-na.x, na.y, na.z), Vector3(-nd.x, nd.y, nd.z),
				Vector3(-nc.x, nc.y, nc.z), Vector3(-nb.x, nb.y, nb.z),
				top, low, low, top)
	builder.smooth(-1)
	# Weather deck.
	for index in range(first, last):
		var a: Vector3 = grid[index][0]
		var b: Vector3 = grid[index + 1][0]
		builder.quad(Vector3(-a.x, a.y, a.z), Vector3(-b.x, b.y, b.z), b, a, deck)
	if not transom:
		return
	var stern: Array = grid[STATIONS.size() - 1]
	for j in range(8):
		var p0: Vector3 = stern[j]
		var p1: Vector3 = stern[j + 1]
		var shade := plate_color(j, hull, boot, anti).darkened(0.05)
		builder.quad(Vector3(-p0.x, p0.y, p0.z), Vector3(-p1.x, p1.y, p1.z), p1, p0, shade)

static func _normal(grid: Array, index: int, j: int) -> Vector3:
	var previous: int = maxi(index - 1, 0)
	var following: int = mini(index + 1, grid.size() - 1)
	var up: int = maxi(j - 1, 0)
	var down: int = mini(j + 1, 8)
	var along: Vector3 = grid[following][j] - grid[previous][j]
	var across: Vector3 = grid[index][down] - grid[index][up]
	var normal := along.cross(across)
	if normal.length_squared() < 1e-9:
		return Vector3.RIGHT
	return normal.normalized()

# --------------------------------------------------------------------------- #
# Assembly
# --------------------------------------------------------------------------- #

## One authored hull per class. A class with no entry falls back to the
## corvette, and a missing file falls back to the procedural hull.
const HULLS := {
	"": "res://assets/models/saar6.glb",
	"corvette": "res://assets/models/saar6.glb",
	"fac": "res://assets/models/tern.glb",
}
const HULL_SCENE: String = "res://assets/models/saar6.glb"

static func build(visuals: Node3D, team: int, compact: bool, hull_number: String,
		hull_model: String = "") -> Dictionary:
	## A class with a model of its own is dispatched first: the authored hull
	## below is the corvette, and it answers for every warship in the game.
	if hull_model == "cargo":
		return build_cargo(visuals, hull_number)
	## Prefer the authored hull if it is present; fall back to the procedural
	## one so the project still runs with no assets at all.
	var scene_path: String = String(HULLS.get(hull_model, HULL_SCENE))
	if ResourceLoader.exists(scene_path):
		var imported := build_imported(visuals, team, scene_path, ShipLayout.of(hull_model))
		if not imported.is_empty():
			return imported
	return build_procedural(visuals, team, compact, hull_number)

static func index_nodes(node: Node, into: Dictionary) -> void:
	into[String(node.name)] = node
	for child in node.get_children():
		index_nodes(child, into)

static func child_starting(node: Node, prefix: String) -> Node:
	for child in node.get_children():
		if String(child.name).begins_with(prefix):
			return child
	return null

static func hostile_overlay() -> StandardMaterial3D:
	## Hostile hulls wear a warm wash over the authored paint. An overlay pass
	## keeps every original material intact — per-surface overrides trip a
	## null-material warning in the renderer on this build.
	# Multiply, not mix. A mix blend paints a flat colour over the hull and
	# takes the panel detail with it; multiplying darkens and shifts the hue
	# while every bit of relative contrast survives underneath.
	var wash := StandardMaterial3D.new()
	wash.albedo_color = Color(0.63, 0.66, 0.42, 1.0)
	wash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wash.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	wash.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	wash.disable_receive_shadows = true
	return wash

static func tint_ship(node: Node, wash: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = wash
	for child in node.get_children():
		tint_ship(child, wash)

## Steady light colours, shared by every hull so a merchant and a corvette agree.
const PORT_LIGHT := Color(1.0, 0.2, 0.18)
const STARBOARD_LIGHT := Color(0.24, 1.0, 0.45)
const WHITE_LIGHT := Color(1.0, 0.95, 0.86)
const BEACON_LIGHT := Color(1.0, 0.28, 0.2)

static func navigation_lights(visuals: Node3D, layout: Dictionary) -> Dictionary:
	## Sidelights, masthead and stern light, positioned off the hull's own module
	## boxes rather than typed in. Those boxes already agree with the geometry —
	## that is what they are for — so a class half the length gets its lights in
	## the right places without a second table to keep in step.
	##
	## The authored hulls arrive with none of this. The procedural hull and the
	## cargo ship have carried running lights all along, which is why the warships
	## were the only things afloat without them.
	var modules: Dictionary = layout.get("modules", {})
	if not modules.has("bridge") or not modules.has("stern") or not modules.has("mid"):
		return {}
	var bridge: Array = modules["bridge"]
	var bridge_at: Vector3 = bridge[1]
	var bridge_size: Vector3 = bridge[2]
	var stern: Array = modules["stern"]
	var stern_at: Vector3 = stern[1]
	var stern_size: Vector3 = stern[2]
	var mid: Array = modules["mid"]
	var mid_at: Vector3 = mid[1]
	var mid_size: Vector3 = mid[2]
	# One unit is the corvette's bridge beam, so every lamp scales with the class.
	var unit: float = maxf(0.35, bridge_size.x / 7.6)
	# A screened sidelight is a hand's width of glass in a hood, not a signboard.
	# At a metre square these read as hazard panels bolted to the deckhouse.
	var lamp := Vector3(0.5, 0.66, 0.36) * unit

	var lights := NavalGeometry.Builder.new()
	# Sidelights hang off the bridge wings, which means outboard of the hull's
	# beam and clear of the superstructure — not off the bridge box, which is
	# narrower than the deckhouse the authored hull actually carries and buries
	# both lamps inside it.
	var wing: float = mid_size.x * 0.5 + lamp.x * 0.35
	var wing_y: float = mid_at.y + mid_size.y * 0.5 + lamp.y * 2.2
	var wing_z: float = bridge_at.z - bridge_size.z * 0.3
	lights.box(Vector3(-wing, wing_y, wing_z), lamp, PORT_LIGHT)
	lights.box(Vector3(wing, wing_y, wing_z), lamp, STARBOARD_LIGHT)
	# Masthead, above the search radar if the class carries one, otherwise above
	# the bridge; and a stern light right aft.
	var mast_at: Vector3 = bridge_at
	var mast_size: Vector3 = bridge_size
	if modules.has("radar"):
		mast_at = (modules["radar"] as Array)[1]
		mast_size = (modules["radar"] as Array)[2]
	var mast_y: float = mast_at.y + mast_size.y * 0.5 + lamp.y
	lights.box(Vector3(0, mast_y, mast_at.z), Vector3(0.62, 0.62, 0.62) * unit, WHITE_LIGHT)
	lights.box(Vector3(0, stern_at.y + stern_size.y * 0.5 + lamp.y * 2.0,
		stern_at.z + stern_size.z * 0.46), Vector3(0.58, 0.58, 0.58) * unit, WHITE_LIGHT)
	var steady := lights.commit(visuals, NavalGeometry.lamp(), "NavigationLights")
	steady.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visuals.set_meta("navigation_lights", steady)

	# The anti-collision beacon is its own mesh because it is the only one that
	# does anything: PatrolBoat blinks it, and you cannot blink one corner of a
	# batched surface.
	var flasher := NavalGeometry.Builder.new()
	flasher.box(Vector3(0, mast_y + lamp.y * 2.2, mast_at.z),
		Vector3(0.55, 0.55, 0.55) * unit, BEACON_LIGHT)
	var beacon := flasher.commit(visuals, NavalGeometry.lamp(), "Beacon")
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"beacon": beacon}

static func build_imported(visuals: Node3D, team: int,
		scene_path: String = HULL_SCENE, layout: Dictionary = {}) -> Dictionary:
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return {}
	var hull := scene.instantiate()
	visuals.add_child(hull)
	var nodes: Dictionary = {}
	index_nodes(hull, nodes)
	var wanted := ["bow", "mid", "stern", "gun", "aft_gun", "engine", "rudder", "bridge",
		"radar", "launcher_port", "launcher_starboard", "ciws", "sam"]
	var mounts := ["gunPivot", "aft_gunPivot", "CiwsPivot", "RadarPivot"]
	for id: String in wanted + mounts:
		if not nodes.has(id):
			push_warning("%s is missing '%s'; using the procedural hull" % [scene_path, id])
			hull.queue_free()
			return {}
	var meshes: Dictionary = {}
	for id: String in wanted:
		meshes[id] = nodes[id]
	var result := {"system_meshes": meshes, "cell_lids": [], "cell_muzzles": [],
		"sam_lids": [], "sam_muzzles": [],
		"turret": nodes["gunPivot"], "aft_turret": nodes["aft_gunPivot"],
		"ciws_turret": nodes["CiwsPivot"], "radar_mount": nodes["RadarPivot"],
		"barrel": child_starting(nodes["gunPivot"], "Barrel"),
		"aft_barrel": child_starting(nodes["aft_gunPivot"], "Barrel")}
	for index in range(4):
		result["cell_lids"].append(nodes.get("CellLid%d" % index))
		result["cell_muzzles"].append(nodes.get("CellMuzzle%d" % index))
		result["sam_lids"].append(nodes.get("SamLid%d" % index))
		result["sam_muzzles"].append(nodes.get("SamMuzzle%d" % index))
	for key: String in ["barrel", "aft_barrel"]:
		if result[key] == null:
			push_warning("%s has no %s; using the procedural hull" % [scene_path, key])
			hull.queue_free()
			return {}
	for slot: Array in [result["cell_lids"], result["cell_muzzles"], result["sam_lids"], result["sam_muzzles"]]:
		if slot.has(null):
			push_warning("%s is missing launch cell nodes; using the procedural hull" % scene_path)
			hull.queue_free()
			return {}
	if team != 0:
		tint_ship(hull, hostile_overlay())
	# After the tint: the wash is applied by walking the imported hull, and the
	# lights are siblings of it, so they keep their own colours either way.
	result.merge(navigation_lights(visuals, layout))
	return result

static func build_procedural(visuals: Node3D, team: int, compact: bool, hull_number: String) -> Dictionary:
	var hull := Color("5c6a72") if team == 0 else Color("6a6455")
	var house := Color("68767e") if team == 0 else Color("746d5e")
	var deck := Color("38454a") if team == 0 else Color("44403a")
	var boot := Color("1e2427")
	var anti := Color("6a3a30")
	var dark := Color("242e33")
	var pale := Color("8e9a98")

	var steel := NavalGeometry.steel(Color.WHITE, 0.66, 0.13, true, 0.075)
	var detail_material := NavalGeometry.steel(Color.WHITE, 0.52, 0.24, true, 0.16)
	var glass_material := NavalGeometry.glass()
	var lamp_material := NavalGeometry.lamp()

	var result := {"system_meshes": {}, "cell_lids": [], "cell_muzzles": [],
		"sam_lids": [], "sam_muzzles": []}
	var meshes: Dictionary = result["system_meshes"]

	# --- hull, split so each compartment can be damaged and charred alone ---
	for part: Array in [["bow", 0, BOW_END, false], ["mid", BOW_END, MID_END, false],
			["stern", MID_END, STATIONS.size() - 1, true]]:
		var builder := NavalGeometry.Builder.new()
		loft(builder, part[1], part[2], hull, boot, anti, deck, part[3])
		var mesh := builder.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.66, 0.13, true, 0.075), part[0] as String)
		meshes[part[0]] = mesh

	var body := NavalGeometry.Builder.new()
	var trim := NavalGeometry.Builder.new()
	var glazing := NavalGeometry.Builder.new()
	var lights := NavalGeometry.Builder.new()

	_bulwark(body, hull, deck, dark)
	_deck_fittings(trim, house, dark, pale, compact)
	_superstructure(visuals, body, trim, glazing, lights, meshes, house, deck, dark, pale, compact)
	_flight_deck(body, trim, deck, house, dark, pale, compact)
	_hull_number(body, hull_number, pale)
	_navigation_lights(lights)

	body.commit(visuals, steel, "HullDetail")
	trim.commit(visuals, detail_material, "Fittings")
	glazing.commit(visuals, glass_material, "Glazing")
	lights.commit(visuals, lamp_material, "Lights")

	_weapons(visuals, result, meshes, house, hull, dark, pale, compact)
	result["barrel"] = result["turret"].get_node("Barrel")
	result["aft_barrel"] = result["aft_turret"].get_node("Barrel")
	result["radar_mount"] = meshes["radar"].get_parent()
	return result

# --------------------------------------------------------------------------- #

static func _bulwark(builder: NavalGeometry.Builder, hull: Color, deck: Color, dark: Color) -> void:
	## Raised forward bulwark and breakwater: the forecastle silhouette.
	var previous_z := -26.4
	while previous_z < -12.0:
		var next_z: float = minf(previous_z + 1.6, -12.0)
		var height: float = lerpf(1.35, 0.55, (previous_z + 26.4) / 14.4)
		for side in [-1.0, 1.0]:
			var a := Vector3(deck_half(previous_z) * side, deck_y(previous_z), previous_z)
			var b := Vector3(deck_half(next_z) * side, deck_y(next_z), next_z)
			builder.slab(a, Vector2(0.3, next_z - previous_z),
				a + Vector3((b.x - a.x) * 0.5 - side * 0.18, height + (b.y - a.y) * 0.5, (next_z - previous_z) * 0.5),
				Vector2(0.22, next_z - previous_z), hull)
			builder.slab(a + Vector3(0, height, 0), Vector2(0.44, next_z - previous_z),
				a + Vector3((b.x - a.x) * 0.5 - side * 0.18, height + 0.12 + (b.y - a.y) * 0.5, (next_z - previous_z) * 0.5),
				Vector2(0.44, next_z - previous_z), dark)
		previous_z = next_z
	# Breakwater plate, angled to throw spray outboard.
	var edge := deck_half(-13.2)
	builder.slab(Vector3(0, deck_y(-13.2), -13.2), Vector2(edge * 2.0, 0.3),
		Vector3(0, deck_y(-13.2) + 1.15, -12.4), Vector2(edge * 1.55, 0.3), deck)
	# Anchor pockets.
	for side in [-1.0, 1.0]:
		var point := topside_point(-23.0, 3.0, side)
		builder.box(point + Vector3(side * 0.05, 0, 0), Vector3(0.32, 1.15, 1.6), Color("18201f"))
		builder.box(point + Vector3(side * 0.18, -0.05, 0), Vector3(0.14, 0.85, 1.2), Color("3d4548"))

static func _deck_fittings(builder: NavalGeometry.Builder, house: Color, dark: Color,
		pale: Color, compact: bool) -> void:
	## Railings, bollards, rafts and ladders: the small stuff that gives scale.
	var rail_zones := [[-11.5, 26.0]] if not compact else [[-11.5, 24.0]]
	for zone: Array in rail_zones:
		for side in [-1.0, 1.0]:
			var z: float = zone[0]
			var stanchion_color := pale.darkened(0.35)
			while z < zone[1]:
				var half := deck_half(z) - 0.22
				var base := Vector3(half * side, deck_y(z), z)
				builder.tube(base, base + Vector3.UP * 1.05, 0.045, stanchion_color, 5)
				var next_z: float = minf(z + 2.2, zone[1])
				var next_half := deck_half(next_z) - 0.22
				var next_base := Vector3(next_half * side, deck_y(next_z), next_z)
				for level in [0.42, 0.72, 1.02]:
					builder.tube(base + Vector3.UP * level, next_base + Vector3.UP * level, 0.032, stanchion_color, 4)
				z = next_z
	# Bollards and fairleads fore and aft.
	for z in [-24.0, -20.5, 20.0, 24.5]:
		for side in [-1.0, 1.0]:
			var base := Vector3((deck_half(z) - 0.55) * side, deck_y(z), z)
			builder.cylinder(base + Vector3.UP * 0.28, 0.17, 0.17, 0.56, dark, 8)
			builder.cylinder(base + Vector3.UP * 0.6, 0.24, 0.2, 0.12, dark, 8)
	# Capstan and windlass on the forecastle.
	builder.cylinder(Vector3(0, deck_y(-21.0) + 0.3, -21.0), 0.6, 0.5, 0.6, house.darkened(0.15), 12)
	builder.box(Vector3(0, deck_y(-21.0) + 0.75, -21.0), Vector3(1.5, 0.5, 1.1), dark)
	# Liferaft canisters on the outboard rails.
	for z in [6.0, 8.4] if not compact else [7.0]:
		for side in [-1.0, 1.0]:
			var base := Vector3((deck_half(z) - 0.5) * side, deck_y(z) + 0.55, z)
			builder.cylinder(base, 0.42, 0.42, 1.55, Color("d3d6cd"), 10,
				Basis(Vector3.FORWARD, PI * 0.5))
			builder.box(base + Vector3(0, -0.42, 0), Vector3(1.7, 0.12, 0.9), dark)
	# Watertight doors and vents along the deckhouse skirt.
	for z in [-9.5, 0.5, 9.5]:
		for side in [-1.0, 1.0]:
			builder.box(Vector3(side * 4.05, deck_y(z) + 0.95, z), Vector3(0.12, 1.7, 0.75), dark)
	for z in [12.5, 15.0]:
		builder.cylinder(Vector3(0, deck_y(z) + 0.35, z), 0.32, 0.28, 0.7, house.darkened(0.2), 8)

static func _superstructure(visuals: Node3D, body: NavalGeometry.Builder,
		trim: NavalGeometry.Builder, glazing: NavalGeometry.Builder,
		lights: NavalGeometry.Builder, meshes: Dictionary,
		house: Color, deck: Color, dark: Color, pale: Color, compact: bool) -> void:
	var base_y := deck_y(-4.0)

	# --- main deckhouse: two tumblehome levels under the bridge ---
	var bridge_builder := NavalGeometry.Builder.new()
	if compact:
		bridge_builder.slab(Vector3(0, base_y, -6.0), Vector2(7.0, 11.5),
			Vector3(0, base_y + 2.6, -6.2), Vector2(5.6, 10.2), house)
		bridge_builder.slab(Vector3(0, base_y + 2.6, -7.0), Vector2(5.4, 6.4),
			Vector3(0, base_y + 4.5, -7.4), Vector2(4.3, 5.2), house.lightened(0.05))
	else:
		body.slab(Vector3(0, base_y, -3.0), Vector2(8.9, 19.0),
			Vector3(0, base_y + 2.9, -3.4), Vector2(7.6, 18.0), house)
		body.slab(Vector3(0, base_y + 2.9, -5.0), Vector2(7.5, 13.5),
			Vector3(0, base_y + 5.3, -5.4), Vector2(6.4, 12.4), house.lightened(0.03))
		bridge_builder.slab(Vector3(0, base_y + 5.3, -6.6), Vector2(6.3, 7.6),
			Vector3(0, base_y + 7.6, -6.9), Vector2(5.2, 6.6), house.lightened(0.06))
	var bridge_top := base_y + (4.5 if compact else 7.6)
	# Bridge roof with a small overhang and a signal deck rail.
	bridge_builder.slab(Vector3(0, bridge_top, -6.9 if not compact else -7.4),
		Vector2(5.6 if not compact else 4.7, 7.0 if not compact else 5.6),
		Vector3(0, bridge_top + 0.22, -6.9 if not compact else -7.4),
		Vector2(5.4 if not compact else 4.5, 6.8 if not compact else 5.4), deck)
	meshes["bridge"] = bridge_builder.commit(visuals,
		NavalGeometry.steel(Color.WHITE, 0.6, 0.16, true, 0.11), "Bridge")

	# --- bridge glazing: a raked window band, front and both wings ---
	var window_y := bridge_top - 1.5
	var front_z := -10.1 if not compact else -9.9
	var half := 2.55 if compact else 3.0
	glazing.slab(Vector3(0, window_y, front_z + 0.28), Vector2(half * 2.0, 0.3),
		Vector3(0, window_y + 1.1, front_z - 0.1), Vector2(half * 2.05, 0.3), Color("0b171d"))
	for side in [-1.0, 1.0]:
		glazing.slab(Vector3(side * (half - 0.05), window_y, front_z + 2.6), Vector2(0.3, 4.6),
			Vector3(side * (half + 0.28), window_y + 1.1, front_z + 2.6), Vector2(0.3, 4.4), Color("0b171d"))
	# Bridge wings.
	for side in [-1.0, 1.0]:
		trim.slab(Vector3(side * (half + 0.6), bridge_top - 0.28, front_z + 1.4), Vector2(1.9, 2.4),
			Vector3(side * (half + 0.75), bridge_top - 0.1, front_z + 1.4), Vector2(1.9, 2.4), deck)
		for post in range(3):
			var origin := Vector3(side * (half + 1.45), bridge_top - 0.1, front_z + 0.35 + post * 1.05)
			trim.tube(origin, origin + Vector3.UP * 0.95, 0.04, pale.darkened(0.3), 5)
		trim.tube(Vector3(side * (half + 1.45), bridge_top + 0.85, front_z + 0.35),
			Vector3(side * (half + 1.45), bridge_top + 0.85, front_z + 2.45), 0.035, pale.darkened(0.3), 4)

	# --- mast: a raked tripod carrying the arrays ---
	var mast_base := Vector3(0, bridge_top + 0.2, -4.2 if not compact else -6.2)
	var mast_top := mast_base + Vector3(0, 4.6 if not compact else 3.2, 0.9)
	for corner in [Vector3(-1.6, 0, -1.1), Vector3(1.6, 0, -1.1), Vector3(0, 0, 1.8)]:
		trim.tube(mast_base + corner, mast_top, 0.16, house.darkened(0.1), 6)
	trim.tube(mast_base + Vector3(-1.6, 1.9, -1.1), mast_base + Vector3(1.6, 1.9, -1.1), 0.08, house.darkened(0.2), 5)
	trim.slab(mast_top + Vector3(0, -0.15, 0), Vector2(2.2, 2.0), mast_top, Vector2(2.0, 1.8), deck)
	# Whip antennas and a yardarm.
	for side in [-1.0, 1.0]:
		trim.tube(mast_top + Vector3(side * 0.8, 0, 0), mast_top + Vector3(side * 2.4, 2.6, 0.2), 0.035, pale.darkened(0.4), 4)
	trim.tube(mast_top + Vector3(0, 0.1, 0), mast_top + Vector3(0, 2.9, -0.1), 0.09, pale.darkened(0.3), 5)

	# --- rotating search radar ---
	var radar_mount := Node3D.new()
	visuals.add_child(radar_mount)
	radar_mount.position = mast_top + Vector3(0, 1.15, 0)
	var radar_builder := NavalGeometry.Builder.new()
	radar_builder.cylinder(Vector3(0, -0.5, 0), 0.42, 0.34, 0.7, house.darkened(0.15), 10)
	radar_builder.slab(Vector3(0, -0.35, 0), Vector2(4.9, 0.55), Vector3(0, 0.72, -0.28), Vector2(4.3, 0.32), pale)
	radar_builder.box(Vector3(0, 0.2, 0.16), Vector3(4.6, 0.9, 0.1), pale.darkened(0.45))
	for offset in [-1.9, -0.65, 0.65, 1.9]:
		radar_builder.box(Vector3(offset, 0.2, -0.12), Vector3(0.12, 1.0, 0.16), pale.darkened(0.25))
	meshes["radar"] = radar_builder.commit(radar_mount,
		NavalGeometry.steel(Color.WHITE, 0.42, 0.4, true, 0.2), "Radar")

	# --- fire-control director and a navigation radome on the bridge roof ---
	trim.cylinder(Vector3(0, bridge_top + 0.55, -7.6 if not compact else -8.0), 0.75, 0.62, 0.7, house.darkened(0.08), 12)
	trim.dome(Vector3(0, bridge_top + 0.85, -7.6 if not compact else -8.0), 0.68, 0.85, Color("cfd2c8"), 12, 4)
	trim.box(Vector3(0, bridge_top + 1.1, -8.35 if not compact else -8.75), Vector3(0.9, 0.55, 0.2), dark)

	# --- funnel and machinery casing (the engine module) ---
	var funnel := NavalGeometry.Builder.new()
	var casing_y := deck_y(10.0)
	funnel.slab(Vector3(0, casing_y, 10.0), Vector2(5.6, 8.0),
		Vector3(0, casing_y + 2.1, 10.0), Vector2(4.8, 7.4), house)
	funnel.slab(Vector3(0, casing_y + 2.1, 9.2), Vector2(3.4, 3.6),
		Vector3(0, casing_y + 4.4, 9.8), Vector2(2.5, 2.9), house.darkened(0.05))
	funnel.slab(Vector3(0, casing_y + 4.4, 9.8), Vector2(2.6, 3.0),
		Vector3(0, casing_y + 4.6, 9.85), Vector2(2.4, 2.8), Color("14191c"))
	for side in [-1.0, 1.0]:
		funnel.box(Vector3(side * 1.05, casing_y + 4.5, 9.8), Vector3(0.7, 0.25, 2.2), Color("0d1113"))
	meshes["engine"] = funnel.commit(visuals,
		NavalGeometry.steel(Color.WHITE, 0.64, 0.16, true, 0.1), "Funnel")

	# --- rudder and shafts under the transom ---
	var running_gear := NavalGeometry.Builder.new()
	running_gear.slab(Vector3(0, -2.1, 25.0), Vector2(0.35, 2.6), Vector3(0, -0.6, 25.4), Vector2(0.3, 2.2), Color("3a4448"))
	meshes["rudder"] = running_gear.commit(visuals,
		NavalGeometry.steel(Color.WHITE, 0.5, 0.4, true, 0.2), "Rudder")
	for side in [-1.0, 1.0]:
		body.cylinder(Vector3(side * 1.9, -2.3, 23.2), 0.22, 0.22, 3.4, Color("55504a"), 8,
			Basis(Vector3.RIGHT, PI * 0.5 + 0.06))
		body.cylinder(Vector3(side * 1.9, -2.45, 25.4), 0.62, 0.62, 0.25, Color("6b6152"), 10,
			Basis(Vector3.RIGHT, PI * 0.5))
		for blade in range(4):
			var spin := Basis(Vector3.FORWARD, TAU * float(blade) / 4.0)
			body.box(Vector3(side * 1.9, -2.45, 25.4) + spin * Vector3(0, 0.75, 0),
				Vector3(0.42, 1.1, 0.09), Color("7a6d59"), spin * Basis(Vector3.UP, 0.4))

	# --- masthead and deck floodlights ---
	lights.box(mast_top + Vector3(0, 2.9, -0.1), Vector3(0.22, 0.3, 0.22), Color(1.0, 0.98, 0.9))
	if not compact:
		lights.box(Vector3(0, casing_y + 4.75, 9.8), Vector3(0.18, 0.24, 0.18), Color(1.0, 0.35, 0.25))

static func _weapons(visuals: Node3D, result: Dictionary, meshes: Dictionary,
		house: Color, hull: Color, dark: Color, pale: Color, compact: bool) -> void:
	# --- main gun mounts ---
	result["turret"] = _gun_mount(visuals, meshes, "gun", Vector3(0, deck_y(-18.0), -18.0), house, dark, 1.0)
	var aft := _gun_mount(visuals, meshes, "aft_gun", Vector3(0, deck_y(21.0), 21.0), house, dark, 0.86)
	aft.rotation.y = PI
	result["aft_turret"] = aft

	# --- vertical launch modules ---
	var cell_lids: Array = result["cell_lids"]
	var cell_muzzles: Array = result["cell_muzzles"]
	var banks := {"launcher_port": -2.8, "launcher_starboard": 2.8}
	for bank: String in banks:
		var centre := Vector3(banks[bank], 0, 4.0)
		var builder := NavalGeometry.Builder.new()
		var base_y := deck_y(4.0)
		builder.slab(Vector3(centre.x, base_y, 4.0), Vector2(2.9, 7.4),
			Vector3(centre.x, base_y + 1.7, 4.0), Vector2(2.5, 7.0), house.darkened(0.12))
		builder.slab(Vector3(centre.x, base_y + 1.7, 4.0), Vector2(2.6, 7.1),
			Vector3(centre.x, base_y + 1.85, 4.0), Vector2(2.6, 7.1), dark)
		meshes[bank] = builder.commit(visuals,
			NavalGeometry.steel(Color.WHITE, 0.58, 0.3, true, 0.13), bank)
	var lid_material := NavalGeometry.steel(Color("4d5a5f"), 0.5, 0.35)
	var cell_positions := [Vector3(-2.8, 0, 2.5), Vector3(-2.8, 0, 5.5),
		Vector3(2.8, 0, 2.5), Vector3(2.8, 0, 5.5)]
	for index in range(4):
		var point: Vector3 = cell_positions[index]
		point.y = deck_y(point.z) + 1.9
		var aperture := NavalGeometry.Builder.new()
		aperture.box(Vector3.ZERO, Vector3(1.5, 0.1, 1.7), Color("070d10"))
		aperture.box(Vector3(0, -0.5, 0), Vector3(1.25, 1.0, 1.45), Color("161d21"))
		var hole := aperture.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.9, 0.1, true, 0.3), "Cell")
		hole.position = point
		var lid_builder := NavalGeometry.Builder.new()
		lid_builder.slab(Vector3(0, 0, 0.05), Vector2(1.62, 1.8), Vector3(0, 0.14, 0.05), Vector2(1.5, 1.68), Color("55636a"))
		var lid := lid_builder.commit(visuals, lid_material, "CellLid")
		lid.position = point + Vector3(0, 0.1, -0.85)
		cell_lids.append(lid)
		var muzzle := Node3D.new()
		visuals.add_child(muzzle)
		muzzle.position = point + Vector3.UP * 0.3
		cell_muzzles.append(muzzle)

	# --- IR SAM battery between the launch modules ---
	var sam_builder := NavalGeometry.Builder.new()
	var sam_y := deck_y(3.0)
	sam_builder.slab(Vector3(0, sam_y, 3.0), Vector2(2.6, 5.0), Vector3(0, sam_y + 1.35, 3.0), Vector2(2.2, 4.6), house.darkened(0.08))
	sam_builder.slab(Vector3(0, sam_y + 1.35, 3.0), Vector2(2.3, 4.7), Vector3(0, sam_y + 1.5, 3.0), Vector2(2.3, 4.7), dark)
	meshes["sam"] = sam_builder.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.55, 0.32, true, 0.15), "SamBattery")
	var sam_lids: Array = result["sam_lids"]
	var sam_muzzles: Array = result["sam_muzzles"]
	for index in range(4):
		var point := Vector3(-0.55 + float(index % 2) * 1.1, sam_y + 1.55, 2.0 + float(index / 2) * 2.0)
		var aperture := NavalGeometry.Builder.new()
		aperture.box(Vector3.ZERO, Vector3(0.72, 0.1, 1.2), Color("070d10"))
		var hole := aperture.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.9, 0.1, true, 0.3), "SamCell")
		hole.position = point
		var lid_builder := NavalGeometry.Builder.new()
		lid_builder.box(Vector3(0, 0, 0.05), Vector3(0.78, 0.1, 1.3), Color("55636a"))
		var lid := lid_builder.commit(visuals, lid_material, "SamLid")
		lid.position = point + Vector3(0, 0.08, -0.62)
		sam_lids.append(lid)
		var muzzle := Node3D.new()
		visuals.add_child(muzzle)
		muzzle.position = point + Vector3.UP * 0.25
		sam_muzzles.append(muzzle)

	# --- close-in weapon system on its own sponson ---
	var pedestal := NavalGeometry.Builder.new()
	pedestal.slab(Vector3(0, deck_y(13.5) + 2.1, 13.5), Vector2(3.6, 4.2),
		Vector3(0, deck_y(13.5) + 3.6, 13.5), Vector2(3.2, 3.8), house.darkened(0.1))
	pedestal.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.55, 0.3, true, 0.13), "CiwsSponson")
	var ciws_turret := Node3D.new()
	visuals.add_child(ciws_turret)
	ciws_turret.position = Vector3(0, deck_y(13.5) + 3.6, 13.5)
	var ciws := NavalGeometry.Builder.new()
	ciws.cylinder(Vector3(0, 0.45, 0), 1.25, 1.1, 0.9, house.darkened(0.05), 12)
	ciws.slab(Vector3(0, 0.9, 0.1), Vector2(2.0, 2.2), Vector3(0, 1.9, 0.25), Vector2(1.7, 1.9), Color("d5d8ce"))
	ciws.dome(Vector3(0, 1.9, 0.25), 0.88, 1.35, Color("dfe1d6"), 12, 4)
	ciws.cylinder(Vector3(0, 1.1, -1.15), 0.52, 0.46, 1.5, Color("2f3a40"), 10, Basis(Vector3.RIGHT, PI * 0.5))
	for index in range(6):
		var angle := TAU * float(index) / 6.0
		ciws.cylinder(Vector3(sin(angle) * 0.22, 1.1 + cos(angle) * 0.22, -2.6),
			0.075, 0.075, 2.5, Color("1d262b"), 6, Basis(Vector3.RIGHT, PI * 0.5))
	ciws.box(Vector3(0, 0.35, 1.15), Vector3(1.5, 1.0, 0.9), Color("3b464b"))
	meshes["ciws"] = ciws.commit(ciws_turret, NavalGeometry.steel(Color.WHITE, 0.45, 0.35, true, 0.2), "Ciws")
	result["ciws_turret"] = ciws_turret

static func _gun_mount(visuals: Node3D, meshes: Dictionary, id: String, base: Vector3,
		house: Color, dark: Color, size: float) -> Node3D:
	var mount := Node3D.new()
	visuals.add_child(mount)
	mount.position = base
	var barbette := NavalGeometry.Builder.new()
	barbette.cylinder(Vector3(0, 0.28, 0), 1.9 * size, 1.75 * size, 0.56, house.darkened(0.18), 14)
	barbette.commit(mount, NavalGeometry.steel(Color.WHITE, 0.6, 0.28, true, 0.14), "Barbette")
	var turret := NavalGeometry.Builder.new()
	# Faceted low-observable gun house: raked front, tapered sides.
	turret.slab(Vector3(0, 0.5, 0.35 * size), Vector2(3.1 * size, 4.3 * size),
		Vector3(0, 1.85, -0.15 * size), Vector2(2.1 * size, 3.2 * size), house.lightened(0.04))
	turret.slab(Vector3(0, 1.85, -0.15 * size), Vector2(2.1 * size, 3.2 * size),
		Vector3(0, 2.15, -0.3 * size), Vector2(1.5 * size, 2.3 * size), house.lightened(0.08))
	turret.box(Vector3(0, 1.15, -2.0 * size), Vector3(1.05 * size, 0.95, 0.5), dark)
	meshes[id] = turret.commit(mount, NavalGeometry.steel(Color.WHITE, 0.5, 0.34, true, 0.14), id)
	var barrel_builder := NavalGeometry.Builder.new()
	var axis := Basis(Vector3.RIGHT, PI * 0.5)
	barrel_builder.cylinder(Vector3(0, 0, 1.35), 0.34, 0.24, 1.5, Color("34403f"), 10, axis)
	barrel_builder.cylinder(Vector3(0, 0, -0.4), 0.19, 0.155, 4.0, Color("222c30"), 10, axis)
	barrel_builder.cylinder(Vector3(0, 0, -2.75), 0.23, 0.21, 0.85, Color("161e21"), 10, axis)
	for index in range(3):
		barrel_builder.cylinder(Vector3(0, 0, -2.55 + index * 0.24), 0.26, 0.26, 0.07, Color("39454a"), 10, axis)
	var barrel := barrel_builder.commit(mount, NavalGeometry.steel(Color.WHITE, 0.38, 0.55, true, 0.3), "Barrel")
	barrel.position = Vector3(0, 1.15, -3.5)
	return mount

static func _hull_number(builder: NavalGeometry.Builder, hull_number: String, paint: Color) -> void:
	## Pennant number painted on both bows, following the flare of the plating.
	var digits: Array[int] = []
	for character in hull_number:
		if character >= "0" and character <= "9":
			digits.append(int(character))
	if digits.is_empty():
		return
	var width := 0.95
	var span := float(digits.size()) * (width + 0.22) - 0.22
	for side: float in [-1.0, 1.0]:
		for index in range(digits.size()):
			var origin_z := -20.6 + (float(index) * (width + 0.22) - span * 0.5) * side
			for segment: int in SEGMENT_MAP[digits[index]]:
				var rect: Rect2 = SEGMENT_RECTS[segment]
				var z0 := origin_z + (rect.position.x - 0.5) * width * side
				var z1 := origin_z + (rect.position.x + rect.size.x - 0.5) * width * side
				var y0 := 1.55 + rect.position.y
				var y1 := 1.55 + rect.position.y + rect.size.y
				var a := topside_point(z0, y0, side)
				var b := topside_point(z1, y0, side)
				var c := topside_point(z1, y1, side)
				var d := topside_point(z0, y1, side)
				var lift := Vector3(0.035 * side, 0, 0)
				if side > 0:
					builder.quad(a + lift, d + lift, c + lift, b + lift, paint)
				else:
					builder.quad(a + lift, b + lift, c + lift, d + lift, paint)

static func _flight_deck(body: NavalGeometry.Builder, trim: NavalGeometry.Builder,
		deck: Color, house: Color, dark: Color, pale: Color, compact: bool) -> void:
	## Aft working deck: painted landing spot, boat bay and towing gear.
	var spot := Vector3(0, 0, 22.5)
	var paint := Color("c9cdbe")
	var lift := 0.035
	# Landing circle, drawn as a ring of short arcs just above the plating.
	for index in range(28):
		var angle := TAU * float(index) / 28.0
		var next := TAU * float(index + 1) / 28.0
		var inner := 3.1
		var outer := 3.55
		var a := spot + Vector3(sin(angle) * inner, deck_y(spot.z) + lift, cos(angle) * inner)
		var b := spot + Vector3(sin(next) * inner, deck_y(spot.z) + lift, cos(next) * inner)
		var c := spot + Vector3(sin(next) * outer, deck_y(spot.z) + lift, cos(next) * outer)
		var d := spot + Vector3(sin(angle) * outer, deck_y(spot.z) + lift, cos(angle) * outer)
		body.quad(d, c, b, a, paint)
	# Approach centreline.
	body.quad(Vector3(-0.32, deck_y(19.0) + lift, 17.4), Vector3(0.32, deck_y(19.0) + lift, 17.4),
		Vector3(0.32, deck_y(19.0) + lift, 26.4), Vector3(-0.32, deck_y(19.0) + lift, 26.4), paint)
	if compact:
		return
	# Rigid inflatable in a recessed bay on the port quarter.
	var bay := Vector3(-2.9, deck_y(15.5), 15.5)
	body.slab(bay, Vector2(2.9, 6.4), bay + Vector3(0, 0.85, 0), Vector2(2.6, 6.0), dark)
	body.slab(bay + Vector3(0, 0.85, 0), Vector2(2.1, 5.4), bay + Vector3(0, 1.55, 0.1), Vector2(1.3, 4.4), Color("2b3339"))
	body.slab(bay + Vector3(0, 1.5, 0), Vector2(1.5, 4.8), bay + Vector3(0, 1.85, 0.1), Vector2(1.1, 3.6), Color("d5d2c4"))
	# Davit arm over the bay.
	trim.tube(bay + Vector3(-1.4, 0.2, -2.6), bay + Vector3(-1.4, 3.4, -2.6), 0.11, house.darkened(0.15), 6)
	trim.tube(bay + Vector3(-1.4, 3.4, -2.6), bay + Vector3(-1.4, 3.3, 1.9), 0.09, house.darkened(0.15), 6)
	# Towing bitts and a deck hatch on the quarterdeck.
	trim.box(Vector3(0, deck_y(26.0) + 0.22, 26.0), Vector3(2.2, 0.44, 1.0), dark)
	trim.box(Vector3(2.6, deck_y(18.0) + 0.14, 18.0), Vector3(1.6, 0.28, 1.6), house.darkened(0.2))

static func _navigation_lights(lights: NavalGeometry.Builder) -> void:
	lights.box(topside_point(-9.0, 6.4, -1.0) + Vector3(-0.3, 0, 0), Vector3(0.28, 0.3, 0.22), Color(1.0, 0.18, 0.16))
	lights.box(topside_point(-9.0, 6.4, 1.0) + Vector3(0.3, 0, 0), Vector3(0.28, 0.3, 0.22), Color(0.2, 1.0, 0.42))
	lights.box(Vector3(0, deck_y(26.0) + 0.6, 26.0), Vector3(0.22, 0.26, 0.22), Color(1.0, 0.98, 0.92))

# --------------------------------------------------------------------------- #
# Cargo ship
# --------------------------------------------------------------------------- #

## z, half-beam, keel y, deck y. A merchant is nothing like a warship in
## section: no flare, no bilge turn, a long parallel midbody and 5.5 m of
## freeboard where the corvette has 3.3. Slab-sided is the point.
const CARGO_STATIONS := [
	[-36.0, 0.55, -1.0, 6.2],
	[-33.0, 2.20, -2.4, 6.0],
	[-29.0, 4.00, -3.6, 5.9],
	[-24.0, 5.60, -4.4, 5.8],
	[-16.0, 6.70, -4.7, 5.7],
	[ -8.0, 7.00, -4.7, 5.6],
	[  0.0, 7.00, -4.7, 5.6],
	[  8.0, 7.00, -4.7, 5.6],
	[ 16.0, 7.00, -4.7, 5.6],
	[ 24.0, 6.60, -4.5, 5.7],
	[ 30.0, 5.80, -3.9, 5.9],
	[ 34.0, 5.00, -3.0, 6.1],
	[ 36.0, 4.60, -2.2, 6.2],
]
## Container colours. Weathered, not toybox — they read at tactical range as
## texture on the deck rather than as a stack of primaries.
const CONTAINER_HUES := ["8a4038", "6a6f64", "a8763a", "3f5a63", "7c7468", "934f36"]

static func cargo_profile(index: int) -> Array:
	## Half a section, deck edge down to the keel. Rectangular sections make a
	## barge; a merchant wants a flat topside, a hard knuckle and a full bilge
	## turn carrying most of the beam nearly to the keel.
	var row: Array = CARGO_STATIONS[index]
	var half: float = float(row[1])
	var keel: float = float(row[2])
	var deck: float = float(row[3])
	var z: float = float(row[0])
	var bilge: float = keel + (deck - keel) * 0.26
	return [
		Vector3(half, deck, z),
		Vector3(half, bilge + (deck - bilge) * 0.42, z),
		Vector3(half * 0.96, bilge, z),
		Vector3(half * 0.55, keel + (deck - keel) * 0.07, z),
		Vector3(half * 0.06, keel, z),
	]

static func loft_cargo(builder: NavalGeometry.Builder, first: int, last: int, color: Color) -> void:
	## Welded plate, so the strakes are flat-shaded and the chines read as chines.
	for index in range(first, last):
		var fwd: Array = cargo_profile(index)
		var aft: Array = cargo_profile(index + 1)
		for strake in range(fwd.size() - 1):
			var tint := color.darkened(0.03 * float(strake))
			builder.quad(fwd[strake], aft[strake], aft[strake + 1], fwd[strake + 1], tint)
			var mirror := Vector3(-1, 1, 1)
			builder.quad(fwd[strake + 1] * mirror, aft[strake + 1] * mirror,
				aft[strake] * mirror, fwd[strake] * mirror, tint)

static func cargo_deck(z: float) -> float:
	## Deck height at a station, interpolated. The sheer is slight but it is
	## there, and deck fittings need to sit on it rather than through it.
	for index in range(CARGO_STATIONS.size() - 1):
		var a: Array = CARGO_STATIONS[index]
		var b: Array = CARGO_STATIONS[index + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var t: float = (z - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return lerpf(float(a[3]), float(b[3]), t)
	return 5.6

static func cargo_half(z: float) -> float:
	for index in range(CARGO_STATIONS.size() - 1):
		var a: Array = CARGO_STATIONS[index]
		var b: Array = CARGO_STATIONS[index + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var t: float = (z - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), t)
	return 7.0

static func build_cargo(visuals: Node3D, _pennant: String) -> Dictionary:
	## A general cargo ship, ~72 m. Deliberately unlike the warships: dark hull,
	## cream deckhouse right aft, deck cargo. At tactical zoom the silhouette has
	## to say "merchant" before the player reads a single label.
	##
	## One thing here is load-bearing rather than decorative. The engine module's
	## collision box is the funnel, standing clear above the hull — the same
	## trick the corvette uses. Shells and the pointer both take the *first* box
	## a ray meets, so a below-decks engine room would be unhittable and the
	## training level would be unwinnable.
	var paint := Color("2b3138")
	var boot := Color("7a2f26")
	var deck := Color("4a4238")
	var house := Color("cdc6b4")
	var shade := Color("9b9585")
	var dark := Color("1a1d20")
	var metal := Color("70776f")

	var meshes: Dictionary = {}
	var body := NavalGeometry.Builder.new()
	var trim := NavalGeometry.Builder.new()
	var glazing := NavalGeometry.Builder.new()
	var lights := NavalGeometry.Builder.new()

	# --- hull, in three damageable compartments ------------------------------ #
	for part: Array in [["bow", 0, 4], ["mid", 4, 8], ["stern", 8, 12]]:
		var shell := NavalGeometry.Builder.new()
		loft_cargo(shell, int(part[1]), int(part[2]), paint)
		# Boot-topping: a band of anti-fouling red at the waterline, which is
		# most of what makes a dark hull read as a merchant rather than a rock.
		for index in range(int(part[1]), int(part[2])):
			var a: Array = cargo_profile(index)
			var b: Array = cargo_profile(index + 1)
			for side: float in [-1.0, 1.0]:
				var mirror := Vector3(side, 1, 1)
				var fa: Vector3 = a[1].lerp(a[2], 0.35) * mirror
				var fb: Vector3 = b[1].lerp(b[2], 0.35) * mirror
				var ga: Vector3 = a[2].lerp(a[3], 0.30) * mirror
				var gb: Vector3 = b[2].lerp(b[3], 0.30) * mirror
				var out := Vector3(side * 0.06, 0, 0)
				if side > 0.0:
					shell.quad(fa + out, fb + out, gb + out, ga + out, boot)
				else:
					shell.quad(ga + out, gb + out, fb + out, fa + out, boot)
		# Transom.
		if String(part[0]) == "stern":
			var last: Array = cargo_profile(CARGO_STATIONS.size() - 1)
			for strake in range(last.size() - 1):
				var mirror := Vector3(-1, 1, 1)
				shell.quad(last[strake], last[strake] * mirror,
					last[strake + 1] * mirror, last[strake + 1], paint.darkened(0.12))
		meshes[String(part[0])] = shell.commit(visuals,
			NavalGeometry.steel(Color.WHITE, 0.70, 0.10, true, 0.07), String(part[0]))

	# --- weather deck --------------------------------------------------------- #
	for index in range(CARGO_STATIONS.size() - 1):
		var a: Array = cargo_profile(index)
		var b: Array = cargo_profile(index + 1)
		var mirror := Vector3(-1, 1, 1)
		body.quad(a[0] * mirror, a[0], b[0], b[0] * mirror, deck)

	# --- forecastle: bulwark, breakwater, ground tackle ----------------------- #
	for index in range(0, 4):
		var a: Array = CARGO_STATIONS[index]
		var b: Array = CARGO_STATIONS[index + 1]
		for side: float in [-1.0, 1.0]:
			body.beam(Vector3(side * float(a[1]), float(a[3]) + 0.7, float(a[0])), Vector2(0.22, 1.4),
				Vector3(side * float(b[1]), float(b[3]) + 0.7, float(b[0])), Vector2(0.22, 1.4), paint)
	trim.wedge(Vector3(0, cargo_deck(-25.0) + 0.55, -25.0), Vector3(9.0, 1.1, 2.4), shade.darkened(0.35))
	trim.cylinder(Vector3(0, cargo_deck(-30.0) + 0.5, -30.0), 0.55, 0.55, 1.0, metal, 10,
		Basis(Vector3.FORWARD, PI * 0.5))
	for side: float in [-1.0, 1.0]:
		trim.cylinder(Vector3(side * 1.5, cargo_deck(-30.0) + 0.5, -30.0), 0.8, 0.8, 0.5, dark, 12,
			Basis(Vector3.FORWARD, PI * 0.5))
		trim.box(Vector3(side * (cargo_half(-31.0) - 0.1), 1.6, -31.0), Vector3(0.3, 1.6, 2.2), dark)

	# --- four holds, coamings and hatch covers -------------------------------- #
	for hold_z: float in [-21.0, -11.0, -1.0, 9.0]:
		var top := cargo_deck(hold_z)
		body.slab(Vector3(0, top, hold_z), Vector2(11.4, 8.6),
			Vector3(0, top + 1.25, hold_z), Vector2(11.0, 8.2), shade.darkened(0.42))
		body.slab(Vector3(0, top + 1.25, hold_z), Vector2(11.2, 8.4),
			Vector3(0, top + 1.5, hold_z), Vector2(10.8, 8.0), Color("59605f"))
		for rib in range(7):
			body.box(Vector3(0, top + 1.58, hold_z - 3.3 + float(rib) * 1.1),
				Vector3(10.6, 0.12, 0.34), dark)

	# --- deck cargo: the silhouette cue --------------------------------------- #
	var stack := 0
	for bay in range(7):
		var bay_z := -30.0 + float(bay) * 6.6
		var top := cargo_deck(bay_z) + 1.6
		for column in range(3):
			for tier in range(2 if (bay + column) % 3 != 0 else 1):
				stack += 1
				var hue := Color(CONTAINER_HUES[stack % CONTAINER_HUES.size()])
				body.box(Vector3(float(column - 1) * 2.7, top + 1.3 + float(tier) * 2.55, bay_z),
					Vector3(2.5, 2.5, 6.1), hue.darkened(0.04 * float(stack % 3)))
				# Corrugation: a few ribs read as ribbing at any useful distance.
				for rib in range(3):
					body.box(Vector3(float(column - 1) * 2.7,
						top + 1.3 + float(tier) * 2.55, bay_z - 2.0 + float(rib) * 2.0),
						Vector3(2.56, 2.2, 0.16), hue.darkened(0.16))

	# --- two deck cranes ------------------------------------------------------ #
	for crane_z: float in [-16.0, 4.0]:
		var base := cargo_deck(crane_z) + 1.5
		trim.cylinder(Vector3(0, base + 2.2, crane_z), 1.5, 1.25, 4.4, house.darkened(0.18), 12)
		trim.box(Vector3(0, base + 4.9, crane_z), Vector3(3.0, 1.6, 3.4), house.darkened(0.1))
		var jib_tip := Vector3(0, base + 11.0, crane_z - 8.6)
		trim.beam(Vector3(0, base + 5.2, crane_z - 0.6), Vector2(1.3, 1.3), jib_tip, Vector2(0.7, 0.7), shade)
		trim.tube(jib_tip, jib_tip + Vector3(0, -5.2, 0), 0.05, Color("cfcabb"), 4)
		trim.box(jib_tip + Vector3(0, -5.5, 0), Vector3(0.7, 0.9, 0.7), dark)

	# --- deckhouse, right aft. Top two levels are the bridge module ----------- #
	var house_z := 21.0
	var house_base := cargo_deck(house_z)
	for level in range(2):
		var low := house_base + float(level) * 2.7
		body.slab(Vector3(0, low, house_z), Vector2(12.6 - float(level) * 0.5, 8.6),
			Vector3(0, low + 2.7, house_z), Vector2(12.2 - float(level) * 0.5, 8.4), house)
		for port in range(5):
			for side: float in [-1.0, 1.0]:
				glazing.box(Vector3(side * (6.0 - float(level) * 0.25), low + 1.5, house_z - 3.0 + float(port) * 1.5),
					Vector3(0.12, 0.7, 0.8), Color("14202a"))
	var wheel := NavalGeometry.Builder.new()
	for level in range(2):
		var low := house_base + 5.4 + float(level) * 2.7
		wheel.slab(Vector3(0, low, house_z), Vector2(11.6 - float(level) * 0.6, 8.2),
			Vector3(0, low + 2.7, house_z), Vector2(11.2 - float(level) * 0.9, 8.0), house)
	# Wheelhouse window band and the bridge wings that overhang the ship's side.
	var wheel_y := house_base + 8.4
	wheel.slab(Vector3(0, wheel_y + 0.6, house_z - 3.9), Vector2(10.6, 0.4),
		Vector3(0, wheel_y + 2.0, house_z - 4.1), Vector2(10.2, 0.4), Color("101a22"))
	for side: float in [-1.0, 1.0]:
		wheel.slab(Vector3(side * 6.4, wheel_y, house_z - 1.0), Vector2(3.0, 4.0),
			Vector3(side * 7.6, wheel_y + 0.32, house_z - 1.0), Vector2(3.0, 4.0), house.darkened(0.08))
		for rail in range(4):
			trim.tube(Vector3(side * (5.6 + float(rail) * 0.7), wheel_y + 0.32, house_z - 2.8),
				Vector3(side * (5.6 + float(rail) * 0.7), wheel_y + 1.4, house_z - 2.8), 0.05, metal, 4)
	meshes["bridge"] = wheel.commit(visuals,
		NavalGeometry.steel(Color.WHITE, 0.58, 0.14, true, 0.11), "Bridge")

	# --- engine casing and funnel = the engine module ------------------------- #
	# It has to stand clear above the hull boxes or it cannot be hit. See the
	# note at the top of this function.
	var funnel := NavalGeometry.Builder.new()
	var casing_z := 29.0
	var casing_y := cargo_deck(casing_z)
	funnel.slab(Vector3(0, casing_y, casing_z), Vector2(8.4, 7.0),
		Vector3(0, casing_y + 4.6, casing_z), Vector2(7.4, 6.4), house)
	funnel.slab(Vector3(0, casing_y + 4.6, casing_z + 0.3), Vector2(5.0, 5.2),
		Vector3(0, casing_y + 9.2, casing_z + 0.6), Vector2(4.0, 4.4), dark)
	funnel.slab(Vector3(0, casing_y + 7.3, casing_z + 0.5), Vector2(5.15, 5.35),
		Vector3(0, casing_y + 8.3, casing_z + 0.55), Vector2(4.75, 4.95), Color("a8372c"))
	for side: float in [-1.0, 1.0]:
		funnel.cylinder(Vector3(side * 1.0, casing_y + 9.5, casing_z + 0.6), 0.42, 0.42, 0.9, dark, 10)
	meshes["engine"] = funnel.commit(visuals,
		NavalGeometry.steel(Color.WHITE, 0.64, 0.16, true, 0.10), "Funnel")

	# --- masthead radar, on its own pivot so it can turn ---------------------- #
	var radar_mount := Node3D.new()
	visuals.add_child(radar_mount)
	radar_mount.position = Vector3(0, house_base + 12.2, house_z)
	var scanner := NavalGeometry.Builder.new()
	scanner.box(Vector3(0, 0, 0), Vector3(3.4, 0.16, 0.4), Color("d6d0c2"))
	scanner.box(Vector3(0, -0.3, 0), Vector3(0.7, 0.6, 0.7), dark)
	meshes["radar"] = scanner.commit(radar_mount,
		NavalGeometry.steel(Color.WHITE, 0.5, 0.3, true, 0.2), "Radar")
	trim.tube(Vector3(0, house_base + 10.8, house_z), Vector3(0, house_base + 12.2, house_z), 0.14, metal, 6)
	for side: float in [-1.0, 1.0]:
		trim.tube(Vector3(side * 1.6, house_base + 10.8, house_z + 1.4),
			Vector3(0, house_base + 12.2, house_z), 0.09, metal, 5)
	trim.tube(Vector3(-2.6, house_base + 11.6, house_z + 0.2),
		Vector3(2.6, house_base + 11.6, house_z + 0.2), 0.07, metal, 5)
	# Foremast up forward.
	trim.tube(Vector3(0, cargo_deck(-27.0), -27.0), Vector3(0, cargo_deck(-27.0) + 7.0, -27.0), 0.12, metal, 6)
	trim.tube(Vector3(-2.2, cargo_deck(-27.0) + 5.2, -27.0),
		Vector3(2.2, cargo_deck(-27.0) + 5.2, -27.0), 0.07, metal, 5)

	# --- steering gear, rudder and screw -------------------------------------- #
	var steering := NavalGeometry.Builder.new()
	steering.slab(Vector3(0, -2.9, 34.2), Vector2(0.55, 4.2), Vector3(0, -0.5, 34.5), Vector2(0.5, 3.6),
		Color("39424a"))
	meshes["rudder"] = steering.commit(visuals,
		NavalGeometry.steel(Color.WHITE, 0.66, 0.2, true, 0.14), "Rudder")
	body.cylinder(Vector3(0, -3.1, 31.5), 0.42, 0.42, 3.4, Color("55504a"), 10, Basis(Vector3.RIGHT, PI * 0.5))
	for blade in range(4):
		var spin := Basis(Vector3.FORWARD, TAU * float(blade) / 4.0)
		body.box(spin * Vector3(0, 1.5, 33.3), Vector3(0.9, 2.4, 0.18), Color("7d6a46"), spin)

	# --- boats, rafts, railings, lights --------------------------------------- #
	for side: float in [-1.0, 1.0]:
		trim.slab(Vector3(side * 6.0, house_base + 3.1, house_z + 3.4), Vector2(1.9, 5.6),
			Vector3(side * 6.0, house_base + 4.1, house_z + 3.4), Vector2(2.3, 6.0), Color("c96a2c"))
		for davit in range(2):
			trim.tube(Vector3(side * 5.2, house_base + 2.7, house_z + 1.4 + float(davit) * 4.0),
				Vector3(side * 6.6, house_base + 5.2, house_z + 1.4 + float(davit) * 4.0), 0.11, metal, 5)
	for index in range(28):
		var rail_z := -33.0 + float(index) * 2.5
		if rail_z > 16.0 and rail_z < 34.0:
			continue
		var half := cargo_half(rail_z) - 0.25
		var top := cargo_deck(rail_z)
		for side: float in [-1.0, 1.0]:
			trim.tube(Vector3(side * half, top, rail_z), Vector3(side * half, top + 1.05, rail_z), 0.045, metal, 4)
	lights.box(Vector3(-7.8, house_base + 8.6, house_z - 1.0), Vector3(0.2, 0.22, 0.24), Color(1.0, 0.2, 0.18))
	lights.box(Vector3(7.8, house_base + 8.6, house_z - 1.0), Vector3(0.2, 0.22, 0.24), Color(0.24, 1.0, 0.45))
	lights.box(Vector3(0, cargo_deck(-27.0) + 7.2, -27.0), Vector3(0.2, 0.2, 0.2), Color(1.0, 0.95, 0.86))
	lights.box(Vector3(0, house_base + 12.5, house_z), Vector3(0.2, 0.2, 0.2), Color(1.0, 0.95, 0.86))

	body.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.72, 0.08, true, 0.09), "Hull")
	trim.commit(visuals, NavalGeometry.steel(Color.WHITE, 0.58, 0.24, true, 0.16), "Fittings")
	glazing.commit(visuals, NavalGeometry.glass(Color("0e1a22")), "Glazing")
	lights.commit(visuals, NavalGeometry.lamp(), "Lights")
	# Her anti-collision beacon, on the same footing as the warships': its own
	# mesh, because PatrolBoat blinks it.
	var flasher := NavalGeometry.Builder.new()
	flasher.box(Vector3(0, house_base + 13.8, house_z), Vector3(0.34, 0.34, 0.34), BEACON_LIGHT)
	var beacon := flasher.commit(visuals, NavalGeometry.lamp(), "Beacon")
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Every mount is absent rather than hidden: PatrolBoat treats these as
	# optional and ShipLayout stubs the matching modules.
	return {
		"beacon": beacon,
		"system_meshes": meshes,
		"turret": null, "aft_turret": null, "ciws_turret": null,
		"barrel": null, "aft_barrel": null,
		"cell_lids": [], "cell_muzzles": [], "sam_lids": [], "sam_muzzles": [],
		"radar_mount": radar_mount,
	}

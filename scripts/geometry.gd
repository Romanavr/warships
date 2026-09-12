class_name NavalGeometry
extends RefCounted
## Procedural mesh and material builders. No external art or plugins required.
##
## Everything the fleet is made of comes from here: a shared plated-steel
## material, a batching mesh builder so a detailed ship is still a handful of
## draw calls, and lofted hull generation.

static var _detail_normal: Texture2D
static var _detail_rough: Texture2D

# --------------------------------------------------------------------------- #
# Procedural surface detail
# --------------------------------------------------------------------------- #

static func detail_normal() -> Texture2D:
	if _detail_normal != null:
		return _detail_normal
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.085
	noise.fractal_octaves = 3
	for y in range(256):
		for x in range(256):
			var height: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			height = 0.45 + height * 0.55
			# Welded plate seams: shallow grooves that catch the sun on big surfaces.
			if x % 64 == 0 or y % 43 == 0:
				height -= 0.42
			elif (x + 1) % 64 == 0 or (y + 1) % 43 == 0:
				height -= 0.2
			var shade := clampf(height, 0.0, 1.0)
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	image.bump_map_to_normal_map(1.9)
	_detail_normal = ImageTexture.create_from_image(image)
	return _detail_normal

static func detail_roughness() -> Texture2D:
	if _detail_rough != null:
		return _detail_rough
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 27
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	for y in range(128):
		for x in range(128):
			# Weathering: salt-scoured panels are rougher than fresh paint.
			var value := clampf(0.72 + noise.get_noise_2d(float(x), float(y)) * 0.45, 0.35, 1.0)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	_detail_rough = ImageTexture.create_from_image(image)
	return _detail_rough

# --------------------------------------------------------------------------- #
# Materials
# --------------------------------------------------------------------------- #

static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	## Plain flat material. Kept for effects, debris and sprites.
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	if glow:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

static func steel(color: Color, roughness: float = 0.58, metallic: float = 0.28,
		vertex_color: bool = false, detail_scale: float = 0.1) -> StandardMaterial3D:
	## Painted marine steel: plate seams, weathered roughness, a little metal.
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	result.metallic_specular = 0.45
	result.vertex_color_use_as_albedo = vertex_color
	result.vertex_color_is_srgb = vertex_color
	result.normal_enabled = true
	result.normal_texture = detail_normal()
	result.normal_scale = 0.6
	result.roughness_texture = detail_roughness()
	result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.uv1_triplanar = true
	result.uv1_triplanar_sharpness = 2.0
	result.uv1_scale = Vector3.ONE * detail_scale
	return result

static func glass(tint: Color = Color("0d1a20")) -> StandardMaterial3D:
	## Dark armoured bridge glazing. Low roughness so it mirrors the sky.
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = 0.06
	result.metallic = 0.92
	result.metallic_specular = 0.8
	return result

static func lamp() -> StandardMaterial3D:
	## Unshaded navigation and signal lights; the environment glow blooms them.
	var result := StandardMaterial3D.new()
	result.albedo_color = Color.WHITE
	result.vertex_color_use_as_albedo = true
	result.vertex_color_is_srgb = true
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.disable_receive_shadows = true
	return result

static func charred() -> StandardMaterial3D:
	## What a destroyed module looks like: burnt, matte, no paint left.
	var result := StandardMaterial3D.new()
	result.albedo_color = Color("1c2429")
	result.roughness = 0.95
	result.metallic = 0.1
	result.normal_enabled = true
	result.normal_texture = detail_normal()
	result.normal_scale = 1.4
	result.uv1_triplanar = true
	result.uv1_scale = Vector3.ONE * 0.22
	return result

# --------------------------------------------------------------------------- #
# Batching mesh builder
# --------------------------------------------------------------------------- #

class Builder extends RefCounted:
	## Accumulates many primitives into one surface so a fully detailed ship
	## still costs a dozen draw calls instead of two hundred.
	var _surface := SurfaceTool.new()
	var _count: int = 0
	var _smooth: int = -1

	func _init() -> void:
		_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	func is_empty() -> bool:
		return _count == 0

	func smooth(group: int) -> void:
		_smooth = group

	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-12:
			return
		normal = normal.normalized()
		# Godot's front face is the clockwise winding, which is the reverse of
		# the counter-clockwise normal computed above.
		for point in [a, c, b]:
			_surface.set_smooth_group(_smooth)
			_surface.set_color(color)
			_surface.set_normal(normal)
			_surface.add_vertex(point)
		_count += 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
		tri(a, b, c, color)
		tri(a, c, d, color)

	func smooth_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
			ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		## Explicit per-vertex normals, for lofted surfaces that must read curved.
		_vertex(a, na, ca); _vertex(c, nc, cc); _vertex(b, nb, cb)
		_vertex(a, na, ca); _vertex(d, nd, cd); _vertex(c, nc, cc)
		_count += 2

	func _vertex(point: Vector3, normal: Vector3, color: Color) -> void:
		_surface.set_smooth_group(_smooth)
		_surface.set_color(color)
		_surface.set_normal(normal)
		_surface.add_vertex(point)

	func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
		frustum(center, Vector2(size.x, size.y), Vector2(size.x, size.y), size.z, color, basis)

	func frustum(center: Vector3, front: Vector2, back: Vector2, length: float,
			color: Color, basis: Basis = Basis.IDENTITY, shade: float = 1.0) -> void:
		## A box that may taper between its -Z and +Z faces. The workhorse:
		## every hull deckhouse, funnel and gun house is one of these.
		var half := length * 0.5
		var fx := front.x * 0.5
		var fy := front.y * 0.5
		var bx := back.x * 0.5
		var by := back.y * 0.5
		var points: Array[Vector3] = [
			Vector3(-fx, -fy, -half), Vector3(fx, -fy, -half), Vector3(fx, fy, -half), Vector3(-fx, fy, -half),
			Vector3(-bx, -by, half), Vector3(bx, -by, half), Vector3(bx, by, half), Vector3(-bx, by, half)]
		for index in range(8):
			points[index] = center + basis * points[index]
		# Cheap directional shading keeps flat faces from merging visually.
		var top := color.lightened(0.07 * shade)
		var side := color.darkened(0.05 * shade)
		var under := color.darkened(0.22 * shade)
		quad(points[3], points[2], points[1], points[0], color)
		quad(points[4], points[5], points[6], points[7], color)
		quad(points[7], points[6], points[2], points[3], top)
		quad(points[0], points[1], points[5], points[4], under)
		quad(points[4], points[7], points[3], points[0], side)
		quad(points[1], points[2], points[6], points[5], side)

	func slab(bottom_center: Vector3, bottom_size: Vector2, top_center: Vector3,
			top_size: Vector2, color: Color, shade: float = 1.0) -> void:
		## Free hexahedron between two horizontal rectangles. Superstructure
		## tumblehome, raked fronts and sloped faces are all this one shape.
		## Sizes are (beam, length); centres carry the height and any offset.
		var bx := bottom_size.x * 0.5
		var bz := bottom_size.y * 0.5
		var tx := top_size.x * 0.5
		var tz := top_size.y * 0.5
		var p := [
			bottom_center + Vector3(-bx, 0, -bz), bottom_center + Vector3(bx, 0, -bz),
			bottom_center + Vector3(bx, 0, bz), bottom_center + Vector3(-bx, 0, bz),
			top_center + Vector3(-tx, 0, -tz), top_center + Vector3(tx, 0, -tz),
			top_center + Vector3(tx, 0, tz), top_center + Vector3(-tx, 0, tz)]
		var top := color.lightened(0.09 * shade)
		var under := color.darkened(0.25 * shade)
		var side := color.darkened(0.04 * shade)
		quad(p[7], p[6], p[5], p[4], top)
		quad(p[0], p[1], p[2], p[3], under)
		quad(p[4], p[5], p[1], p[0], color)
		quad(p[6], p[7], p[3], p[2], color.darkened(0.07 * shade))
		quad(p[7], p[4], p[0], p[3], side)
		quad(p[5], p[6], p[2], p[1], side)

	func dome(center: Vector3, radius: float, height: float, color: Color,
			sides: int = 12, rings: int = 4) -> void:
		## Half-ellipsoid. Radomes, sonar bulbs, rotor hubs.
		smooth(_count + 8192)
		for ring in range(rings):
			var a0: float = PI * 0.5 * float(ring) / rings
			var a1: float = PI * 0.5 * float(ring + 1) / rings
			for i in range(sides):
				var t0 := TAU * float(i) / sides
				var t1 := TAU * float(i + 1) / sides
				var points: Array[Vector3] = []
				var normals: Array[Vector3] = []
				for pair in [[a0, t0], [a0, t1], [a1, t1], [a1, t0]]:
					var offset := Vector3(cos(pair[0]) * sin(pair[1]) * radius,
						sin(pair[0]) * height, cos(pair[0]) * cos(pair[1]) * radius)
					points.append(center + offset)
					normals.append(Vector3(offset.x / radius, offset.y / maxf(height, 0.01) * 0.6,
						offset.z / radius).normalized())
				smooth_quad(points[0], points[1], points[2], points[3],
					normals[0], normals[1], normals[2], normals[3], color, color, color, color)
		smooth(-1)

	func beam(front_center: Vector3, front_size: Vector2, back_center: Vector3,
			back_size: Vector2, color: Color, shade: float = 1.0) -> void:
		## Hexahedron between two cross-sections, taken perpendicular to the line
		## joining their centres. Works along any axis, so one call shapes a
		## fuselage segment, a drooping wing panel or an upright fin.
		var axis := back_center - front_center
		var length := axis.length()
		if length < 0.0001:
			return
		var direction := axis / length
		var right := Vector3.UP.cross(direction)
		if right.length_squared() < 0.02:
			right = Vector3.RIGHT.cross(direction)
			if right.length_squared() < 0.02:
				right = Vector3.FORWARD.cross(direction)
		right = right.normalized()
		var up := direction.cross(right).normalized()
		var fx := right * front_size.x * 0.5
		var fy := up * front_size.y * 0.5
		var bx := right * back_size.x * 0.5
		var by := up * back_size.y * 0.5
		var p: Array[Vector3] = [
			front_center - fx - fy, front_center + fx - fy,
			front_center + fx + fy, front_center - fx + fy,
			back_center - bx - by, back_center + bx - by,
			back_center + bx + by, back_center - bx + by]
		var top := color.lightened(0.07 * shade)
		var under := color.darkened(0.2 * shade)
		var side := color.darkened(0.04 * shade)
		quad(p[3], p[2], p[1], p[0], color)
		quad(p[4], p[5], p[6], p[7], color.darkened(0.06 * shade))
		quad(p[7], p[6], p[2], p[3], top)
		quad(p[0], p[1], p[5], p[4], under)
		quad(p[4], p[7], p[3], p[0], side)
		quad(p[1], p[2], p[6], p[5], side)

	func wedge(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
		## Triangular prism rising toward -Z. Breakwaters and spray rails.
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		var p: Array[Vector3] = [
			Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz),
			Vector3(-hx, size.y, hz), Vector3(hx, size.y, hz)]
		for index in range(6):
			p[index] = center + basis * p[index]
		quad(p[3], p[2], p[1], p[0], color.darkened(0.22))
		quad(p[4], p[5], p[2], p[3], color)
		quad(p[1], p[5], p[4], p[0], color.darkened(0.05))
		tri(p[0], p[4], p[3], color.darkened(0.12))
		tri(p[1], p[2], p[5], color.darkened(0.12))

	func cylinder(center: Vector3, bottom: float, top: float, height: float,
			color: Color, sides: int = 12, basis: Basis = Basis.IDENTITY, caps: bool = true) -> void:
		var half := height * 0.5
		smooth(_count + 4096)
		for i in range(sides):
			var a := TAU * float(i) / sides
			var b := TAU * float(i + 1) / sides
			var na := Vector3(sin(a), 0, cos(a))
			var nb := Vector3(sin(b), 0, cos(b))
			var p0 := center + basis * (na * bottom + Vector3.DOWN * half)
			var p1 := center + basis * (nb * bottom + Vector3.DOWN * half)
			var p2 := center + basis * (nb * top + Vector3.UP * half)
			var p3 := center + basis * (na * top + Vector3.UP * half)
			var wa := (basis * na).normalized()
			var wb := (basis * nb).normalized()
			smooth_quad(p0, p1, p2, p3, wa, wb, wb, wa, color, color, color, color)
		smooth(-1)
		if not caps:
			return
		var top_center := center + basis * (Vector3.UP * half)
		var bottom_center := center + basis * (Vector3.DOWN * half)
		for i in range(sides):
			var a := TAU * float(i) / sides
			var b := TAU * float(i + 1) / sides
			var na := Vector3(sin(a), 0, cos(a))
			var nb := Vector3(sin(b), 0, cos(b))
			if top > 0.001:
				tri(top_center, center + basis * (na * top + Vector3.UP * half),
					center + basis * (nb * top + Vector3.UP * half), color.lightened(0.08))
			if bottom > 0.001:
				tri(bottom_center, center + basis * (nb * bottom + Vector3.DOWN * half),
					center + basis * (na * bottom + Vector3.DOWN * half), color.darkened(0.2))

	func tube(from: Vector3, to: Vector3, radius: float, color: Color, sides: int = 8) -> void:
		## Cylinder between two points. Masts, stays, railings, barrels.
		var axis := to - from
		var length := axis.length()
		if length < 0.0001:
			return
		var basis := _look_basis(axis / length)
		cylinder((from + to) * 0.5, radius, radius, length, color, sides, basis, false)

	func _look_basis(direction: Vector3) -> Basis:
		var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		var x := up.cross(direction).normalized()
		var z := direction.cross(x).normalized()
		return Basis(x, direction, z)

	func commit(parent: Node3D, surface_material: Material, node_name: String = "") -> MeshInstance3D:
		if _count == 0:
			return null
		_surface.index()
		var mesh := MeshInstance3D.new()
		mesh.mesh = _surface.commit()
		mesh.material_override = surface_material
		if node_name != "":
			mesh.name = node_name
		parent.add_child(mesh)
		return mesh

# --------------------------------------------------------------------------- #
# Legacy simple primitives (effects, debris, markers)
# --------------------------------------------------------------------------- #

static func box(parent: Node3D, size: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = offset
	return mesh

static func cylinder(parent: Node3D, bottom: float, top: float, height: float,
		offset: Vector3, color: Color, sides: int = 8) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = sides
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = offset
	return mesh

static func ring(parent: Node3D, radius: float, color: Color, thickness: float = 0.13) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = radius - thickness
	shape.outer_radius = radius + thickness
	shape.rings = 48
	shape.ring_segments = 6
	mesh.mesh = shape
	mesh.material_override = material(color, true)
	parent.add_child(mesh)
	return mesh

static func hull_section(parent: Node3D, front_width: float, back_width: float,
		length: float, offset: Vector3, color: Color) -> MeshInstance3D:
	var vertices := PackedVector3Array([
		Vector3(-front_width, 1.0, -length / 2), Vector3(front_width, 1.0, -length / 2),
		Vector3(back_width, 1.0, length / 2), Vector3(-back_width, 1.0, length / 2),
		Vector3(-front_width * 0.65, -0.9, -length / 2), Vector3(front_width * 0.65, -0.9, -length / 2),
		Vector3(back_width * 0.65, -0.9, length / 2), Vector3(-back_width * 0.65, -0.9, length / 2)
	])
	var faces := [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
		1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in range(0, faces.size(), 3):
		for corner in [0, 2, 1]:
			surface.add_vertex(vertices[faces[triangle + corner]])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = offset
	return mesh

# --------------------------------------------------------------------------- #
# Terrain
# --------------------------------------------------------------------------- #

static func island(parent: Node3D, point: Vector3, radius: float, height: float) -> void:
	## Layered ridge with a sand skirt, rock band and scrub cap.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(point.x * 73 + point.z * 131))
	var count := 22
	var rings: Array[PackedVector3Array] = []
	var profiles := [Vector2(1.34, -0.22), Vector2(1.14, -0.02), Vector2(1.02, 0.035), Vector2(0.92, 0.14),
		Vector2(0.70, 0.46), Vector2(0.42, 0.83), Vector2(0.15, 1.0)]
	var distortion: Array[float] = []
	var ridge: Array[float] = []
	for i in range(count):
		distortion.append(rng.randf_range(0.82, 1.18))
		ridge.append(rng.randf_range(0.78, 1.16))
	for level in range(profiles.size()):
		var vertices := PackedVector3Array()
		for i in range(count):
			var angle := TAU * float(i) / count
			var blend: float = clampf(float(level) / 2.0, 0.0, 1.0)
			var wobble: float = lerpf(distortion[i], ridge[i], blend)
			var distance: float = radius * profiles[level].x * wobble
			var altitude: float = height * profiles[level].y
			if level >= 3:
				altitude *= rng.randf_range(0.82, 1.14)
			vertices.append(Vector3(cos(angle) * distance, altitude, sin(angle) * distance))
		rings.append(vertices)
	var builder := Builder.new()
	var palette := [Color("bcae8d"), Color("d2c6a4"), Color("b4a888"), Color("87856c"), Color("5c6a52"), Color("68785a")]
	for level in range(profiles.size() - 1):
		for i in range(count):
			var next := (i + 1) % count
			var color: Color = palette[level] * rng.randf_range(0.9, 1.1)
			color.a = 1.0
			builder.smooth(level + 1 if level >= 2 else -1)
			builder.quad(rings[level + 1][i], rings[level + 1][next], rings[level][next], rings[level][i], color)
	builder.smooth(-1)
	for i in range(count):
		var color: Color = palette[5] * rng.randf_range(0.9, 1.1)
		color.a = 1.0
		builder.tri(Vector3(0, height, 0), rings[6][(i + 1) % count], rings[6][i], color)
	var rock := steel(Color.WHITE, 0.94, 0.0, true, 0.12)
	rock.normal_scale = 1.1
	var mesh := builder.commit(parent, rock, "Island")
	mesh.position = point

class_name OceanSurface
extends Node3D
## CPU buoyancy and GPU displacement share these exact wave parameters and clock.
## Waves are Gerstner: crests are displaced horizontally as well as vertically,
## so finding the height under a hull means inverting that displacement.

# (direction.x, direction.y, steepness, wavelength)
const WAVES: Array[Vector4] = [
	Vector4(1.0, 0.35, 0.066, 73.0),
	Vector4(-0.42, 1.0, 0.058, 44.0),
	Vector4(0.75, 0.78, 0.051, 29.0),
	Vector4(-0.88, 0.40, 0.043, 19.0),
	Vector4(0.28, -0.96, 0.035, 13.0),
]
const GRAVITY := 9.81

var water: ShaderMaterial
var horizon_water: ShaderMaterial
var clock: float = 0.0

static func deferred() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func _ready() -> void:
	water = ShaderMaterial.new()
	water.shader = preload("res://shaders/ocean.gdshader")
	for index in range(WAVES.size()):
		water.set_shader_parameter("wave_%d" % index, WAVES[index])
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1500, 1500)
	# 449 subdivisions is 202,000 vertices, each running five Gerstner waves.
	# That is affordable on a deferred desktop renderer and is not on WebGL.
	var detail: int = 449 if deferred() else 180
	plane.subdivide_width = detail
	plane.subdivide_depth = detail
	mesh.mesh = plane
	mesh.material_override = water
	mesh.extra_cull_margin = 6.0
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	if not deferred():
		# The wind spectrum and the slick detail are the two things this
		# renderer cannot pay for. Four octaves still reads as wind-blown water;
		# seven is what makes it look wet up close.
		water.set_shader_parameter("wind_octaves", 4)
		water.set_shader_parameter("foam_octaves", 2)
		water.set_shader_parameter("rich_slicks", false)
		water.set_shader_parameter("detail_range", 900.0)
	# A calm, detail-free sheet carries the sea out to the horizon.
	horizon_water = ShaderMaterial.new()
	horizon_water.shader = water.shader
	for index in range(WAVES.size()):
		horizon_water.set_shader_parameter("wave_%d" % index, WAVES[index])
	horizon_water.set_shader_parameter("detail_range", 1.0)
	horizon_water.set_shader_parameter("choppiness", 0.45)
	horizon_water.set_shader_parameter("swell_scale", 0.0)
	var horizon := MeshInstance3D.new()
	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(26000, 26000)
	far_plane.subdivide_width = 3
	far_plane.subdivide_depth = 3
	horizon.mesh = far_plane
	horizon.material_override = horizon_water
	# Sits just under the deepest trough of the near-field swell.
	horizon.position.y = -1.9
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(horizon)

func set_sun(travel: Vector3, color: Color) -> void:
	for material in [water, horizon_water]:
		material.set_shader_parameter("sun_travel", travel.normalized())
		material.set_shader_parameter("sun_color", color)

func set_slicks(patches: Array) -> void:
	## patches: Array of Vector4(x, z, radius, strength). Pushed every frame,
	## since slicks drift, spread and fade.
	var packed := PackedVector4Array()
	for patch: Vector4 in patches:
		if packed.size() >= 12:
			break
		packed.append(patch)
	var live := packed.size()
	while packed.size() < 12:
		packed.append(Vector4(0, 0, 1, 0))
	for material in [water, horizon_water]:
		material.set_shader_parameter("slicks", packed)
		material.set_shader_parameter("slick_count", live)

func set_shores(islands: Array) -> void:
	## Feeds island footprints to the shader for shallow water and surf.
	var packed := PackedVector4Array()
	for island: Dictionary in islands:
		if packed.size() >= 6:
			break
		var point: Vector3 = island["position"]
		packed.append(Vector4(point.x, point.z, float(island["radius"]) + 5.0, 0.0))
	while packed.size() < 6:
		packed.append(Vector4(0, 0, -1000, 0))
	for material in [water, horizon_water]:
		material.set_shader_parameter("shores", packed)
		material.set_shader_parameter("shore_count", mini(islands.size(), 6))

func set_clock(value: float) -> void:
	clock = value
	water.set_shader_parameter("ocean_time", clock)
	horizon_water.set_shader_parameter("ocean_time", clock)

func height_at(point: Vector3) -> float:
	return sample_height(Vector2(point.x, point.z), clock)

static func displacement(source: Vector2, time: float) -> Vector3:
	var offset := Vector3.ZERO
	for wave in WAVES:
		var k: float = TAU / wave.w
		var celerity: float = sqrt(GRAVITY / k)
		var direction := Vector2(wave.x, wave.y).normalized()
		var amplitude: float = wave.z / k
		var phase: float = k * (direction.dot(source) - celerity * time)
		offset += Vector3(direction.x * amplitude * cos(phase), amplitude * sin(phase),
			direction.y * amplitude * cos(phase))
	return offset

static func sample_height(point: Vector2, time: float) -> float:
	# Invert the horizontal part of the Gerstner displacement so we report the
	# height of the surface actually drawn above this map position.
	var source := point
	for iteration in range(3):
		var offset := displacement(source, time)
		source = point - Vector2(offset.x, offset.z)
	return displacement(source, time).y

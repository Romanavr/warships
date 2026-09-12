class_name PatrolBoat
extends Node3D
## Modular corvette. Component state is independent of geometry and shared tuning.
const DEFAULT_LOADOUT = preload("res://ships/kestrel.tres")
const RELOAD: float = 3.2
const GUN_RANGE: float = 600.0
const MISSILE_RANGE: float = 1400.0
const MISSILE_RELOAD: float = 8.0
@export var loadout: ShipLoadout = DEFAULT_LOADOUT
var world: Node3D
var team: int = 0
var callsign: String = "K-01"
var manual: bool = false
var speed: float = 0.0
var throttle: float = 0.0
# Helm state. A rudder takes time to swing and only bites when water is moving
# past it, so the hull has to be making way before it will answer.
const HELM_RATE: float = 2.10
const TURN_RATE: float = 0.54
const FLOW_SPEED: float = 0.34
const DRIFT_RESPONSE: float = 1.15
var helm: float = 0.0
var course := Vector3.ZERO
var cooldown: float = 0.0
var aft_cooldown: float = 0.0
var missile_cooldown: float = 0.0
var missile_ammo: int:
	get:
		return cell_loaded.count(true)
var cell_loaded: Array[bool] = [true, true, true, true]
var cell_banks: Array[String] = ["launcher_port", "launcher_port", "launcher_starboard", "launcher_starboard"]
var cell_muzzles: Array[Node3D] = []
var cell_lids: Array[MeshInstance3D] = []
var systems: Dictionary = {}
var system_meshes: Dictionary = {}
var fire_sources: Dictionary = {}
var stock_materials: Dictionary = {}
# Chance per hit that a loaded launch bank cooks off, scaled by the weight of
# the hit and how many cells are still live.
const MAGAZINE_RISK: float = 0.11
const DC_COOLDOWN: float = 16.0
const DC_DURATION: float = 4.0
var damage_control: float = 0.0
var dc_cooldown: float = 0.0
var offline_by_design: Array[String] = []
## An unarmed hull: no crew action, no magazine, nothing to shoot with.
var noncombatant: bool = false
## A friendly told to keep station on another hull instead of going hunting.
## She fights from where she is, which is the whole point: a close-in gun covers
## about 190 m, and an escort that charges to gun range is an escort standing
## outside the umbrella she was sent to stand under.
var station_on: PatrolBoat
var station_offset := Vector3.ZERO
## Under a cease-fire. A disabled merchant is still burning and still taking
## water, and the campaign does not want her sinking after the player has
## already done what was asked, so damage stops reaching her.
var protected: bool = false
var explosive_death: bool = false
var flooding: float = 0.0
var sunk: bool = false
var sinking_time: float = 0.0
var oil_clock: float = 0.0
var next_secondary: float = 0.0
var secondary_left: int = 0
var colliders: Array[RID] = []
var target: PatrolBoat
var destination := Vector3.ZERO
var has_move_order: bool = false
var explicit_target: bool = false
# Missile doctrine. A crew that empties four cells into a working CIWS learns
# nothing; this one probes, notices what happened, and reacts.
var probes_fired: int = 0
var seen_intercepts: int = 0
var suppressing_ciws: bool = false
var probe_clock: float = 0.0
const PROBE_WAIT: float = 15.0
var status: String = "PATROL"
var visuals: Node3D
var turret: Node3D
var aft_turret: Node3D
var ciws_turret: Node3D
var radar_mount: Node3D
var beacon: MeshInstance3D
var beacon_phase: float = 0.0
var barrel: MeshInstance3D
var aft_barrel: MeshInstance3D
var selection: MeshInstance3D
var fire_clock: float = 0.0
var wake_clock: float = 0.0
var ciws_clock: float = 0.0
var ciws_heat: float = 0.0
var ciws_cooling: float = 0.0
var ciws_ammo: int = 120
var ciws_enabled: bool = true
var ciws_status: String = "SEARCHING"
var ciws_target: Node3D
var sam_ammo: int = 4
var sam_cooldown: float = 5.0
var sam_status: String = "SEARCHING"
var sam_muzzles: Array[Node3D] = []
var sam_lids: Array[MeshInstance3D] = []
var gun_health: float:
	get:
		return systems["gun"].health if systems.has("gun") else 0.0
	set(value):
		if systems.has("gun"):
			systems["gun"].health = value

func _ready() -> void:
	visuals = Node3D.new()
	add_child(visuals)
	ciws_ammo = loadout.ciws_rounds
	noncombatant = loadout.civilian
	var layout: Dictionary = ShipLayout.of(loadout.hull_model)
	build_systems(layout)
	build_ship()
	selection = NavalGeometry.ring(self, float(layout["selection_radius"]), Color("8ce0c8"), 0.1)
	selection.visible = false
	selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A class built on the corvette mesh is that model scaled to its real length.
	# One with a model of its own is authored true-size and left alone.
	if bool(layout["scale_to_length"]):
		var factor: float = loadout.length / ShipLayout.CORVETTE_LENGTH
		visuals.scale = Vector3.ONE * factor
		selection.scale = Vector3.ONE * factor
	strip_offline_kit()

func strip_offline_kit() -> void:
	## Kit this class was never fitted with. What the Tern is missing — no CIWS
	## to swat the player's missiles, no anti-ship missiles of its own — used to
	## be hard-coded here; it now comes off the loadout, so a new class is a
	## resource rather than another branch. See the difficulty work in
	## docs/ROADMAP.md.
	offline_by_design = loadout.offline_by_design.duplicate()
	if offline_by_design.is_empty():
		return
	for id: String in offline_by_design:
		systems[id].health = 0
		systems[id].disabled_reported = true
		if system_meshes.has(id):
			system_meshes[id].visible = false
	show_mount(turret, "gun")
	show_mount(aft_turret, "aft_gun")
	show_mount(ciws_turret, "ciws")
	if offline_by_design.has("ciws"):
		ciws_ammo = 0
		ciws_enabled = false
	if offline_by_design.has("sam"):
		sam_ammo = 0
		for lid in sam_lids:
			lid.visible = false
	# Only the banks that are missing lose their rounds, so a hull can carry one
	# live launcher.
	for i in range(cell_lids.size()):
		if offline_by_design.has(cell_banks[i]):
			cell_loaded[i] = false
			cell_lids[i].visible = false

func add_stub(id: String) -> void:
	## A module this class was never built with at all — a freighter's gun
	## mounts, say. It exists only so `operational(id)` has something to answer
	## with: no collider, no geometry, nothing to hit.
	var system := ShipSystem.new(id, id, 1.0, Vector3.ZERO, Vector3.ZERO, "mid")
	system.health = 0.0
	system.disabled_reported = true
	systems[id] = system

func add_system(id: String, label: String, point: Vector3, bounds: Vector3, room: String, hull: bool = false) -> void:
	var system := ShipSystem.new(id, label, float(loadout.component_health.get(id, 1.0)), point, bounds, room, hull)
	systems[id] = system
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("boat", self)
	body.set_meta("section", id)
	visuals.add_child(body)
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds
	collision.shape = shape
	body.add_child(collision)
	colliders.append(body.get_rid())

func build_systems(layout: Dictionary) -> void:
	## The boxes are the ship: shells and the pointer hit these, never the
	## geometry. Where they sit per class is ShipLayout's business.
	var modules: Dictionary = layout["modules"]
	for id: String in ShipLayout.MODULE_IDS:
		if not modules.has(id):
			add_stub(id)
			continue
		var row: Array = modules[id]
		add_system(id, String(row[0]), row[1], row[2], String(row[3]), bool(row[4]))

func build_ship() -> void:
	var compact := loadout.length < 40.0
	var model := ShipModel.build(visuals, team, compact, callsign, loadout.hull_model)
	system_meshes = model["system_meshes"]
	turret = model["turret"]
	aft_turret = model["aft_turret"]
	ciws_turret = model["ciws_turret"]
	barrel = model["barrel"]
	aft_barrel = model["aft_barrel"]
	cell_lids.assign(model["cell_lids"])
	cell_muzzles.assign(model["cell_muzzles"])
	sam_lids.assign(model["sam_lids"])
	sam_muzzles.assign(model["sam_muzzles"])
	radar_mount = model["radar_mount"]
	beacon = model.get("beacon")
	# Offset per hull, so a division under way does not flash in unison like a
	# string of fairy lights.
	beacon_phase = randf() * BEACON_PERIOD
	for id: String in system_meshes:
		stock_materials[id] = system_meshes[id].material_override

func operational(id: String) -> bool:
	return systems[id].working()

func usable_missiles() -> int:
	var count := 0
	for i in range(4):
		if cell_loaded[i] and operational(cell_banks[i]):
			count += 1
	return count

func is_combat_capable() -> bool:
	# Reload is temporary, loss of propulsion is not disarmament. CIWS is defensive only.
	return not sunk and (operational("gun") or operational("aft_gun") or
		(operational("radar") and usable_missiles() > 0))

func hull_fraction() -> float:
	var health := 0.0
	var maximum := 0.0
	for id: String in ["bow", "mid", "stern"]:
		health += systems[id].health
		maximum += systems[id].maximum
	return health / maximum

## Anti-collision flash: a short pulse on a long period, the way a ship's is,
## rather than a lazy on-off blink.
const BEACON_PERIOD: float = 1.7
const BEACON_FLASH: float = 0.13

func blink_beacon() -> void:
	# A hull with the sea coming over her has lost the ship's supply: the steady
	# lights go out with the beacon.
	if sunk and visuals.has_meta("navigation_lights"):
		var steady = visuals.get_meta("navigation_lights")
		if is_instance_valid(steady):
			steady.visible = false
	if not is_instance_valid(beacon):
		return
	beacon.visible = not sunk and fmod(world.elapsed + beacon_phase, BEACON_PERIOD) < BEACON_FLASH

func _physics_process(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	aft_cooldown = maxf(0, aft_cooldown - delta)
	damage_control = maxf(0, damage_control - delta)
	probe_clock += delta
	dc_cooldown = maxf(0, dc_cooldown - delta)
	missile_cooldown = maxf(0, missile_cooldown - delta)
	# Recoil runs the barrels back out. A hull with no guns fitted has no barrel
	# to run out, so every mount reference on this class is optional.
	if is_instance_valid(barrel):
		barrel.position.z = move_toward(barrel.position.z, -3.5, delta * 2)
	if is_instance_valid(radar_mount) and operational("radar"):
		radar_mount.rotation.y += delta * 1.9
	blink_beacon()
	if is_instance_valid(aft_barrel):
		aft_barrel.position.z = move_toward(aft_barrel.position.z, -3.5, delta * 2)
	if sunk:
		process_sinking(delta)
		return
	process_damage(delta)
	if sunk:
		return
	process_ciws(delta)
	process_sam(delta)
	var turn := 0.0
	if manual:
		throttle = Input.get_axis("astern", "ahead")
		turn = Input.get_axis("starboard", "port")
		var aim := player_aim()
		aim_gun(aim, delta)
		if Input.is_action_pressed("fire") and not world.pointer_over_ui():
			if world.cleared("gun"):
				shoot(aim)
			else:
				world.refuse("gun", "Main battery is not cleared to fire")
		status = "DIRECT CONTROL" if is_combat_capable() else "WEAPONS LOST"
	else:
		turn = think(delta)
	var engine: ShipSystem = systems["engine"]
	var maximum_speed := loadout.speed * engine.fraction() * (1.0 - flooding * 0.65)
	speed = move_toward(speed, throttle * maximum_speed, delta * (2.4 if manual else 1.2))
	# The wheel is an order to the rudder, not to the bow.
	helm = move_toward(helm, clampf(turn, -1.0, 1.0), delta * HELM_RATE)
	var authority: float = systems["rudder"].fraction()
	if not operational("bridge"):
		authority *= 0.35
	# Rudder bite comes from flow over the blade: dead in the water, nothing.
	var flow := clampf(absf(speed) / maxf(loadout.speed * FLOW_SPEED, 0.01), 0.0, 1.0)
	rotation.y += helm * TURN_RATE * flow * authority * delta * (-1 if speed < 0 else 1)
	# The hull carries its own momentum, so a turn skids before the ship follows.
	course = course.lerp(-basis.z * speed, 1.0 - exp(-delta * DRIFT_RESPONSE))
	var next := position + course * delta
	if world.position_clear(next, self):
		position = next
	else:
		speed = move_toward(speed, 0, delta * 10)
		course = course.lerp(Vector3.ZERO, 1.0 - exp(-delta * 4.0))
		if not manual:
			rotation.y += delta * 0.14 * authority
	update_buoyancy(delta)
	wake_clock += delta
	if wake_clock > 0.12 and absf(speed) > 0.6:
		wake_clock = 0
		world.wake(position + basis.z * (loadout.length * 0.46), rotation.y, absf(speed) / loadout.speed)
		world.bow_spray(visuals.to_global(Vector3(0, 0.4, -24)), basis.x, absf(speed) / loadout.speed)

func merchant_think(_delta: float) -> float:
	## A merchant holds her course and speed and takes no interest in anyone.
	## She must never reach the gunnery code below: `nearest_enemy()` screens on
	## whether the *candidate* can fight, not the caller, so an unarmed hull will
	## happily acquire a warship and then try to sight down a turret it does not
	## have.
	target = null
	explicit_target = false
	if sunk or not operational("engine"):
		throttle = 0.0
		status = "DEAD IN THE WATER"
		return 0.0
	throttle = 0.85
	status = "MERCHANT / IN TRANSIT"
	if not has_move_order:
		return 0.0
	var course_to := destination - position
	course_to.y = 0.0
	if course_to.length() < 120.0:
		has_move_order = false
		return 0.0
	return steer_toward(course_to)

func update_buoyancy(delta: float) -> void:
	var response := 1 - exp(-delta * 2)
	position.y = lerpf(position.y, world.ocean.height_at(position), response)
	var bow: float = world.ocean.height_at(position - basis.z * (loadout.length * 0.426))
	var stern: float = world.ocean.height_at(position + basis.z * (loadout.length * 0.426))
	var port: float = world.ocean.height_at(position - basis.x * (loadout.beam * 0.4))
	var starboard: float = world.ocean.height_at(position + basis.x * (loadout.beam * 0.4))
	visuals.position.y = -flooding * 1.8
	visuals.rotation.x = lerpf(visuals.rotation.x, atan2(bow - stern, loadout.length * 0.852), response)
	visuals.rotation.z = lerpf(visuals.rotation.z, atan2(starboard - port, loadout.beam * 0.8) + flooding * 0.25, response)
	selection.position.y = world.ocean.height_at(position) - position.y + 1.4

func think(delta: float) -> float:
	if noncombatant:
		return merchant_think(delta)
	if not is_instance_valid(target) or not target.is_combat_capable():
		target = null
		explicit_target = false
	var previous := target
	if not explicit_target:
		target = world.nearest_enemy(self)
	if target != previous:
		# A fresh contact is a fresh problem: nothing learned about this one yet.
		probes_fired = 0
		seen_intercepts = 0
		suppressing_ciws = false
		probe_clock = PROBE_WAIT
	var desired := Vector3.ZERO
	throttle = 0
	var keeping: bool = is_instance_valid(station_on) and not station_on.sunk
	# Nothing to steer toward when there is nothing to fight. This used to send
	# every idle hull to a fixed waypoint left over from the first build — a
	# marked point in the water that no level ever referred to and that the
	# player had no reason to care about.
	if keeping:
		# Station is relative to the covering ship's heading, so the formation
		# turns with her rather than smearing across the sea when she manoeuvres.
		var post: Vector3 = station_on.position \
			+ station_offset.rotated(Vector3.UP, station_on.rotation.y)
		desired = post - position
		var gap := desired.length()
		if gap < 22.0:
			# Close enough. Match her speed rather than stopping dead, or the
			# escort falls astern the moment the covering ship works up.
			throttle = clampf(station_on.throttle, 0.0, 0.6)
			desired = -station_on.global_basis.z
			status = "ON STATION"
		else:
			throttle = clampf(gap / 80.0, 0.15, 0.95)
			status = "CLOSING ON STATION"
		if is_instance_valid(target):
			status = "ON STATION / ENGAGING"
	elif has_move_order:
		desired = destination - position
		if desired.length() < 28:
			has_move_order = false
		else:
			throttle = clampf(desired.length() / 70, 0, 0.8)
		status = "TRANSITING"
	elif is_instance_valid(target):
		var distance := position.distance_to(target.position)
		desired = target.position - position
		if not is_combat_capable() or flooding > 0.7:
			desired = -desired
			throttle = 0.7
			status = "WITHDRAWING"
		elif distance > 410:
			throttle = 0.8
			status = "CLOSING TO GUN RANGE"
		elif distance < 260:
			desired = -desired
			throttle = 0.5
			status = "OPENING RANGE"
		else:
			desired = Vector3(desired.z, 0, -desired.x)
			throttle = 0.25
			status = "ENGAGING"
	else:
		status = "HOLD / NO ACTIVE THREATS"
	if is_instance_valid(target) and target.is_combat_capable():
		var distance := position.distance_to(target.position)
		var aim := gun_aim_point(target, distance)
		aim_gun(aim, delta)
		if distance < loadout.gun_range:
			shoot(aim)
		if distance > 120 and distance < loadout.missile_range and world.clear_shot(self, target):
			if should_launch_at(target) and launch_missile(target):
				probes_fired += 1
				probe_clock = 0.0
	return steer_toward(desired)

func steer_toward(desired: Vector3) -> float:
	## Turn the wheel toward a heading, giving way to land on the way.
	if desired.length() < 0.5:
		return 0
	desired = world.avoidance(self, desired.normalized())
	var heading := atan2(-desired.x, -desired.z)
	var error := wrapf(heading - rotation.y, -PI, PI)
	if absf(error) > 1:
		throttle = minf(throttle, 0.4)
	# A stopped ship cannot turn, so the crew keeps enough way on to steer.
	if absf(error) > 0.25:
		throttle = maxf(throttle, 0.32)
	return clampf(error * 2, -1, 1)

func aim_gun(aim: Vector3, delta: float) -> void:
	for id: String in ["gun", "aft_gun"]:
		if not operational(id):
			continue
		var mount := turret if id == "gun" else aft_turret
		var local := visuals.to_local(aim) - mount.position
		var angle := atan2(-local.x, -local.z)
		mount.rotation.y = rotate_toward(mount.rotation.y, angle, delta * (2.4 if manual else 0.9))

func player_aim() -> Vector3:
	## The player picks the aim point, including which part of a hull to hit.
	## The only help given is lead: the shot is displaced by however far the
	## target will travel while the shell is in the air, so travel time is not
	## something to fight, but choosing the bridge over the waterline still is.
	var pick: Dictionary = world.pointer_target(colliders)
	var aim: Vector3 = pick["position"]
	var unit: Node3D = pick["unit"]
	if is_instance_valid(unit) and unit != self:
		world.designate(unit)
		var flight := position.distance_to(aim) / 230.0
		if unit is PatrolBoat:
			aim -= unit.basis.z * unit.speed * flight
		elif unit is CombatHelicopter:
			aim += unit.velocity * flight
	return aim

func reload_time() -> float:
	return RELOAD * (0.55 if manual else 1.0)

func gun_ready(aft: bool = false) -> float:
	var span := reload_time() + (0.4 if aft else 0.0)
	return 1.0 - (aft_cooldown if aft else cooldown) / maxf(span, 0.01)

func missile_reload_time() -> float:
	return loadout.missile_reload * (0.6 if manual else 1.0)

func shoot(aim: Vector3) -> bool:
	if sunk:
		return false
	var fired := false
	for id: String in ["gun", "aft_gun"]:
		if not operational(id) or (cooldown > 0 if id == "gun" else aft_cooldown > 0):
			continue
		var mount := turret if id == "gun" else aft_turret
		var tube := barrel if id == "gun" else aft_barrel
		var muzzle := mount.to_global(Vector3(0, 1, -6.8))
		var direction := muzzle.direction_to(aim)
		if muzzle.distance_to(aim) > loadout.gun_range or muzzle.distance_to(aim) < 20:
			continue
		if (-mount.global_basis.z).angle_to(direction) > 0.14:
			continue
		# All geometry blocks fire, including our own bridge or an allied ship.
		var obstruction := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, aim, 3))
		if not obstruction.is_empty():
			var blocked_by: PatrolBoat = (obstruction.collider.get_meta("boat") if obstruction.collider.has_meta("boat") else null)
			if blocked_by == null or blocked_by.team == team:
				continue
		if id == "gun":
			cooldown = reload_time()
		else:
			aft_cooldown = reload_time() + 0.4
		tube.position.z = -2.6
		world.fire_shell(muzzle, aim, colliders, manual)
		world.muzzle_flash(muzzle, -mount.global_basis.z, 2.6 if id == "gun" else 2.2)
		fired = true
	return fired

func missile_status(boat: PatrolBoat) -> String:
	if sunk:
		return "VESSEL LOST"
	if manual and not world.cleared("missile"):
		return "NOT CLEARED"
	if not operational("radar"):
		return "RADAR OFFLINE"
	if missile_ammo == 0:
		return "MAGAZINE EMPTY"
	if usable_missiles() == 0:
		return "VLS OFFLINE"
	if missile_cooldown > 0:
		return "READY IN %.1fs" % missile_cooldown
	if not is_instance_valid(boat) or boat.sunk or boat.team == team:
		return "NO HOSTILE LOCK"
	var distance := position.distance_to(boat.position)
	if distance > loadout.missile_range:
		return "OUT OF RANGE"
	if distance < 100:
		return "INSIDE MIN RANGE"
	return "READY"

func launch_missile(boat: PatrolBoat) -> bool:
	if missile_status(boat) != "READY":
		return false
	for slot in range(4):
		if not cell_loaded[slot] or not operational(cell_banks[slot]):
			continue
		cell_loaded[slot] = false
		cell_lids[slot].rotation.x = -1.35
		var origin := cell_muzzles[slot].global_position
		missile_cooldown = missile_reload_time()
		if manual:
			world.tally.missiles += 1
		world.fire_missile(origin, boat, self)
		return true
	return false

func process_ciws(delta: float) -> void:
	ciws_clock = maxf(0, ciws_clock - delta)
	ciws_cooling = maxf(0, ciws_cooling - delta)
	if not ciws_enabled or not operational("ciws") or ciws_ammo <= 0:
		ciws_status = "OFFLINE" if not operational("ciws") else ("EMPTY" if ciws_ammo <= 0 else "HOLD")
		return
	# The hold is on aircraft only: a missile inbound on us is still shot at.
	ciws_target = world.incoming_missile(self, loadout.ciws_range)
	var against_aircraft := false
	if not is_instance_valid(ciws_target) and not holding_air():
		ciws_target = world.nearest_aircraft(self, 150.0)
		against_aircraft = is_instance_valid(ciws_target)
	if not is_instance_valid(ciws_target):
		ciws_status = "SEARCHING"
		ciws_heat = maxf(0, ciws_heat - delta)
		return
	var muzzle := ciws_turret.to_global(Vector3(0, 0.8, -3.3))
	var flight := muzzle.distance_to(ciws_target.position) / 650.0
	var aim: Vector3 = ciws_target.position + ciws_target.velocity * flight
	var desired := ciws_turret.global_transform.looking_at(aim, Vector3.UP).basis
	var mount_scale := ciws_turret.global_basis.get_scale()
	ciws_turret.global_basis = ciws_turret.global_basis.orthonormalized().slerp(desired.orthonormalized(), minf(1, delta * 8)).orthonormalized().scaled(mount_scale)
	ciws_status = "TRACKING"
	if ciws_cooling > 0:
		ciws_status = "COOLING"
		return
	if (-ciws_turret.global_basis.z).angle_to(muzzle.direction_to(aim)) > 0.10 or ciws_clock > 0:
		return
	var obstruction := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(muzzle, aim, 3, colliders))
	if not obstruction.is_empty():
		ciws_status = "MASKED"
		return
	ciws_status = "INTERCEPTING"
	ciws_ammo -= 1
	ciws_clock = 0.05
	ciws_heat += 0.05
	if ciws_heat >= 0.65:
		ciws_heat = 0
		ciws_cooling = 0.9
	world.fire_ciws(muzzle, aim, colliders, against_aircraft)
	if ciws_ammo % 3 == 0:
		world.burst(muzzle, Color("ffe7b1"), 1, 0.07)

func can_intercept() -> bool:
	return not sunk and ciws_enabled and operational("ciws") and ciws_ammo > 0

func note_interception() -> void:
	## One of ours was shot down on the way in.
	seen_intercepts += 1

func should_launch_at(contact: PatrolBoat) -> bool:
	## Send a couple and wait to see whether they arrive. If they are being
	## swatted, put the guns on the mount doing the swatting before spending any
	## more; if they are getting through, keep sending them.
	# Nothing at all if there is an island in the way: the seeker would lose the
	# track on the way in, so the round is thrown away before it is fired.
	if not world.line_of_sight(self, contact):
		return false
	if not contact.can_intercept():
		suppressing_ciws = false
		return true
	if seen_intercepts > 0:
		suppressing_ciws = true
		return false
	suppressing_ciws = false
	if probes_fired < 2:
		return true
	# Two are in the air. Nothing is learned by emptying the magazine behind them.
	return probe_clock > PROBE_WAIT

func gun_aim_point(contact: PatrolBoat, distance: float) -> Vector3:
	## Centre of mass normally; the CIWS mount while suppressing it.
	var local := Vector3(0, 2.2, 0)
	if suppressing_ciws and contact.systems.has("ciws") and contact.operational("ciws"):
		local = contact.systems["ciws"].position
	return contact.visuals.to_global(local) - contact.basis.z * contact.speed * distance / 230.0

func holding_air() -> bool:
	## Only ours, and only when the mission says so. A hostile hull is never
	## told to stop shooting at aircraft.
	return team == 0 and world != null and world.air_hold

func can_engage_air() -> bool:
	if holding_air():
		return false
	return not sunk and ((operational("sam") and sam_ammo > 0) or (operational("ciws") and ciws_ammo > 0))

func process_sam(delta: float) -> void:
	sam_cooldown = maxf(0, sam_cooldown - delta)
	if holding_air():
		sam_status = "HOLD"
		return
	if not operational("sam") or sam_ammo == 0:
		sam_status = "OFFLINE" if not operational("sam") else "EMPTY"
		return
	var aircraft: CombatHelicopter = world.nearest_aircraft(self, 850.0)
	sam_status = "SEARCHING"
	if aircraft == null:
		return
	sam_status = "RELOADING" if sam_cooldown > 0 else "ENGAGING"
	if sam_cooldown > 0:
		return
	var slot := 4 - sam_ammo
	sam_ammo -= 1
	sam_cooldown = 8.0
	sam_lids[slot].rotation.x = -1.3
	world.fire_sam(sam_muzzles[slot].global_position, aircraft, self)

func order_move(point: Vector3) -> void:
	destination = Vector3(point.x, 0, point.z)
	has_move_order = true
	explicit_target = false

func order_attack(boat: PatrolBoat) -> void:
	target = boat
	explicit_target = true
	has_move_order = false

func take_hit(id: String, damage: float, point: Vector3, by_player: bool = false, depth: int = 0) -> void:
	if protected:
		return
	if sunk or not systems.has(id):
		return
	var system: ShipSystem = systems[id]
	# A wrecked module is a hole, not armour: the round carries on into the
	# compartment behind it instead of being absorbed by scrap.
	if not system.working() and depth < 2:
		if system.hull:
			# Nothing left to break in this compartment — the sea comes in.
			flooding = minf(1.0, flooding + damage / 1900.0)
			world.report_hit(point, damage * 0.35, false, by_player)
			if manual:
				world.report_player_damage(damage * 0.5)
			return
		if systems.has(system.compartment):
			take_hit(system.compartment, damage * 0.75, point, by_player, depth + 1)
			return
	var was_working := system.working()
	damage_system(id, damage)
	# A hit into a loaded launch bank can take the magazine with it.
	if not sunk and id.begins_with("launcher"):
		var live := 0
		for slot in range(4):
			if cell_banks[slot] == id and cell_loaded[slot]:
				live += 1
		if live > 0 and randf() < MAGAZINE_RISK * clampf(damage / 64.0, 0.5, 2.0) * float(live) * 0.5:
			world.magazine_detonation(self, visuals.to_global(system.position))
			return
	system.fire = minf(1.0, system.fire + damage / system.maximum * 0.9)
	flash_component(id, 6.5)
	if system.compartment != id:
		# The compartment around the hit lights up too, so the strike is legible
		# even when the module itself is small or hidden behind the deckhouse.
		flash_component(system.compartment, 2.2)
	world.report_hit(point, damage, was_working and not system.working(), by_player)
	if manual:
		world.report_player_damage(damage)

func char_tree(node: Node, burnt: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = burnt
	for child in node.get_children():
		char_tree(child, burnt)

func restore_tree(node: Node, stock: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = stock
	for child in node.get_children():
		restore_tree(child, stock)

func flash_component(id: String, energy: float = 4.5) -> void:
	## The struck module glows white-hot for a moment. Reading the hit on the
	## target itself is worth more than any amount of sparks in front of it.
	var mesh: MeshInstance3D = system_meshes.get(id)
	if mesh == null or not (mesh.material_override is StandardMaterial3D):
		return
	var material: StandardMaterial3D = mesh.material_override
	material.emission_enabled = true
	material.emission = Color(1.0, 0.66, 0.34)
	material.emission_energy_multiplier = energy
	var fade := create_tween()
	fade.tween_property(material, "emission_energy_multiplier", 0.0, 0.4)

func damage_system(id: String, damage: float) -> void:
	var system: ShipSystem = systems[id]
	if not system.working():
		return
	system.health = maxf(0, system.health - damage)
	if system.health <= 0:
		disable_system(system)

func disable_system(system: ShipSystem) -> void:
	if system.disabled_reported:
		return
	system.disabled_reported = true
	if not sunk:
		world.report_module_lost(visuals.to_global(system.position), system.label,
			self == world.player_ship)
	var mesh: MeshInstance3D = system_meshes.get(system.id)
	if mesh != null:
		# Imported modules carry their fittings as children, so the char has to
		# reach the whole assembly, not just the shell.
		char_tree(mesh, NavalGeometry.charred())
	if system.id == "gun":
		world.detach_part(turret)
	elif system.id == "aft_gun":
		world.detach_part(aft_turret)
	elif system.id == "radar":
		world.detach_part(mesh, 0.8)
	if system.id == "ciws":
		world.detach_part(ciws_turret, 0.8)
	if system.hull:
		for side: float in [-1.0, 1.0]:
			var seat := ShipModel.topside_point(system.position.z, 1.8, side)
			var panel := NavalGeometry.box(visuals, Vector3(0.22, 2.4, 4.6), seat, Color("4a565c"))
			panel.rotation.z = -side * 0.12
			world.detach_part(panel, 0.7)
	world.cooling_sparks(visuals.to_global(system.position), 0.5)
	world.debris(visuals.to_global(system.position), 5)
	world.report("%s / %s destroyed" % [callsign, system.label])

func take_blast(point: Vector3, damage: float, by_player: bool = false) -> void:
	if protected:
		return
	if sunk:
		return
	world.report_hit(point, damage, true, by_player)
	if manual:
		world.report_player_damage(damage)
	for id: String in systems:
		var system: ShipSystem = systems[id]
		var distance := point.distance_to(visuals.to_global(system.position))
		var falloff := clampf(1.0 - distance / 32.0, 0, 1)
		if falloff > 0:
			damage_system(id, damage * falloff)
			system.fire = minf(1.0, system.fire + falloff)
	flooding = minf(1.0, flooding + 0.09)
	if hull_fraction() < 0.1:
		begin_sinking(true)

func revive_module(id: String) -> void:
	## Bring a wrecked module back: clear the charring, put the assembly back on
	## the ship and let it report being destroyed again if it goes a second time.
	var system: ShipSystem = systems[id]
	system.disabled_reported = false
	var mesh: MeshInstance3D = system_meshes.get(id)
	if mesh != null:
		restore_tree(mesh, stock_materials.get(id))
		mesh.visible = true
	match id:
		"gun":
			if is_instance_valid(turret):
				turret.visible = true
		"aft_gun":
			if is_instance_valid(aft_turret):
				aft_turret.visible = true
		"ciws":
			if is_instance_valid(ciws_turret):
				ciws_turret.visible = true
		"radar":
			if is_instance_valid(radar_mount):
				radar_mount.visible = true

func take_supplies_repair() -> String:
	## A repair crate makes the ship whole again: every compartment and every
	## module back to full, fires out, water pumped. It does not touch the
	## magazines — that is what the ordnance crate is for.
	var revived := 0
	for id: String in systems:
		if offline_by_design.has(id):
			continue
		var system: ShipSystem = systems[id]
		if not system.working():
			revived += 1
		system.health = system.maximum
		system.fire = 0.0
		if not system.disabled_reported:
			continue
		revive_module(id)
	flooding = 0.0
	dc_cooldown = 0.0
	damage_control = 0.0
	visuals.position.y = 0.0
	update_fires()
	if revived > 0:
		return "Fully repaired, %d module%s back online" % [revived, "" if revived == 1 else "s"]
	return "Fully repaired"

func take_supplies_ordnance() -> String:
	var loaded := 0
	for slot in range(cell_lids.size()):
		if loaded >= 2:
			break
		if not cell_loaded[slot] and operational(cell_banks[slot]):
			cell_loaded[slot] = true
			cell_lids[slot].rotation.x = 0.0
			loaded += 1
	ciws_ammo = mini(loadout.ciws_rounds, ciws_ammo + 40)
	if sam_ammo < 4 and operational("sam"):
		sam_ammo += 1
	if loaded == 0:
		return "Ammunition topped up"
	return "%d anti-ship missile%s loaded" % [loaded, "" if loaded == 1 else "s"]

func show_mount(mount: Node3D, id: String) -> void:
	## A mount this class was never fitted with is not a node at all.
	if is_instance_valid(mount):
		mount.visible = not offline_by_design.has(id)

func repair(fraction: float = 1.0) -> void:
	## Underway replenishment between levels: hull, machinery and magazines.
	##
	## `fraction` is how much of each system's *maximum* the yard puts back, not
	## a target level — so at less than one a wrecked mount comes back
	## part-working and a lightly scratched one comes back new. The campaign
	## passes one, a full repair; the parameter exists so a level can ask for
	## less without the damage model needing to know why.
	var given: float = clampf(fraction, 0.0, 1.0)
	for id: String in systems:
		var system: ShipSystem = systems[id]
		if offline_by_design.has(id):
			continue
		system.health = minf(system.maximum, system.health + system.maximum * given)
		system.fire = 0.0
		system.disabled_reported = false
	flooding = 0.0
	sunk = false
	sinking_time = 0.0
	secondary_left = 0
	for id: String in system_meshes:
		var mesh: MeshInstance3D = system_meshes[id]
		restore_tree(mesh, stock_materials.get(id))
		mesh.visible = not offline_by_design.has(id)
	show_mount(turret, "gun")
	show_mount(aft_turret, "aft_gun")
	show_mount(ciws_turret, "ciws")
	if is_instance_valid(radar_mount):
		radar_mount.visible = true
	for slot in range(cell_lids.size()):
		var fitted := not offline_by_design.has(cell_banks[slot])
		cell_loaded[slot] = fitted
		cell_lids[slot].visible = fitted
		cell_lids[slot].rotation.x = 0.0
	sam_ammo = 0 if offline_by_design.has("sam") else 4
	for index in range(sam_lids.size()):
		sam_lids[index].visible = sam_ammo > 0
		sam_lids[index].rotation.x = 0.0
	ciws_ammo = loadout.ciws_rounds
	ciws_heat = 0.0
	ciws_cooling = 0.0
	missile_cooldown = 0.0
	cooldown = 0.0
	aft_cooldown = 0.0
	damage_control = 0.0
	dc_cooldown = 0.0
	for source in fire_sources.values():
		source.set_intensity(0.0)
	visuals.position.y = 0.0
	position.y = world.ocean.height_at(position)

func take_shockwave(point: Vector3, damage: float) -> void:
	if protected:
		return
	## Blast arriving from a distance. take_blast() falls off over 32 m because
	## it models a warhead going off against this hull; a magazine detonation a
	## hundred metres away needs its own path or it does nothing at all.
	if sunk or damage <= 0.0:
		return
	for id: String in ["bow", "mid", "stern"]:
		damage_system(id, damage * 0.34)
	for id: String in systems:
		systems[id].fire = minf(1.0, systems[id].fire + damage / 420.0)
	flooding = minf(1.0, flooding + damage / 900.0)
	world.report_hit(visuals.to_global(Vector3(0, 3, 0)), damage, false, false)
	if manual:
		world.report_player_damage(damage)
	update_fires()
	if hull_fraction() < 0.1:
		begin_sinking(true)

func cease_fire() -> void:
	## The campaign calls this once a "disable her, do not sink her" objective is
	## met. Without it the player can do exactly what was asked and still lose
	## the ship: every further hit overpenetrates into the compartment, the
	## engine-room fire spreads to its neighbours, and the flooding finishes the
	## job on its own. Put the fires out and stop reading damage.
	protected = true
	for id: String in systems:
		systems[id].fire = 0.0
	flooding = minf(flooding, 0.3)
	update_fires()

func process_damage(delta: float) -> void:
	if protected:
		return
	if sunk:
		return
	var spread: Dictionary = {}
	var leak := 0.0
	for id: String in systems:
		var system: ShipSystem = systems[id]
		if system.hull and system.fraction() < 0.5:
			leak += (1.0 - system.fraction() * 2.0) * 0.009
		if system.fire > 0:
			# Real component damage per second. Fire can still destroy a mount,
			# but it is a race the crew can win rather than a death sentence.
			damage_system(id, system.fire * (2.0 if system.hull else 2.8) * delta)
			if system.fire > 0.6:
				for neighbor_id: String in systems:
					var neighbor: ShipSystem = systems[neighbor_id]
					if neighbor_id != id and (neighbor.compartment == system.compartment or
						(system.hull and neighbor.hull and absf(neighbor.position.z - system.position.z) < 20)):
						spread[neighbor_id] = float(spread.get(neighbor_id, 0)) + system.fire * 0.018 * delta
			system.fire = maxf(0, system.fire - firefighting() * delta)
	for id: String in spread:
		systems[id].fire = minf(1.0, systems[id].fire + float(spread[id]))
	flooding = clampf(flooding + (leak - pumping()) * delta, 0.0, 1.0)
	update_fires()
	if flooding >= 1.0 or hull_fraction() < 0.08:
		begin_sinking(hull_fraction() < 0.08)

## How many compartments burn visibly at once. Three columns of alpha-blended
## smoke per hull is affordable on the deferred renderer and is not on the one
## the web build uses.
const VISIBLE_FIRES: int = 3
static func visible_fires() -> int:
	return VISIBLE_FIRES if FireSource.rich() else 1

func firefighting() -> float:
	## Standing damage-control effort. Small fires are smothered quickly, big
	## ones take a while, and a wrecked bridge means a slower, sloppier response.
	var effort := 0.075
	if not operational("bridge"):
		effort *= 0.55
	if damage_control > 0.0:
		effort += 0.9
	return effort

func pumping() -> float:
	## Standing pumping effort: enough to hold minor flooding, nowhere near
	## enough to out-pump a hull that has been opened up. The damage-control
	## party is what actually gets water back out.
	var effort := 0.013
	if not operational("bridge"):
		effort *= 0.6
	if damage_control > 0.0:
		effort += 0.15
	return effort

func run_damage_control() -> bool:
	## The player's damage-control party: knocks the fires down and shores up
	## flooding. On a cooldown, so it is a decision rather than a button mash.
	if sunk or dc_cooldown > 0.0:
		return false
	dc_cooldown = DC_COOLDOWN
	damage_control = DC_DURATION
	flooding = maxf(0.0, flooding - 0.22)
	world.report("%s / damage control party away" % callsign)
	return true

func update_fires() -> void:
	## One persistent emitter per burning compartment, kept alive so the smoke
	## column is continuous instead of a string of puffs. Only the worst few
	## burn visibly: alpha-blended smoke is expensive and a fully involved hull
	## would otherwise stack a dozen columns on top of each other.
	var burning: Array[String] = []
	for id: String in systems:
		if systems[id].fire > 0.06:
			burning.append(id)
	burning.sort_custom(func(a, b): return systems[a].fire > systems[b].fire)
	if burning.size() > visible_fires():
		burning.resize(visible_fires())
	for id: String in systems:
		var system: ShipSystem = systems[id]
		if burning.has(id):
			if not fire_sources.has(id):
				var source := FireSource.new()
				source.scale_factor = clampf(loadout.length / ShipLayout.CORVETTE_LENGTH, 0.55, 1.5)
				fire_sources[id] = source
				visuals.add_child(source)
				source.position = system.position + Vector3.UP * (2.2 if system.hull else 0.8)
			fire_sources[id].set_intensity(system.fire)
		elif fire_sources.has(id):
			fire_sources[id].set_intensity(0.0)

func begin_sinking(explosive: bool) -> void:
	# Counted once, here, because every route to the bottom ends at this call.
	if not sunk and team == 1 and world != null:
		world.tally.sunk += 1
	if sunk:
		return
	sunk = true
	manual = false
	explosive_death = explosive
	if team == 1 and not noncombatant:
		# Hostiles go down with something worth collecting. A freighter has no
		# ordnance to salvage.
		world.drop_crate(position, SupplyCrate.REPAIR if world.destruction_count % 2 == 0 else SupplyCrate.ORDNANCE)
	status = "SINKING"
	world.destruction_count += 1
	world.ship_lost(self)
	# Nothing aboard a merchant cooks off, and `break_up()` throws gun mounts
	# off a hull that has none.
	if explosive and not noncombatant:
		break_up()
	# An immediate slick under the hull, then a spreading trail as she goes down.
	world.oil_slick(position, loadout.length * 0.55, 95.0)
	world.report("%s / abandoned — sinking" % callsign)

func break_up() -> void:
	## She comes apart: mounts cook off and go over the side, the bridge is
	## carried away, and the blast rolls out across the water. Visual only —
	## nothing here damages another ship. A magazine detonation is the one that
	## reaches other hulls, and it earns that by being rare.
	for id: String in ["gun", "aft_gun", "radar", "bridge", "ciws", "sam"]:
		if systems.has(id):
			damage_system(id, systems[id].maximum)
	world.explosion(visuals.to_global(Vector3(0, 3, 2)), 2.4)
	world.shock_ring(position, 7.0, 3.6, 0.95, 0.85)
	world.camera_shake = minf(1.0, world.camera_shake + 0.55)
	# Mounts blowing off, spaced along the hull so it reads as a sequence.
	for part: Array in [[turret, Vector3(0, 4, -18), 1.25], [aft_turret, Vector3(0, 4, 21), 1.1],
			[ciws_turret, Vector3(0, 7, 13), 1.0]]:
		var mount: Node3D = part[0]
		if is_instance_valid(mount) and mount.visible:
			world.explosion(visuals.to_global(part[1]), float(part[2]))
			world.detach_part(mount, 1.5)
	if is_instance_valid(radar_mount):
		world.detach_part(radar_mount, 1.3)
	if system_meshes.has("bridge"):
		world.detach_part(system_meshes["bridge"], 0.9)
	world.debris(visuals.to_global(Vector3(0, 4, 0)), 22, 2.4)
	world.cooling_sparks(visuals.to_global(Vector3(0, 4, -4)), 2.0)
	for id: String in ["mid", "stern", "bow"]:
		systems[id].fire = 1.0
	update_fires()
	secondary_left = 4
	next_secondary = 1.1

func process_sinking(delta: float) -> void:
	sinking_time += delta
	position.y = -minf(22, sinking_time * 0.32)
	visuals.rotation.z = lerpf(visuals.rotation.z, 0.55, delta * 0.1)
	speed = move_toward(speed, 0, delta * 0.7)
	position += -basis.z * speed * delta
	selection.visible = false
	if secondary_left > 0 and sinking_time >= next_secondary:
		secondary_left -= 1
		next_secondary += randf_range(1.6, 3.2)
		var reach: float = loadout.length * 0.41
		var along := randf_range(-reach, reach)
		world.explosion(visuals.to_global(Vector3(randf_range(-2.5, 2.5), 3, along)), randf_range(0.55, 1.1))
		world.debris(visuals.to_global(Vector3(0, 4, along)), 6, 1.6)
	if sinking_time < 22 and fmod(sinking_time, 0.8) < delta:
		var span: float = loadout.length * 0.22
		world.smoke(visuals.to_global(Vector3(randf_range(-3, 3), 4, randf_range(-span, span))), 1.6)
	# Fuel keeps coming up long after the hull is gone.
	oil_clock += delta
	if oil_clock > 1.1 and sinking_time < 48.0:
		oil_clock = 0.0
		# Fresh oil surfaces over the wreck and the drift carries it away. The
		# release point wanders, so the ribbon meanders rather than running
		# arrow-straight downwind.
		var spread: float = loadout.length * (0.55 + sinking_time * 0.03)
		var across := Vector3(-world.OIL_DRIFT.z, 0, world.OIL_DRIFT.x)
		var meander := sin(sinking_time * 0.55) * 11.0 + randf_range(-4.0, 4.0)
		world.oil_slick(position + across * meander, clampf(spread, 12.0, 44.0))
	if sinking_time > 70:
		visible = false

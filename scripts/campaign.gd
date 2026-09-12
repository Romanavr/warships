class_name Campaign
extends RefCounted
## The mission script: four levels in the Strait of Hormuz, each one a list of
## beats the interpreter walks in order.
##
## The old wave table could say "two small boats, then a helicopter". It could
## not say "shoot *this module*", "you are not cleared for missiles yet", "these
## friendlies die on cue" or "someone talks now" — which is every interesting
## thing a scripted level does. A beat is one verb and its arguments, so a level
## is data and the machinery below is the only code.
##
## Verbs:
##   {"say": [who, text]}        a line of radio traffic, queued
##   {"wait": 4.0}               seconds
##   {"wait": "say"}             until the radio queue drains
##   {"wait": "objective"}       until the active objective is met
##   {"wait": "hostiles"}        until nothing hostile can still fight
##   {"spawn": {...}}            units, optionally tagged for later beats
##   {"objective": {...}}        what the player is being asked to do
##   {"clear": ["gun"]}          which weapons the player may use from here
##   {"protect": "tag"}          cease fire: that hull stops taking damage
##   {"strike": {...}}           a scripted missile kill the player watches
##   {"air": 0}                  bring a helicopter on station for a team
##   {"resupply": true}          hull and magazines back to full, crates out
##   {"watch": {...}}            hold the camera on a tagged group
##   {"control": "air"|"ship"}   put the player at the other set of controls
##   {"despawn": "tag"}          quietly take a unit off the board
##   {"banner": [title, sub]}    a centre-screen announcement
##   {"air_hold": true}         the player's ship stops engaging aircraft
##   {"hint": [key, keys, text]} a one-line prompt, shown once per campaign

## How much of each system a between-level replenishment puts back, as a share
## of that system's maximum. One is a full repair: whatever the last level cost,
## the next one starts fresh.
##
## It was briefly 0.6, to make the damage taken in one level carry into the next.
## The mechanism is sound and `repair()` still takes any fraction, but a
## four-level campaign is short enough that starting each one whole is the better
## game — arriving at the last level already worn down punishes the player for
## the level they just won.
const REPLENISH: float = 1.0

## Where an escort sits relative to the ship she is covering: one on each
## quarter, in her local frame, so the formation turns with her.
##
## The distances are not arbitrary. `avoidance()` pushes any two hulls apart
## below 95 m, so a station inside that would have the escort shoved off it and
## oscillating back; and a close-in gun reaches 190 m, so it has to be inside
## that or the escort is standing outside the umbrella she was sent to stand
## under. 127 m out and 190 m apart from each other satisfies both.
const STATIONS: Array[Vector3] = [Vector3(-95, 0, 85), Vector3(95, 0, 85)]

const TRADER := preload("res://ships/trader.tres")
const FAC := preload("res://ships/tern.tres")
const FAC_ASM := preload("res://ships/tern_asm.tres")

static func duel() -> Array[Dictionary]:
	## Skirmish mode: one corvette against one corvette. No orders, no escorts,
	## no clearances to wait for — the campaign teaches the game, this is the
	## game with the teaching taken out.
	return [
		{
			"title": "DUEL",
			"brief": "One corvette against one — everything you have is released",
			"beats": [
				{"clear": ["gun", "missile"]},
				{"spawn": {"class": "corvette", "tag": "duellist", "bearing": 0.15,
					"range": 1500.0, "callsign": "USS CARNEY"}},
				{"watch": {"tag": "duellist", "seconds": 4.0}},
				{"say": ["hostile_captain", "No task group, Kestrel. No gunships, no orders. Just the two of us. Come ahead."]},
				{"hint": ["duel", "T · X",
					"T designates her. Guns for her mounts, missiles for her hull — or the other way round."]},
				{"objective": {"kind": "destroy", "tag": "duellist", "label": "SINK THE CORVETTE"}},
				{"wait": "objective"},
				{"say": ["command", "She is gone. Clean fight, Kestrel."]},
			],
		},
	]

static func levels() -> Array[Dictionary]:
	return [
		{
			"title": "CLOSE THE STRAIT",
			"brief": "Stop the merchant — disable her, do not sink her",
			"beats": [
				{"say": ["command", "Kestrel, Fleet Command. Tehran has closed the strait to US-flagged traffic as of this morning. You are the enforcement."]},
				{"wait": "say"},
				{"spawn": {"class": "trader", "tag": "meridian", "bearing": -0.22, "range": 640.0,
					"callsign": "MV MERIDIAN", "course": 1.35}},
				{"say": ["command", "Contact fine on your port bow — the box boat Meridian, running the closure. Order her to heave to."]},
				{"wait": 7.0},
				{"say": ["merchant", "Kestrel, Meridian. We are in an international transit lane, we are not heaving to, and my owners will hear about this. Out."]},
				{"wait": "say"},
				{"say": ["command", "She has made her choice. Put rounds into her engine room — the funnel, right aft. Nothing else."]},
				{"wait": "say"},
				{"say": ["command", "Stopped, Kestrel. Not on the bottom. Sink a merchant and this ends badly for every one of us."]},
				{"clear": ["gun"]},
				{"hint": ["engine_room", "LMB",
					"Point at the gold diamond on her funnel and hold the left button."]},
				{"wait": 0.1},
				{"objective": {"kind": "disable", "tag": "meridian", "module": "engine",
					"label": "DISABLE HER ENGINE ROOM", "fail_if_sunk": true,
					"fail_text": "You sank a civilian hull. Mission failed."}},
				{"wait": "objective"},
				{"protect": "meridian"},
				{"banner": ["MERIDIAN STOPPED", "Dead in the water"]},
				{"say": ["command", "Her engine room is gone and she is dead in the water. Check fire."]},
				{"wait": 4.0},
				{"say": ["command", "New contacts to the south, closing fast — two US patrol craft coming to collect her."]},
				{"say": ["command", "Guns only, Kestrel. You are not cleared for missiles. Let us not start a war over a box boat."]},
				{"spawn": {"class": "fac", "count": 2, "tag": "escorts", "bearing": 2.6,
					"range": 900.0, "spread": 240.0}},
				{"watch": {"tag": "escorts", "seconds": 4.0}},
				{"objective": {"kind": "destroy", "tag": "escorts", "label": "SINK BOTH PATROL CRAFT"}},
				{"wait": "objective"},
				{"say": ["command", "Both down. That is how it is done."]},
				{"wait": "say"},
				# She has served her purpose as a teaching hull. Leaving a dead
				# freighter parked in the sector for the rest of the campaign
				# gives the player something to wonder about that has no answer.
				{"say": ["command", "A tug is coming out of Bandar Abbas for the Meridian. Let her go — she is somebody else's problem now."]},
				{"wait": "say"},
				{"despawn": "meridian"},
				{"say": ["command", "Stand by, Kestrel. This will not be the last of them."]},
			],
		},
		{
			"title": "VAMPIRE",
			"brief": "Four missile-armed patrol craft — CIWS hot",
			"beats": [
				{"say": ["command", "Kestrel, four fast craft leaving Bandar-e-Jask at speed. These ones are carrying anti-ship missiles."]},
				{"wait": "say"},
				{"say": ["command", "Keep your close-in gun hot and watch for the vampire warning. You are cleared for anti-ship missiles of your own — use them."]},
				{"clear": ["gun", "missile"]},
				{"banner": ["WEAPONS FREE", "Anti-ship missiles released"]},
				{"hint": ["vampire", "CIWS",
					"When VAMPIRE flashes, a missile is inbound. Your close-in gun answers it on its own."]},
				{"spawn": {"class": "fac_asm", "count": 4, "tag": "wolves", "bearing": -2.1,
					"range": 1150.0, "spread": 300.0}},
				{"watch": {"tag": "wolves", "seconds": 4.5}},
				{"objective": {"kind": "destroy", "tag": "wolves", "label": "DESTROY ALL FOUR CRAFT"}},
				{"wait": "objective"},
			],
		},
		{
			"title": "GUNSHIP",
			"brief": "Hostile attack helicopter — your own air is inbound",
			"beats": [
				{"resupply": true},
				# Two things kept the player from ever fighting this duel. Viper
				# used to arrive at 780 m — inside the ship's own 850 m SAM
				# envelope — and the handover to the cockpit is four lines of
				# dialogue away. The ship shot him down while the player was
				# still reading. So he now comes from beyond the envelope, and
				# the ship's air defence is held until the player has the stick.
				{"air_hold": true},
				{"say": ["command", "Air contact, low and fast, sixteen hundred out. US gunship — they have stopped sending boats."]},
				{"spawn": {"class": "air", "team": 1, "tag": "viper", "bearing": 1.9, "range": 1600.0}},
				{"watch": {"tag": "viper", "seconds": 3.0}},
				{"say": ["hostile_air", "Viper Three, tally one corvette, in the open, no air cover. Rolling in."]},
				{"air": 0, "tag": "shaheen"},
				{"say": ["pilot", "Not quite, Viper. Kestrel, Shaheen One — I am off your stern and I have him."]},
				{"wait": "say"},
				{"control": "air"},
				{"air_hold": false},
				{"hint": ["cockpit", "SPACE · SHIFT",
					"You are flying now. Space and Shift for height, Z for flares if he shoots."]},
				{"say": ["command", "You have the cockpit. Kestrel is covering you now — take him."]},
				{"objective": {"kind": "hostiles", "label": "SHOOT DOWN THE GUNSHIP"}},
				{"wait": "objective"},
				{"say": ["pilot", "Splash one. Shaheen One is winchester and turning for the deck."]},
				{"wait": "say"},
				# The helm comes back before the aircraft dies, so the player is
				# never left holding a dead stick.
				{"control": "ship"},
				{"spawn": {"class": "corvette", "tag": "carney", "bearing": -2.85,
					"range": 2100.0, "callsign": "USS CARNEY"}},
				{"watch": {"tag": "shaheen", "seconds": 14.0, "hold": "until_lost"}},
				{"wait": 1.4},
				{"strike": {"at": "shaheen", "weapon": "sam", "from": "carney",
					"bearing": -2.85, "range": 1900.0}},
				{"say": ["command", "SAM launch to the north — that is not the gunship. Shaheen, break, break!"]},
				{"wait": "watch"},
				{"say": ["command", "Shaheen One is down. There is a corvette out there we never saw."]},
				{"wait": "say"},
				{"despawn": "carney"},
				{"say": ["command", "She is hauling off to the north. We are not finished with her."]},
			],
		},
		{
			"title": "THE CORVETTE",
			"brief": "The ship that killed Shaheen — you have been resupplied",
			"beats": [
				{"resupply": true},
				{"say": ["command", "Kestrel, the corvette that killed Shaheen is still out there, and this time you are not alone."]},
				{"spawn": {"class": "fac", "team": 0, "count": 2, "tag": "allies", "bearing": 0.5,
					"range": 420.0, "spread": 180.0, "callsign": "PEYKAAP", "station": true}},
				{"watch": {"tag": "allies", "seconds": 5.0}},
				{"say": ["command", "Peykaap One and Two, joining from the north. Keep them under your close-in gun and they will live."]},
				{"wait": "say"},
				{"spawn": {"class": "corvette", "tag": "halstead", "bearing": -2.8, "range": 1750.0,
					"callsign": "USS CARNEY"}},
				{"watch": {"tag": "halstead", "seconds": 5.0}},
				{"say": ["hostile", "Still here? After what I did to your helicopter? You have no idea what you are dealing with."]},
				{"wait": "say"},
				{"say": ["hostile_captain", "Kestrel, USS Carney. You are outranged and outgunned. Come about and go home."]},
				{"wait": "say"},
				{"say": ["command", "Do not come about, Kestrel. Get inside her missile envelope and finish it. That is for Shaheen."]},
				{"hint": ["masking", "TERRAIN",
					"Put an island between you and her and her missiles lose the track."]},
				{"objective": {"kind": "destroy", "tag": "halstead", "label": "SINK THE CORVETTE"}},
				{"wait": "objective"},
				{"wait": 4.0},
				{"say": ["command", "Carney is gone. That is for Shaheen One, and the strait is closed. Bring her home, Kestrel."]},
			],
		},
	]

# --------------------------------------------------------------------------- #

var world: Node3D
var level: int = -1
var beats: Array = []
var step: int = 0
var timer: float = 0.0
var objective: Dictionary = {}
var tags: Dictionary = {}
var waiting: Variant = null
var finished: bool = false

## The levels this run is playing. Held per instance rather than read from the
## static table each time, so a mode with a different set of levels — the duel —
## is a different table rather than a different code path through the same one.
var table: Array[Dictionary] = []

func _init(host: Node3D, levels_played: Array[Dictionary] = []) -> void:
	world = host
	table = levels_played if not levels_played.is_empty() else levels()

func title() -> String:
	if level < 0 or level >= table.size():
		return ""
	return String(table[level]["title"])

func brief() -> String:
	if level < 0 or level >= table.size():
		return ""
	return String(table[level]["brief"])

func count() -> int:
	return table.size()

func begin(index: int) -> void:
	if index < 0 or index >= table.size():
		finished = true
		return
	level = index
	beats = (table[index]["beats"] as Array).duplicate()
	step = 0
	timer = 0.0
	waiting = null
	objective = {}
	tags.clear()
	world.wave_index = index
	world.wave_state = "fighting"
	# The radio starts this level empty. A line queued by the level that just
	# ended is still playing when this one begins, and every `wait: "say"` here
	# waits for it too — which pushed level three's handover to the cockpit far
	# enough back that the gunship was dead before the player had the stick.
	if world.comms != null:
		world.comms.clear()
	# Something to go and collect while the contact closes, as there was on
	# every wave. `resupply` is the heavier thing that also mends the hull.
	world.scatter_supplies()
	world.report("LEVEL %d · %s" % [index + 1, title()])
	if not world.test_mode:
		world.audio.play("alarm", -3.0)

func advance(delta: float) -> void:
	## One beat per frame at most, so a run of instant verbs still resolves in
	## order rather than all inside the same tick.
	if finished or level < 0:
		return
	check_objective(delta)
	if world.mission_state != "active":
		return
	if waiting != null:
		if not still_waiting(delta):
			waiting = null
		return
	if step >= beats.size():
		complete_level()
		return
	var beat: Dictionary = beats[step]
	step += 1
	run(beat)

func still_waiting(delta: float) -> bool:
	if waiting is float:
		timer -= delta
		return timer > 0.0
	match String(waiting):
		"say":
			return world.comms != null and world.comms.busy()
		"objective":
			return not objective.is_empty() and String(objective.get("state", "")) == "active"
		"hostiles":
			return world.hostiles_remaining() > 0
		"watch":
			return not world.cutaway.is_empty()
	return false

func run(beat: Dictionary) -> void:
	if beat.has("say"):
		var line: Array = beat["say"]
		world.say(String(line[0]), String(line[1]))
	elif beat.has("wait"):
		var value: Variant = beat["wait"]
		if value is float or value is int:
			timer = float(value)
			waiting = timer
		else:
			waiting = String(value)
	elif beat.has("spawn"):
		spawn(beat["spawn"])
	elif beat.has("objective"):
		objective = (beat["objective"] as Dictionary).duplicate()
		objective["state"] = "active"
	elif beat.has("clear"):
		world.clearance.clear()
		for weapon: String in ["gun", "missile", "rocket"]:
			world.clearance[weapon] = (beat["clear"] as Array).has(weapon)
	elif beat.has("protect"):
		for unit in units_for(String(beat["protect"])):
			if is_instance_valid(unit) and unit is PatrolBoat:
				unit.cease_fire()
	elif beat.has("strike"):
		strike(beat["strike"])
	elif beat.has("watch"):
		var spec: Dictionary = beat["watch"]
		world.show_units(units_for(String(spec.get("tag", ""))),
			float(spec.get("seconds", 4.0)), String(spec.get("hold", "")))
	elif beat.has("air"):
		world.restore_air_support()
		if String(beat.get("tag", "")) != "" and is_instance_valid(world.player_air):
			tags[String(beat["tag"])] = [world.player_air] as Array[Node3D]
	elif beat.has("control"):
		world.take_the_controls(String(beat["control"]))
	elif beat.has("despawn"):
		for unit in units_for(String(beat["despawn"])):
			if unit is PatrolBoat:
				world.boats.erase(unit)
			unit.queue_free()
	elif beat.has("resupply"):
		# A level may ask for less than a full repair by giving a fraction
		# instead of `true`; none currently does.
		var restored: float = float(beat["resupply"]) if beat["resupply"] is float else REPLENISH
		if is_instance_valid(world.player_ship):
			world.player_ship.repair(restored)
			world.report("Replenishment complete — magazines full, hull at %d%%"
				% int(round(world.player_ship.hull_fraction() * 100.0)))
		world.scatter_supplies()
	elif beat.has("banner"):
		var text: Array = beat["banner"]
		world.hud.announce(String(text[0]), String(text[1]))
	elif beat.has("air_hold"):
		world.air_hold = bool(beat["air_hold"])
	elif beat.has("hint"):
		var prompt: Array = beat["hint"]
		world.hud.hint(String(prompt[0]), String(prompt[1]), String(prompt[2]))

func bearing_point(bearing: float, range_m: float) -> Vector3:
	## Relative to where the player is pointed, so a scripted contact always
	## arrives from the same side of the bow whatever the helm has been doing.
	var ship: Node3D = world.player_ship
	if not is_instance_valid(ship):
		return Vector3(sin(bearing), 0, cos(bearing)) * range_m
	var ahead := -ship.global_basis.z
	return ship.position + Vector3(ahead.x, 0, ahead.z).normalized().rotated(Vector3.UP, bearing) * range_m

func spawn(spec: Dictionary) -> void:
	var kind := String(spec.get("class", "fac"))
	var team := int(spec.get("team", 1))
	var total := int(spec.get("count", 1))
	var bearing := float(spec.get("bearing", 0.0))
	var reach := float(spec.get("range", 900.0))
	var spread := float(spec.get("spread", 0.0))
	var tag := String(spec.get("tag", ""))
	var made: Array[Node3D] = []
	var origin := bearing_point(bearing, reach)
	for index in range(total):
		if kind == "air":
			var craft: Node3D = world.spawn_helicopter(team, origin + Vector3.UP * 60.0)
			made.append(craft)
			continue
		var across := Vector3(cos(bearing), 0, -sin(bearing)) * (float(index) - float(total - 1) * 0.5) * spread
		world.next_id += 1
		var name := String(spec.get("callsign", "CONTACT"))
		var callsign := "%s / %02d" % [name, world.next_id]
		var loadout: ShipLoadout = null
		match kind:
			"trader": loadout = TRADER
			"fac": loadout = FAC
			"fac_asm": loadout = FAC_ASM
		var boat: PatrolBoat = world.spawn_boat(team, origin + across, callsign, false, loadout)
		# Point them at the player, unless the beat gives an explicit course.
		if spec.has("course"):
			boat.rotation.y = float(spec["course"])
			boat.has_move_order = true
			boat.destination = boat.position - boat.global_basis.z * 2600.0
		else:
			boat.rotation.y = bearing + PI + world.player_ship.rotation.y
		if bool(spec.get("station", false)) and is_instance_valid(world.player_ship):
			boat.station_on = world.player_ship
			boat.station_offset = STATIONS[index % STATIONS.size()]
		made.append(boat)
	if tag != "":
		tags[tag] = made

func units_for(tag: String) -> Array:
	var listed: Array = tags.get(tag, [])
	var alive: Array = []
	for unit in listed:
		if is_instance_valid(unit):
			alive.append(unit)
	return alive

func strike(spec: Dictionary) -> void:
	## A scripted loss the player watches happen. Real missiles, because a
	## friendly that simply blinks out is a friendly nobody believes was killed —
	## but the victims are pre-wrecked and their close-in guns are off, so the
	## outcome cannot come down to a dice roll.
	var victims := units_for(String(spec.get("at", "")))
	if victims.is_empty():
		return
	if String(spec.get("weapon", "missile")) == "sam":
		return sam_strike(spec, victims)
	var shooters := units_for(String(spec.get("from", "")))
	if shooters.is_empty():
		return
	var shooter: PatrolBoat = shooters[0]
	for index in range(victims.size()):
		var victim: PatrolBoat = victims[index]
		victim.ciws_enabled = false
		victim.sam_ammo = 0
		for id: String in ["bow", "mid", "stern"]:
			victim.systems[id].health = victim.systems[id].maximum * 0.05
		var origin: Vector3 = shooter.visuals.to_global(Vector3(0, 4, 0))
		world.fire_missile(origin, victim, shooter)
		world.warn_vampire()
	# Whatever is still afloat when the missiles should have arrived goes anyway.
	world.get_tree().create_timer(14.0).timeout.connect(func():
		for victim in victims:
			if is_instance_valid(victim) and not victim.sunk:
				victim.begin_sinking(true))

func sam_strike(spec: Dictionary, victims: Array) -> void:
	## A surface-to-air round from a ship the player cannot see yet. The
	## aircraft is pre-weakened so the outcome is the scripted one rather than a
	## coin toss, and its flares are gone — a gunship that decoys its own
	## scripted death leaves the level with nothing to say.
	var origin: Vector3 = bearing_point(float(spec.get("bearing", -2.8)),
		float(spec.get("range", 1800.0))) + Vector3.UP * 12.0
	var shooters := units_for(String(spec.get("from", "")))
	var shooter: PatrolBoat = shooters[0] if not shooters.is_empty() else world.player_ship
	for victim in victims:
		if victim is CombatHelicopter:
			victim.flare_packs = 0
			victim.health = minf(victim.health, 24.0)
			world.fire_sam(origin, victim, shooter)
	# Whatever is still flying once the round should have arrived goes anyway.
	# The level cannot hinge on a seeker connecting.
	world.get_tree().create_timer(float(spec.get("watchdog", 6.5))).timeout.connect(func():
		for victim in victims:
			if is_instance_valid(victim) and victim is CombatHelicopter and not victim.destroyed:
				victim.take_damage(9999.0))

func check_objective(_delta: float) -> void:
	if objective.is_empty() or String(objective.get("state", "")) != "active":
		return
	var kind := String(objective.get("kind", ""))
	var listed := units_for(String(objective.get("tag", "")))
	# The fail test runs first, so a hull that sinks while being disabled fails
	# rather than racing the success test.
	if bool(objective.get("fail_if_sunk", false)):
		for unit in listed:
			if unit is PatrolBoat and unit.sunk:
				objective["state"] = "failed"
				world.fail_mission(String(objective.get("fail_text", "Mission failed.")))
				return
	match kind:
		"disable":
			var module := String(objective.get("module", "engine"))
			for unit in listed:
				if unit is PatrolBoat and not unit.operational(module):
					objective["state"] = "met"
		"destroy":
			if listed.is_empty():
				return
			var standing := 0
			for unit in listed:
				if not unit.sunk and unit.is_combat_capable():
					standing += 1
			if standing == 0:
				objective["state"] = "met"
		"hostiles":
			if world.hostiles_remaining() == 0:
				objective["state"] = "met"
	if String(objective["state"]) == "met" and not world.test_mode:
		world.audio.play("cleared", -5.0)

func progress() -> String:
	## The line under the level title in the mission panel.
	if objective.is_empty():
		return "%d hostile%s remaining" % [world.hostiles_remaining(),
			"" if world.hostiles_remaining() == 1 else "s"]
	var label := String(objective.get("label", ""))
	if String(objective.get("state", "")) != "active":
		return label + " — DONE"
	if String(objective.get("kind", "")) == "disable":
		var listed := units_for(String(objective.get("tag", "")))
		if not listed.is_empty() and listed[0] is PatrolBoat:
			var unit: PatrolBoat = listed[0]
			var module := String(objective.get("module", "engine"))
			return "%s · %d%%" % [label, int(unit.systems[module].fraction() * 100.0)]
	return label

func marker_unit() -> Node3D:
	## The hull the objective names, so the HUD can point at the right module on
	## it rather than following whatever the player happens to have locked.
	if objective.is_empty() or not objective.has("module"):
		return null
	if String(objective.get("state", "")) != "active":
		return null
	var listed := units_for(String(objective.get("tag", "")))
	return listed[0] if not listed.is_empty() else null

func complete_level() -> void:
	# Freeze what the player did, and hand it to the debrief card. Closing it
	# here rather than at the start of the next level means the figures stop at
	# the moment the level was won, not at the moment the next one loads.
	world.close_tally(level)
	if level + 1 >= count():
		finished = true
		world.mission_state = "complete"
		world.wave_state = "over"
		world.report("Every contact destroyed. The strait is closed.")
		return
	world.wave_state = "cleared"
	# Long enough to read a seven-line card without it feeling like a wall.
	world.wave_clock = 9.0
	world.report("Level %d cleared" % (level + 1))
	if not world.test_mode:
		world.audio.play("cleared", -4.0)

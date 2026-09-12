class_name ShipLayout
extends RefCounted
## Where each module sits on each class of hull, and how the hull is presented.
##
## These boxes are the ship as far as the game is concerned: shells and the
## pointer both hit them, never the geometry. So they have to agree with what
## `ship_model.gd` actually builds — the corvette's engine room is a box around
## the funnel because that is where the funnel is, and that is what makes it
## possible to aim at. Split the two apart and they drift on the first tweak, so
## the table lives here in code rather than in the `.tres` files. What belongs in
## a `.tres` is the tuning that differs per ship: health, speed, fitted kit.
##
## A class need not list every module. Anything it leaves out becomes a stub in
## `PatrolBoat.add_stub()` — present so `operational(id)` has an answer, but with
## no collider and no geometry.

## Every module id the game knows about, in the order they are built.
const MODULE_IDS: Array[String] = ["bow", "mid", "stern", "gun", "aft_gun", "engine",
	"rudder", "bridge", "radar", "launcher_port", "launcher_starboard", "ciws", "sam"]

const CORVETTE_LENGTH: float = 54.0

# Built on first use rather than declared const: a const Dictionary of Vector3s
# is awkward to keep readable, and this is read once per hull at spawn.
static var _table: Dictionary = {}

static func of(hull_model: String) -> Dictionary:
	if _table.is_empty():
		_build()
	return _table.get(hull_model, _table["corvette"])

static func scaled(source: Dictionary, factor: float, radius: float) -> Dictionary:
	## The same layout at another size. The fast attack craft used to be the
	## corvette mesh shrunk, so its boxes came along for free; now it has a hull
	## of its own the boxes have to be brought down to meet it, and deriving
	## them keeps the two from drifting apart.
	var modules: Dictionary = {}
	for id: String in source["modules"]:
		var row: Array = (source["modules"][id] as Array).duplicate()
		row[1] = (row[1] as Vector3) * factor
		row[2] = (row[2] as Vector3) * factor
		modules[id] = row
	return {"scale_to_length": false, "selection_radius": radius, "modules": modules}

static func _build() -> void:
	# Module rows are [label, centre, size, compartment, is_hull].
	#
	# The hull boxes have to cover the ship the player can see, keel to deck
	# edge. When they stopped at y = 2.8 a well-aimed shell flew clean over them
	# and passed through the ship without registering anything.
	_table["corvette"] = {
		# Built on the corvette mesh, so a shorter hull of this class is the
		# same model scaled down.
		"scale_to_length": true,
		"selection_radius": 29.0,
		"modules": {
			"bow": ["Bow hull", Vector3(0, 0.6, -18), Vector3(8.4, 7.4, 18), "bow", true],
			"mid": ["Citadel hull", Vector3(0, 0.6, 0), Vector3(10.4, 7.6, 18), "mid", true],
			"stern": ["Stern hull", Vector3(0, 0.6, 18), Vector3(9.6, 7.4, 18), "stern", true],
			"gun": ["Forward gun", Vector3(0, 4, -18), Vector3(4, 2.5, 4), "bow", false],
			"aft_gun": ["Aft gun", Vector3(0, 4, 21), Vector3(3.6, 2.4, 3.6), "stern", false],
			"engine": ["Engine room", Vector3(0, 3.4, 11), Vector3(5.6, 5.0, 8), "stern", false],
			"rudder": ["Steering gear", Vector3(0, 0.0, 25), Vector3(3, 1.5, 2), "stern", false],
			"bridge": ["Bridge", Vector3(0, 6.0, -5), Vector3(7.6, 5.6, 13), "mid", false],
			"radar": ["Search radar", Vector3(0, 12, -3), Vector3(5, 2, 2), "mid", false],
			"launcher_port": ["Port VLS", Vector3(-2.8, 4, 4), Vector3(2, 2.8, 6), "mid", false],
			"launcher_starboard": ["Stbd VLS", Vector3(2.8, 4, 4), Vector3(2, 2.8, 6), "mid", false],
			"ciws": ["CIWS mount", Vector3(0, 8, 12), Vector3(3.2, 3, 3.2), "stern", false],
			"sam": ["IR SAM bank", Vector3(0, 4.6, 3), Vector3(2, 2, 4), "mid", false],
		},
	}
	# 28 m fast attack craft: the corvette's layout brought down to its length,
	# so a shell that used to land on its bridge still lands on its bridge.
	_table["fac"] = scaled(_table["corvette"], 28.0 / CORVETTE_LENGTH, 15.5)
	# A 72 m general cargo ship. Hull boxes run keel (-4.7) to deck edge (+5.6),
	# so their tops sit at y = 6.1.
	#
	# The engine room and the wheelhouse are the two boxes that matter, and both
	# deliberately stand *above* that: a ray — a shell, or the player's pointer —
	# takes the first box it meets, so an engine room modelled below decks could
	# never be hit and the training level could never be finished. The engine box
	# is the funnel, exactly as it is on the corvette, and it is separated in z
	# from the wheelhouse so a beam-on shot can pick one or the other.
	_table["cargo"] = {
		"scale_to_length": false,
		"selection_radius": 40.0,
		"modules": {
			"bow": ["Forepeak", Vector3(0, 0.6, -26), Vector3(12.0, 11.0, 20), "bow", true],
			"mid": ["Cargo holds", Vector3(0, 0.6, 0), Vector3(14.4, 11.0, 32), "mid", true],
			"stern": ["Stern hull", Vector3(0, 0.6, 26), Vector3(13.4, 11.0, 20), "stern", true],
			"engine": ["Engine room", Vector3(0, 11.0, 29), Vector3(7.2, 9.0, 7.0), "stern", false],
			"bridge": ["Wheelhouse", Vector3(0, 11.5, 21), Vector3(11.0, 8.0, 8.0), "stern", false],
			"rudder": ["Steering gear", Vector3(0, -1.5, 34.5), Vector3(4.0, 3.0, 3.0), "stern", false],
			"radar": ["Navigation radar", Vector3(0, 17.6, 21), Vector3(3.4, 1.4, 1.4), "stern", false],
		},
	}

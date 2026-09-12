class_name Tally
extends RefCounted
## What the player actually did this level, counted so the game can say so.
##
## The campaign used to roll straight from one level into the next, which means
## playing it well and merely surviving it looked identical. Everything here is
## counted at a place the world already funnels the event through — `fire_shell`,
## `report_hit`, `report_module_lost`, `report_player_damage` — so nothing new
## has to be threaded down into the weapons or the damage model.
##
## Deliberately not a score. A single number invites optimising the number;
## four honest figures invite reading them and shooting differently next time.

var shells: int = 0
var landed: int = 0
var missiles: int = 0
var missile_hits: int = 0
var modules: int = 0
var sunk: int = 0
var taken: float = 0.0
var started: float = 0.0
var seconds: float = 0.0

func reset(now: float) -> void:
	shells = 0
	landed = 0
	missiles = 0
	missile_hits = 0
	modules = 0
	sunk = 0
	taken = 0.0
	started = now
	seconds = 0.0

func close(now: float) -> void:
	seconds = maxf(0.0, now - started)

func accuracy() -> float:
	return 0.0 if shells == 0 else clampf(float(landed) / float(shells), 0.0, 1.0)

func clock() -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]

func rating() -> String:
	## A line of judgement, from the two figures that separate a gunner from
	## someone holding the trigger down: did the rounds land, and did they land
	## somewhere that mattered.
	if shells + missiles == 0:
		return "NO ROUNDS EXPENDED"
	if accuracy() >= 0.6 and modules >= 3:
		return "GUNNERY EXCELLENT"
	if accuracy() >= 0.45:
		return "GUNNERY GOOD"
	if accuracy() >= 0.25:
		return "ROUNDS WASTED"
	return "SHOOTING WILD"

func rows() -> Array[Array]:
	## [label, value, emphasis] — emphasis marks the two lines worth reading first.
	return [
		["ROUNDS FIRED", str(shells), false],
		["ROUNDS ON TARGET", "%d · %d%%" % [landed, int(round(accuracy() * 100.0))], true],
		["MISSILES", "%d fired · %d hit" % [missiles, missile_hits], false],
		["MODULES KNOCKED OUT", str(modules), true],
		["CONTACTS SUNK", str(sunk), false],
		["DAMAGE TAKEN", "%d" % int(round(taken)), false],
		["TIME", clock(), false],
	]

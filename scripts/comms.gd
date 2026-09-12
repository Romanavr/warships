class_name Comms
extends Control
## Radio traffic during a mission: a portrait, a name, and one typed line, low
## on the left where it does not cover the sea.
##
## Deliberately not the briefing card. `briefing.gd` pauses the tree and takes
## the whole screen because nothing else is happening yet; this runs while the
## player is being shot at, so it never pauses, never blocks the pointer, and
## gets out of the way on its own.

## Who can talk, and what they look like. The key is what a `say` beat names.
const SPEAKERS := {
	"command": ["ADMIRAL NASIRI", "FLEET COMMAND", "command.png", Color("6fe0bd")],
	"pilot": ["SHAHEEN 1", "ARMY AVIATION", "our_pilot.png", Color("58c8d8")],
	"merchant": ["MASTER, MV MERIDIAN", "CHANNEL 16", "merchant.png", Color("e8be6e")],
	"hostile": ["ADM. RONALD GRUMP", "TASK GROUP TREMENDOUS", "enemy.png", Color("ef8a76")],
	"hostile_air": ["VIPER 3", "US NAVAL AVIATION", "us_pilot.png", Color("ef8a76")],
	"hostile_captain": ["CAPT. HALSTEAD", "US NAVY", "enemy_captain.png", Color("ef8a76")],
	# A mayday comes over the international distress channel in clear, not over
	# anyone's command net — hence its own speaker and its own colour.
	"distress": ["DISTRESS", "CHANNEL 16 · ALL SHIPS", "enemy_captain.png", Color("ffd36a")],
}
const PORTRAIT_DIR: String = "res://assets/portraits/"
const TYPE_RATE: float = 30.0
## Reading speed, in characters per second, used to decide how long a finished
## line stays up. A fixed hold meant a forty-character line sat there twice as
## long as it needed to and a hundred-and-sixty-character one was pulled
## mid-sentence, which is the same defect in both directions.
const READ_RATE: float = 26.0
const HOLD_MIN: float = 1.8
const HOLD_MAX: float = 5.0
const FADE: float = 0.45
const PLATE: float = 72.0
const MAX_WIDTH: float = 528.0
const TEXT_SIZE: int = 15
## Baseline of the first spoken row, measured from the panel top. It has to
## clear the rule under the header by more than the font's ascent, or the rule
## runs straight through the first line.
const BODY_TOP: float = 73.0

const INK := Color("dfe8e6")
const MUTED := Color("7e969c")
const DIM := Color("4d6067")
const PANEL := Color(0.028, 0.048, 0.062, 0.95)
const LINE_TINT := Color(0.35, 0.45, 0.48, 0.5)

# Portraits are decoded once and kept. Without this every line would decode a
# 512 px PNG in the middle of a fight.
static var _portraits: Dictionary = {}

var world: Node3D
var font: Font
var queue: Array[Dictionary] = []
var current: Dictionary = {}
var age: float = 0.0
var shown: int = 0
var ticks: int = 0
var unkeyed: bool = false
var carrier: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Never swallow a click: the fire button is the mouse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func rate() -> float:
	## A headless run should not spend eight seconds per line typing to nobody.
	return 4000.0 if world != null and world.test_mode else TYPE_RATE

func hold() -> float:
	## Long enough to read the line that is actually up, not so long that it
	## blocks the next call.
	if world != null and world.test_mode:
		return 0.02
	var length: int = String(current.get("line", "")).length()
	return clampf(float(length) / READ_RATE, HOLD_MIN, HOLD_MAX)

func column() -> float:
	return minf(MAX_WIDTH, size.x - 300.0) - PLATE - 40.0

func text_height(line: String) -> float:
	## The panel is sized to the line it is carrying. A one-sentence
	## acknowledgement taking the same room as a three-line order is wasted sea.
	if font == null:
		return 20.0
	# max_lines is left at -1 deliberately. It used to be 3, which silently
	# clipped the tail off any order longer than three rows; the panel grows to
	# fit the line instead.
	return font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, column(), TEXT_SIZE).y

func row_height() -> float:
	return font.get_height(TEXT_SIZE) if font != null else float(TEXT_SIZE)

func say(speaker: String, line: String) -> void:
	# Translated here rather than at draw time: the typewriter counts characters,
	# and counting them in one language while drawing another types gibberish.
	line = Lang.t(line)
	## Queue a line. Beats fire instantly and several can land together, so this
	## is a queue rather than a slot — otherwise the third line would wipe the
	## first before anyone read it.
	queue.append({"speaker": speaker, "line": line})

func push_carrier() -> void:
	if world != null and world.audio != null:
		world.audio.set_carrier(carrier * (0.35 if unkeyed else 1.0))

func busy() -> bool:
	return not current.is_empty() or not queue.is_empty()

func clear() -> void:
	queue.clear()
	current = {}
	carrier = 0.0
	push_carrier()

static func portrait(file: String) -> Texture2D:
	if _portraits.has(file):
		return _portraits[file]
	var path := PORTRAIT_DIR + file
	var result: Texture2D = null
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			result = resource
	if result == null:
		# No `.import` sidecar in a fresh checkout, so read the file directly.
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			result = ImageTexture.create_from_image(image)
	_portraits[file] = result
	return result

static func release() -> void:
	_portraits.clear()

func _process(delta: float) -> void:
	if current.is_empty():
		if queue.is_empty():
			if visible:
				visible = false
			# Net closed: let the carrier hiss fall away rather than cut.
			carrier = maxf(0.0, carrier - delta * 3.0)
			push_carrier()
			return
		current = queue.pop_front()
		age = 0.0
		shown = 0
		ticks = 0
		unkeyed = false
		visible = true
		# Someone keys the handset: relay click, then the carrier opens.
		if world != null and world.audio != null:
			world.audio.key_radio()
	age += delta
	carrier = minf(1.0, carrier + delta * 6.0)
	push_carrier()
	var line: String = String(current["line"])
	if shown < line.length():
		var want := int(age * rate())
		if want != shown:
			shown = mini(want, line.length())
			ticks += 1
			if ticks % 4 == 0 and world != null and world.audio != null:
				world.audio.play("marker", -26.0, randf_range(1.5, 2.1))
	else:
		var done := float(line.length()) / rate()
		# Unkey once the line has been read, not the instant it finishes typing.
		if not unkeyed and age > done + hold() * 0.6:
			unkeyed = true
			carrier = 0.35
			if world != null and world.audio != null:
				world.audio.unkey_radio()
		if age > done + hold() + FADE:
			current = {}
	queue_redraw()

func _draw() -> void:
	if current.is_empty() or font == null or size.x < 10.0:
		return
	var who: Array = SPEAKERS.get(String(current["speaker"]),
		["UNKNOWN", "", "", MUTED]) as Array
	var line: String = String(current["line"])
	var typed := line.length() > 0 and shown >= line.length()
	var alpha := 1.0
	if typed:
		var done := float(line.length()) / rate()
		alpha = clampf(1.0 - (age - done - hold()) / FADE, 0.0, 1.0)
	var tint: Color = who[3]

	var width := minf(MAX_WIDTH, size.x - 300.0)
	var body := column()
	# Two heights, and the difference matters. The panel is drawn to fit what has
	# actually been typed — reserving room for the whole line left a hand's width
	# of empty panel under a one-row opening — but its top is placed from the
	# height the finished line will need, so the portrait and the speaker's name
	# stay put while the text grows down towards them. Sizing and placing from
	# the same growing number instead walks the whole panel up the screen a row
	# at a time, mid-sentence.
	var full := maxf(PLATE + 20.0, BODY_TOP + text_height(line) + 14.0)
	var height := maxf(PLATE + 20.0, BODY_TOP + text_height(spoken_so_far(line)) + 14.0)
	var origin := Vector2(18, size.y - 250.0 - full)

	draw_colored_polygon(PackedVector2Array([
		origin + Vector2(10, 0), origin + Vector2(width, 0),
		origin + Vector2(width, height - 10), origin + Vector2(width - 10, height),
		origin + Vector2(0, height), origin + Vector2(0, 10)]),
		Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * alpha))
	draw_polyline(PackedVector2Array([
		origin + Vector2(10, 0), origin + Vector2(width, 0),
		origin + Vector2(width, height - 10), origin + Vector2(width - 10, height),
		origin + Vector2(0, height), origin + Vector2(0, 10), origin + Vector2(10, 0)]),
		Color(tint.r, tint.g, tint.b, 0.22 * alpha), 1.0, true)
	draw_rect(Rect2(origin + Vector2(0, 10), Vector2(2, height - 20)),
		Color(tint.r, tint.g, tint.b, alpha))

	# --- portrait -------------------------------------------------------------- #
	var frame := Rect2(origin + Vector2(10, 10), Vector2(PLATE, PLATE))
	var art := portrait(String(who[2]))
	if art != null:
		draw_texture_rect(art, frame, false, Color(1, 1, 1, alpha))
	else:
		draw_rect(frame, Color(0.08, 0.11, 0.13, alpha))
		draw_circle(frame.position + frame.size * Vector2(0.5, 0.42), frame.size.x * 0.17,
			Color(0.17, 0.21, 0.23, alpha))
	var scan := 0.0
	while scan < frame.size.y:
		draw_rect(Rect2(frame.position + Vector2(0, scan), Vector2(frame.size.x, 1)),
			Color(0.0, 0.05, 0.07, 0.20 * alpha))
		scan += 3.0
	if not typed:
		# A band of interference crawling down the picture while the set is
		# transmitting, so the portrait is alive rather than a pasted photograph.
		var sweep: float = fmod(age * 46.0, frame.size.y)
		draw_rect(Rect2(frame.position + Vector2(0, sweep), Vector2(frame.size.x, 2)),
			Color(tint.r, tint.g, tint.b, 0.20 * alpha))
	draw_polyline(PackedVector2Array([frame.position, frame.position + Vector2(frame.size.x, 0),
		frame.end, frame.position + Vector2(0, frame.size.y), frame.position]),
		Color(tint.r, tint.g, tint.b, 0.7 * alpha), 1.0, true)
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var point := frame.position + frame.size * corner
		draw_line(point, point + Vector2(7.0 * (1.0 - corner.x * 2.0), 0),
			Color(tint.r, tint.g, tint.b, alpha), 1.8)
		draw_line(point, point + Vector2(0, 7.0 * (1.0 - corner.y * 2.0)),
			Color(tint.r, tint.g, tint.b, alpha), 1.8)

	# --- header: who is talking, on what, and whether they are still keyed ----- #
	var text := origin + Vector2(PLATE + 24.0, 26.0)
	# Transmit lamp: solid and breathing while the handset is keyed, hollow once
	# they have let go of it, which is the cue that the line is finished.
	var lamp := text + Vector2(4, -5)
	if unkeyed:
		draw_arc(lamp, 4.0, 0, TAU, 14, Color(DIM.r, DIM.g, DIM.b, alpha), 1.2, true)
	else:
		var breath: float = 0.6 + 0.4 * sin(age * 8.0)
		draw_circle(lamp, 4.0, Color(tint.r, tint.g, tint.b, alpha * breath))
		draw_arc(lamp, 6.5, 0, TAU, 16, Color(tint.r, tint.g, tint.b, alpha * 0.28), 1.0, true)
	tracked(text + Vector2(16, 0), Lang.t(String(who[0])), 12, Color(tint.r, tint.g, tint.b, alpha), 2.0)
	if String(who[1]) != "":
		tracked(text + Vector2(16, 15), Lang.t(String(who[1])), 9, Color(DIM.r, DIM.g, DIM.b, alpha), 1.6)

	# Signal strength, driven by the same carrier value the audio mix uses, so
	# the picture and the hiss agree with each other.
	var meter := origin + Vector2(width - 20.0, 30.0)
	var lit: float = carrier * 5.0
	for index in range(5):
		var tall := 4.0 + float(index) * 2.6
		var cell := Rect2(meter + Vector2(-float(4 - index) * 6.0, -tall), Vector2(4, tall))
		draw_rect(cell, Color(0.08, 0.13, 0.15, 0.85 * alpha))
		if lit - float(index) > 0.05:
			draw_rect(cell, Color(tint.r, tint.g, tint.b,
				alpha * (0.35 + 0.65 * clampf(lit - float(index), 0.0, 1.0))))
	# More traffic waiting: say so, or a player who looks away misses that there
	# was a second half to the order.
	if not queue.is_empty():
		var more := "+%d" % queue.size()
		var more_wide := font.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font, origin + Vector2(width - 18.0 - more_wide, 44.0), more,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(MUTED.r, MUTED.g, MUTED.b, alpha))

	draw_line(text + Vector2(0, 24), text + Vector2(body, 24),
		Color(LINE_TINT.r, LINE_TINT.g, LINE_TINT.b, LINE_TINT.a * alpha), 1.0)

	# --- the line -------------------------------------------------------------- #
	# Drawn twice: the sea under this panel goes from near-black to sun glare
	# depending on where the camera is, and a single pass loses words to it.
	var spoken := spoken_so_far(line)
	var at := origin + Vector2(PLATE + 24.0, BODY_TOP)
	draw_multiline_string(font, at + Vector2(1, 1), spoken, HORIZONTAL_ALIGNMENT_LEFT, body,
		TEXT_SIZE, -1, Color(0, 0, 0, 0.55 * alpha))
	draw_multiline_string(font, at, spoken, HORIZONTAL_ALIGNMENT_LEFT, body, TEXT_SIZE, -1,
		Color(INK.r, INK.g, INK.b, alpha))
	if not typed:
		# Caret at the end of what has been typed, on whichever row that is.
		var row := row_height()
		var rows := maxf(1.0, roundf(font.get_multiline_string_size(spoken,
			HORIZONTAL_ALIGNMENT_LEFT, body, TEXT_SIZE).y / row))
		var tail := font.get_string_size(last_row(spoken, body), HORIZONTAL_ALIGNMENT_LEFT,
			-1, TEXT_SIZE).x
		var caret := at + Vector2(minf(tail + 2.0, body), (rows - 1.0) * row)
		draw_rect(Rect2(caret + Vector2(0, -float(TEXT_SIZE) * 0.72),
			Vector2(2, float(TEXT_SIZE) * 0.8)), Color(tint.r, tint.g, tint.b, alpha * 0.8))

func spoken_so_far(line: String) -> String:
	return line.substr(0, shown)

func last_row(text: String, body: float) -> String:
	## The greedy word wrap the text server is doing, replayed so the caret can
	## sit at the end of the final row. Measuring only the text after the last
	## space — the obvious shortcut — puts the caret under the middle of any row
	## that happens to hold more than one word.
	if font == null:
		return text
	var row := ""
	for word: String in text.split(" ", false):
		var candidate: String = word if row.is_empty() else row + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x > body:
			row = word
		else:
			row = candidate
	# A trailing space means the next word has not been typed yet, but the caret
	# has already moved past the one before it.
	return row + (" " if text.ends_with(" ") else "")

func tracked(point: Vector2, value: String, font_size: int, color: Color, spacing: float) -> void:
	var cursor := point.x
	for index in range(value.length()):
		draw_string(font, Vector2(cursor, point.y), value[index], HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)
		cursor += font.get_string_size(value[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing

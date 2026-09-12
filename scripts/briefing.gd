extends Control
## The pre-mission call. One hostile portrait, one line of dialogue, typed out,
## then the player answers it and the first wave begins.
##
## The speaker's name lives in SPEAKER so it is a one-line change. He used to be
## a real, living person by name, which was fine for a private build and not
## fine for anything else; he is now a parody who is unmistakably the reference
## without being the man.

const SPEAKER: String = "ADM. RONALD J. GRUMP"
const TITLE: String = "COMMANDER · TASK GROUP TREMENDOUS"
const LINE: String = "You gonna pay for this. Bigly. Attack them!"
const CHANNEL: String = "PRIORITY SIGNAL · HOSTILE COMMAND NET"
const PORTRAIT_PATH: String = "res://assets/portraits/enemy.png"
const TYPE_RATE: float = 26.0   ## Characters per second.

const INK := Color("dfe8e6")
const MUTED := Color("7e969c")
const DIM := Color("4d6067")
const GOLD := Color("e8be6e")
const RED := Color("ef8a76")
const PANEL := Color(0.031, 0.055, 0.070, 0.86)
const LINE_TINT := Color(0.35, 0.45, 0.48, 0.55)

var world: Node3D
var font: Font
var portrait: Texture2D
var age := 0.0
var shown := 0
var finished := false
var closing := 0.0
var ticks := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	portrait = load_portrait()

func load_portrait() -> Texture2D:
	## Imported resource first; a raw file on disk second, so dropping a new PNG
	## in place works without a re-import; a drawn placeholder if neither is
	## there.
	if ResourceLoader.exists(PORTRAIT_PATH):
		var resource := load(PORTRAIT_PATH)
		if resource is Texture2D:
			return resource
	var image := Image.load_from_file(ProjectSettings.globalize_path(PORTRAIT_PATH))
	if image != null and not image.is_empty():
		return ImageTexture.create_from_image(image)
	return null

func _process(delta: float) -> void:
	age += delta
	if closing > 0.0:
		closing += delta
		modulate.a = clampf(1.0 - closing * 3.2, 0.0, 1.0)
		if closing > 0.34:
			queue_free()
		queue_redraw()
		return
	if not finished:
		var want := int(maxf(0.0, age - 0.55) * TYPE_RATE)
		if want != shown:
			shown = mini(want, LINE.length())
			# One soft tick every few letters, not one per letter.
			ticks += 1
			if ticks % 3 == 0 and world != null and world.audio != null:
				world.audio.play("marker", -20.0, randf_range(0.85, 1.15))
			if shown >= LINE.length():
				finished = true
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if not pressed or closing > 0.0:
		return
	get_viewport().set_input_as_handled()
	if not finished:
		# First press skips the typewriter, second one answers the call.
		shown = LINE.length()
		finished = true
		return
	dismiss()

func dismiss() -> void:
	closing = 0.001
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if world != null:
		world.begin_mission()

func _draw() -> void:
	var view := size
	if view.x < 10.0:
		return
	# --- scrim: dark, with the corners pulled down further ------------------- #
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.012, 0.024, 0.031, 0.90))
	var bars := maxf(28.0, view.y * 0.09)
	draw_rect(Rect2(Vector2.ZERO, Vector2(view.x, bars)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(Vector2(0, view.y - bars), Vector2(view.x, bars)), Color(0, 0, 0, 0.55))

	var width := minf(940.0, view.x - 80.0)
	var plate := minf(268.0, width * 0.3)
	var height := maxf(plate + 56.0, 300.0)
	var origin := Vector2((view.x - width) * 0.5, (view.y - height) * 0.5)
	panel(Rect2(origin, Vector2(width, height)))
	draw_rect(Rect2(origin, Vector2(3, height)), RED)

	# --- portrait ------------------------------------------------------------ #
	var frame := Rect2(origin + Vector2(28, 28), Vector2(plate, plate))
	draw_rect(frame.grow(3), Color(0.06, 0.09, 0.11, 0.95))
	if portrait != null:
		draw_texture_rect(portrait, frame, false)
	else:
		draw_placeholder(frame)
	# Scanlines and a cold tint, so it reads as a signal rather than a photo.
	var scan := 0.0
	while scan < frame.size.y:
		draw_rect(Rect2(frame.position + Vector2(0, scan), Vector2(frame.size.x, 1)),
			Color(0.0, 0.05, 0.07, 0.22))
		scan += 3.0
	draw_rect(frame.grow(3), Color.TRANSPARENT)
	rule_box(frame.grow(3), GOLD.darkened(0.25))
	# Corner ticks on the frame.
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var point := frame.position + frame.size * corner
		var dx: float = 1.0 - corner.x * 2.0
		var dy: float = 1.0 - corner.y * 2.0
		draw_line(point, point + Vector2(14 * dx, 0), GOLD, 2.0)
		draw_line(point, point + Vector2(0, 14 * dy), GOLD, 2.0)

	# --- the caller ----------------------------------------------------------- #
	var text := origin + Vector2(plate + 56, 54)
	var column := width - plate - 84
	var live := sin(age * 5.0) > -0.2
	if live:
		draw_circle(text + Vector2(4, -5), 4.0, RED)
	tracked(text + Vector2(16, 0), CHANNEL, 10, RED, 2.2)
	draw_string(font, text + Vector2(0, 44), SPEAKER, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
	tracked(text + Vector2(2, 66), TITLE, 10, MUTED, 1.8)
	draw_line(text + Vector2(0, 84), text + Vector2(column, 84), LINE_TINT, 1.0)

	var spoken := LINE.substr(0, shown)
	draw_multiline_string(font, text + Vector2(0, 118), "“" + spoken,
		HORIZONTAL_ALIGNMENT_LEFT, column, 22, 3, INK)
	if not finished and fmod(age, 0.7) < 0.35:
		var run := font.get_string_size("“" + spoken, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_rect(Rect2(text + Vector2(minf(run.x, column) + 3, 102), Vector2(9, 3)), GOLD)
	elif finished:
		var run := font.get_string_size("“" + spoken, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		if run.x < column - 12:
			draw_string(font, text + Vector2(run.x + 1, 118), "”",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)

	# --- orders and the prompt ------------------------------------------------ #
	var foot := origin + Vector2(plate + 56, height - 62)
	tracked(foot, "ORDERS", 10, DIM, 2.0)
	draw_string(font, foot + Vector2(0, 20), first_objective(),
		HORIZONTAL_ALIGNMENT_LEFT, column, 13, MUTED)
	if finished:
		var prompt := "PRESS ANY KEY TO ANSWER"
		var span := tracked_width(prompt, 11, 2.6)
		var pulse: float = 0.55 + 0.45 * (0.5 + 0.5 * sin(age * 3.4))
		tracked(Vector2((view.x - span) * 0.5, origin.y + height + 40), prompt, 11,
			GOLD * Color(1, 1, 1, pulse), 2.6)
	else:
		var skip := "SPACE TO SKIP"
		var span := tracked_width(skip, 10, 2.4)
		tracked(Vector2((view.x - span) * 0.5, origin.y + height + 40), skip, 10, DIM, 2.4)

func first_objective() -> String:
	if world != null and world.campaign != null:
		var table: Array[Dictionary] = world.campaign.table
		var index: int = clampi(world.wave_index + 1, 0, table.size() - 1)
		return String(table[index]["brief"]) + "."
	return "Hold the sector."

func draw_placeholder(frame: Rect2) -> void:
	## No portrait on disk: a blank service photograph, so the layout still reads.
	draw_rect(frame, Color(0.08, 0.11, 0.13))
	var centre := frame.position + Vector2(frame.size.x * 0.5, frame.size.y * 0.44)
	draw_circle(centre, frame.size.x * 0.17, Color(0.17, 0.21, 0.23))
	var shoulders := frame.size.x * 0.31
	draw_rect(Rect2(centre + Vector2(-shoulders, frame.size.y * 0.16),
		Vector2(shoulders * 2.0, frame.size.y * 0.4)), Color(0.17, 0.21, 0.23))
	var label := "NO IMAGE"
	var span := tracked_width(label, 10, 2.4)
	tracked(frame.position + Vector2((frame.size.x - span) * 0.5, frame.size.y - 18), label, 10, DIM, 2.4)

func panel(rect: Rect2) -> void:
	var clip := 14.0
	var points := PackedVector2Array([
		rect.position + Vector2(clip, 0),
		rect.position + Vector2(rect.size.x, 0),
		rect.position + Vector2(rect.size.x, rect.size.y - clip),
		rect.position + Vector2(rect.size.x - clip, rect.size.y),
		rect.position + Vector2(0, rect.size.y),
		rect.position + Vector2(0, clip)])
	draw_colored_polygon(points, PANEL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, LINE_TINT, 1.0, true)

func rule_box(rect: Rect2, color: Color) -> void:
	draw_polyline(PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.end, rect.position + Vector2(0, rect.size.y), rect.position]), color, 1.0, true)

func tracked(point: Vector2, value: String, font_size: int, color: Color, spacing: float) -> float:
	var cursor := point.x
	for index in range(value.length()):
		draw_string(font, Vector2(cursor, point.y), value[index], HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)
		cursor += font.get_string_size(value[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return cursor - point.x

func tracked_width(value: String, font_size: int, spacing: float) -> float:
	var total := 0.0
	for index in range(value.length()):
		total += font.get_string_size(value[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return total

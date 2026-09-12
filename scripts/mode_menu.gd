extends Control
## The first thing the game asks: which of these are you here to play.
##
## Same construction as the briefing card — it pauses the tree behind itself and
## runs at PROCESS_MODE_ALWAYS, so nothing moves until a choice is made. It is
## deliberately two options and nothing else; a front end with settings in it is
## a different job, and the settings that exist are already on the toolbar.

const INK := Color("dfe8e6")
const MUTED := Color("7e969c")
const DIM := Color("4d6067")
const MINT := Color("6fe0bd")
const GOLD := Color("e8be6e")
const PANEL := Color(0.031, 0.055, 0.070, 0.90)
const LINE_TINT := Color(0.35, 0.45, 0.48, 0.55)

## [code, label] for the language row.
const OPTIONS: Array[Array] = [["en", "ENGLISH"], ["ru", "РУССКИЙ"]]

## [key, title, subtitle, body]
const CHOICES: Array[Array] = [
	["1", "CAMPAIGN", "Four levels · Strait of Hormuz",
		"Close the strait. Starts by teaching you where to put your rounds."],
	["2", "DUEL", "One corvette against one",
		"No orders and no escorts. Everything you have is released from the first second."],
]

var world: Node3D
var font: Font
var age := 0.0
var picked := -1
var hovered := 0
var closing := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	age += delta
	if closing > 0.0:
		closing += delta
		modulate.a = clampf(1.0 - closing * 3.4, 0.0, 1.0)
		if closing > 0.32:
			var choice := picked
			queue_free()
			world.begin_mode(choice)
	queue_redraw()

func card(index: int) -> Rect2:
	var wide := minf(760.0, size.x - 80.0)
	var tall := 92.0
	var origin := Vector2((size.x - wide) * 0.5, size.y * 0.5 - tall - 12.0)
	return Rect2(origin + Vector2(0, float(index) * (tall + 16.0)), Vector2(wide, tall))

func _unhandled_input(event: InputEvent) -> void:
	if closing > 0.0:
		return
	if event is InputEventMouseMotion:
		for index in range(CHOICES.size()):
			if card(index).has_point(event.position):
				hovered = index
		return
	var chosen := -1
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1, KEY_KP_1: chosen = 0
			KEY_2, KEY_KP_2: chosen = 1
			KEY_UP, KEY_W: hovered = maxi(0, hovered - 1)
			KEY_DOWN, KEY_S: hovered = mini(CHOICES.size() - 1, hovered + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: chosen = hovered
			KEY_L: Lang.set_language(Lang.ENGLISH if Lang.russian() else Lang.RUSSIAN)
	elif event is InputEventMouseButton and event.pressed:
		if language_rect().has_point(event.position):
			Lang.set_language(Lang.ENGLISH if Lang.russian() else Lang.RUSSIAN)
			get_viewport().set_input_as_handled()
			return
		for index in range(CHOICES.size()):
			if card(index).has_point(event.position):
				chosen = index
	get_viewport().set_input_as_handled()
	if chosen >= 0:
		picked = chosen
		closing = 0.001
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if world != null and world.audio != null:
			world.audio.play("marker", -6.0, 1.0)

func _draw() -> void:
	if font == null or size.x < 10.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.024, 0.031, 0.93))
	var bars := maxf(28.0, size.y * 0.09)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, bars)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(Vector2(0, size.y - bars), Vector2(size.x, bars)), Color(0, 0, 0, 0.5))

	var head := card(0)
	tracked(Vector2(head.position.x, head.position.y - 74.0), Lang.t("STRAIT OF HORMUZ"), 11, MINT, 3.0)
	draw_string(font, Vector2(head.position.x, head.position.y - 40.0), Lang.t("Choose your fight"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK)

	for index in range(CHOICES.size()):
		var choice: Array = CHOICES[index]
		var rect := card(index)
		var live: bool = index == hovered
		var accent: Color = MINT if live else LINE_TINT
		draw_colored_polygon(PackedVector2Array([
			rect.position + Vector2(12, 0), rect.position + Vector2(rect.size.x, 0),
			rect.position + Vector2(rect.size.x, rect.size.y - 12), rect.end - Vector2(12, 0),
			rect.position + Vector2(0, rect.size.y), rect.position + Vector2(0, 12)]),
			Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a if live else PANEL.a * 0.7))
		draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), accent)
		if live:
			draw_polyline(PackedVector2Array([
				rect.position + Vector2(12, 0), rect.position + Vector2(rect.size.x, 0),
				rect.position + Vector2(rect.size.x, rect.size.y - 12), rect.end - Vector2(12, 0),
				rect.position + Vector2(0, rect.size.y), rect.position + Vector2(0, 12),
				rect.position + Vector2(12, 0)]), Color(MINT.r, MINT.g, MINT.b, 0.55), 1.0, true)
		# The number to press, as a key cap.
		var cap := Rect2(rect.position + Vector2(22, 30), Vector2(30, 30))
		draw_rect(cap, Color(0.10, 0.16, 0.18, 0.9))
		draw_rect(cap, accent, false, 1.0)
		draw_string(font, cap.position + Vector2(11, 21), String(choice[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK if live else MUTED)
		tracked(rect.position + Vector2(72, 40), Lang.t(String(choice[1])), 18, INK if live else MUTED, 2.6)
		tracked(rect.position + Vector2(74, 57), Lang.t(String(choice[2])), 9, GOLD if live else DIM, 1.8)
		draw_string(font, rect.position + Vector2(74, 78), Lang.t(String(choice[3])),
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 96, 11, MUTED if live else DIM)

	var prompt := Lang.t("1 or 2 · arrows and Enter · or click")
	var span := tracked_width(prompt, 10, 2.4)
	var beat: float = 0.55 + 0.45 * (0.5 + 0.5 * sin(age * 3.2))
	tracked(Vector2((size.x - span) * 0.5, card(1).end.y + 46.0), prompt, 10,
		Color(DIM.r, DIM.g, DIM.b, beat), 2.4)
	# The language switch lives here because this is the one screen every player
	# sees before anything else, and the choice is remembered between runs.
	var here := language_rect()
	draw_rect(here, Color(0.06, 0.10, 0.12, 0.85))
	draw_rect(here, Color(MINT.r, MINT.g, MINT.b, 0.4), false, 1.0)
	tracked(here.position + Vector2(12, 20), Lang.t("LANGUAGE"), 9, DIM, 2.0)
	for index in range(OPTIONS.size()):
		var option: Array = OPTIONS[index]
		var chosen: bool = Lang.current == String(option[0])
		tracked(here.position + Vector2(90 + index * 86, 20), String(option[1]), 11,
			MINT if chosen else DIM, 1.6)
	tracked(here.position + Vector2(here.size.x - 26, 20), "L", 10, MUTED, 1.4)

func language_rect() -> Rect2:
	var wide := 270.0
	return Rect2(Vector2((size.x - wide) * 0.5, card(1).end.y + 70.0), Vector2(wide, 30))

func tracked(point: Vector2, value: String, font_size: int, color: Color, spacing: float) -> void:
	var cursor := point.x
	for index in range(value.length()):
		draw_string(font, Vector2(cursor, point.y), value[index], HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)
		cursor += font.get_string_size(value[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing

func tracked_width(value: String, font_size: int, spacing: float) -> float:
	var total := 0.0
	for index in range(value.length()):
		total += font.get_string_size(value[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return maxf(total - spacing, 0.0)

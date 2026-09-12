extends Control
## Arcade combat overlay. Drawn procedurally: clipped-corner panels, tracked
## capitals, segmented readouts, a reticle that confirms every hit, and a
## gridded minimap.

const INK := Color("dfe8e6")
const MUTED := Color("7e969c")
const DIM := Color("4d6067")
const MINT := Color("6fe0bd")
const CYAN := Color("58c8d8")
const GOLD := Color("e8be6e")
const RED := Color("ef8a76")
const PANEL := Color(0.031, 0.055, 0.070, 0.80)
const PANEL_DEEP := Color(0.016, 0.031, 0.043, 0.88)
const LINE := Color(0.42, 0.72, 0.75, 0.30)
const TRACK := Color("1c2b32")
## Half-width of the settled target bracket, in pixels. Named because it is a
## deliberate number: at 30 the bracket plus its name plate covered the hull it
## was pointing at, which is the opposite of what a target mark is for.
const LOCK_SPAN: float = 15.0
## The gunsight. Kept out of the palette above on purpose: every other colour
## here is a state, and this one has to be legible before it is meaningful.
const SIGHT := Color("fff1cf")
const SIGHT_COLD := Color("ff6a4d")
# What losing each module actually does, taken from the code that implements it.
# The same effects apply to a hostile hull, which is what makes aiming a choice.
const EFFECTS := {
	"bow": "Leaks below half · all three sink her",
	"mid": "Leaks below half · all three sink her",
	"stern": "Leaks below half · all three sink her",
	"gun": "Forward mount stops firing",
	"aft_gun": "Aft mount stops firing",
	"engine": "Speed falls with it · dead, no way on",
	"rudder": "Steering authority falls with it",
	"bridge": "Helm down to a third · fires burn longer",
	"radar": "No anti-ship missile launches",
	"launcher_port": "Two missile cells offline",
	"launcher_starboard": "Two missile cells offline",
	"ciws": "No missile interception, no close AA",
	"sam": "No air-defence missiles",
}

var world: Node3D
var font: Font
var buttons: Array[Button] = []
var details := false
var pulse: float = 0.0

# Feedback state.
var hit_flash: float = 0.0
var hit_kill: bool = false
var damage_flash: float = 0.0
var banner_text: String = ""
var banner_sub: String = ""
var banner_age: float = 99.0
var lock_since: float = 0.0
var last_lock: Node3D
var numbers: Array[Dictionary] = []
var callouts: Array[Dictionary] = []
# Caption boxes already placed this frame, so two contacts on the same bearing
# do not print their ranges on top of each other.
var arrow_labels: Array[Rect2] = []
var pickup_text: String = ""
var pickup_kind: int = 0
var pickup_age: float = 99.0
var vampire_age: float = 99.0
var last_wave_shown: int = -2
var last_state_shown: String = ""
# A one-line prompt when something the player has never had before becomes
# available. Shown once each — a hint repeated is a hint being ignored.
var hint_key: String = ""
var hint_label: String = ""
var hint_text: String = ""
var hint_age: float = 99.0
var hints_given: Dictionary = {}

# Panel geometry, shared by the drawing and the pointer-blocking test.
var mission_rect := Rect2()
var status_rect := Rect2()
var wing_rect := Rect2()
var weapon_rect := Rect2()
var vitals_rect := Rect2()
var minimap_rect := Rect2()
var target_rect := Rect2()
var details_rect := Rect2()
var toolbar_rect := Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	make_button("TAB · SWAP", world.swap_control)
	make_button("Ⅱ", toggle_pause)
	make_button("SYSTEMS", func(): details = not details)
	make_button("♪", func(): world.audio.toggle_silence())
	make_button("FULLSCREEN", world.toggle_fullscreen)
	make_button("RENDER 100%", world.cycle_render_scale)
	make_button("+ ENEMY BOAT", func(): world.spawn_extra(1))
	make_button("+ ENEMY AIR", func(): world.spawn_helicopter(1))
	make_button("RESTART", world.restart)

func make_button(title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.tooltip_text = title
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", MINT)
	button.add_theme_color_override("font_pressed_color", MINT)
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_DEEP if state == "normal" else Color(0.09, 0.19, 0.21, 0.92)
		style.border_color = LINE if state == "normal" else MINT
		style.set_border_width_all(1)
		style.set_corner_radius_all(0)
		style.corner_radius_top_left = 6
		style.corner_radius_bottom_right = 6
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	add_child(button)
	buttons.append(button)

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused

# --------------------------------------------------------------------------- #
# Feedback hooks, called by the world
# --------------------------------------------------------------------------- #

func flash_hit(destroyed_part: bool) -> void:
	hit_flash = 1.35 if destroyed_part else 1.0
	hit_kill = destroyed_part or hit_kill

func flash_damage(amount: float) -> void:
	damage_flash = clampf(damage_flash + amount / 90.0, 0.0, 1.2)

func add_damage_number(point: Vector3, amount: float, critical: bool) -> void:
	if numbers.size() > 26:
		numbers.pop_front()
	numbers.append({"point": point, "amount": amount, "age": 0.0, "critical": critical,
		"drift": Vector2(randf_range(-14, 14), 0)})

func raise_vampire() -> void:
	vampire_age = 0.0

func add_callout(point: Vector3, text: String, tint: Color) -> void:
	## A named result, floated at the point of impact: "CIWS MOUNT DISABLED".
	if callouts.size() > 8:
		callouts.pop_front()
	# Several modules can go in one blast; stack them rather than overlapping.
	var row := 0
	for entry: Dictionary in callouts:
		if float(entry["age"]) < 0.7:
			row += 1
	# One blast can take half a dozen modules. Past three the list stops being
	# information and starts being a wall of red.
	if row >= 3:
		return
	callouts.append({"point": point, "text": text, "age": 0.0, "tint": tint, "row": row})

func announce_pickup(kind: int, message: String) -> void:
	pickup_kind = kind
	pickup_text = message
	pickup_age = 0.0

## How long a prompt stays up. Long enough to read twice, short enough that it
## is gone before it becomes furniture.
const HINT_HOLD: float = 7.0

func hint(key: String, label: String, text: String) -> void:
	## Teach one thing, the first time it is true, and never again.
	if hints_given.has(key):
		return
	hints_given[key] = true
	hint_key = key
	hint_label = label
	hint_text = text
	hint_age = 0.0

func playing() -> bool:
	## Actually at the controls — not paused, not behind the briefing card, and
	## the mission still running.
	return not get_tree().paused and not is_instance_valid(world.briefing) \
		and world.mission_state == "active"

func watch_unlocks() -> void:
	## Teaching, in the order the player needs it: designate, then shoot, then
	## shoot with the other thing. Each step waits for the one before it to be
	## given *and* for the player to have done it, so nobody is told to press X
	## before they have ever designated anything.
	#
	# Only while the game is being played. `cleared()` is permissive by default
	# and the mission is "active" from the first frame, so the guns prompt used
	# to fire behind the full-screen briefing card, count down its seven seconds
	# unseen, and mark itself given — which is why it only ever appeared on a
	# restart, when the card gets dismissed fast enough to leave time on it.
	if not playing() or world.wave_index < 0:
		return
	if world.selected is CombatHelicopter:
		hint("air", "LMB · X · Z", "Rockets. X for the air-to-air missile, Z to throw flares.")
		return
	var designated: bool = is_instance_valid(world.locked_target)
	# 1. What a target is and how to name one.
	if not hints_given.has("lock"):
		if designated:
			hint("lock", "T", "Press T to designate the contact you want to shoot at.")
		return
	# 2. How to shoot it. Held back until they have actually designated
	#    something, so the two never arrive in the same breath.
	if not hints_given.has("fire"):
		if world.cleared("gun") and designated:
			hint("fire", "LMB", "Now hold the left mouse button to fire where you are pointing.")
		return
	# 3. And the other weapon, once the mission has released it.
	if world.cleared("missile") and designated:
		hint("asm", "T · X", "T designates, X sends an anti-ship missile at whatever is designated.")
		return
	# The camera, once the shooting is understood — it is comfort, not survival.
	if world.elapsed > 45.0:
		hint("camera", "MMB", "Middle mouse button and drag swings the view round your ship.")

func draw_hint() -> void:
	if hint_text == "" or hint_age > HINT_HOLD:
		return
	var alpha: float = clampf(minf(hint_age * 3.0, (HINT_HOLD - hint_age) * 1.6), 0.0, 1.0)
	var key_wide := tracked_width(hint_label, 10, 1.6) + 16.0
	var body_wide := font.get_string_size(Lang.t(hint_text), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var wide := key_wide + 14.0 + body_wide + 28.0
	var origin := Vector2((size.x - wide) * 0.5, size.y - 186.0)
	var frame := Rect2(origin, Vector2(wide, 30))
	draw_rect(frame, Color(0.03, 0.05, 0.06, 0.88 * alpha))
	draw_rect(frame, Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha), false, 1.0)
	var cap := Rect2(origin + Vector2(14, 8), Vector2(key_wide, 15))
	draw_rect(cap, Color(GOLD.r * 0.25, GOLD.g * 0.22, 0.08, alpha))
	draw_rect(cap, Color(GOLD.r, GOLD.g, GOLD.b, alpha), false, 1.0)
	tracked(origin + Vector2(22, 19), hint_label, 10, Color(GOLD.r, GOLD.g, GOLD.b, alpha), 1.6)
	draw_string(font, origin + Vector2(14 + key_wide + 14, 19), Lang.t(hint_text),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK.r, INK.g, INK.b, alpha))

func announce(title: String, subtitle: String) -> void:
	banner_text = title
	banner_sub = subtitle
	banner_age = 0.0

# --------------------------------------------------------------------------- #
# Input
# --------------------------------------------------------------------------- #

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_P:
			toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			get_viewport().set_input_as_handled()
			world.restart()
			return
	if visible and event is InputEventMouseButton and blocks_pointer(event.position):
		for button in buttons:
			if button.visible and button.get_global_rect().has_point(event.position):
				return
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	pulse += delta
	hit_flash = maxf(0.0, hit_flash - delta * 2.1)
	if hit_flash <= 0.0:
		hit_kill = false
	damage_flash = maxf(0.0, damage_flash - delta * 1.1)
	banner_age += delta
	# A prompt's welcome does not wear out while the game is paused.
	if playing():
		hint_age += delta
	pickup_age += delta
	vampire_age += delta
	for index in range(numbers.size() - 1, -1, -1):
		numbers[index]["age"] += delta
		if numbers[index]["age"] > 1.5:
			numbers.remove_at(index)
	for index in range(callouts.size() - 1, -1, -1):
		callouts[index]["age"] += delta
		if callouts[index]["age"] > 2.3:
			callouts.remove_at(index)
	if world.locked_target != last_lock:
		last_lock = world.locked_target
		lock_since = pulse
	watch_campaign()
	watch_unlocks()
	# This node runs with PROCESS_MODE_ALWAYS, which is what makes it the right
	# place to decide whether the pointer is visible.
	world.update_cursor()
	buttons[1].text = "▶" if get_tree().paused else "Ⅱ"
	buttons[3].text = "MUTED" if world.audio.silenced else "♪ M"
	buttons[4].text = "WINDOWED" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "FULLSCREEN"
	buttons[5].text = "RENDER %d%%" % int(round(world.render_scale * 100.0))
	for i in range(buttons.size()):
		buttons[i].visible = i < 4 or details
		buttons[i].position = Vector2(size.x - 390 + i * 94, 18)
		buttons[i].size = Vector2(86, 28)
		if i >= 4:
			buttons[i].position = Vector2(34 + (i - 4) * 118, details_rect.end.y + 14)
			buttons[i].size = Vector2(110, 26)
	layout()
	queue_redraw()

func watch_campaign() -> void:
	## Raise a banner whenever the campaign changes phase.
	# End-of-level banners are gone: the debrief card lands in the same place and
	# says the same thing with the figures attached. Two things fighting for the
	# middle of the screen is one thing too many.
	if world.mission_state != "active":
		last_state_shown = world.mission_state
		return
	if world.wave_state == "fighting" and last_wave_shown != world.wave_index:
		last_wave_shown = world.wave_index
		var wave: Dictionary = world.current_wave()
		announce("LEVEL %d" % (world.wave_index + 1), str(wave.get("title", "")))
		last_state_shown = "fighting"
	elif world.wave_state == "cleared" and last_state_shown != "cleared":
		last_state_shown = "cleared"

func layout() -> void:
	mission_rect = Rect2(18, 18, 284, 62)
	toolbar_rect = Rect2(size.x - 394, 14, 386, 36)
	# A bigger map, with the target readout stacked directly above it. When the
	# player looks at the map to find the contact they have designated, the name
	# and the range for it should be in the same glance rather than across the
	# screen from it.
	minimap_rect = Rect2(size.x - 294, size.y - 294, 276, 276)
	target_rect = Rect2(size.x - 294, minimap_rect.position.y - 186, 276, 172)
	# Our own ship gets the same treatment as theirs, on the other side of the
	# screen: you should be able to see what is still working on your own hull
	# without opening a panel, and it should be told the same way.
	status_rect = Rect2(18, size.y - 190, 268, 172)
	wing_rect = Rect2(18, size.y - 238, 268, 44)
	weapon_rect = Rect2(size.x * 0.5 - 200, size.y - 90, 400, 72)
	# Condition used to be its own strip in the middle of the screen. It belongs
	# with the picture of the ship it describes: one panel answers "how is my
	# ship", instead of the answer being split across two corners.
	vitals_rect = Rect2()
	details_rect = Rect2(18, 92, 712, 330)

func wing_drawn() -> bool:
	## The wing panel is only there when there is another unit to swap to.
	if world.selected == world.player_ship:
		return is_instance_valid(world.player_air) and not world.player_air.sunk
	return is_instance_valid(world.player_ship) and not world.player_ship.sunk

func blocks_pointer(point: Vector2) -> bool:
	if not visible:
		return false
	if mission_rect.has_point(point) or toolbar_rect.has_point(point):
		return true
	if status_rect.has_point(point):
		return true
	if wing_rect.has_point(point) and wing_drawn():
		return true
	if weapon_rect.has_point(point) or minimap_rect.has_point(point):
		return true
	if target_rect.has_point(point):
		return true
	return details and details_rect.has_point(point)

# --------------------------------------------------------------------------- #
# Drawing primitives
# --------------------------------------------------------------------------- #

func text_at(point: Vector2, value: String, font_size: int = 12, color: Color = INK) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, font_size), color)

func tracked(point: Vector2, value: String, font_size: int, color: Color, spacing: float = 1.6) -> float:
	var cursor := point.x
	for index in range(value.length()):
		var glyph := value[index]
		draw_string(font, Vector2(cursor, point.y), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		cursor += font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return cursor - point.x

func tracked_width(value: String, font_size: int, spacing: float) -> float:
	var total := 0.0
	for index in range(value.length()):
		total += font.get_string_size(value[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	return maxf(total - spacing, 0.0)

func panel(rect: Rect2, accent: Color = Color.TRANSPARENT, deep: bool = false) -> void:
	var clip := 9.0
	var points := PackedVector2Array([
		rect.position + Vector2(clip, 0),
		rect.position + Vector2(rect.size.x, 0),
		rect.position + Vector2(rect.size.x, rect.size.y - clip),
		rect.position + Vector2(rect.size.x - clip, rect.size.y),
		rect.position + Vector2(0, rect.size.y),
		rect.position + Vector2(0, clip)])
	draw_colored_polygon(points, PANEL_DEEP if deep else PANEL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, LINE, 1.0, true)
	if accent.a > 0.0:
		draw_rect(Rect2(rect.position + Vector2(0, clip), Vector2(2, rect.size.y - clip * 2)), accent)

func bracket(centre: Vector2, half: Vector2, color: Color, arm: float = 6.0, thickness: float = 1.6) -> void:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var origin := centre + half * corner
		draw_line(origin, origin - Vector2(arm * corner.x, 0), color, thickness)
		draw_line(origin, origin - Vector2(0, arm * corner.y), color, thickness)

func bar(point: Vector2, width: float, fraction: float, color: Color, height: float = 5.0) -> void:
	draw_rect(Rect2(point, Vector2(width, height)), TRACK)
	var filled := width * clampf(fraction, 0, 1)
	if filled > 0.5:
		draw_rect(Rect2(point, Vector2(filled, height)), color)
	draw_rect(Rect2(point, Vector2(width, height)), Color(color.r, color.g, color.b, 0.28), false, 1.0)

func segmented(point: Vector2, width: float, fraction: float, color: Color, cells: int = 12, height: float = 6.0) -> void:
	var gap := 2.0
	var cell := (width - gap * (cells - 1)) / cells
	var lit := fraction * cells
	for index in range(cells):
		var rect := Rect2(point + Vector2(index * (cell + gap), 0), Vector2(cell, height))
		var level := clampf(lit - index, 0.0, 1.0)
		draw_rect(rect, TRACK)
		if level > 0.02:
			draw_rect(rect, Color(color.r, color.g, color.b, 0.35 + level * 0.65))

# --------------------------------------------------------------------------- #
# Icons — every readout should say what it is without a caption
# --------------------------------------------------------------------------- #

func glyph_points(kind: String, size: float) -> PackedVector2Array:
	var h := size
	var w := size * 0.5
	match kind:
		"missile":
			# Pointed nose, straight body, swept tail fins, nozzle. Reads as a
			# rocket rather than an arrowhead, and still holds up at 14 px.
			return PackedVector2Array([
				Vector2(0, -h * 0.50),
				Vector2(w * 0.34, -h * 0.20), Vector2(w * 0.34, h * 0.12),
				Vector2(w * 0.86, h * 0.33), Vector2(w * 0.70, h * 0.45),
				Vector2(w * 0.30, h * 0.34), Vector2(w * 0.30, h * 0.50),
				Vector2(-w * 0.30, h * 0.50), Vector2(-w * 0.30, h * 0.34),
				Vector2(-w * 0.70, h * 0.45), Vector2(-w * 0.86, h * 0.33),
				Vector2(-w * 0.34, h * 0.12), Vector2(-w * 0.34, -h * 0.20)])
		"rocket":
			return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.55, -h * 0.05),
				Vector2(w * 0.55, h * 0.26), Vector2(w * 0.85, h * 0.5), Vector2(-w * 0.85, h * 0.5),
				Vector2(-w * 0.55, h * 0.26), Vector2(-w * 0.55, -h * 0.05)])
		"shell":
			return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.55, -h * 0.12),
				Vector2(w * 0.55, h * 0.5), Vector2(-w * 0.55, h * 0.5), Vector2(-w * 0.55, -h * 0.12)])
		"flame":
			return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.5, -h * 0.02),
				Vector2(w * 0.44, h * 0.3), Vector2(0, h * 0.5), Vector2(-w * 0.44, h * 0.3),
				Vector2(-w * 0.5, -h * 0.02), Vector2(-w * 0.16, -h * 0.16)])
		"shield":
			return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.62, -h * 0.28),
				Vector2(w * 0.62, h * 0.1), Vector2(0, h * 0.5), Vector2(-w * 0.62, h * 0.1),
				Vector2(-w * 0.62, -h * 0.28)])
		"drop":
			return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.55, h * 0.08),
				Vector2(w * 0.3, h * 0.45), Vector2(-w * 0.3, h * 0.45), Vector2(-w * 0.55, h * 0.08)])
	return PackedVector2Array()

func glyph(kind: String, at: Vector2, size: float, color: Color, filled: bool = true) -> void:
	if kind == "flare":
		# Six-point starburst.
		var star := PackedVector2Array()
		for index in range(12):
			var radius: float = size * (0.5 if index % 2 == 0 else 0.2)
			var angle := PI * float(index) / 6.0 - PI * 0.5
			star.append(at + Vector2(cos(angle), sin(angle)) * radius)
		if filled:
			draw_colored_polygon(star, color)
		else:
			star.append(star[0])
			draw_polyline(star, color, 1.0, true)
		return
	if kind == "burst":
		# CIWS: a muzzle throwing a cone of rounds.
		draw_circle(at + Vector2(0, size * 0.32), size * 0.14, color)
		for lean: float in [-0.42, 0.0, 0.42]:
			var direction := Vector2(sin(lean), -cos(lean))
			draw_line(at + direction * size * 0.16, at + direction * size * 0.55, color, 1.6)
		return
	var points := glyph_points(kind, size)
	if points.is_empty():
		return
	for index in range(points.size()):
		points[index] += at
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 1.0, true)

func icon_row(point: Vector2, count: int, total: int, color: Color, kind: String,
		step: float = 14.0, size_px: float = 14.0) -> void:
	## Rounds remaining, drawn as the thing they actually are.
	for index in range(total):
		var at := point + Vector2(index * step, 0)
		if index < count:
			glyph(kind, at, size_px, color)
		else:
			glyph(kind, at, size_px, DIM, false)

func pips(point: Vector2, count: int, total: int, color: Color) -> void:
	for i in range(total):
		var rect := Rect2(point + Vector2(i * 13, 0), Vector2(8, 11))
		draw_rect(rect, TRACK)
		if i < count:
			draw_rect(rect, color)
		else:
			draw_rect(rect, DIM, false, 1.0)

func dial(centre: Vector2, radius: float, fraction: float, color: Color) -> void:
	draw_arc(centre, radius, -PI * 0.5, PI * 1.5, 32, TRACK, 2.5, true)
	if fraction > 0.005:
		draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(fraction, 0, 1), 32, color, 2.5, true)

# --------------------------------------------------------------------------- #
# Frame
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if font == null or world.camera == null:
		return
	draw_markers()
	draw_objective_marker()
	draw_damage_numbers()
	draw_callouts()
	# Everything anchored in the world goes down before the chrome does, so a
	# panel covers an edge arrow rather than the arrow landing across the panel.
	draw_offscreen_contacts()
	draw_mission()
	draw_wing()
	draw_status()
	draw_weapons()
	draw_target()
	draw_minimap()
	draw_feed()
	draw_reticle()
	draw_pickup()
	draw_vampire()
	draw_vignette()
	draw_banner()
	draw_hint()
	draw_debrief()
	if details:
		draw_details()
	# The pause card is for a game the player paused, not for one that has not
	# started. The mode menu and the briefing both pause the tree behind
	# themselves, and the controls list was drawing straight through both of
	# them.
	if get_tree().paused and not is_instance_valid(world.menu) \
			and not is_instance_valid(world.briefing):
		draw_pause()

func draw_mission() -> void:
	panel(mission_rect, MINT)
	var origin := mission_rect.position
	var wave: Dictionary = world.current_wave()
	var title := Lang.t("STANDING BY")
	if world.wave_index >= 0:
		title = "LEVEL %d · %s" % [world.wave_index + 1, wave.get("title", "")]
	tracked(origin + Vector2(15, 25), title, 12, INK, 1.5)
	var line := ""
	var tint := GOLD
	match world.mission_state:
		"complete":
			line = "Sector clear"
			tint = MINT
		"failed":
			line = "Kestrel lost — press R"
			tint = RED
		_:
			match world.wave_state:
				"briefing":
					line = "Contact in %d…" % maxi(1, ceili(world.wave_clock))
				"fighting":
					# What the level is actually asking for. A hostile count is
					# the right answer to "clear the sector" and the wrong one to
					# "disable her engine room and do not sink her" — which is
					# the whole of the first level, and it was never stated
					# anywhere the player could see it during the fight.
					line = world.campaign.progress() if world.campaign != null \
						else "%d hostiles remaining" % world.hostiles_remaining()
					tint = RED if not line.ends_with("DONE") else MINT
				"cleared":
					line = "Level clear — next in %d…" % maxi(1, ceili(world.wave_clock))
					tint = MINT
	text_at(origin + Vector2(15, 45), line, 11, tint)
	var minutes := int(world.elapsed) / 60
	var clock := "%02d:%02d" % [minutes, int(world.elapsed) % 60]
	var clock_width := font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	text_at(origin + Vector2(mission_rect.size.x - clock_width - 15, 25), clock, 12, MUTED)
	# Wave pips.
	for index in range(world.level_count()):
		var rect := Rect2(origin + Vector2(mission_rect.size.x - 62 + index * 15, 37), Vector2(11, 6))
		draw_rect(rect, TRACK)
		if index < world.wave_index:
			draw_rect(rect, MINT)
		elif index == world.wave_index:
			draw_rect(rect, GOLD)
		else:
			draw_rect(rect, DIM, false, 1.0)

func draw_wing() -> void:
	## The unit you are not currently controlling.
	# Never bind a freed node to a typed local; check validity first.
	var other: Node3D = null
	if world.selected == world.player_ship:
		if is_instance_valid(world.player_air):
			other = world.player_air
	elif is_instance_valid(world.player_ship):
		other = world.player_ship
	# Nothing to swap to: draw nothing. A panel reading NO AIR SUPPORT for three
	# levels out of four is a permanent apology taking up the corner of the
	# screen, and it tells the player nothing they can act on.
	if not is_instance_valid(other) or other.sunk:
		return
	panel(wing_rect, CYAN if other is CombatHelicopter else MINT)
	var origin := wing_rect.position
	var air := other is CombatHelicopter
	var glyph := origin + Vector2(18, 19)
	var tint := CYAN if air else MINT
	if air:
		draw_line(glyph - Vector2(6, 0), glyph + Vector2(6, 0), tint, 1.6)
		draw_line(glyph - Vector2(0, 5), glyph + Vector2(0, 5), tint, 1.6)
	else:
		draw_polyline(PackedVector2Array([glyph + Vector2(-5, 4), glyph + Vector2(0, -5), glyph + Vector2(5, 4)]), tint, 1.6)
	text_at(origin + Vector2(34, 16), other.callsign, 10, MUTED)
	var health: float = other.health / other.maximum_health if air else other.hull_fraction()
	bar(origin + Vector2(wing_rect.size.x - 88, 11), 58, health, MINT if health > 0.35 else RED, 4.0)
	text_at(origin + Vector2(wing_rect.size.x - 24, 16), "TAB", 9, DIM)
	if air:
		text_at(origin + Vector2(34, 30), "H · " + String(other.task), 9, GOLD if other.explicit_target else DIM)

func draw_status() -> void:
	## Who you are, how fast you are going, and what is still working on your own
	## hull — told the same way as the contact you are shooting at, because there
	## is no reason for the player to learn two languages for the same fact.
	var unit: Node3D = world.selected
	if not is_instance_valid(unit):
		return
	var air := unit is CombatHelicopter
	panel(status_rect, CYAN if air else MINT)
	var origin := status_rect.position
	var wide := status_rect.size.x
	tracked(origin + Vector2(15, 26), unit.callsign, 13, INK, 1.4)
	text_at(origin + Vector2(wide - 40, 24), Lang.t("YOU"), 9, CYAN)
	text_at(origin + Vector2(15, 44), unit.status if not air else String(unit.task), 9, MUTED)
	if air:
		text_at(origin + Vector2(15, 62), Lang.t("ALT"), 9, MUTED)
		bar(origin + Vector2(52, 54), 110, clampf(unit.flight_height / 170.0, 0, 1), CYAN)
		text_at(origin + Vector2(wide - 52, 62), "%3d m" % int(maxf(0, unit.position.y)), 9, MUTED)
		var airframe: float = unit.health / unit.maximum_health
		var air_tint := MINT if airframe > 0.35 else RED
		glyph("shield", origin + Vector2(22, 82), 13.0, air_tint)
		segmented(origin + Vector2(36, 76), 118, airframe, air_tint, 12, 9.0)
		text_at(origin + Vector2(160, 86), "%3d%%" % int(round(airframe * 100.0)), 11, air_tint)
		icon_row(origin + Vector2(196, 82), unit.flare_packs, 3, GOLD, "flare", 14.0, 12.0)
		draw_air_schematic(Rect2(origin + Vector2(13, 96), Vector2(wide - 26, 64)), unit, CYAN)
		return
	text_at(origin + Vector2(15, 62), Lang.t("SPEED"), 9, MUTED)
	bar(origin + Vector2(52, 54), 110, absf(unit.speed) / unit.loadout.speed, CYAN)
	text_at(origin + Vector2(wide - 56, 62), "%2.0f kn" % (absf(unit.speed) * 1.94), 9, MUTED)

	var hull: float = unit.hull_fraction()
	var tint := MINT if hull > 0.35 else RED
	glyph("shield", origin + Vector2(22, 82), 13.0, tint)
	segmented(origin + Vector2(36, 76), 118, hull, tint, 12, 9.0)
	text_at(origin + Vector2(160, 86), "%3d%%" % int(round(hull * 100.0)), 11, tint)

	# The two problems you can do something about, and whether the damage-control
	# party is free to do it. Only drawn while they are actually happening.
	var flooding: float = unit.flooding
	var burning := 0.0
	for system: ShipSystem in unit.systems.values():
		burning = maxf(burning, system.fire)
	var ready: bool = float(unit.dc_cooldown) <= 0.0
	var cluster := origin + Vector2(wide - 74, 0)
	if flooding > 0.01:
		glyph("drop", cluster + Vector2(0, 82), 12.0, GOLD)
		bar(cluster + Vector2(-6, 89), 12, flooding, GOLD, 2.0)
	if burning > 0.05:
		var flicker := 0.6 + 0.4 * sin(pulse * 9.0)
		glyph("flame", cluster + Vector2(20, 82), 12.0, Color(1.0, 0.42, 0.28, flicker))
		bar(cluster + Vector2(14, 89), 12, burning, RED, 2.0)
	if flooding > 0.01 or burning > 0.05 or not ready:
		text_at(cluster + Vector2(34, 86), "DC" if ready else "%d" % int(ceil(unit.dc_cooldown)),
			10, MINT if ready else DIM)

	draw_ship_profile(Rect2(origin + Vector2(13, 96), Vector2(wide - 26, 64)), unit, tint)

# --------------------------------------------------------------------------- #
# The designated contact
# --------------------------------------------------------------------------- #

func target_class(unit: Node3D) -> String:
	if unit is CombatHelicopter:
		return Lang.t("ROTARY WING · ATTACK")
	if unit is PatrolBoat:
		if unit.noncombatant:
			return Lang.t("MERCHANT HULL · UNARMED")
		return String(unit.loadout.designation).to_upper()
	return "UNKNOWN CONTACT"

func relative_bearing(from: Node3D, to: Node3D) -> float:
	## Degrees off our own bow, negative to port. Absolute bearings are for
	## navigation; "forty to starboard" is what you steer and shoot on.
	var flat := Vector2(to.position.x - from.position.x, to.position.z - from.position.z)
	if flat.length() < 0.001:
		return 0.0
	var ahead := Vector2(-sin(from.rotation.y), -cos(from.rotation.y))
	return rad_to_deg(atan2(flat.dot(Vector2(-ahead.y, ahead.x)), flat.dot(ahead)))

func fitted(unit: PatrolBoat, id: String) -> bool:
	## A module this class actually carries, as opposed to one stubbed in so
	## `operational()` has an answer.
	if not unit.systems.has(id):
		return false
	return float(unit.systems[id].maximum) > 1.0 and not (id in unit.offline_by_design)

func draw_ship_profile(area: Rect2, unit: PatrolBoat, tint: Color) -> void:
	## The contact drawn from abeam, with every fitted module in its own place.
	##
	## This was a plan view, and a plan view of a warship is a bad picture of
	## one: from above she is a pointed sliver and the only thing you can read
	## off her is port and starboard. From the side you get the shape a player
	## actually recognises — hull, bridge, mast, funnel aft — and the modules
	## land where the eye already expects them, because it is the same silhouette
	## being shot at out on the water.
	var modules: Dictionary = (ShipLayout.of(unit.loadout.hull_model) as Dictionary).get("modules", {})
	if modules.is_empty():
		return
	# Length comes from the hull boxes alone; height has to take in the mast, so
	# it comes from everything she actually carries.
	var fore: float = INF
	var aft: float = -INF
	var low: float = INF
	var high: float = -INF
	for id: String in modules:
		var row: Array = modules[id]
		var at: Vector3 = row[1]
		var box: Vector3 = row[2]
		if bool(row[4]):
			fore = minf(fore, at.z - box.z * 0.5)
			aft = maxf(aft, at.z + box.z * 0.5)
		elif not fitted(unit, id):
			continue
		low = minf(low, at.y - box.y * 0.5)
		high = maxf(high, at.y + box.y * 0.5)
	if aft - fore < 0.01 or high - low < 0.01:
		return
	# A little air above the masthead so the silhouette is not jammed to the top.
	high += (high - low) * 0.06
	var along: float = area.size.x / (aft - fore)
	var up: float = area.size.y / (high - low)
	var plot := func(z: float, y: float) -> Vector2:
		return area.position + Vector2((z - fore) * along, (high - y) * up)

	# --- hull, one band per compartment, shaded by what is left of it -------- #
	for id: String in ["bow", "mid", "stern"]:
		if not modules.has(id) or not unit.systems.has(id):
			continue
		var row: Array = modules[id]
		var at: Vector3 = row[1]
		var box: Vector3 = row[2]
		var head: float = at.z - box.z * 0.5
		var tail: float = at.z + box.z * 0.5
		var deck: float = at.y + box.y * 0.5
		var keel: float = at.y - box.y * 0.5
		var left: float = unit.systems[id].fraction()
		var shape := PackedVector2Array()
		if id == "bow":
			# Raked stem, so she has a bow rather than a brick.
			shape = PackedVector2Array([plot.call(head, deck), plot.call(tail, deck),
				plot.call(tail, keel), plot.call(head + box.z * 0.42, keel)])
		elif id == "stern":
			# Cut-up under the counter.
			shape = PackedVector2Array([plot.call(head, deck), plot.call(tail, deck),
				plot.call(tail, keel + box.y * 0.18), plot.call(head, keel)])
		else:
			shape = PackedVector2Array([plot.call(head, deck), plot.call(tail, deck),
				plot.call(tail, keel), plot.call(head, keel)])
		draw_colored_polygon(shape, Color(tint.r, tint.g, tint.b, 0.14 + 0.34 * left))
		var edge := shape.duplicate()
		edge.append(shape[0])
		# Drawn dark first and tinted over, which is what gives a flat vector
		# drawing its weight — the reference does the same thing.
		draw_polyline(edge, Color(0.02, 0.05, 0.06, 0.8), 1.8, true)
		draw_polyline(edge, Color(tint.r, tint.g, tint.b, 0.7), 1.0, true)

	# --- hull detail, in the manner of a drawn side elevation ---------------- #
	# Waterline, deck line, portholes, a boot-topping stripe and a guardrail on
	# the forecastle. None of it carries information: it is there so the
	# silhouette reads as a ship at a glance instead of as a bar chart of
	# coloured boxes, which is what tells the eye where to look for the mounts.
	var sea: Vector2 = plot.call(fore, 0.0)
	draw_line(Vector2(area.position.x, sea.y), Vector2(area.end.x, sea.y),
		Color(CYAN.r, CYAN.g, CYAN.b, 0.4), 1.0)
	var deck_y: float = plot.call(fore, hull_deck(modules)).y
	var ink := Color(0.02, 0.05, 0.06, 0.8)
	if sea.y - deck_y > 6.0:
		draw_line(Vector2(area.position.x + area.size.x * 0.08, deck_y),
			Vector2(area.end.x, deck_y), Color(tint.r, tint.g, tint.b, 0.45), 1.0)
		draw_line(Vector2(area.position.x + area.size.x * 0.12, sea.y - 2.0),
			Vector2(area.end.x, sea.y - 2.0), Color(ink.r, ink.g, ink.b, 0.5), 2.0)
		var port_y: float = deck_y + (sea.y - deck_y) * 0.4
		for index in range(9):
			var at: float = area.position.x + area.size.x * (0.24 + 0.072 * float(index))
			if at > area.end.x - 8.0:
				break
			draw_circle(Vector2(at, port_y), 1.1, Color(ink.r, ink.g, ink.b, 0.75))
		# Guardrail along the forecastle, where the reference has one.
		var rail_top := deck_y - 4.0
		draw_line(Vector2(area.position.x + area.size.x * 0.09, rail_top),
			Vector2(area.position.x + area.size.x * 0.25, rail_top),
			Color(tint.r, tint.g, tint.b, 0.5), 1.0)
		for index in range(4):
			var post: float = area.position.x + area.size.x * (0.09 + 0.053 * float(index))
			draw_line(Vector2(post, rail_top), Vector2(post, deck_y),
				Color(tint.r, tint.g, tint.b, 0.4), 1.0)

	# --- everything fitted above decks -------------------------------------- #
	for id: String in ShipLayout.MODULE_IDS:
		if not modules.has(id) or not fitted(unit, id):
			continue
		var row: Array = modules[id]
		if bool(row[4]):
			continue
		var at: Vector3 = row[1]
		var box: Vector3 = row[2]
		var corner: Vector2 = plot.call(at.z - box.z * 0.5, at.y + box.y * 0.5)
		var far: Vector2 = plot.call(at.z + box.z * 0.5, at.y - box.y * 0.5)
		var rect := Rect2(corner, Vector2(maxf(6.0, far.x - corner.x), maxf(5.0, far.y - corner.y)))
		var working: bool = unit.operational(id)
		var paint := Color(tint.r, tint.g, tint.b, 0.95) if working \
			else Color(DIM.r, DIM.g, DIM.b, 0.85)
		if not working:
			draw_rect(rect, Color(0.03, 0.05, 0.06, 0.96))
		module_icon(id, rect, paint, working)
		if not working:
			# Struck through. At this size the slash is the only thing that reads
			# as "gone" rather than merely "dim".
			draw_line(rect.position + Vector2(1.5, 1.5), rect.end - Vector2(1.5, 1.5),
				Color(DIM.r, DIM.g, DIM.b, 0.95), 1.2)
		if world.aimed_unit == unit and world.aimed_section == id:
			bracket(rect.get_center(), rect.size * 0.5 + Vector2(3.5, 3.5), INK, 3.5, 1.5)

func module_icon(id: String, rect: Rect2, paint: Color, filled: bool) -> void:
	## Each module drawn as the thing it is rather than as another rectangle.
	## Nine identical squares along a hull tell you how many there are and
	## nothing else; a barrel, a funnel and a dish are recognisable at 8 px and,
	## more to the point, are recognisable as *different from each other*, which
	## is the only question this readout exists to answer.
	var middle := rect.get_center()
	var half := rect.size * 0.5
	var body := func(shrink: Vector2) -> void:
		var box := Rect2(rect.position + shrink, rect.size - shrink * 2.0)
		if filled:
			draw_rect(box, paint)
			draw_rect(box, Color(0, 0, 0, 0.45), false, 1.0)
		else:
			draw_rect(box, paint, false, 1.2)
	match id:
		"gun", "aft_gun":
			# A turret is a low house with a barrel out of the front.
			var house := Rect2(rect.position + Vector2(0, half.y * 0.55),
				Vector2(rect.size.x * 0.72, rect.size.y * 0.72))
			if filled:
				draw_rect(house, paint)
			else:
				draw_rect(house, paint, false, 1.2)
			var barrel_y := middle.y + half.y * 0.1
			draw_line(Vector2(house.position.x + house.size.x * 0.4, barrel_y),
				Vector2(rect.end.x + 1.0, barrel_y - half.y * 0.35), paint, 1.8)
		"engine":
			# The funnel, raked aft, with exhaust off the top.
			draw_colored_polygon(PackedVector2Array([
				rect.position + Vector2(rect.size.x * 0.18, 0),
				rect.position + Vector2(rect.size.x, 0),
				rect.end, rect.position + Vector2(0, rect.size.y)]),
				paint if filled else Color(paint.r, paint.g, paint.b, 0.25))
			if not filled:
				draw_polyline(PackedVector2Array([
					rect.position + Vector2(rect.size.x * 0.18, 0),
					rect.position + Vector2(rect.size.x, 0),
					rect.end, rect.position + Vector2(0, rect.size.y),
					rect.position + Vector2(rect.size.x * 0.18, 0)]), paint, 1.2, true)
			for puff: float in [0.3, 0.62]:
				draw_circle(Vector2(rect.position.x + rect.size.x * puff,
					rect.position.y - 2.5), 1.4, Color(paint.r, paint.g, paint.b, 0.55))
		"bridge":
			# A deckhouse with a row of windows.
			body.call(Vector2.ZERO)
			var band := rect.position.y + rect.size.y * 0.3
			for slot in range(3):
				var at := rect.position.x + rect.size.x * (0.2 + 0.28 * float(slot))
				draw_rect(Rect2(Vector2(at, band), Vector2(maxf(1.5, rect.size.x * 0.13), 2.0)),
					Color(0.03, 0.06, 0.08, 0.9) if filled else paint)
		"radar":
			# Mast with a dish turning on it.
			draw_line(Vector2(middle.x, rect.end.y), Vector2(middle.x, rect.position.y + half.y * 0.5),
				paint, 1.6)
			# Screen y grows downward, so a dish facing the sky is the *upper*
			# half of the circle. Sweeping the lower half drew a bowl catching
			# rain, which is a fair description of the wrong thing.
			draw_arc(Vector2(middle.x, rect.position.y + half.y * 0.6),
				maxf(3.0, half.x * 0.85), PI * 1.12, PI * 1.88, 14, paint, 1.8, true)
		"launcher_port", "launcher_starboard":
			# A cell block: lids in a row, which is what a VLS looks like.
			body.call(Vector2(0, rect.size.y * 0.2))
			for slot in range(2):
				var at := rect.position.x + rect.size.x * (0.22 + 0.4 * float(slot))
				draw_line(Vector2(at, rect.position.y + rect.size.y * 0.28),
					Vector2(at, rect.end.y - rect.size.y * 0.22),
					Color(0.03, 0.06, 0.08, 0.9) if filled else paint, 1.4)
		"ciws":
			# The radome and its gun: a dome on a stalk.
			draw_line(Vector2(middle.x, rect.end.y), Vector2(middle.x, middle.y), paint, 1.6)
			draw_arc(Vector2(middle.x, middle.y - half.y * 0.1), maxf(2.6, half.x * 0.62),
				PI, TAU, 12, paint, 2.0, true)
			draw_line(Vector2(middle.x, middle.y - half.y * 0.1),
				Vector2(middle.x + half.x * 0.9, rect.position.y), paint, 1.4)
		"sam":
			# A canted box launcher with a round in it.
			body.call(Vector2(0, rect.size.y * 0.24))
			glyph("missile", Vector2(middle.x, middle.y - 1.0),
				maxf(7.0, rect.size.y * 1.1), paint, filled)
		"rudder":
			# A blade under the counter.
			draw_colored_polygon(PackedVector2Array([
				rect.position + Vector2(rect.size.x * 0.3, 0),
				rect.position + Vector2(rect.size.x, 0),
				rect.position + Vector2(rect.size.x * 0.7, rect.size.y)]),
				paint if filled else Color(paint.r, paint.g, paint.b, 0.3))
		_:
			body.call(Vector2.ZERO)

func hull_deck(modules: Dictionary) -> float:
	## Height of the main deck: the top of the midships hull box.
	if not modules.has("mid"):
		return 0.0
	var row: Array = modules["mid"]
	return (row[1] as Vector3).y + (row[2] as Vector3).y * 0.5

func draw_air_schematic(area: Rect2, unit: CombatHelicopter, tint: Color) -> void:
	## Aircraft have no module boxes to draw, so this is a silhouette and the two
	## numbers that decide an air engagement: how high, and how many flares.
	var centre := area.position + Vector2(area.size.y * 0.7, area.size.y * 0.5)
	var reach: float = area.size.y * 0.42
	draw_arc(centre, reach, 0, TAU, 28, Color(tint.r, tint.g, tint.b, 0.35), 1.2, true)
	draw_line(centre - Vector2(reach, 0), centre + Vector2(reach, 0), Color(tint.r, tint.g, tint.b, 0.9), 1.8)
	draw_line(centre - Vector2(0, reach), centre + Vector2(0, reach), Color(tint.r, tint.g, tint.b, 0.9), 1.8)
	draw_rect(Rect2(centre - Vector2(reach * 0.55, 4), Vector2(reach * 1.3, 8)),
		Color(tint.r, tint.g, tint.b, 0.85))
	var text := area.position + Vector2(area.size.y * 1.5, area.size.y * 0.42)
	text_at(text, "ALTITUDE %d m" % int(maxf(0.0, unit.position.y)), 10, MUTED)
	text_at(text + Vector2(0, 15), "%d flare packs" % unit.flare_packs, 10, MUTED)

func draw_target() -> void:
	## What is designated, what is left of it, and what is still working. Until
	## now the only statement of the designated contact was a bracket out in the
	## world, which leaves the screen the moment the camera turns — so the answer
	## to "what am I shooting at" could be nowhere on the display at all.
	# Never bind a freed node to a typed local — the assignment itself throws,
	# which aborts _draw and takes the rest of the overlay with it. A target that
	# is despawned rather than sunk (the campaign does exactly that to Carney)
	# reaches this line freed.
	var unit: Node3D = null
	if is_instance_valid(world.locked_target):
		unit = world.locked_target
	var live: bool = unit != null and not unit.sunk
	panel(target_rect, GOLD if live else DIM)
	var origin := target_rect.position
	var wide := target_rect.size.x
	tracked(origin + Vector2(15, 19), Lang.t("TARGET"), 9, GOLD if live else DIM, 2.4)
	if not live:
		text_at(origin + Vector2(15, 44), Lang.t("NO CONTACT DESIGNATED"), 11, DIM)
		text_at(origin + Vector2(15, 62), Lang.t("T · designate nearest"), 9, DIM)
		return

	var tint := contact_tint(unit, RED)
	tracked(origin + Vector2(15, 42), unit.callsign, 14, INK, 1.6)
	text_at(origin + Vector2(15, 57), target_class(unit), 9, MUTED)

	var anchor: Node3D = world.selected
	if is_instance_valid(anchor):
		var span: float = Vector2(unit.position.x - anchor.position.x,
			unit.position.z - anchor.position.z).length()
		var figure := "%d m" % int(span)
		var figure_wide := font.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, origin + Vector2(wide - 15 - figure_wide, 43), figure,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
		var off := relative_bearing(anchor, unit)
		var bearing := "%s %02d°" % ["STBD" if off >= 0.0 else "PORT", int(round(absf(off)))]
		var bearing_wide := font.get_string_size(bearing, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		text_at(origin + Vector2(wide - 15 - bearing_wide, 58), bearing, 9, MUTED)
		# Which weapon actually reaches it. Firing into empty sea because the
		# contact was 200 m outside gun range is a mistake the HUD can prevent.
		var envelope := Lang.t("OUT OF RANGE")
		var envelope_tint := DIM
		var reach: float = 640.0 if anchor is CombatHelicopter else anchor.loadout.gun_range
		if world.target_masked:
			# Terrain between us. Worth its own word rather than being folded
			# into "out of range": it is the state the player can do something
			# about by moving, and the state they can put their own hull into on
			# purpose when a vampire is inbound.
			envelope = Lang.t("MASKED")
			envelope_tint = GOLD
		elif span <= reach:
			envelope = Lang.t("GUNS")
			envelope_tint = MINT
		elif not (anchor is CombatHelicopter) and world.cleared("missile") \
				and span <= anchor.loadout.missile_range:
			envelope = Lang.t("ASM")
			envelope_tint = CYAN
		var envelope_wide := tracked_width(envelope, 9, 1.6)
		tracked(origin + Vector2(wide - 15 - envelope_wide, 79), envelope, 9, envelope_tint, 1.6)

	var health: float = unit.health / unit.maximum_health if unit is CombatHelicopter \
		else unit.hull_fraction()
	bar(origin + Vector2(15, 74), 150, health, tint, 5.0)
	text_at(origin + Vector2(171, 80), "%d%%" % int(round(health * 100.0)), 9, tint)

	var plate := Rect2(origin + Vector2(13, 90), Vector2(wide - 26, 60))
	if unit is CombatHelicopter:
		draw_air_schematic(plate, unit, tint)
		return
	if not (unit is PatrolBoat):
		return
	draw_ship_profile(plate, unit, tint)
	# What the shell under the pointer would actually cost her. This is the whole
	# argument for aiming at a module rather than at the ship, and it was only
	# ever stated in the SYSTEMS panel, which nobody has open during a fight.
	var caption := ""
	var caption_tint := DIM
	if world.aimed_unit == unit and world.aimed_section != "" \
			and unit.systems.has(world.aimed_section):
		var id: String = world.aimed_section
		if unit.operational(id):
			caption = "%s — %s" % [Lang.t(String(unit.systems[id].label)).to_upper(),
				String(EFFECTS.get(id, ""))]
			caption_tint = GOLD
		else:
			caption = "%s — already gone" % Lang.t(String(unit.systems[id].label)).to_upper()
	if caption != "":
		draw_string(font, origin + Vector2(15, target_rect.size.y - 10), caption,
			HORIZONTAL_ALIGNMENT_LEFT, wide - 30, 9, caption_tint)

func draw_weapons() -> void:
	var unit: Node3D = world.selected
	if not is_instance_valid(unit):
		return
	panel(weapon_rect, GOLD)
	var origin := weapon_rect.position
	if unit is CombatHelicopter:
		var air_labels := ["CANNON", "ROCKETS", "AIR-TO-AIR · X"]
		var air_glyphs := ["shell", "rocket", "missile"]
		for i in range(3):
			glyph(air_glyphs[i], origin + Vector2(24 + i * 128, 20), 13.0, MUTED)
			text_at(origin + Vector2(34 + i * 128, 24), air_labels[i], 9, MUTED)
		segmented(origin + Vector2(18, 32), 106, float(unit.cannon_rounds) / 120.0, CYAN, 12)
		segmented(origin + Vector2(146, 32), 106, float(unit.rockets) / 8.0, GOLD, 8)
		icon_row(origin + Vector2(280, 38), unit.air_missiles, 2, CYAN, "missile")
		text_at(origin + Vector2(18, 62), "LMB fire · X air-to-air · Space/Shift altitude · Z flares", 9, DIM)
		return
	# A weapon the mission has not cleared reads as held, not as ready: the
	# label goes amber, the count is replaced by HOLD, and the icons grey out.
	# Refusing a keypress with nothing on screen to explain it reads as a bug.
	var asm_free: bool = world.cleared("missile")
	var gun_free: bool = world.cleared("gun")
	var labels := ["GUNS · LMB", "ASM · X" if asm_free else "ASM · HOLD", "CIWS", "SAM"]
	var glyphs := ["shell", "missile", "burst", "missile"]
	for i in range(4):
		var held: bool = (i == 0 and not gun_free) or (i == 1 and not asm_free)
		glyph(glyphs[i], origin + Vector2(24 + i * 96, 20), 13.0, GOLD if held else MUTED)
		text_at(origin + Vector2(34 + i * 96, 24), labels[i], 9, GOLD if held else MUTED)
	dial(origin + Vector2(30, 46), 10, unit.gun_ready(), MINT)
	glyph("shell", origin + Vector2(30, 46), 9.0, MINT if unit.gun_ready() >= 1.0 else DIM)
	dial(origin + Vector2(58, 46), 10, unit.gun_ready(true) if unit.operational("aft_gun") else 0.0, MINT)
	glyph("shell", origin + Vector2(58, 46), 9.0, MINT if unit.gun_ready(true) >= 1.0 and unit.operational("aft_gun") else DIM)
	var cells: int = 2 if unit.loadout.length < 40 else 4
	if asm_free:
		icon_row(origin + Vector2(120, 42), unit.usable_missiles(), cells, MINT, "missile")
		bar(origin + Vector2(114, 54), 70, 1.0 - unit.missile_cooldown / unit.missile_reload_time(), GOLD, 3.0)
	else:
		icon_row(origin + Vector2(120, 42), 0, cells, DIM, "missile")
		text_at(origin + Vector2(114, 60), "WEAPONS HOLD", 9, GOLD)
	var ciws_tint := GOLD if unit.ciws_status == "INTERCEPTING" else (MINT if unit.ciws_enabled else DIM)
	segmented(origin + Vector2(210, 38), 74, float(unit.ciws_ammo) / unit.loadout.ciws_rounds if unit.operational("ciws") else 0.0, ciws_tint, 10)
	text_at(origin + Vector2(210, 62), unit.ciws_status, 9, DIM)
	icon_row(origin + Vector2(312, 42), unit.sam_ammo if unit.operational("sam") else 0, 4, CYAN, "missile")
	text_at(origin + Vector2(306, 62), unit.sam_status, 9, DIM)

## How far the map reaches. 2400 m covered every spawn, which sounds like a
## virtue and is not: gun range is 600 m and missiles reach 1400, so every fight
## the player was actually in happened inside the middle third of the display
## while the outer two thirds showed empty sea. Anything further out still gets
## a rim arrow saying which way it is.
const RADAR_RANGE: float = 1800.0

func radar_frame() -> Array:
	## Screen-aligned basis for the radar, so up on the map is forward on screen.
	var camera: Camera3D = world.camera
	var right := Vector2(camera.basis.x.x, camera.basis.x.z)
	var ahead := Vector2(-camera.basis.z.x, -camera.basis.z.z)
	if right.length() < 0.001:
		right = Vector2(1, 0)
	if ahead.length() < 0.001:
		ahead = Vector2(0, 1)
	return [right.normalized(), ahead.normalized()]

func radar_offset(point: Vector3, anchor: Vector3, frame: Array, factor: float) -> Vector2:
	var offset := Vector2(point.x - anchor.x, point.z - anchor.z)
	return Vector2(offset.dot(frame[0]), -offset.dot(frame[1])) * factor

func map_mark(at: Vector2, unit: Node3D, color: Color, frame: Array) -> void:
	## One contact on the map. Class is carried by shape, not by colour alone —
	## six identical red dots is what made the old display read as chaos. Ships
	## also point where their bow points, so you can see who is turning in.
	if unit is CombatHelicopter:
		draw_arc(at, 7.5, 0, TAU, 18, Color(color.r, color.g, color.b, 0.45), 1.2, true)
		draw_line(at - Vector2(7, 0), at + Vector2(7, 0), color, 2.0)
		draw_line(at - Vector2(0, 7), at + Vector2(0, 7), color, 2.0)
		return
	var heading := Vector2(-sin(unit.rotation.y), -cos(unit.rotation.y))
	var ahead := Vector2(heading.dot(frame[0]), -heading.dot(frame[1]))
	ahead = ahead.normalized() if ahead.length() > 0.001 else Vector2(0, -1)
	var side := Vector2(-ahead.y, ahead.x)
	if unit is PatrolBoat and unit.noncombatant:
		# A merchant is a box, not an arrowhead. An unarmed hull should not look
		# like a threat bearing down on you.
		var box := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			box.append(at + ahead * corner.y * 8.5 + side * corner.x * 4.6)
		box.append(box[0])
		draw_colored_polygon(box, Color(color.r, color.g, color.b, 0.25))
		draw_polyline(box, color, 1.4, true)
		return
	var capital: bool = unit is PatrolBoat and unit.loadout.length >= 40.0
	var nose: float = 11.0 if capital else 7.2
	var beam: float = 5.4 if capital else 3.9
	var hull := PackedVector2Array([at + ahead * nose,
		at + side * beam - ahead * nose * 0.2,
		at - ahead * nose * 0.8 + side * beam * 0.75,
		at - ahead * nose * 0.8 - side * beam * 0.75,
		at - side * beam - ahead * nose * 0.2])
	draw_colored_polygon(hull, color)
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, Color(0, 0, 0, 0.45), 1.0, true)
	if capital:
		# A corvette is worth telling apart from a patrol boat at a glance.
		draw_arc(at, 13.0, 0, TAU, 20, Color(color.r, color.g, color.b, 0.30), 1.0, true)

func map_lock(at: Vector2) -> void:
	## The designated contact, marked on the map as well as in the world. Which
	## of four red marks you are about to shoot at was previously unanswerable
	## from the map alone.
	var beat: float = 0.55 + 0.45 * sin(pulse * 5.0)
	draw_arc(at, 14.0, 0, TAU, 24, Color(GOLD.r, GOLD.g, GOLD.b, 0.30 + 0.4 * beat), 1.4, true)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var origin := at + corner * 14.0
		draw_line(origin, origin - Vector2(5.0 * corner.x, 0), GOLD, 1.7)
		draw_line(origin, origin - Vector2(0, 5.0 * corner.y), GOLD, 1.7)

func draw_minimap() -> void:
	panel(minimap_rect, CYAN, true)
	var centre := minimap_rect.position + minimap_rect.size * 0.5
	var radius := minimap_rect.size.x * 0.5 - 18.0
	var factor := radius / RADAR_RANGE
	var anchor: Vector3 = world.selected.position if is_instance_valid(world.selected) else Vector3.ZERO
	var frame := radar_frame()

	draw_circle(centre, radius, Color(0.02, 0.06, 0.08, 0.66))
	# Two rings and eight rim ticks. Three labelled rings, a full crosshair, a
	# needle in the corner and a caption in the other one added up to more
	# furniture than contacts, which is the whole complaint about this display.
	for step: float in [0.5, 1.0]:
		draw_arc(centre, radius * step, 0, TAU, 64, Color(CYAN.r, CYAN.g, CYAN.b, 0.15), 1.0, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var ray := Vector2(cos(angle), sin(angle))
		var cardinal: bool = index % 2 == 0
		draw_line(centre + ray * (radius - (8.0 if cardinal else 4.0)), centre + ray * radius,
			Color(CYAN.r, CYAN.g, CYAN.b, 0.26 if cardinal else 0.13), 1.0)
	# The wedge the camera is actually showing, drawn as two edges and the
	# faintest wash between them. As a solid fill it was the loudest thing on the
	# display, which is backwards — it is context, not a contact.
	var spread := deg_to_rad(world.camera.fov * 0.5)
	var left := centre + Vector2(sin(-spread), -cos(spread)) * radius * 0.94
	var right_edge := centre + Vector2(sin(spread), -cos(spread)) * radius * 0.94
	draw_colored_polygon(PackedVector2Array([centre, left, right_edge]),
		Color(INK.r, INK.g, INK.b, 0.028))
	draw_line(centre, left, Color(INK.r, INK.g, INK.b, 0.10), 1.0)
	draw_line(centre, right_edge, Color(INK.r, INK.g, INK.b, 0.10), 1.0)
	# Scale, low and just off the six o'clock spoke. Dead astern is the quietest
	# part of the display, but the spoke itself already carries a rim tick, and a
	# figure with a tick struck through it is worse than no figure.
	var scale_ray := Vector2(cos(deg_to_rad(104.0)), sin(deg_to_rad(104.0)))
	for entry: Array in [[0.5, "%.1f" % (RADAR_RANGE * 0.5 / 1000.0)],
			[1.0, "%.1f km" % (RADAR_RANGE / 1000.0)]]:
		var caption := String(entry[1])
		var caption_wide := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var at := centre + scale_ray * (radius * float(entry[0]) - 7.0)
		draw_string(font, at - Vector2(caption_wide * 0.5, 0), caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(CYAN.r, CYAN.g, CYAN.b, 0.42))

	for island: Dictionary in world.islands:
		var point: Vector3 = island["position"]
		var at := centre + radar_offset(point, anchor, frame, factor)
		if at.distance_to(centre) > radius + float(island["radius"]) * factor:
			continue
		draw_circle(at, maxf(2.5, float(island["radius"]) * factor), Color("35604f"))

	for crate in get_tree().get_nodes_in_group("supply"):
		var at := centre + radar_offset(crate.position, anchor, frame, factor)
		if at.distance_to(centre) > radius:
			continue
		var tint: Color = SupplyCrate.REPAIR_GREEN if crate.kind == SupplyCrate.REPAIR \
			else SupplyCrate.ORDNANCE_ORANGE
		# A cross, so a crate never reads as a contact.
		draw_line(at - Vector2(4, 0), at + Vector2(4, 0), tint, 1.8)
		draw_line(at - Vector2(0, 4), at + Vector2(0, 4), tint, 1.8)

	# Inbound missiles get their own mark, with a tail showing where it is going:
	# the thing most worth reacting to, and the direction is the reaction.
	for missile in get_tree().get_nodes_in_group("guided_missiles"):
		if missile.detonated or not is_instance_valid(missile.source) or missile.source.team == 0:
			continue
		var at := centre + radar_offset(missile.position, anchor, frame, factor)
		if at.distance_to(centre) > radius:
			continue
		var throb: float = 0.55 + 0.45 * sin(pulse * 11.0)
		var run := Vector2(missile.velocity.x, missile.velocity.z)
		if run.length() > 0.5:
			var screen_run := Vector2(run.dot(frame[0]), -run.dot(frame[1])).normalized()
			draw_line(at - screen_run * 11.0, at, Color(1.0, 0.32, 0.26, throb * 0.5), 1.4)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(4, 0),
			at + Vector2(0, 5), at + Vector2(-4, 0)]), Color(1.0, 0.32, 0.26, throb))

	for unit in world.all_units():
		if unit.sunk:
			continue
		var local := radar_offset(unit.position, anchor, frame, factor)
		var beyond := local.length() > radius
		if beyond:
			local = local.normalized() * radius
		var color := contact_tint(unit, (CYAN if unit is CombatHelicopter else MINT) if unit.team == 0 else RED)
		var at := centre + local
		if beyond:
			# On the rim, pointing out: it is over there, further than the map goes.
			var facing := local.normalized()
			var side := Vector2(-facing.y, facing.x)
			draw_colored_polygon(PackedVector2Array([at + facing * 4.0, at - facing * 4.0 + side * 3.6,
				at - facing * 4.0 - side * 3.6]), Color(color.r, color.g, color.b, 0.8))
			if unit == world.locked_target:
				draw_arc(at, 7.5, 0, TAU, 14, GOLD, 1.4, true)
			continue
		if unit == world.selected:
			map_mark(at, unit, INK, frame)
			# Our own course, drawn ahead of us: the one line on this display
			# worth having, because everything else is relative to it.
			var heading := Vector2(-sin(unit.rotation.y), -cos(unit.rotation.y))
			var course := Vector2(heading.dot(frame[0]), -heading.dot(frame[1])).normalized()
			draw_line(at + course * 13.0, at + course * 30.0, Color(INK.r, INK.g, INK.b, 0.30), 1.3)
			continue
		map_mark(at, unit, color, frame)
		if unit == world.locked_target:
			map_lock(at)

	# North, as a letter on the rim rather than a needle in a corner.
	var north := Vector2(Vector2(0, -1).dot(frame[0]), -Vector2(0, -1).dot(frame[1])).normalized()
	var letter := centre + north * (radius - 10.0)
	text_at(letter - Vector2(3, -4), "N", 9, MUTED)

func draw_feed() -> void:
	var origin := Vector2(mission_rect.position.x + 6, mission_rect.end.y + 22)
	for index in range(mini(world.events.size(), 3)):
		var age: float = world.elapsed - (world.notice_until - 3.0) + index * 1.1
		var alpha: float = clampf(1.4 - age * 0.28, 0.0, 1.0) * (1.0 - index * 0.28)
		if alpha <= 0.02:
			continue
		var tint := INK if index == 0 else MUTED
		draw_line(origin + Vector2(0, index * 17 - 4), origin + Vector2(0, index * 17 + 2),
			Color(MINT.r, MINT.g, MINT.b, alpha))
		draw_string(font, origin + Vector2(9, index * 17), world.events[index],
			HORIZONTAL_ALIGNMENT_LEFT, 380, 11, Color(tint.r, tint.g, tint.b, alpha))

func draw_details() -> void:
	var unit: Node3D = world.selected
	if not is_instance_valid(unit):
		return
	panel(details_rect, CYAN, true)
	var origin := details_rect.position
	if unit is CombatHelicopter:
		tracked(origin + Vector2(20, 32), "GUNSHIP CONTROLS", 14, CYAN, 2.0)
		var lines := [
			"FLIGHT   W/S forward and back · A/D turn",
			"HEIGHT   Space climb · Shift descend",
			"WEAPONS  LMB rockets or cannon · X guided missile",
			"DEFENCE  Z flares · T next contact · Tab back to the ship"]
		for index in range(lines.size()):
			text_at(origin + Vector2(20, 66 + index * 26), lines[index], 12)
		return
	tracked(origin + Vector2(20, 32), "DAMAGE CONTROL", 14, CYAN, 2.0)
	text_at(origin + Vector2(details_rect.size.x - 186, 32), "condition · what losing it costs", 10, DIM)
	var index := 0
	for id: String in unit.systems:
		var system: ShipSystem = unit.systems[id]
		if system.maximum <= 1:
			continue
		var at := origin + Vector2(22 + (index % 3) * 228, 62 + (index / 3) * 52)
		var fraction := system.fraction()
		var color := MINT if fraction > 0.5 else GOLD
		if not system.working():
			color = RED
		text_at(at, system.label, 10, color if fraction < 1.0 else MUTED)
		segmented(at + Vector2(0, 8), 172, fraction, color, 10, 5.0)
		text_at(at + Vector2(0, 26), String(EFFECTS.get(id, "")), 9, DIM if system.working() else RED)
		if system.fire > 0.12:
			var flicker := 0.55 + 0.45 * sin(pulse * 9.0 + index)
			glyph("flame", at + Vector2(180, -3), 13.0, Color(1.0, 0.55, 0.25, flicker))
		index += 1
	text_at(origin + Vector2(22, details_rect.size.y - 16),
		"W/S throttle · A/D helm · LMB guns · X missile · C damage control · I CIWS · Tab helicopter", 10, DIM)

## The controls, grouped the way a player looks for them. Pause is the one
## moment there is room to state all of this, so it is stated there in full
## rather than left to a panel nobody opens mid-fight.
const SHIP_KEYS: Array[Array] = [
	["W · S", "ahead and astern"],
	["A · D", "helm"],
	["LMB", "fire the guns at the pointer"],
	["X", "anti-ship missile at the designated contact"],
	["T", "designate the next contact, nearest first"],
	["TAB", "take the other set of controls"],
]
const AIR_KEYS: Array[Array] = [
	["W · S", "forward and back"],
	["A · D", "turn"],
	["SPACE · SHIFT", "climb and descend"],
	["LMB", "rockets, or cannon when they are gone"],
	["X", "air-to-air missile"],
	["Z", "flares"],
	["TAB", "back to the ship"],
]
const GENERAL_KEYS: Array[Array] = [
	["MMB", "orbit the camera · Shift to slide it"],
	["ESC · P", "pause"],
	["R", "restart the level"],
	["SYSTEMS", "full damage readout"],
]

func draw_pause() -> void:
	var air: bool = world.selected is CombatHelicopter
	var rows: Array[Array] = (AIR_KEYS if air else SHIP_KEYS) + GENERAL_KEYS
	var wide := 400.0
	var tall := 92.0 + float(rows.size()) * 19.0
	var origin := Vector2((size.x - wide) * 0.5, (size.y - tall) * 0.5 - 30.0)
	panel(Rect2(origin, Vector2(wide, tall)), MINT, true)
	tracked(origin + Vector2(28, 40), Lang.t("PAUSED"), 20, INK, 3.0)
	var heading := Lang.t("GUNSHIP CONTROLS") if air else Lang.t("SHIP CONTROLS")
	var heading_wide := tracked_width(heading, 9, 2.2)
	tracked(origin + Vector2(wide - 28 - heading_wide, 38), heading, 9, MINT, 2.2)
	draw_line(origin + Vector2(28, 54), origin + Vector2(wide - 28, 54), LINE, 1.0)
	# One column for the keys and one for what they do. Starting each description
	# after its own key cap leaves the second column ragged, and a ragged list of
	# nine things is read as nine things rather than as one list.
	var column := 0.0
	for row: Array in rows:
		column = maxf(column, tracked_width(String(row[0]), 9, 1.4) + 12.0)
	for index in range(rows.size()):
		var row: Array = rows[index]
		var line := origin + Vector2(28, 76 + index * 19)
		# A key cap, so the thing to press reads as a thing to press.
		var key := String(row[0])
		var key_wide := tracked_width(key, 9, 1.4) + 12.0
		var cap := Rect2(line + Vector2(0, -10), Vector2(key_wide, 14))
		draw_rect(cap, TRACK)
		draw_rect(cap, Color(MINT.r, MINT.g, MINT.b, 0.35), false, 1.0)
		tracked(line + Vector2(6, 0), key, 9, INK, 1.4)
		text_at(line + Vector2(column + 14, 0), Lang.t(String(row[1])), 10, MUTED)

# --------------------------------------------------------------------------- #
# Combat feedback
# --------------------------------------------------------------------------- #

func draw_ui_pointer(at: Vector2) -> void:
	## Over a panel there is no reticle, and the system cursor is hidden while
	## the game is being played, so the HUD draws its own arrow — otherwise the
	## toolbar turns into a guessing game.
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		return
	var arrow := PackedVector2Array([at, at + Vector2(0, 16),
		at + Vector2(4.4, 11.8), at + Vector2(7.6, 17.8), at + Vector2(10.8, 16.0),
		at + Vector2(7.6, 10.2), at + Vector2(12.6, 9.2)])
	# White body, dark edge. A dark arrow outlined in pale grey vanished against
	# every panel it was for, which is the only place it is ever drawn.
	var shadow := arrow.duplicate()
	for index in range(shadow.size()):
		shadow[index] += Vector2(1.5, 1.5)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.5))
	draw_colored_polygon(arrow, Color(0.98, 0.99, 1.0, 1.0))
	var outline := arrow.duplicate()
	outline.append(arrow[0])
	draw_polyline(outline, Color(0.03, 0.05, 0.06, 0.95), 1.4, true)

func draw_reticle() -> void:
	var pointer := get_global_mouse_position()
	if not is_instance_valid(world.selected) or blocks_pointer(pointer):
		draw_ui_pointer(pointer)
		return
	var air := world.selected is CombatHelicopter
	var reach: float = 640.0 if air else world.selected.loadout.gun_range
	var in_range: bool = world.selected.position.distance_to(world.mouse_on_sea()) < reach
	# Not mint. The in-range reticle used to be the same blue-green as the sea it
	# is drawn on, which is close to invisible and worse than invisible for
	# anyone who does not separate those hues easily. A warm near-white against
	# blue water is the one colour nothing else on this screen is, and everything
	# is laid down over a dark copy of itself so it survives sun glare and foam.
	var color := SIGHT if in_range else SIGHT_COLD
	var shadow := Color(0.02, 0.03, 0.04, 0.75)
	draw_arc(pointer, 9, 0, TAU, 28, shadow, 3.2, true)
	draw_arc(pointer, 9, 0, TAU, 28, Color(color.r, color.g, color.b, 0.95), 1.6, true)
	for corner: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_line(pointer + corner * 13, pointer + corner * 20, shadow, 3.4)
		draw_line(pointer + corner * 13, pointer + corner * 20, color, 1.7)
	draw_circle(pointer, 2.4, shadow)
	draw_circle(pointer, 1.5, color)
	if hit_flash <= 0.0:
		return
	# Hit confirmation: four ticks that snap outward and fade.
	var tint := Color(1.0, 0.5, 0.24) if hit_kill else Color(1.0, 1.0, 1.0)
	var strength := clampf(hit_flash, 0.0, 1.0)
	tint.a = strength
	var punch: float = 1.0 - clampf(hit_flash / 1.35, 0.0, 1.0)
	var spread: float = 11.0 + punch * 16.0
	var length: float = 12.0 + punch * 8.0
	var weight: float = (3.4 if hit_kill else 2.6) * (0.5 + strength * 0.5)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var from := pointer + corner * spread
		var to := pointer + corner * (spread + length)
		draw_line(from, to, Color(0, 0, 0, strength * 0.4), weight + 2.0)
		draw_line(from, to, tint, weight)
	if hit_kill:
		draw_arc(pointer, 7.0 + punch * 22.0, 0, TAU, 28, Color(tint.r, tint.g, tint.b, strength * 0.6), 2.0, true)

func draw_damage_numbers() -> void:
	var camera: Camera3D = world.camera
	for entry: Dictionary in numbers:
		var point: Vector3 = entry["point"]
		if camera.is_position_behind(point):
			continue
		var age: float = entry["age"]
		var drift: Vector2 = entry["drift"]
		var screen := camera.unproject_position(point) + Vector2(0, -age * 34.0) + drift * age
		var alpha := clampf(1.0 - age / 1.5, 0.0, 1.0)
		var critical: bool = entry["critical"]
		var tint := Color(1.0, 0.62, 0.32, alpha) if critical else Color(1.0, 0.95, 0.85, alpha)
		var amount := float(entry["amount"])
		var label := "%d" % int(round(amount))
		var scale: int = 20 if critical else int(clampf(12.0 + amount * 0.09, 12.0, 19.0))
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, scale).x
		draw_string(font, screen - Vector2(width * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, scale,
			Color(0, 0, 0, alpha * 0.5))
		draw_string(font, screen - Vector2(width * 0.5 + 1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, scale, tint)

func edge_arrow(target: Vector3, color: Color, glyph: String, always: bool) -> void:
	## Points at anything worth knowing about that is not currently on screen.
	var camera: Camera3D = world.camera
	# Keep the arrows out of the right-hand column. They are pinned to the edge
	# of their frame, and with the map at its old size that edge fell just short
	# of it; at the size it is now the arrows and their range labels were landing
	# on top of the contacts they were pointing at.
	var right: float = minf(size.x - 96.0, minimap_rect.position.x - 28.0)
	var frame := Rect2(96, 132, maxf(240.0, right - 96.0), size.y - 288)
	var middle := frame.position + frame.size * 0.5
	var half := frame.size * 0.5
	var behind := camera.is_position_behind(target)
	var screen := camera.unproject_position(target)
	if behind:
		screen = middle - (screen - middle)
	var offset := screen - middle
	if offset.length() < 1.0:
		offset = Vector2(0, -1)
	var reach: float = minf(half.x / maxf(absf(offset.x), 0.001), half.y / maxf(absf(offset.y), 0.001))
	if not behind and reach >= 1.0:
		if not always:
			return
		reach = 1.0
	var at := middle + offset * minf(reach, 1.0)
	var facing := offset.normalized()
	var side := Vector2(-facing.y, facing.x)
	draw_colored_polygon(PackedVector2Array([at + facing * 15.0, at - facing * 8.0 + side * 9.5,
		at - facing * 8.0 - side * 9.5]), color)
	draw_polyline(PackedVector2Array([at + facing * 15.0, at - facing * 8.0 + side * 9.5,
		at - facing * 8.0 - side * 9.5, at + facing * 15.0]), Color(0, 0, 0, 0.35), 1.0)
	var distance := 0.0
	if is_instance_valid(world.selected):
		distance = world.selected.position.distance_to(target)
	var label := "%s · %d m" % [glyph, int(distance)]
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var caption := at - facing * 27.0 - Vector2(width * 0.5, -4)
	caption.x = clampf(caption.x, 12.0, frame.end.x - width)
	# Four contacts on much the same bearing printed four ranges in the same
	# place, which came out as one unreadable smear. The arrow still goes down —
	# it is the direction that matters — but only the first caption on that
	# patch of screen is drawn.
	var box := Rect2(caption + Vector2(0, -11), Vector2(width, 15))
	for taken: Rect2 in arrow_labels:
		if taken.intersects(box):
			return
	arrow_labels.append(box)
	draw_string(font, caption + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.45))
	draw_string(font, caption, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)

func contact_tint(unit: Node3D, base: Color) -> Color:
	## Dim means "disarmed, ignore it". A merchant is not armed in the first
	## place, so dimming her reads as already dealt with — she gets caution
	## amber instead.
	if unit is PatrolBoat and unit.noncombatant:
		return GOLD
	return base if unit.is_combat_capable() else DIM

func draw_offscreen_contacts() -> void:
	arrow_labels.clear()
	# The designated contact goes down first and in its own colour. It is the one
	# whose bearing the player is actually steering on, so it must not be the
	# arrow whose range figure loses the tie with a contact behind it.
	var ordered: Array[Node3D] = []
	if is_instance_valid(world.locked_target):
		ordered.append(world.locked_target)
	for unit in world.all_units():
		if unit != world.locked_target:
			ordered.append(unit)
	for unit in ordered:
		if unit.team != 1 or unit.sunk:
			continue
		var color := GOLD if unit == world.locked_target else contact_tint(unit, RED)
		edge_arrow(unit.position + Vector3.UP * 8.0, color,
			"AIR" if unit is CombatHelicopter else "SHIP", false)
	for crate in get_tree().get_nodes_in_group("supply"):
		var tint: Color = SupplyCrate.REPAIR_GREEN if crate.kind == SupplyCrate.REPAIR \
			else SupplyCrate.ORDNANCE_ORANGE
		edge_arrow(crate.position + Vector3.UP * 6.0, Color(tint.r, tint.g, tint.b, 0.8),
			"REPAIR" if crate.kind == SupplyCrate.REPAIR else "AMMO", false)

func draw_pickup() -> void:
	if pickup_age > 2.4 or pickup_text == "":
		return
	var alpha := clampf(minf(pickup_age * 6.0, (2.4 - pickup_age) * 1.6), 0.0, 1.0)
	var tint: Color = SupplyCrate.REPAIR_GREEN if pickup_kind == SupplyCrate.REPAIR \
		else SupplyCrate.ORDNANCE_ORANGE
	var head := "REPAIR CRATE" if pickup_kind == SupplyCrate.REPAIR else "ORDNANCE CRATE"
	var centre := Vector2(size.x * 0.5, size.y * 0.62 - pickup_age * 14.0)
	var width := tracked_width(head, 15, 2.4)
	tracked(centre - Vector2(width * 0.5, 0), head, 15, Color(tint.r, tint.g, tint.b, alpha), 2.4)
	var sub := font.get_string_size(pickup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, centre + Vector2(-sub * 0.5, 20), pickup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(INK.r, INK.g, INK.b, alpha))

func draw_callouts() -> void:
	var camera: Camera3D = world.camera
	for entry: Dictionary in callouts:
		var point: Vector3 = entry["point"]
		if camera.is_position_behind(point):
			continue
		var age: float = entry["age"]
		var screen := camera.unproject_position(point) + Vector2(0,
			-22.0 - age * 20.0 - float(entry.get("row", 0)) * 19.0)
		var alpha := clampf(minf(age * 8.0, (2.3 - age) * 1.6), 0.0, 1.0)
		var tint: Color = entry["tint"]
		var label: String = entry["text"]
		var width := tracked_width(label, 10, 1.1)
		var box := Rect2(screen - Vector2(width * 0.5 + 5, 11), Vector2(width + 10, 15))
		draw_rect(box, Color(0.02, 0.03, 0.04, alpha * 0.60))
		draw_rect(box, Color(tint.r, tint.g, tint.b, alpha * 0.5), false, 1.0)
		tracked(screen - Vector2(width * 0.5, 0), label, 10, Color(tint.r, tint.g, tint.b, alpha), 1.1)

func draw_vampire() -> void:
	## An icon, not a word: a missile silhouette blinking slowly high on screen,
	## with a count when there is more than one. It has to be noticed without
	## being read, and without sitting between the player and the fight.
	var inbound: int = world.inbound_missiles()
	if inbound <= 0 and vampire_age > 5.0:
		return
	# Roughly one and a half blinks a second — present, not frantic.
	var blink := 0.45 + 0.55 * (0.5 + 0.5 * sin(pulse * 4.6))
	var settle := clampf(1.0 - maxf(vampire_age - 4.0, 0.0), 0.0, 1.0)
	var alpha := blink * (1.0 if inbound > 0 else settle)
	var tint := Color(1.0, 0.30, 0.24, alpha)
	var centre := Vector2(size.x * 0.5, 112.0)
	# The rocket points down at you, with its exhaust trailing up behind it.
	glyph_flipped("missile", centre, 34.0, tint)
	var flare := Color(1.0, 0.62, 0.25, alpha * (0.55 + 0.45 * (0.5 + 0.5 * sin(pulse * 21.0))))
	for offset: float in [-3.0, 0.0, 3.0]:
		var length: float = 9.0 if offset == 0.0 else 6.0
		draw_line(centre + Vector2(offset, -18), centre + Vector2(offset * 1.6, -18 - length), flare, 2.0)
	for side: float in [-1.0, 1.0]:
		var edge := centre + Vector2(side * 30.0, 0)
		draw_polyline(PackedVector2Array([edge + Vector2(side * -7, -8), edge,
			edge + Vector2(side * -7, 8)]), Color(tint.r, tint.g, tint.b, alpha * 0.85), 2.4)
	if inbound > 1:
		var label := "x%d" % inbound
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, centre + Vector2(-width * 0.5, 34), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)

func glyph_flipped(kind: String, at: Vector2, size_px: float, color: Color) -> void:
	var points := glyph_points(kind, size_px)
	if points.is_empty():
		return
	for index in range(points.size()):
		points[index] = at + Vector2(points[index].x, -points[index].y)
	draw_colored_polygon(points, color)

func draw_vignette() -> void:
	if damage_flash <= 0.01:
		return
	var strength := clampf(damage_flash, 0.0, 1.0)
	for step in range(9):
		var inset := float(step) * 7.0
		var alpha := strength * 0.13 * (1.0 - float(step) / 9.0)
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0),
			Color(0.85, 0.16, 0.12, alpha), false, 7.0)

func draw_banner() -> void:
	if banner_age > 3.4 or banner_text == "":
		return
	var alpha := clampf(minf(banner_age * 4.0, (3.4 - banner_age) * 1.4), 0.0, 1.0)
	var centre := Vector2(size.x * 0.5, size.y * 0.22)
	var width := tracked_width(banner_text, 30, 5.0)
	tracked(centre - Vector2(width * 0.5, 0), banner_text, 30, Color(INK.r, INK.g, INK.b, alpha), 5.0)
	var sub_width := font.get_string_size(banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, centre + Vector2(-sub_width * 0.5, 24), banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(GOLD.r, GOLD.g, GOLD.b, alpha))
	draw_line(centre + Vector2(-width * 0.5 - 22, -11), centre + Vector2(-width * 0.5 - 6, -11), Color(MINT.r, MINT.g, MINT.b, alpha), 2.0)
	draw_line(centre + Vector2(width * 0.5 + 6, -11), centre + Vector2(width * 0.5 + 22, -11), Color(MINT.r, MINT.g, MINT.b, alpha), 2.0)

func debrief_showing() -> bool:
	## Between levels, and after the last one either way. Not during a fight: the
	## card is a full stop, and there is nothing to stop while the level is still
	## running.
	if world.debrief == null:
		return false
	return world.wave_state == "cleared" or world.mission_state != "active"

func draw_debrief() -> void:
	## What the player actually did, at the one moment they have time to read it.
	##
	## The campaign used to roll from one level straight into the next, so
	## finishing a level well and merely surviving it looked exactly the same on
	## screen — and a game whose whole mechanic is *where* you put your rounds
	## should be willing to tell you where you put them. Deliberately figures
	## rather than a score: one number invites optimising the number.
	if not debrief_showing():
		return
	var card: Tally = world.debrief
	var rows: Array[Array] = card.rows()
	var wide := 340.0
	var tall := 108.0 + float(rows.size()) * 20.0
	var origin := Vector2((size.x - wide) * 0.5, (size.y - tall) * 0.5 - 40.0)
	var frame := Rect2(origin, Vector2(wide, tall))
	var won: bool = world.mission_state != "failed"
	var accent := MINT if won else RED
	panel(frame, accent, true)

	var heading := "LEVEL %d COMPLETE" % (world.debrief_level + 1)
	if world.mission_state == "failed":
		heading = "LEVEL %d LOST" % (world.debrief_level + 1)
	elif world.mission_state == "complete":
		heading = "THE STRAIT IS CLOSED"
	var heading_wide := tracked_width(heading, 15, 2.4)
	tracked(origin + Vector2((wide - heading_wide) * 0.5, 36), heading, 15, INK, 2.4)
	var verdict := Lang.t(card.rating())
	var verdict_wide := tracked_width(verdict, 10, 2.0)
	tracked(origin + Vector2((wide - verdict_wide) * 0.5, 54), verdict, 10, accent, 2.0)
	draw_line(origin + Vector2(28, 66), origin + Vector2(wide - 28, 66), LINE, 1.0)

	for index in range(rows.size()):
		var row: Array = rows[index]
		var line := origin + Vector2(28, 88 + index * 20)
		var emphasis: bool = bool(row[2])
		tracked(line, Lang.t(String(row[0])), 9, MUTED if not emphasis else INK, 1.6)
		var value := String(row[1])
		var value_wide := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1,
			12 if emphasis else 11).x
		draw_string(font, Vector2(origin.x + wide - 28 - value_wide, line.y), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12 if emphasis else 11,
			accent if emphasis else INK)

	var foot := "Press R to fight it again" if world.mission_state == "failed" \
		else ("Stand by for the next contact" if world.mission_state == "active" else "")
	if foot != "":
		var foot_wide := font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, origin + Vector2((wide - foot_wide) * 0.5, tall - 14), foot,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)

func draw_markers() -> void:
	var camera: Camera3D = world.camera
	for unit in world.all_units():
		if not unit.visible or unit.sunk or camera.is_position_behind(unit.position):
			continue
		var air := unit is CombatHelicopter
		var anchor: Vector3 = unit.position + Vector3.UP * (7.0 if air else 16.0)
		var screen := camera.unproject_position(anchor)
		if screen.x < 12 or screen.x > size.x - 48 or screen.y < 84 or screen.y > size.y - 120:
			continue
		var friendly: bool = unit.team == 0
		var color := contact_tint(unit, (CYAN if air else MINT) if friendly else RED)
		var health: float = unit.health / unit.maximum_health if air else unit.hull_fraction()
		if air:
			draw_line(screen - Vector2(8, 0), screen + Vector2(8, 0), color, 1.8)
			draw_line(screen - Vector2(0, 4), screen + Vector2(0, 4), color, 1.8)
		elif friendly:
			draw_polyline(PackedVector2Array([screen + Vector2(-6, 3), screen + Vector2(0, -5), screen + Vector2(6, 3)]), color, 1.8)
		else:
			draw_polyline(PackedVector2Array([screen + Vector2(-6, -4), screen + Vector2(0, 5), screen + Vector2(6, -4),
				screen + Vector2(-6, -4)]), color, 1.8)
		bar(screen + Vector2(-18, 10), 36, health, color, 3.0)
		if unit == world.selected or unit == world.locked_target:
			text_at(screen + Vector2(14, 2), unit.callsign, 10, color)
		elif not friendly and is_instance_valid(world.selected):
			text_at(screen + Vector2(14, 2), "%d m" % int(world.selected.position.distance_to(unit.position)), 10, color)
		if unit == world.locked_target:
			draw_lock(camera, unit, color)

func draw_objective_marker() -> void:
	## When the mission names a module — "disable her engine room" — point at
	## the module itself, on the ship itself. Telling the player in a line of
	## dialogue that the engine room is aft is not the same as showing them
	## which box to put shells into.
	if world.campaign == null:
		return
	var unit: Node3D = world.campaign.marker_unit()
	if not is_instance_valid(unit) or unit.sunk:
		return
	var module := String(world.campaign.objective.get("module", ""))
	if module == "" or not unit.systems.has(module):
		return
	var system = unit.systems[module]
	var point: Vector3 = unit.visuals.to_global(system.position)
	var camera: Camera3D = world.camera
	if camera.is_position_behind(point):
		return
	var at := camera.unproject_position(point)
	if at.x < 30 or at.x > size.x - 30 or at.y < 90 or at.y > size.y - 130:
		return
	var live: bool = unit.operational(module)
	var tint := GOLD if live else MINT
	var beat: float = 0.5 + 0.5 * sin(pulse * 4.2)
	# A diamond that breathes, with a crosshair through it — deliberately a
	# different shape from the target bracket so the two never read as one thing.
	var span: float = 17.0 + 4.0 * beat
	draw_polyline(PackedVector2Array([
		at + Vector2(0, -span), at + Vector2(span, 0),
		at + Vector2(0, span), at + Vector2(-span, 0), at + Vector2(0, -span)]),
		tint, 2.2, true)
	draw_polyline(PackedVector2Array([
		at + Vector2(0, -span - 5), at + Vector2(span + 5, 0),
		at + Vector2(0, span + 5), at + Vector2(-span - 5, 0), at + Vector2(0, -span - 5)]),
		Color(tint.r, tint.g, tint.b, 0.30 * beat), 1.2, true)
	draw_line(at - Vector2(span + 12, 0), at - Vector2(span + 4, 0), tint, 1.6)
	draw_line(at + Vector2(span + 4, 0), at + Vector2(span + 12, 0), tint, 1.6)
	var label: String = Lang.t(String(system.label)).to_upper() if live \
		else (Lang.t(String(system.label)).to_upper() + " — DOWN")
	var width := tracked_width(label, 10, 1.8) + 14.0
	var plate := Rect2(at + Vector2(-width * 0.5, -span - 26), Vector2(width, 16))
	draw_rect(plate, Color(0.04, 0.05, 0.05, 0.9))
	draw_rect(plate, tint, false, 1.0)
	tracked(plate.position + Vector2(7, 11.5), label, 10, tint, 1.8)
	if live:
		bar(at + Vector2(-20, span + 8), 40, system.fraction(), tint, 3.0)

func draw_lock(camera: Camera3D, unit: Node3D, _color: Color) -> void:
	## The designated contact, marked in the world. This was a 60 px double
	## bracket with a filled name plate under it and the word TARGET over it,
	## which covered most of the ship it was pointing at. The name, the range,
	## the condition and the lock state all live in the target panel now, so all
	## this has to do is say "this one" — four small corner ticks and a ring that
	## closes on it do that without hiding the hull.
	var body := camera.unproject_position(unit.position + Vector3.UP * 4.0)
	var settle: float = clampf((pulse - lock_since) * 3.2, 0.0, 1.0)
	var span: float = LOCK_SPAN + 10.0 * (1.0 - ease(settle, 0.3))
	bracket(body, Vector2(span, span * 0.8), GOLD, 5.0, 1.5)
	if settle < 1.0:
		# The closing ring is what the eye catches when a new contact is taken.
		draw_arc(body, span * 2.2, 0, TAU, 24,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * (1.0 - settle)), 1.2, true)
	else:
		# One tick below, so a settled mark still reads as deliberate.
		draw_line(body + Vector2(0, span * 0.8 + 3.0), body + Vector2(0, span * 0.8 + 8.0), GOLD, 1.4)

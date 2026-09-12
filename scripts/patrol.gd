extends Node3D

const BoatScript = preload("res://scripts/boat.gd")
const ShellScript = preload("res://scripts/shell.gd")
const EffectScript = preload("res://scripts/effect.gd")
const HudScript = preload("res://scripts/hud.gd")
const MissileScript = preload("res://scripts/missile.gd")
const HelicopterScript = preload("res://scripts/helicopter.gd")
const SamScript = preload("res://scripts/sam.gd")
const FlareScript = preload("res://scripts/flare.gd")
const CiwsRoundScript = preload("res://scripts/ciws_round.gd")
const BlastScript = preload("res://scripts/blast.gd")
const CrateScript = preload("res://scripts/pickup.gd")
var ocean: OceanSurface
var locked_target: Node3D
## Our own ship's air defence, held by the campaign. A scripted duel the player
## is supposed to fight themselves is not a duel if the ship shoots the other
## aircraft down during the briefing that hands over the cockpit.
var air_hold: bool = false
## Which hull and which module the pointer is resting on, refreshed by
## `pointer_target()`. The HUD names it, so the player can see what a shell into
## that box would actually cost the other ship before firing it.
var aimed_unit: Node3D
var aimed_section: String = ""
## Terrain between us and the designated contact, refreshed once per physics
## tick so the HUD never has to run a space query of its own.
var target_masked: bool = false
## What the player did this level, and what they did last level — the second is
## what the debrief card between levels is reading.
var tally: Tally = Tally.new()
var debrief: Tally = null
var debrief_level: int = 0
var camera_distance: float = 220.0
var camera_pitch: float = 48.0
var camera_yaw: float = -0.22
var camera_shake: float = 0.0
# Direct-control look-ahead, as fractions of the current zoom distance.
const LEAD_TRAVEL: float = 0.30
const LEAD_POINTER: float = 0.26
const LEAD_LIMIT: float = 0.46
const LEAD_PULL_BACK: float = 0.18
var camera_lead := Vector3.ZERO
# 1.0 renders the 3D at the display's true pixel count; lower trades sharpness
# for frame time. native_3d_scale is the factor that gets us to 1:1 at all.
var render_scale: float = 1.0
var native_3d_scale: float = 1.0
var last_render_target := Vector2.ZERO
var slicks: Array[Dictionary] = []
var vampire_cooldown: float = 0.0
const SETTINGS_PATH: String = "user://settings.cfg"
const RENDER_STEPS: Array[float] = [1.0, 0.85, 0.70, 0.55]
# Surface drift. Oil lays a trail downwind rather than spreading as a disc.
const OIL_DRIFT := Vector3(0.92, 0.0, 0.39)
const OIL_SPEED: float = 1.8
# A slick spreads, but it does not spread forever. Without a ceiling the merge
# path below grew one patch without bound and covered the sector.
const SLICK_MAX_RADIUS: float = 105.0
const SLICK_SPREAD_RATE: float = 0.013
# How far a magazine detonation reaches. Generous, so it is worth noticing.
const MAGAZINE_REACH: float = 190.0
var missiles_launched: int = 0
var destruction_count: int = 0
var missiles_intercepted: int = 0
var enemy_missiles_launched: int = 0
var sams_launched: int = 0
var sam_decoyed: int = 0
var inspect_target: bool = false
# --- campaign ---
var campaign: Campaign
## Survives the scene reload that R does, so a failed level retries itself.
static var last_level: int = 0
## Which weapons the player is cleared to use. Empty means everything, so the
## sandbox and every existing test are unaffected.
var clearance: Dictionary = {}
var wave_index: int = -1
var wave_state: String = "briefing"
var wave_clock: float = 3.5
var player_ship: PatrolBoat
var player_air: CombatHelicopter
var controlled: Node3D
var audio: GameAudio
var smoke_texture: ImageTexture
var boats: Array[PatrolBoat] = []
var selected: Node3D
var camera: Camera3D
var hud: Control
var briefing: Control
var comms: Comms
var effects: Node3D
var projectiles: Node3D
var camera_focus := Vector3(0, 0, 15)
var direct_control: bool = true
var mission_state: String = "active"
var islands: Array[Dictionary] = []
var events: Array[String] = ["Incoming transmission on the hostile command net."]
var notice_until: float = 0
var elapsed: float = 0
var next_id: int = 3
var test_mode: bool = false

func _ready() -> void:
	setup_display()
	setup_inputs()
	build_environment()
	effects = Node3D.new()
	add_child(effects)
	Vfx.live_bursts = 0
	projectiles = Node3D.new()
	add_child(projectiles)
	audio = GameAudio.new()
	# Headless runs never synthesise, never read and never write the player's
	# settings — otherwise a test run can leave the game muted.
	audio.muted = test_mode or DisplayServer.get_name() == "headless"
	add_child(audio)
	Lang.load_language()
	setup_smoke_texture()
	player_ship = spawn_boat(0, Vector3(0, 0, 240), "KESTREL / 01")
	player_ship.rotation.y = PI
	take_control(player_ship)
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 52
	camera.near = 0.3
	camera.far = 9000
	camera.current = true
	camera_focus = player_ship.position
	camera_distance = 125.0
	camera_pitch = 30.0
	camera_yaw = PI
	update_camera(1)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HudScript.new()
	hud.world = self
	canvas.add_child(hud)
	comms = Comms.new()
	comms.world = self
	canvas.add_child(comms)
	load_settings()
	# The music and the hostile's voice keep running under the briefing, so the
	# audio node has to survive the pause the briefing puts the world into.
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	open_menu.call_deferred(canvas)
	campaign = Campaign.new(self)
	wave_index = last_level - 1
	warm_shaders.call_deferred()
	if "--start-paused" in OS.get_cmdline_user_args():
		get_tree().paused = true
	if "--capture" in OS.get_cmdline_user_args():
		capture_preview()

func briefing_done() -> void:
	while is_instance_valid(briefing):
		await get_tree().create_timer(0.2).timeout

## What a warship's bridge puts on the air on the way down. Picked in order so
## a long fight does not repeat itself, and a hull only ever calls once.
const DISTRESS_CALLS: Array[String] = [
	"Mayday, mayday, mayday. %s, we are holed below the waterline and listing. All hands, abandon ship.",
	"SOS, SOS — %s. Engine room flooded, we have lost the pumps. Position marked, any vessel, any vessel.",
	"%s is going down. Get the rafts away, get them away now!",
	"Mayday. %s, we cannot contain the flooding. Abandoning ship. Tell them we held the line.",
	"This is %s. Fires out of control aft, she is settling by the stern. All hands off.",
]
var distress_index: int = 0

func ship_lost(boat: PatrolBoat) -> void:
	## A hostile warship going down calls it in. A merchant does not — she is not
	## on anyone's net — and the player's own hull loses with a banner instead.
	if boat.team != 1 or boat.noncombatant or test_mode:
		return
	var call_text: String = DISTRESS_CALLS[distress_index % DISTRESS_CALLS.size()]
	distress_index += 1
	var who: String = "hostile_captain" if boat.loadout.length >= 40.0 else "distress"
	get_tree().create_timer(1.1).timeout.connect(
		func(): if is_instance_valid(self): say(who, call_text % boat.callsign))

func say(speaker: String, line: String) -> void:
	## A line of radio traffic. Queued, so beats can fire several at once.
	if comms != null:
		comms.say(speaker, line)

func warm_shaders() -> void:
	## Fire one of everything, once, below the world, before the player can see
	## anything.
	##
	## Godot compiles a shader the first time something using it is drawn, and on
	## the web that compile happens inside the frame that needed it. The average
	## frame time was fine at ~15 ms; it was the 90 ms spikes that read as lag,
	## and they land exactly when a new effect appears for the first time — the
	## first explosion, the first splash, the first column of smoke. Paying for
	## all of them up front turns a fight full of hitches into a steady one.
	# Nothing to warm without a renderer, and the warm-up puts real projectiles
	# and emitters into the world — which a headless test then finds sitting in
	# `projectiles` where it expected its own missile.
	if test_mode or DisplayServer.get_name() == "headless":
		return
	var below := Vector3(0, -900, 0)
	explosion(below, 1.0)
	smoke(below, 1.0)
	smoke_puff(below, 1.0, 0.4, Vector3.UP, Color(0.5, 0.5, 0.5, 0.5), 1.0)
	splash(below, 1.0)
	debris(below, 4, 1.0)
	cooling_sparks(below, 1.0)
	launch_efflux(below)
	shock_ring(below, 4.0, 2.0, 0.4, 0.2)
	wake(below, 0.0, 1.0)
	bow_spray(below, Vector3.RIGHT, 1.0)
	fire_shell(below, below + Vector3(0, 0, 40), colliders_of(player_ship), false)
	fire_ciws(below, below + Vector3(0, 0, 30), colliders_of(player_ship), false, false)
	# A fire carries six separate particle materials of its own.
	var pilot := FireSource.new()
	pilot.scale_factor = 1.0
	effects.add_child(pilot)
	pilot.global_position = below
	pilot.set_intensity(1.0)
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(pilot):
			pilot.queue_free())

func colliders_of(unit: Node3D) -> Array[RID]:
	return unit.colliders if is_instance_valid(unit) else ([] as Array[RID])

## Which set of levels this run is playing. "campaign" is the four scripted
## levels; "duel" is one corvette against one.
var mode: String = "campaign"
var menu: Control
var start_canvas: CanvasLayer

func open_menu(canvas: CanvasLayer) -> void:
	## Asked before anything else. Skipped wherever the briefing is skipped —
	## a test that flips `test_mode` right after `instantiate()` has to win the
	## race against this, which is why it opens a frame late.
	start_canvas = canvas
	if skip_front_end():
		begin_mode(0)
		return
	menu = load("res://scripts/mode_menu.gd").new()
	menu.world = self
	canvas.add_child(menu)
	get_tree().paused = true

func skip_front_end() -> bool:
	return test_mode or DisplayServer.get_name() == "headless" \
		or "--no-briefing" in OS.get_cmdline_user_args() \
		or "--capture" in OS.get_cmdline_user_args()

func level_table() -> Array[Dictionary]:
	return Campaign.duel() if mode == "duel" else Campaign.levels()

func begin_mode(choice: int) -> void:
	## The menu's answer. The duel needs no briefing card: there is no task
	## group to be called by and nothing to explain that the level does not.
	menu = null
	mode = "duel" if choice == 1 else "campaign"
	# Only lay out a fresh run if one has not started. This is called from a
	# deferred opener, so anything that drives `update_wave()` before that lands
	# already has a level under way — and building a new Campaign here threw it
	# away silently, leaving beats that never ran and a level that never spawned
	# anything.
	if campaign == null or wave_index < 0:
		campaign = Campaign.new(self, level_table())
	if mode == "duel":
		get_tree().paused = false
		wave_clock = 1.2
		return
	if start_canvas != null:
		open_briefing(start_canvas)
	else:
		get_tree().paused = false

func open_briefing(canvas: CanvasLayer) -> void:
	## The hostile commander calls before the first wave. The world is paused
	## behind it, so nothing moves or shoots until the player answers.
	if test_mode or DisplayServer.get_name() == "headless":
		return
	if "--no-briefing" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args():
		return
	briefing = load("res://scripts/briefing.gd").new()
	briefing.world = self
	canvas.add_child(briefing)
	# The call gets the whole screen; the instruments come up when it ends.
	hud.visible = false
	get_tree().paused = true

func begin_mission() -> void:
	## Called by the briefing when the player answers it.
	briefing = null
	hud.visible = true
	get_tree().paused = false
	report("Helm and weapons are yours. Weapons free.")
	audio.play("alarm", -4.0)

func load_settings() -> void:
	## Headless runs never touch the player's settings file.
	if test_mode or DisplayServer.get_name() == "headless":
		return
	var file := ConfigFile.new()
	if file.load(SETTINGS_PATH) != OK:
		# No settings yet: still take the platform's default rather than 1.0.
		render_scale = default_render_scale()
		apply_render_scale()
		return
	render_scale = clampf(float(file.get_value("video", "render_scale", default_render_scale())),
		0.4, 1.0)
	if bool(file.get_value("video", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	audio.set_silenced(bool(file.get_value("audio", "muted", false)))
	apply_render_scale()

func save_settings() -> void:
	if test_mode or DisplayServer.get_name() == "headless":
		return
	var file := ConfigFile.new()
	file.set_value("audio", "muted", audio.silenced)
	file.set_value("video", "render_scale", render_scale)
	file.set_value("video", "fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	file.save(SETTINGS_PATH)

func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
		else DisplayServer.WINDOW_MODE_FULLSCREEN)
	report("Windowed" if full else "Fullscreen")
	apply_render_scale.call_deferred()
	save_settings()

func cycle_render_scale() -> void:
	var index := RENDER_STEPS.find(render_scale)
	render_scale = RENDER_STEPS[(index + 1) % RENDER_STEPS.size()]
	apply_render_scale()
	report("Render scale %d%%" % int(round(render_scale * 100.0)))
	save_settings()

## Whether the deferred renderer is available. The web platform runs on WebGL 2,
## which means the Compatibility backend: no screen-space reflections, no
## ambient occlusion, no temporal anti-aliasing and no FSR. Asking for them
## there is not an error, it is simply ignored — which makes it easy to ship a
## build that quietly looks wrong. Everything those effects were carrying has to
## be replaced by something Compatibility can actually do.
static func deferred_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func default_render_scale() -> float:
	## What a first run should render at before the player has chosen anything.
	##
	## The browser gets less. Its canvas is sized to the window at the display's
	## full pixel ratio, so on a 3K monitor the 3D buffer alone is several times
	## what it is in the 1280x800 window — on top of a 37 MB WebAssembly heap
	## with a shared memory pool. Firefox on Windows is the first to run out of
	## address space and refuse to start, and a player who cannot start the game
	## has no way to reach the setting that would have fixed it. Desktop is
	## unaffected: it has real memory and a real allocator.
	##
	## The RENDER button still steps it back up for anyone whose machine can
	## take it, and the choice is saved.
	if deferred_renderer():
		return 1.0
	return 0.65

func setup_display() -> void:
	## The 2D stretch keeps the HUD legible on a Retina panel, but it also sizes
	## the root viewport well above the window's real pixel count — which would
	## have the 3D supersampling itself several times over for no visible gain.
	## scaling_3d_scale touches only the 3D buffer, so the HUD stays crisp.
	var view := get_viewport()
	if view == null:
		return
	# The 3D buffer is upscaled into the oversized root before the display
	# downsamples it again; a plain bilinear stretch loses real detail across
	# that round trip, so use FSR, which carries a sharpening pass.
	if deferred_renderer():
		view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		view.fsr_sharpness = 0.18
		# Temporal anti-aliasing. The ocean's fine wind-wave octaves and the
		# water's specular are both sub-pixel at native resolution, and no amount
		# of MSAA touches shader aliasing — TAA is what stops the sea crawling.
		view.use_taa = true
	else:
		# Compatibility has neither. Bilinear is the only upscaler, and FXAA is
		# the only thing that touches shader aliasing, so the sea will crawl more
		# than it does on the desktop build. MSAA still helps the hull edges.
		# Bilinear is the only upscaler here, and screen-space AA is not offered
		# either, so MSAA is the whole anti-aliasing budget. The sea will crawl
		# more than it does on the desktop build.
		view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		view.msaa_3d = Viewport.MSAA_4X
	# The root viewport has not settled at _ready time, and it changes again on
	# every resize or fullscreen toggle.
	apply_render_scale.call_deferred()

func apply_render_scale() -> void:
	var view := get_viewport()
	if view == null:
		return
	last_render_target = Vector2(view.get_texture().get_size())
	# get_visible_rect() reports the 2D coordinate space, not the render target,
	# and scaling_3d_scale is a fraction of the render target.
	var current: float = maxf(float(view.get_texture().get_size().x), 1.0)
	var target: float = float(DisplayServer.window_get_size().x)
	native_3d_scale = clampf(target / current, 0.15, 1.0)
	view.scaling_3d_scale = clampf(native_3d_scale * render_scale, 0.15, 1.0)

func setup_inputs() -> void:
	var keys := {"ahead": KEY_W, "astern": KEY_S, "port": KEY_A, "starboard": KEY_D,
		"climb": KEY_SPACE, "descend": KEY_SHIFT}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", click)
	if not InputMap.has_action("missile"):
		InputMap.add_action("missile")
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("missile", right)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_X
		InputMap.action_add_event("missile", key)

func build_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.background_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	sky_material.set_shader_parameter("zenith", Color("2a5476"))
	sky_material.set_shader_parameter("horizon", Color("b7c4c6"))
	sky_material.set_shader_parameter("ground", Color("2b3d43"))
	sky_material.set_shader_parameter("cloud_lit", Color("fdf6ea"))
	sky_material.set_shader_parameter("cloud_shadow", Color("6a7382"))
	sky_material.set_shader_parameter("cloud_cover", 0.44)
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_sky_contribution = 1.0
	settings.ambient_light_energy = 1.0
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.tonemap_exposure = 1.0
	settings.tonemap_white = 1.55
	# Distance haze only: enough to separate the sector from the horizon.
	settings.fog_enabled = true
	settings.fog_mode = Environment.FOG_MODE_DEPTH
	settings.fog_light_color = Color("9fb2bb")
	settings.fog_light_energy = 1.0
	settings.fog_density = 0.00042
	settings.fog_depth_begin = 260.0
	settings.fog_depth_end = 4200.0
	settings.fog_depth_curve = 0.85
	settings.fog_sky_affect = 0.12
	settings.fog_aerial_perspective = 0.35
	settings.glow_enabled = true
	settings.glow_intensity = 0.55
	settings.glow_strength = 1.0
	settings.glow_bloom = 0.06
	settings.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	settings.glow_hdr_threshold = 1.15
	settings.glow_hdr_scale = 2.0
	if deferred_renderer():
		settings.ssao_enabled = true
		settings.ssao_radius = 1.8
		settings.ssao_intensity = 1.7
		settings.ssao_power = 1.5
		settings.ssao_light_affect = 0.15
		settings.ssr_enabled = true
		settings.ssr_max_steps = 42
		settings.ssr_fade_in = 0.2
		settings.ssr_fade_out = 12.0
		settings.ssr_depth_tolerance = 0.6
	else:
		# Compatibility tonemaps noticeably hotter than Forward+ at the same
		# exposure — left alone the sea blows out to white. Pull the exposure
		# down, then lean on fog to put back some of the depth that the missing
		# reflections and occlusion were providing.
		settings.tonemap_exposure = 0.72
		settings.tonemap_white = 2.10
		settings.fog_density = 0.00068
		settings.fog_aerial_perspective = 0.45
		settings.adjustment_saturation = 1.02
		settings.glow_intensity = 0.34
		settings.glow_hdr_threshold = 1.45
	settings.adjustment_enabled = true
	settings.adjustment_contrast = 1.08
	settings.adjustment_saturation = 1.1
	settings.adjustment_brightness = 1.0
	environment.environment = settings
	var attributes := CameraAttributesPractical.new()
	attributes.exposure_multiplier = 1.0
	environment.camera_attributes = attributes
	add_child(environment)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-34, -62, 0)
	sun.light_color = Color("ffeed2")
	sun.light_energy = 1.55
	sun.light_specular = 0.5
	sun.shadow_enabled = true
	sun.shadow_blur = 0.9
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 760.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.14
	sun.directional_shadow_split_3 = 0.4
	# A cool bounce from the sea keeps shadowed hull sides readable.
	var fill := DirectionalLight3D.new()
	add_child(fill)
	fill.rotation_degrees = Vector3(-16, 118, 0)
	fill.light_color = Color("8fb4c6")
	fill.light_energy = 0.4
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	# Weak up-light from the sea keeps overhangs and undersides from going flat.
	var bounce := DirectionalLight3D.new()
	add_child(bounce)
	bounce.rotation_degrees = Vector3(58, 40, 0)
	bounce.light_color = Color("6f95a4")
	bounce.light_energy = 0.16
	bounce.light_specular = 0.0
	bounce.shadow_enabled = false
	ocean = OceanSurface.new()
	add_child(ocean)
	add_island(Vector3(-113, 0, -45), 40, 13)
	add_island(Vector3(440, 0, -90), 75, 24)
	add_island(Vector3(580, 0, 400), 65, 20)
	add_island(Vector3(-620, 0, -780), 120, 35)
	ocean.set_shores(islands)
	ocean.set_sun(-sun.global_transform.basis.z, sun.light_color)
	# An inhabited outpost gives the patrol a sense of place and scale.
	build_outpost()

func build_outpost() -> void:
	## Lighthouse, quarters and a jetty on the near island.
	var builder := NavalGeometry.Builder.new()
	var base := Vector3(-113, 12.4, -45)
	builder.slab(base, Vector2(11.0, 9.0), base + Vector3(0, 5.4, 0), Vector2(10.2, 8.4), Color("cfc0a4"))
	builder.slab(base + Vector3(0, 5.4, 0), Vector2(11.6, 9.6), base + Vector3(0, 6.4, 0), Vector2(6.5, 5.0), Color("7d5f4b"))
	for offset in [-3.4, 0.0, 3.4]:
		builder.box(base + Vector3(offset, 2.8, -4.55), Vector3(1.7, 1.9, 0.2), Color("2d3a41"))
	var tower := base + Vector3(10.0, 0.0, 1.0)
	builder.cylinder(tower + Vector3(0, 6.5, 0), 1.7, 1.25, 13.0, Color("e6e2d4"), 14)
	builder.cylinder(tower + Vector3(0, 13.4, 0), 1.5, 1.5, 0.8, Color("8d3f34"), 14)
	builder.cylinder(tower + Vector3(0, 14.6, 0), 1.15, 1.15, 1.6, Color("2a3238"), 12)
	builder.cylinder(tower + Vector3(0, 15.7, 0), 1.5, 0.2, 1.2, Color("8d3f34"), 14)
	# Jetty out into the shallows.
	for index in range(9):
		var post := Vector3(-97.0, 0.0, -28.0 + index * 3.0)
		builder.cylinder(post + Vector3(0, 0.6, 0), 0.24, 0.24, 4.0, Color("6b5f4d"), 8)
	builder.slab(Vector3(-97, 2.3, -14.0), Vector2(4.0, 30.0), Vector3(-97, 2.6, -14.0), Vector2(4.0, 30.0), Color("7c7159"))
	var outpost := builder.commit(self, NavalGeometry.steel(Color.WHITE, 0.78, 0.05, true, 0.09), "Outpost")
	outpost.position = Vector3.ZERO
	var beam := NavalGeometry.Builder.new()
	beam.cylinder(base + Vector3(10.0, 14.6, 1.0), 1.05, 1.05, 1.2, Color(1.0, 0.92, 0.6), 12)
	beam.commit(self, NavalGeometry.lamp(), "LighthouseLamp")

func add_island(point: Vector3, radius: float, height: float) -> void:
	islands.append({"position": point, "radius": radius})
	# The ocean shader draws the shallows and surf, so the island only needs
	# its own sand skirt running down under the waterline.
	NavalGeometry.island(self, point, radius, height)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height * 2
	collision.shape = shape
	body.add_child(collision)

func spawn_boat(team: int, point: Vector3, callsign: String, small: bool = false,
		loadout: ShipLoadout = null) -> PatrolBoat:
	## The loadout has to be set before the node enters the tree: `_ready()`
	## builds the module boxes and the hull from it, and neither is rebuilt.
	var boat := BoatScript.new()
	boat.world = self
	if loadout != null:
		boat.loadout = loadout
	elif small:
		boat.loadout = preload("res://ships/tern.tres")
	boat.team = team
	boat.callsign = callsign
	boat.missile_cooldown = 4.0 + boats.size() * 1.5
	if boats.is_empty():
		boat.missile_cooldown = 0.0
	boat.position = point
	add_child(boat)
	boats.append(boat)
	return boat

func spawn_extra(team: int) -> void:
	if boats.size() >= 16:
		report("Sandbox limit: 16 boats. Restart to clear wrecks.")
		return
	var point := camera_focus + Vector3(-160 if team == 0 else 160, 0, 180 if team == 0 else -800)
	point.x = clampf(point.x, -1600, 1600)
	point.z = clampf(point.z, -1600, 1600)
	var found := false
	for attempt in range(80):
		if position_clear(point, null):
			found = true
			break
		point += Vector3(65, 0, 75)
		if point.x > 1650:
			point.x = -1600
		if point.z > 1650:
			point.z = -1600
	if not found:
		report("No clear spawn position available.")
		return
	next_id += 1
	var boat := spawn_boat(team, point, ("FRIENDLY" if team == 0 else "CONTACT") + " / %02d" % next_id)
	if team == 1:
		boat.rotation.y = PI
	report("%s entered the area" % boat.callsign)
	# Extra units are sandbox additions; the patrol outcome stays latched.

func all_units() -> Array:
	## Freed nodes are filtered out rather than trusted away. The invariant is
	## that a unit leaves `boats` before it is freed — `Campaign.despawn()` is
	## the only place that happens — but everything in the HUD walks this list,
	## so one `queue_free()` that forgets the erase does not cost a stray warning:
	## `_draw` aborts on the first stale entry and the whole overlay disappears.
	var live: Array = []
	for unit in boats:
		if is_instance_valid(unit):
			live.append(unit)
	for unit in get_tree().get_nodes_in_group("aircraft"):
		if is_instance_valid(unit):
			live.append(unit)
	return live

func take_control(unit: Node3D) -> void:
	## The player is always at the controls of something; there is no RTS layer.
	if not is_instance_valid(unit) or unit.sunk:
		return
	for other in all_units():
		other.manual = false
		other.selection.visible = false
	selected = unit
	unit.manual = true
	unit.selection.visible = true
	inspect_target = false

func order_air_support() -> void:
	## Point the gunship at whatever you have designated, or release it back to
	## escorting. The whole air-support interface in one key.
	if not is_instance_valid(player_air) or player_air.destroyed:
		report("No air support on station")
		return
	if player_air.manual:
		report("You are flying it")
		return
	if is_instance_valid(locked_target) and not locked_target.sunk:
		player_air.order_attack(locked_target)
		report("%s / engage %s" % [player_air.callsign, locked_target.callsign])
	else:
		player_air.explicit_target = false
		player_air.target = null
		report("%s / resume escort" % player_air.callsign)

func take_the_controls(which: String) -> void:
	## The campaign moving the player between the helm and the cockpit. Falls
	## back to the ship rather than stranding the player on a dead aircraft.
	var target: Node3D = player_ship
	if which == "air" and is_instance_valid(player_air) and not player_air.destroyed:
		target = player_air
	if not is_instance_valid(target) or target.sunk:
		return
	take_control(target)
	report("You have the " + ("aircraft" if target == player_air else "helm"))

func swap_control() -> void:
	## Tab hands the helm to the AI crew and takes the helicopter, or back.
	var next: Node3D = null
	if selected == player_ship:
		if is_instance_valid(player_air) and not player_air.destroyed:
			next = player_air
		else:
			report("No air support on station")
			return
	else:
		next = player_ship
	if not is_instance_valid(next) or next.sunk:
		return
	take_control(next)
	camera_focus = next.position
	report("Now flying %s" % next.callsign if next is CombatHelicopter else "Now conning %s" % next.callsign)

func unit_at_screen(point: Vector2, team: int) -> Node3D:
	var best: Node3D
	var distance := 42.0
	for unit in all_units():
		if unit.team != team or unit.sunk or camera.is_position_behind(unit.position):
			continue
		var projected := camera.unproject_position(unit.position + Vector3.UP * 3)
		var next := projected.distance_to(point)
		if next < distance:
			distance = next
			best = unit
	return best

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("missile"):
		launch_selected_missile()
		return
	if camera_locked():
		# Everything that moves the view or the player's unit is held for the
		# length of a scripted shot. Firing and the helm are left alone: the
		# player can still defend themselves, they just cannot wander off.
		var blocked := [KEY_TAB, KEY_G, KEY_F, KEY_V]
		if event is InputEventKey and event.pressed and not event.echo \
				and blocked.has(event.physical_keycode):
			return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB: swap_control()
			KEY_T: cycle_target()
			KEY_Z:
				if selected is CombatHelicopter:
					selected.deploy_flares()
			KEY_V: camera_pitch = 19.0 if camera_pitch > 25.0 else 46.0
			KEY_F1: hud.visible = not hud.visible
			KEY_G: inspect_target = not inspect_target
			KEY_M:
				report("Sound off" if audio.toggle_silence() else "Sound on")
				save_settings()
			KEY_F11:
				toggle_fullscreen()
			KEY_H:
				order_air_support()
			KEY_C:
				if is_instance_valid(player_ship) and not player_ship.run_damage_control():
					report("Damage control party is already committed")
			KEY_I:
				if is_instance_valid(player_ship):
					player_ship.ciws_enabled = not player_ship.ciws_enabled
					report("CIWS " + ("free" if player_ship.ciws_enabled else "held"))
			KEY_F:
				if is_instance_valid(selected):
					camera_focus = selected.position
					inspect_target = false
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(55, camera_distance * 0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(700, camera_distance * 1.14)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) \
			and not camera_locked():
		var reach: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		if Input.is_key_pressed(KEY_SHIFT):
			# Shift and drag still slides the view across the sea, which is what
			# the middle button used to do on its own.
			var right := camera.basis.x
			var forward := Vector3(camera.basis.z.x, 0, camera.basis.z.z).normalized()
			camera_focus -= (right * event.relative.x + forward * event.relative.y * 1.6) \
				* camera_distance / reach
		else:
			# Drag to swing the view round the ship, the way every other
			# third-person game does it. Q/E and the arrow keys still work; this
			# is the one every player tries first.
			camera_yaw -= event.relative.x / reach * ORBIT_SPEED
			camera_pitch = clampf(camera_pitch - event.relative.y / reach * TILT_SPEED, 12.0, 72.0)

# --------------------------------------------------------------------------- #
# Campaign
# --------------------------------------------------------------------------- #

func _physics_process(delta: float) -> void:
	elapsed += delta
	vampire_cooldown = maxf(0.0, vampire_cooldown - delta)
	ocean.set_clock(elapsed)
	update_slicks(delta)
	tick_cutaway(delta)
	update_wave(delta)
	if not is_instance_valid(selected) or selected.sunk:
		if is_instance_valid(player_ship) and not player_ship.sunk:
			take_control(player_ship)
	auto_lock()
	# Whether terrain is between us and the designated contact, answered once a
	# physics tick. The panel that displays it is drawn from `_draw`, and running
	# a space query from the render pass means asking the physics server for an
	# answer at the point in the frame it is least able to give one.
	target_masked = is_instance_valid(selected) and is_instance_valid(locked_target) \
		and not line_of_sight(selected, locked_target)
	update_soundtrack()

func setup_sandbox() -> void:
	## Test-only fixture: halt the campaign and recreate a fixed engagement of
	## two ships and one helicopter per side, in a stable spawn order.
	wave_state = "sandbox"
	mission_state = "sandbox"
	if boats.size() > 1:
		return
	spawn_boat(0, Vector3(-65, 0, 450), "TERN / 02", true)
	var enemy := spawn_boat(1, Vector3(80, 0, -520), "CONTACT / 01")
	enemy.rotation.y = PI * 0.9
	var escort := spawn_boat(1, Vector3(290, 0, -650), "CONTACT / 02", true)
	escort.rotation.y = PI
	locked_target = enemy
	# The player's gunship now arrives with the level that needs it rather than
	# at start-up, so the fixture has to put its own on the board — the sandbox
	# is defined as one helicopter per side.
	player_air = spawn_helicopter(0)
	spawn_helicopter(1, Vector3(140, 60, -430))

func current_wave() -> Dictionary:
	if campaign == null:
		return {}
	return {"title": campaign.title(), "brief": campaign.brief()}

func level_count() -> int:
	return campaign.count() if campaign != null else 0

var refusals: Dictionary = {}

func refuse(weapon: String, reason: String) -> void:
	## Say no out loud, but not sixty times a second — the trigger is held down.
	if elapsed - float(refusals.get(weapon, -99.0)) < 2.5:
		return
	refusals[weapon] = elapsed
	report(reason)
	if not test_mode:
		audio.play("warn", -8.0)

func cleared(weapon: String) -> bool:
	## Permissive by default: a level has to take a weapon away deliberately.
	return bool(clearance.get(weapon, true))

func fail_mission(reason: String) -> void:
	if mission_state != "active":
		return
	mission_state = "failed"
	wave_state = "over"
	report(reason + " Press R to fight it again.")
	if not test_mode:
		audio.play("warn", -1.0)

func hostiles_remaining() -> int:
	var count := 0
	for unit in all_units():
		if unit.team == 1 and not unit.sunk and unit.is_combat_capable():
			count += 1
	return count

func update_wave(delta: float) -> void:
	if mission_state != "active":
		return
	if not is_instance_valid(player_ship) or player_ship.sunk:
		mission_state = "failed"
		wave_state = "over"
		# A lost level gets its debrief too. Being told how the fight you just
		# lost actually went is more use than being told only that you lost it.
		close_tally(wave_index)
		report("KESTREL is lost. Press R to fight it again.")
		if not test_mode:
			audio.play("warn", -1.0)
		return
	if campaign == null:
		campaign = Campaign.new(self, level_table())
	match wave_state:
		"briefing":
			# The opening pause also covers the briefing card, which pauses the
			# tree — so this only ticks once the player is actually playing.
			wave_clock -= delta
			if wave_clock <= 0.0:
				begin_level(wave_index + 1)
		"fighting":
			campaign.advance(delta)
		"cleared":
			wave_clock -= delta
			if wave_clock <= 0.0:
				wave_state = "briefing"
				wave_clock = 4.0
				report(next_brief())

func next_brief() -> String:
	if campaign == null:
		return ""
	var next := wave_index + 1
	return String(campaign.table[next]["brief"]) if next < campaign.table.size() else ""

func close_tally(level: int) -> void:
	## The level is over: stop the clock and put the figures up for the card.
	tally.close(elapsed)
	debrief = tally
	# Losing the ship during the opening countdown, before level one has begun,
	# leaves wave_index at -1 and the card reading "LEVEL 0 LOST".
	debrief_level = maxi(level, 0)
	tally = Tally.new()
	tally.reset(elapsed)

func begin_level(index: int) -> void:
	if campaign == null:
		campaign = Campaign.new(self, level_table())
	last_level = index
	# Any hold the last level left set is not this level's business.
	air_hold = false
	tally.reset(elapsed)
	campaign.begin(index)

func restart_level() -> void:
	## R after a failure retries the level you lost, not the whole campaign.
	get_tree().paused = false
	get_tree().reload_current_scene()

func drop_crate(point: Vector3, kind: int) -> void:
	var crate := CrateScript.new()
	crate.world = self
	crate.kind = kind
	add_child(crate)
	crate.position = Vector3(point.x, 0.0, point.z)

func collect_crate(crate: SupplyCrate, message: String) -> void:
	report("%s crate — %s" % [crate.label(), message])
	hud.announce_pickup(crate.kind, message)
	if not test_mode:
		audio.play("pickup", -5.0)

func scatter_supplies() -> void:
	## Two crates dropped within reach at the start of each wave, so there is
	## always something to go and get while the contact closes.
	var bearing := randf_range(-PI, PI)
	for index in range(2):
		var angle := bearing + PI * float(index)
		var point := player_ship.position + Vector3(sin(angle), 0, cos(angle)) * randf_range(210.0, 340.0)
		point.x = clampf(point.x, -1700, 1700)
		point.z = clampf(point.z, -1700, 1700)
		drop_crate(point, SupplyCrate.REPAIR if index == 0 else SupplyCrate.ORDNANCE)

func restore_air_support() -> void:
	if is_instance_valid(player_air) and not player_air.destroyed:
		player_air.health = player_air.maximum_health
		return
	player_air = spawn_helicopter(0)

func auto_lock() -> void:
	## Arcade convenience: something hostile is always designated, so X always
	## has somewhere to send a missile.
	if is_instance_valid(locked_target) and not locked_target.sunk:
		return
	# The hull the mission names wins over the nearest one. When a level says
	# "disable her engine room", the objective diamond and the target bracket
	# have to be on the same ship — put them on two and the player has to work
	# out for themselves which of the two the orders meant.
	if campaign != null:
		var named: Node3D = campaign.marker_unit()
		if is_instance_valid(named) and not named.sunk and named.team == 1:
			locked_target = named
			return
	var best: Node3D = null
	var closest := INF
	var anchor: Vector3 = selected.position if is_instance_valid(selected) else Vector3.ZERO
	for unit in all_units():
		if unit.team != 1 or unit.sunk:
			continue
		var distance: float = anchor.distance_to(unit.position)
		if distance < closest:
			closest = distance
			best = unit
	locked_target = best

func update_soundtrack() -> void:
	if test_mode:
		return
	var hot := 0.15
	if wave_state == "fighting":
		hot = 1.0
	elif wave_state == "briefing" and wave_index >= 0:
		hot = 0.5
	if mission_state != "active":
		hot = 0.0
	audio.set_intensity(hot)
	audio.set_rotor(1.0 if selected is CombatHelicopter else 0.0)

# --------------------------------------------------------------------------- #
# Player feedback
# --------------------------------------------------------------------------- #

func report_hit(point: Vector3, damage: float, destroyed_part: bool, by_player: bool,
		label: String = "") -> void:
	## Every round the player lands answers back: a spark burst, a tick in the
	## reticle, a floating number and a sound keyed to what it did.
	# Impact scales with the weight of the hit, so a shell reads very differently
	# from a cannon round grazing the superstructure.
	var weight := clampf(damage / 70.0, 0.28, 1.7)
	impact(point, weight * (1.5 if destroyed_part else 1.0))
	# Cannon and CIWS strikes are far too frequent to confirm individually;
	# only the hits that matter earn a marker.
	if not by_player or (damage < 6.0 and not destroyed_part):
		return
	camera_shake = minf(1.0, camera_shake + (0.35 if destroyed_part else 0.13))
	hud.flash_hit(destroyed_part)
	hud.add_damage_number(point, damage, destroyed_part)
	if test_mode:
		return
	audio.play("marker", -8.0 if not destroyed_part else -4.0)
	audio.play_at("strike", point, -6.0, randf_range(0.92, 1.1))
	if destroyed_part:
		audio.play("kill", -5.0)

func warn_vampire() -> void:
	## "Vampire" is the real call for an inbound anti-ship missile. One short
	## alert per launch, rate limited: it has to register without becoming noise
	## in the middle of a gun action.
	if vampire_cooldown > 0.0:
		return
	vampire_cooldown = 2.2
	hud.raise_vampire()
	if not test_mode:
		audio.play("vampire", -7.0)

func inbound_missiles() -> int:
	var count := 0
	for missile in get_tree().get_nodes_in_group("guided_missiles"):
		if missile.detonated or not is_instance_valid(missile.source):
			continue
		if missile.source.team != 0:
			count += 1
	return count

func shock_ring(point: Vector3, start: float = 8.0, reach: float = 4.0,
		life: float = 1.0, force: float = 1.0) -> void:
	## A thin ring of blast racing out across the water. A hull breaking up gets
	## a modest one; a magazine going up gets one you cannot miss.
	var node := Node3D.new()
	node.set_script(preload("res://scripts/one_shot_particles.gd"))
	node.set("ttl", life + 0.3)
	effects.add_child(node)
	node.global_position = Vector3(point.x, ocean.height_at(point) + 0.6, point.z)
	var material := NavalGeometry.material(Color(1.25 * force, 0.95 * force, 0.62 * force), true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var ring := NavalGeometry.ring(node, start, Color.WHITE, start * 0.11)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sweep := node.create_tween()
	sweep.tween_property(ring, "scale", Vector3(reach, 1.0, reach), life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sweep.parallel().tween_property(material, "albedo_color", Color(0.4, 0.18, 0.06, 0.0), life)

func magazine_detonation(ship: PatrolBoat, point: Vector3) -> void:
	## The magazine goes up. The ship is gone, and anything alongside is in
	## serious trouble — which is what makes closing to knife range a gamble.
	if ship.sunk:
		return
	report("%s / MAGAZINE DETONATION" % ship.callsign)
	hud.add_callout(point, "MAGAZINE DETONATION", Color("ffd36a"))
	explosion(point, 3.4)
	shock_ring(point, 11.0, 8.0, 1.5, 1.6)
	camera_shake = 1.0
	if not test_mode:
		audio.play_at("blast", point, 3.0, 0.62)
	for unit in all_units():
		if unit == ship or unit.sunk:
			continue
		var distance: float = unit.position.distance_to(point)
		if distance > MAGAZINE_REACH:
			continue
		var falloff: float = pow(1.0 - distance / MAGAZINE_REACH, 1.6)
		if unit is PatrolBoat:
			unit.take_shockwave(point, 300.0 * falloff)
		else:
			unit.take_damage(170.0 * falloff, false)
	ship.begin_sinking(true)

func report_module_lost(point: Vector3, label: String, ours: bool) -> void:
	## Any module coming off any hull is worth calling out — theirs in red as a
	## result, ours in amber as a warning. Losing a mount to fire matters just as
	## much as losing one to a shell, so this is raised where the module dies
	## rather than where a round lands.
	if not ours:
		tally.modules += 1
	hud.add_callout(point, label.to_upper() + " DISABLED",
		Color("ffb454") if ours else Color("ff6a52"))
	if ours and not test_mode:
		audio.play("warn", -9.0)

func report_player_damage(amount: float) -> void:
	tally.taken += amount
	hud.flash_damage(amount)
	if not test_mode and amount > 25.0:
		audio.play("warn", -12.0)

func _process(delta: float) -> void:
	# The root render target changes on resize, fullscreen and display moves, and
	# the notifications for that do not all land before the texture is resized.
	# Watching it directly is cheap and cannot get out of step.
	var view := get_viewport()
	if view != null and Vector2(view.get_texture().get_size()) != last_render_target:
		apply_render_scale()
	update_camera(delta)
	ocean.position = Vector3(snappedf(camera_focus.x, 100), 0, snappedf(camera_focus.z, 100))

func update_cursor() -> void:
	## The pointer is the gunsight — the HUD draws a reticle on it every frame —
	## so the operating system's arrow sitting on top of that is one cursor too
	## many. It is hidden rather than captured: captured locks the pointer to the
	## middle of the window, which is exactly the thing aiming needs it not to do.
	##
	## It comes back whenever the game is not being played, because that is when
	## there are buttons to hit and no reticle to hit them with: paused, or with
	## the briefing card up.
	##
	## Called from the HUD's `_process`, not this node's: the world stops
	## processing while the tree is paused, so driving it from here would hide
	## the cursor and then never give it back at the one moment it is needed.
	if test_mode or DisplayServer.get_name() == "headless":
		return
	var wanted: int = Input.MOUSE_MODE_HIDDEN
	if get_tree().paused or is_instance_valid(briefing):
		wanted = Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted

func unit_travel(unit: Node3D) -> Vector3:
	## Where this craft is actually going, in world units per second.
	if unit is CombatHelicopter:
		return unit.velocity
	return -unit.global_basis.z * unit.speed

func unit_top_speed(unit: Node3D) -> float:
	if unit is CombatHelicopter:
		return 52.0 if unit.variant == "Apache" else 46.0
	return maxf(unit.loadout.speed, 1.0)

func look_ahead(travel: Vector3, pace: float) -> Vector3:
	## The view slides ahead along the course and peeks toward the cursor, so
	## under direct control you are looking where you are going rather than at
	## your own wake. The pointer term reads the cursor's *screen* position, not
	## the point it lands on in the world, or moving the camera would chase it.
	var lead := Vector3.ZERO
	if travel.length_squared() > 0.05:
		var course := Vector3(travel.x, 0, travel.z)
		if course.length_squared() > 0.001:
			lead += course.normalized() * pace * camera_distance * LEAD_TRAVEL
	if not pointer_over_ui():
		var viewport := get_viewport().get_visible_rect().size
		if viewport.y > 1.0:
			var cursor := (get_viewport().get_mouse_position() - viewport * 0.5) / viewport.y
			var right := Vector3(camera.basis.x.x, 0, camera.basis.x.z).normalized()
			var ahead := -Vector3(camera.basis.z.x, 0, camera.basis.z.z).normalized()
			lead += (right * cursor.x - ahead * cursor.y) * camera_distance * LEAD_POINTER
	lead.y = 0.0
	return lead.limit_length(camera_distance * LEAD_LIMIT)

# --- scripted camera ------------------------------------------------------- #
## Holding the camera on something the script wants the player to see. Contacts
## used to simply be there the next time you looked at the radar, and at the
## last level the player never learned they had escorts before the escorts died.
var cutaway: Array[Node3D] = []
var cutaway_left: float = 0.0
var cutaway_hold: String = ""
## The last position the group actually occupied. Without this a group that has
## just been wiped out reports a centre of Vector3.ZERO — which is a real place
## on the map, so the camera lurches to the middle of the sector at exactly the
## moment the player is supposed to be watching their escorts die.
var cutaway_mark := Vector3.ZERO
var cutaway_lost: float = -1.0
## Eased 0..1. A cutaway that snaps in and snaps out reads as a glitch; the same
## move over half a second reads as a camera.
var cutaway_blend: float = 0.0
var cutaway_range: float = 120.0
var home_distance: float = 125.0
const CUTAWAY_LINGER: float = 3.0
const CUTAWAY_BLEND: float = 0.55

func camera_locked() -> bool:
	## While a scripted shot is running the view belongs to the script. The
	## player could otherwise orbit, zoom, pan or swap units through the middle
	## of it — and at the end of level three that means fighting the camera for
	## control of an aircraft that is in the process of being shot down.
	return not cutaway.is_empty()

func show_units(units: Array, seconds: float, hold: String = "") -> void:
	var alive: Array[Node3D] = []
	for unit in units:
		if is_instance_valid(unit):
			alive.append(unit)
	if alive.is_empty():
		return
	if cutaway.is_empty():
		home_distance = camera_distance
	cutaway = alive
	cutaway_left = seconds
	cutaway_hold = hold
	cutaway_lost = -1.0
	cutaway_mark = group_centre()

func group_centre() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for unit in cutaway:
		if is_instance_valid(unit) and not unit.sunk:
			total += unit.position
			count += 1
	return total / float(count) if count > 0 else cutaway_mark

func group_reach() -> float:
	## Frame the whole group with a margin, so two boats abreast both fit and a
	## single contact is actually close enough to see.
	var spread := 0.0
	var airborne := false
	for unit in cutaway:
		if is_instance_valid(unit) and not unit.sunk:
			spread = maxf(spread, cutaway_mark.distance_to(unit.position))
			airborne = airborne or unit is CombatHelicopter
	# An aircraft falls a long way and throws its wreckage further. Stand back.
	var base: float = 105.0 if airborne else 72.0
	return clampf(base + spread * 1.9, 70.0, 260.0)

func cutaway_alive() -> bool:
	for unit in cutaway:
		if is_instance_valid(unit) and not unit.sunk:
			return true
	return false

func cutaway_expired(delta: float) -> bool:
	cutaway_left -= delta
	if cutaway_hold == "until_lost":
		# Stay with them through the strike, then a fixed beat afterwards —
		# measured from when they actually died, not from when the beat ran.
		if cutaway_alive():
			# It should be dead by now; if something went wrong, do not strand
			# the player staring at a healthy aircraft.
			return cutaway_left <= -6.0
		if cutaway_lost < 0.0:
			cutaway_lost = elapsed
		return elapsed - cutaway_lost > CUTAWAY_LINGER
	return cutaway_left <= 0.0

func tick_cutaway(delta: float) -> void:
	## Runs on the fixed timestep. How long a scripted shot lasts must not depend
	## on the frame rate, and the beat interpreter waits on it.
	if cutaway.is_empty():
		return
	if cutaway_alive():
		cutaway_mark = group_centre()
		cutaway_range = group_reach()
	if cutaway_expired(delta) or not is_instance_valid(player_ship):
		cutaway.clear()
		cutaway_hold = ""

func process_cutaway(delta: float) -> bool:
	## Returns true while the scripted camera owns the view. The blend keeps
	## running for half a second after it lets go, so control eases back rather
	## than snapping.
	var running := not cutaway.is_empty()
	cutaway_blend = move_toward(cutaway_blend, 1.0 if running else 0.0, delta / CUTAWAY_BLEND)
	if cutaway_blend <= 0.001:
		return false
	var ease_amount: float = ease(cutaway_blend, 0.4)
	# Keep the subject's height. Flattening the anchor to sea level pointed the
	# camera at the water *underneath* an aircraft rather than at the aircraft,
	# which is how the whole of Shaheen's shoot-down happened off-screen.
	var anchor: Vector3 = cutaway_mark
	anchor.y = maxf(anchor.y, 0.0)
	camera_lead = camera_lead.lerp(Vector3.ZERO, 1.0 - exp(-delta * 4.0))
	# Blend toward the subject rather than assigning it: the player's own ship
	# is still moving under us and the hand-back has to be continuous.
	var want: Vector3 = anchor if running else follow_point()
	camera_focus = camera_focus.lerp(want, 1.0 - exp(-delta * 3.4))
	camera_distance = lerpf(camera_distance,
		lerpf(home_distance, cutaway_range, ease_amount), 1.0 - exp(-delta * 2.6))
	return running or cutaway_blend > 0.02

## Radians of yaw, and degrees of pitch, per full screen-height of drag.
const ORBIT_SPEED: float = 3.6
const TILT_SPEED: float = 150.0

func panning() -> bool:
	## Sliding the view off the ship, as opposed to swinging it round her. Only
	## the first should stop the camera following, or an orbit would leave the
	## ship behind the moment you turned the view.
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and Input.is_key_pressed(KEY_SHIFT)

func follow_point() -> Vector3:
	return selected.position if is_instance_valid(selected) else camera_focus

func update_camera(delta: float) -> void:
	if not camera_locked():
		var orbit := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
		camera_yaw += orbit * delta * 0.65
		var tilt := float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))
		camera_pitch = clampf(camera_pitch + tilt * delta * 24, 12, 72)
	var pace := 0.0
	if process_cutaway(delta):
		pass
	elif inspect_target and is_instance_valid(locked_target):
		camera_lead = camera_lead.lerp(Vector3.ZERO, 1.0 - exp(-delta * 3.0))
		camera_focus = camera_focus.lerp(locked_target.position, 1.0 - exp(-delta * 3))
	elif direct_control and is_instance_valid(selected) and not selected.sunk and not panning():
		var travel := unit_travel(selected)
		pace = clampf(travel.length() / unit_top_speed(selected), 0.0, 1.0)
		# Ease the lead in and out slower than the follow, so course changes
		# swing the view across rather than snapping it.
		camera_lead = camera_lead.lerp(look_ahead(travel, pace), 1.0 - exp(-delta * 2.0))
		camera_focus = camera_focus.lerp(selected.position + camera_lead, 1.0 - exp(-delta * 2.6))
	else:
		camera_lead = camera_lead.lerp(Vector3.ZERO, 1.0 - exp(-delta * 3.0))
	camera_focus.x = clampf(camera_focus.x, -1800, 1800)
	camera_focus.z = clampf(camera_focus.z, -1800, 1800)
	if not direct_control and not inspect_target and not camera_locked() and not panning():
		var pan := Vector3(Input.get_axis("port", "starboard"), 0, Input.get_axis("ahead", "astern"))
		pan = pan.rotated(Vector3.UP, camera_yaw)
		camera_focus += pan * camera_distance * delta * 0.7
	if cutaway.is_empty():
		camera_focus.y = selected.position.y if direct_control and selected is CombatHelicopter else 0.0
	# Pull back a little at speed, so the extra ground the lead covers still fits.
	var pull_back: float = camera_distance * (1.0 + pace * LEAD_PULL_BACK)
	var pitch := deg_to_rad(camera_pitch)
	camera.position = camera_focus + Vector3(sin(camera_yaw) * cos(pitch), sin(pitch), cos(camera_yaw) * cos(pitch)) * pull_back
	camera.look_at(camera_focus)
	camera_shake = move_toward(camera_shake, 0, delta * 1.5)
	camera.h_offset = sin(elapsed * 43) * camera_shake * 0.25
	camera.v_offset = cos(elapsed * 37) * camera_shake * 0.18

func mouse_on_sea(height: float = 0.0) -> Vector3:
	var screen := get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, height)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return hit if hit != null else Vector3.ZERO

func pointer_target(exclude: Array[RID]) -> Dictionary:
	## Where the pointer actually lands in the world. If it falls on a hull the
	## player is picking a module, not a ship, so the exact point is returned.
	var screen := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(screen)
	var to := from + camera.project_ray_normal(screen) * 6000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8, exclude)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# What the pointer is resting on is recorded here rather than raycast a
	# second time from the HUD: this already runs once per physics frame for the
	# manually conned ship, and the overlay only wants to read the answer.
	aimed_unit = null
	aimed_section = ""
	if hit.is_empty():
		return {"position": mouse_on_sea(3.0), "unit": null}
	var unit: Node3D = null
	if hit.collider.has_meta("boat"):
		unit = hit.collider.get_meta("boat")
	elif hit.collider.has_meta("aircraft"):
		unit = hit.collider.get_meta("aircraft")
	aimed_unit = unit
	if hit.collider.has_meta("section"):
		aimed_section = String(hit.collider.get_meta("section"))
	return {"position": hit.position, "unit": unit}

func designate(unit: Node3D, announce: bool = false) -> void:
	## Whatever you are shooting at becomes the designated contact.
	if not is_instance_valid(unit) or unit.sunk or unit.team == 0:
		return
	if locked_target == unit:
		return
	locked_target = unit
	# A silent change of target is one the player only finds out about by
	# noticing the bracket move. Cycling with T says so; incidental designation
	# from a hit does not, or every burst would spam the feed.
	if announce:
		report("Target / %s" % unit.callsign)
		if not test_mode:
			audio.play("marker", -16.0, 1.25)

func pointer_over_ui() -> bool:
	if is_instance_valid(briefing):
		return true
	return hud != null and hud.visible and hud.blocks_pointer(get_viewport().get_mouse_position())

func boat_at(point: Vector3, team: int) -> PatrolBoat:
	var found: PatrolBoat = null
	var distance: float = 30.0
	for boat in boats:
		var next_distance := Vector2(point.x - boat.position.x, point.z - boat.position.z).length()
		if boat.team == team and not boat.sunk and next_distance < distance:
			found = boat
			distance = next_distance
	return found

func nearest_enemy(boat: PatrolBoat) -> PatrolBoat:
	var best: PatrolBoat = null
	var score: float = INF
	for candidate in boats:
		if candidate.team == boat.team or not candidate.is_combat_capable():
			continue
		var next_score := boat.position.distance_to(candidate.position)
		if next_score < score:
			score = next_score
			best = candidate
	return best

func line_of_sight(from: Node3D, to: Node3D) -> bool:
	## Terrain only. Whether one hull can see another past the islands, which is
	## what decides both whether a missile can be guided onto it and whether it
	## is worth firing one.
	if not is_instance_valid(from) or not is_instance_valid(to):
		return false
	var start: Vector3 = from.global_position + Vector3.UP * 6.0
	var end: Vector3 = to.global_position + Vector3.UP * 4.0
	return get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(start, end, 2)).is_empty()

func clear_shot(boat: PatrolBoat, target: PatrolBoat) -> bool:
	## An unarmed hull has no turret to sight from, and nothing to shoot anyway.
	if not is_instance_valid(boat.turret):
		return false
	var start := boat.turret.global_position + Vector3.UP * 0.6
	var end := target.visuals.to_global(Vector3(0, 4, 0))
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 3, boat.colliders))
	return hit.is_empty() or (hit.collider.get_meta("boat") if hit.collider.has_meta("boat") else null) == target

func position_clear(point: Vector3, ignored: PatrolBoat) -> bool:
	if absf(point.x) > 1800 or absf(point.z) > 1800:
		return false
	for island in islands:
		if Vector2(point.x - island.position.x, point.z - island.position.z).length() < float(island.radius) + 32:
			return false
	for boat in boats:
		if boat == ignored or boat.sunk:
			continue
		if Vector2(point.x - boat.position.x, point.z - boat.position.z).length() < 60:
			return false
	return true

func avoidance(boat: PatrolBoat, heading: Vector3) -> Vector3:
	var result := heading
	for island in islands:
		var away: Vector3 = boat.position - Vector3(island.position)
		away.y = 0
		var margin: float = away.length() - float(island.radius)
		if margin < 100:
			result += away.normalized() * (1.0 - maxf(0, margin - 32) / 68) * 3.0
	for other in boats:
		if other == boat or other.sunk:
			continue
		var away := boat.position - other.position
		if away.length() < 95 and away.length() > 0.1:
			result += away.normalized() * (1 - away.length() / 95) * 3.0
	return result.normalized()

func fire_shell(origin: Vector3, aim: Vector3, exclusions: Array[RID], by_player: bool = false) -> void:
	# Counted here rather than in `shoot()`: this is the one call every main-gun
	# round goes through, and rockets come through `fire_rocket` instead, so
	# accuracy stays a statement about gunnery.
	if by_player:
		tally.shells += 1
	var shell := ShellScript.new()
	shell.world = self
	projectiles.add_child(shell)
	# Small dispersion rewards range management without hiding actual impacts.
	var spread := origin.distance_to(aim) * 0.002
	var target := aim + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
	shell.by_player = by_player
	shell.launch(origin, target, exclusions)
	if not test_mode:
		audio.play_at("gun", origin, -5.0, randf_range(0.94, 1.06))

func make_effect(point: Vector3, color: Color, size: Vector3, lifetime: float) -> Node3D:
	var effect := EffectScript.new()
	effect.lifetime = lifetime
	effects.add_child(effect)
	effect.position = point
	NavalGeometry.box(effect, size, Vector3.ZERO, color)
	return effect

func burst(point: Vector3, color: Color, count: int, duration: float = 0.45) -> void:
	var power := clampf(float(count) / 8.0, 0.35, 2.5)
	var process := Vfx.spark_process(power, 14.0 * power, 13.0)
	process.color_ramp = Vfx.ramp([
		[0.0, Color(color.r * 3.0, color.g * 2.4, color.b * 1.5, 1.0)],
		[0.5, Color(color.r * 1.6, color.g * 0.8, color.b * 0.25, 0.85)],
		[1.0, Color(color.r * 0.4, color.g * 0.1, 0.02, 0.0)]])
	Vfx.one_shot(effects, point,
		Vfx.make_particles(count + 3, maxf(duration, 0.5),
			Vfx.particle_material(Vfx.spark(), true), process, 1.1 * power), 0.25)

func debris(point: Vector3, count: int, force: float = 1.0) -> void:
	for index in range(count):
		var effect := make_effect(point, Color("51574d"), Vector3(randf_range(0.2, 0.8), 0.15, randf_range(0.4, 1.4)), 3.0)
		effect.velocity = Vector3(randf_range(-5, 5), randf_range(2, 6), randf_range(-5, 5)) * force
		effect.spin = Vector3(2, 3, 1)
		effect.gravity = 5

func smoke_puff(point: Vector3, radius: float, lifetime: float, drift: Vector3,
		color: Color, expansion: float = 0.5, heat: float = 0.0) -> Node3D:
	var effect := EffectScript.new()
	effect.lifetime = lifetime
	effect.velocity = drift
	effect.grow = expansion
	effects.add_child(effect)
	effect.position = point
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 4.0
	mesh.mesh = quad
	var material := NavalGeometry.material(color, true)
	material.albedo_texture = smoke_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if heat > 0:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = heat
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.fade_material = material
	effect.fade_alpha = color.a
	effect.add_child(mesh)
	return effect

func missile_smoke(point: Vector3) -> void:
	var jitter := Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))
	smoke_puff(point + jitter, randf_range(0.42, 0.65), 6.0, Vector3(0.65, 0.4, 0.2), Color(0.72, 0.76, 0.75, 0.38), randf_range(0.25, 0.45))

func smoke(point: Vector3, intensity: float) -> void:
	## One-shot burning puff. Continuous compartment fires use FireSource.
	var column := Vfx.smoke_process(0.8 * intensity, 5.0, Vector3(1.6, 1.0, 0.5), true)
	Vfx.one_shot(effects, point + Vector3.UP,
		Vfx.make_particles(5, 3.6, Vfx.particle_material(Vfx.smoke(), false, true),
			column, 3.2 * intensity), 0.4)
	Vfx.one_shot(effects, point,
		Vfx.make_particles(5, 0.7, Vfx.particle_material(Vfx.flame(), true),
			Vfx.fire_process(0.8 * intensity, 5.5), 3.0 * intensity), 0.25)

func foam_patch(point: Vector3, heading: float, size: Vector2, lifetime: float,
		alpha: float, expansion: float) -> Node3D:
	## A soft foam decal lying flat on the swell, following the water surface.
	var effect := EffectScript.new()
	effect.lifetime = lifetime
	effect.grow = expansion
	effect.water = ocean
	effect.follow_water = true
	effects.add_child(effect)
	effect.position = point
	effect.rotation.y = heading
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	quad.orientation = PlaneMesh.FACE_Y
	mesh.mesh = quad
	var material := NavalGeometry.material(Color(0.86, 0.93, 0.93, alpha), true)
	material.albedo_texture = smoke_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.fade_material = material
	effect.fade_alpha = alpha
	effect.add_child(mesh)
	return effect

func oil_slick(point: Vector3, radius: float, lifetime: float = 75.0) -> void:
	## Release fuel at a point. The slick is not a decal: it is handed to the
	## ocean shader, which damps the ripples and lays the film on the water's own
	## surface, so it rides the waves and takes the same light as the sea.
	var spot := Vector2(point.x, point.z)
	var patch := {"position": spot, "radius": minf(radius, SLICK_MAX_RADIUS),
		"age": 0.0, "life": lifetime, "strength": 0.0}
	if slicks.size() < 12:
		slicks.append(patch)
		return
	# At capacity, take over the faintest patch rather than growing an existing
	# one: its strength has already eased to near nothing, so nothing pops, and
	# no patch can be kept alive and inflated indefinitely.
	var faintest := 0
	for index in range(1, slicks.size()):
		if float(slicks[index]["strength"]) < float(slicks[faintest]["strength"]):
			faintest = index
	slicks[faintest] = patch

func update_slicks(delta: float) -> void:
	var packed: Array[Vector4] = []
	for index in range(slicks.size() - 1, -1, -1):
		var slick: Dictionary = slicks[index]
		slick["age"] = float(slick["age"]) + delta
		var age: float = slick["age"]
		var life: float = slick["life"]
		if age > life:
			slicks.remove_at(index)
			continue
		# Oil spreads as it ages and the surface carries it downwind.
		slick["position"] = Vector2(slick["position"]) + Vector2(OIL_DRIFT.x, OIL_DRIFT.z) * OIL_SPEED * delta
		# Spreading tails off against a hard ceiling instead of compounding.
		var radius: float = minf(float(slick["radius"]) * (1.0 + age * SLICK_SPREAD_RATE),
			SLICK_MAX_RADIUS)
		# Eased at both ends: oil surfaces over a few seconds and thins out over
		# a long tail rather than switching off.
		var through: float = age / life
		var strength: float = smoothstep(0.0, 0.10, through) * (1.0 - smoothstep(0.45, 1.0, through))
		slick["strength"] = strength
		var spot: Vector2 = slick["position"]
		packed.append(Vector4(spot.x, spot.y, radius, strength))
	ocean.set_slicks(packed)

func wake(point: Vector3, heading: float, strength: float) -> void:
	# Two diverging shoulder waves plus a churned propeller trail behind them.
	for side in [-1, 1]:
		var offset := Vector3(float(side) * 3.2, 0, 1.2).rotated(Vector3.UP, heading)
		var patch := foam_patch(point + offset, heading + side * 0.30,
			Vector2(3.4, 9.0) * maxf(0.45, strength), 5.5, 0.34 * maxf(0.4, strength), 0.55)
		patch.velocity = Vector3(float(side) * 2.2, 0, 2.0).rotated(Vector3.UP, heading) * strength
	var trail := foam_patch(point + Vector3(0, 0, 2.5).rotated(Vector3.UP, heading), heading,
		Vector2(5.0, 12.0) * maxf(0.45, strength), 7.0, 0.22 * maxf(0.4, strength), 0.4)
	trail.velocity = Vector3(0, 0, 1.2).rotated(Vector3.UP, heading) * strength

func bow_spray(point: Vector3, right: Vector3, strength: float) -> void:
	if strength < 0.3:
		return
	for side in [-1, 1]:
		var spray := smoke_puff(point + right * side * 1.9, 0.34, 1.1,
			right * side * 4.0 * strength + Vector3.UP * 2.2,
			Color(0.86, 0.93, 0.93, 0.55), 0.7)
		spray.gravity = 5.0

func impact(point: Vector3, power: float = 1.0) -> void:
	## A round biting steel: a hard white flash, a short fireball, a spray of
	## sparks and torn plating, and a puff of smoke left hanging.
	Vfx.flash(effects, point, 8.5 * power, Color(4.0, 2.8, 1.4, 1.0), 0.17, 17.0 * power)
	var fire := Vfx.fire_core(0.55 * power, 9.0 * power)
	fire.spread = 70.0
	fire.gravity = Vector3(0, 2.0, 0)
	Vfx.one_shot(effects, point,
		Vfx.make_particles(int(11 * power) + 6, 0.48,
			Vfx.particle_material(Vfx.flame(), true), fire, 3.6 * power), 0.2)
	Vfx.one_shot(effects, point,
		Vfx.make_particles(int(22 * power) + 10, 1.05,
			Vfx.particle_material(Vfx.spark(), true),
			Vfx.spark_process(power, 32.0 * power, 17.0), 1.7 * power), 0.25)
	var soot := Vfx.smoke_process(0.55 * power, 5.0 * power, Vector3(0.7, 0.5, 0.3), true)
	soot.spread = 62.0
	Vfx.one_shot(effects, point,
		Vfx.make_particles(int(5 * power) + 3, 1.9,
			Vfx.particle_material(Vfx.smoke(), false, true), soot, 2.4 * power), 0.25)
	debris(point, int(3 * power) + 2, 1.1 * power)

func muzzle_flash(point: Vector3, direction: Vector3, size: float) -> void:
	## Flash, blast smoke pushed down the barrel line, and a few embers.
	Vfx.flash(effects, point + direction * size * 0.35, size * 2.6,
		Color(2.8, 2.0, 1.0, 1.0), 0.075, 9.0 * size)
	var blow := Vfx.smoke_process(size * 0.32, size * 3.4, direction * 5.0 + Vector3.UP, false)
	blow.direction = direction
	blow.spread = 26.0
	blow.initial_velocity_min = size * 5.0
	blow.initial_velocity_max = size * 11.0
	blow.damping_min = 5.0
	blow.damping_max = 9.0
	blow.color_ramp = Vfx.ramp([
		[0.0, Color(0.70, 0.66, 0.60, 0.0)],
		[0.12, Color(0.52, 0.50, 0.47, 0.55)],
		[0.6, Color(0.42, 0.42, 0.41, 0.32)],
		[1.0, Color(0.40, 0.41, 0.42, 0.0)]])
	Vfx.one_shot(effects, point + direction * size * 0.6,
		Vfx.make_particles(8, 1.0, Vfx.particle_material(Vfx.smoke(), false, true),
			blow, size * 1.5), 0.3)

func splash(point: Vector3, power: float = 1.0) -> void:
	var surface := Vector3(point.x, ocean.height_at(point), point.z)
	# A rising column of spray, then a low ring of droplets falling back.
	var column := Vfx.smoke_process(0.5 * power, 17.0 * power, Vector3(0, -19.0, 0), false)
	column.spread = 13.0
	column.scale_curve = Vfx.curve([[0.0, 0.35], [0.35, 1.0], [1.0, 0.5]])
	Vfx.one_shot(effects, surface,
		Vfx.make_particles(int(11 * power) + 5, 1.6,
			Vfx.particle_material(Vfx.smoke(), false, true), column, 2.4 * power), 0.3)
	var ring := Vfx.spark_process(power, 11.0 * power, 19.0)
	ring.color_ramp = Vfx.ramp([
		[0.0, Color(1.15, 1.25, 1.25, 0.95)],
		[0.55, Color(0.85, 0.95, 0.98, 0.7)],
		[1.0, Color(0.7, 0.82, 0.86, 0.0)]])
	ring.direction = Vector3.UP
	ring.spread = 55.0
	Vfx.one_shot(effects, surface,
		Vfx.make_particles(int(14 * power) + 8, 1.35,
			Vfx.particle_material(Vfx.soft(), false), ring, 0.85 * power), 0.25)

func explosion(point: Vector3, power: float = 1.0) -> void:
	var blast := BlastScript.new()
	blast.world = self
	blast.power = power
	blast.position = point
	effects.add_child(blast)
	camera_shake = minf(1.0, camera_shake + power * 25.0 / maxf(20.0, camera_focus.distance_to(point)))
	if not test_mode:
		audio.play_at("blast" if power >= 0.8 else "blast_small", point,
			-3.0 if power >= 0.8 else -10.0, randf_range(0.85, 1.1))

func cycle_target() -> void:
	## T steps through the hostiles nearest first. `all_units()` hands them back
	## in spawn order, so the unsorted version made the same key press jump to a
	## different part of the map every time — the player could not build any
	## expectation of where it would land.
	var contacts: Array[Node3D] = []
	for boat in all_units():
		if boat.team == 1 and not boat.sunk:
			contacts.append(boat)
	if contacts.is_empty():
		locked_target = null
		return
	var anchor: Vector3 = selected.position if is_instance_valid(selected) else Vector3.ZERO
	contacts.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return anchor.distance_squared_to(a.position) < anchor.distance_squared_to(b.position))
	designate(contacts[(contacts.find(locked_target) + 1) % contacts.size()], true)

func launch_selected_missile() -> void:
	if not is_instance_valid(selected) or selected.sunk:
		return
	if not is_instance_valid(locked_target) or locked_target.sunk:
		cycle_target()
	if selected is CombatHelicopter:
		selected.fire_guided(locked_target)
		return
	if not (locked_target is PatrolBoat):
		report("Use automatic air defenses against aircraft")
		return
	if not selected.launch_missile(locked_target):
		report("Missile / " + selected.missile_status(locked_target))

func fire_missile(origin: Vector3, target: PatrolBoat, source: Node3D) -> void:
	var missile := MissileScript.new()
	missile.world = self
	if source.is_in_group("aircraft"):
		missile.warhead_damage = 170.0
	projectiles.add_child(missile)
	missile.launch(origin, target, source)
	missiles_launched += 1
	if source.team == 1:
		enemy_missiles_launched += 1
	report("%s / missile away → %s" % [source.callsign, target.callsign])
	if source.team != 0 and target == player_ship:
		warn_vampire()
	launch_efflux(origin)
	if not test_mode:
		audio.play_at("launch", origin, -7.0)

func launch_efflux(origin: Vector3) -> void:
	## Booster gas rolling off the deck as a cell fires.
	Vfx.flash(effects, origin, 5.5, Color(2.4, 1.6, 0.7, 1.0), 0.16, 8.0)
	var gas := Vfx.smoke_process(1.3, 7.0, Vector3(0.8, -1.0, 0.4), false)
	gas.spread = 78.0
	gas.damping_min = 3.5
	gas.damping_max = 7.0
	Vfx.one_shot(effects, origin,
		Vfx.make_particles(12, 2.6, Vfx.particle_material(Vfx.smoke(), false, true), gas, 4.0), 0.4)

func report(message: String) -> void:
	notice_until = elapsed + 3.0
	events.push_front(message)
	if events.size() > 4:
		events.resize(4)

func setup_smoke_texture() -> void:
	# One reusable procedural sprite: soft, irregular density instead of solid spheres.
	var texture_image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 49
	noise.frequency = 0.065
	noise.fractal_octaves = 4
	for y in range(96):
		for x in range(96):
			var uv := Vector2(float(x) / 95, float(y) / 95) * 2.0 - Vector2.ONE
			var density := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := clampf(1.0 - uv.length() / (0.74 + density * 0.2), 0, 1)
			var alpha := pow(edge, 0.7) * (0.35 + density * 0.65)
			var shade := 0.78 + density * 0.22
			texture_image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	smoke_texture = ImageTexture.create_from_image(texture_image)

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func capture_preview() -> void:
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = true
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	get_viewport().get_texture().get_image().save_png("res://artifacts/patrol-preview.png")
	get_tree().quit()

func incoming_missile(defender: PatrolBoat, radius: float) -> Node3D:
	var best: Node3D
	var best_time := INF
	for missile in get_tree().get_nodes_in_group("guided_missiles"):
		if missile.detonated or not is_instance_valid(missile.source) or missile.source.team == defender.team:
			continue
		var relative: Vector3 = defender.position - missile.position
		var distance := relative.length()
		if distance > radius or distance < 1:
			continue
		var closing: float = missile.velocity.dot(relative.normalized())
		if closing <= 0:
			continue
		var arrival := distance / maxf(1, closing)
		if arrival < best_time:
			best_time = arrival
			best = missile
	return best

func ciws_burnout(point: Vector3) -> void:
	## End of a 20 mm round's run. Cheap by design: this fires twenty times a
	## second per mount, so most rounds get a sprite and only some get particles.
	Vfx.flash(effects, point, 1.7, Color(2.8, 1.5, 0.7, 1.0), 0.11, 0.0)
	if randi() % 3 != 0:
		return
	var sparks := Vfx.spark_process(0.32, 9.0, 12.0)
	sparks.color_ramp = Vfx.ramp([
		[0.0, Color(4.0, 3.2, 2.2, 1.0)],
		[0.35, Color(3.0, 1.4, 0.45, 0.9)],
		[1.0, Color(1.0, 0.25, 0.05, 0.0)]])
	Vfx.one_shot(effects, point,
		Vfx.make_particles(5, 0.42, Vfx.particle_material(Vfx.spark(), true), sparks, 0.5), 0.15)

func ciws_flash(point: Vector3) -> void:
	Vfx.flash(effects, point, 1.9, Color(2.8, 1.5, 0.6, 1.0), 0.045, 2.6)

func fire_ciws(origin: Vector3, aim: Vector3, exclusions: Array[RID], against_aircraft: bool = false, by_player: bool = false) -> void:
	var tracer := CiwsRoundScript.new()
	tracer.world = self
	projectiles.add_child(tracer)
	var spread := 3.5 if against_aircraft else 0.35
	var dispersion := Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))
	tracer.by_player = by_player
	tracer.launch(origin, aim + dispersion, exclusions)
	ciws_flash(origin)
	if not test_mode and randi() % 5 == 0:
		audio.play_at("ciws", origin, -14.0, randf_range(0.95, 1.08))
	if randi() % 4 == 0:
		smoke_puff(origin, 0.3, 0.9, Vector3.UP * 1.8, Color(0.55, 0.58, 0.58, 0.32), 0.4)

func nearest_aircraft(ship: PatrolBoat, radius: float) -> CombatHelicopter:
	var result: CombatHelicopter
	var best := radius
	for aircraft in get_tree().get_nodes_in_group("aircraft"):
		if aircraft.team == ship.team or not aircraft.is_combat_capable():
			continue
		var distance: float = aircraft.position.distance_to(ship.position)
		if distance < best:
			best = distance
			result = aircraft
	return result

func air_surface_target(aircraft: CombatHelicopter) -> PatrolBoat:
	var result: PatrolBoat
	var best := INF
	for ship in boats:
		if ship.team == aircraft.team or ship.sunk or not (ship.is_combat_capable() or ship.can_engage_air()):
			continue
		var distance := ship.position.distance_to(aircraft.position)
		if distance < best:
			best = distance
			result = ship
	return result

func spawn_helicopter(team: int, point: Vector3 = Vector3.ZERO) -> CombatHelicopter:
	if get_tree().get_nodes_in_group("aircraft").size() >= 6:
		report("Air support limit: six helicopters")
		return null
	var aircraft := HelicopterScript.new()
	aircraft.world = self
	aircraft.team = team
	# We are the Iranian side and they are the US task group, so the heavy Hind
	# is ours and the Apache is theirs. These were the other way round, left over
	# from before the faction reskin — as were the callsigns, which had our own
	# aircraft answering to a US Navy name while the campaign called it Shaheen.
	aircraft.variant = "Hind" if team == 0 else "Apache"
	aircraft.callsign = ("SHAHEEN / " if team == 0 else "VIPER / ") + str(get_tree().get_nodes_in_group("aircraft").size() + 1)
	if point == Vector3.ZERO:
		var base: Vector3 = player_ship.position if is_instance_valid(player_ship) else Vector3.ZERO
		point = base + Vector3(-70 if team == 0 else 70, 55, -70 if team == 0 else 70)
	aircraft.position = point
	aircraft.flight_height = maxf(point.y, 35.0)
	add_child(aircraft)
	report(aircraft.callsign + (" on station" if team == 0 else " inbound"))
	return aircraft

func fire_sam(origin: Vector3, aircraft: CombatHelicopter, ship: PatrolBoat) -> void:
	var sam := SamScript.new()
	sam.world = self
	projectiles.add_child(sam)
	sam.launch(origin, aircraft, ship)
	sams_launched += 1
	report(ship.callsign + " / IR SAM away")
	launch_efflux(origin)

func fire_rocket(origin: Vector3, aim: Vector3, ignored: Array[RID], by_player: bool = false) -> void:
	var rocket := ShellScript.new()
	rocket.world = self
	rocket.damage = 25.0
	rocket.by_player = by_player
	rocket.is_rocket = true
	projectiles.add_child(rocket)
	rocket.launch(origin, aim, ignored)
	Vfx.flash(effects, origin, 3.0, Color(2.6, 1.8, 0.8, 1.0), 0.09, 6.0)
	if not test_mode:
		audio.play_at("rocket", origin, -11.0, randf_range(0.92, 1.12))

func deploy_flares(aircraft: CombatHelicopter, generation: int) -> void:
	for i in range(3):
		var flare := FlareScript.new()
		flare.world = self
		flare.aircraft = aircraft
		flare.burst_id = generation
		flare.position = aircraft.position + Vector3(i - 1, -1, 0)
		flare.velocity = aircraft.velocity * 0.5 + aircraft.basis.x * (i - 1) * 12 + Vector3.DOWN * 2
		effects.add_child(flare)
	report(aircraft.callsign + " / flares")

func detach_part(part: Node3D, impulse: float = 1.0) -> void:
	if not is_instance_valid(part) or not part.visible:
		return
	var wreck = load("res://scripts/wreckage.gd").new()
	wreck.world = self
	effects.add_child(wreck)
	wreck.global_transform = part.global_transform
	var copy: Node3D = part.duplicate()
	wreck.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	part.visible = false
	wreck.velocity = Vector3(randf_range(-7, 7), randf_range(13, 20), randf_range(-7, 7)) * impulse
	wreck.spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2

func cooling_sparks(point: Vector3, power: float = 1.0) -> void:
	Vfx.one_shot(effects, point,
		Vfx.make_particles(int(14 * power) + 6, 2.2,
			Vfx.particle_material(Vfx.spark(), true),
			Vfx.spark_process(power, 13.0 * power, 11.0), 1.3 * power), 0.4)

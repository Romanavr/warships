class_name GameAudio
extends Node
## Every sound in the build is synthesised here at load time — effects and the
## music loops alike. No sample files, same as the art.

const RATE: int = 22050
const MUSIC_RATE: int = 22050
const VOICES: int = 16

static var _bank: Dictionary = {}
static var _music: Dictionary = {}

var voices: Array[AudioStreamPlayer] = []
var voice_index: int = 0
var calm: AudioStreamPlayer
var combat: AudioStreamPlayer
var intensity: float = 0.0
var target_intensity: float = 0.0
var rotor: AudioStreamPlayer
var rotor_level: float = 0.0
var carrier: AudioStreamPlayer
var carrier_level: float = 0.0
var muted: bool = false          # headless: never synthesise at all
var silenced: bool = false       # player preference: synthesised but inaudible
var music_thread: Thread
## Single-threaded fallback: render the two loops across a few frames instead of
## on a worker, for platforms that cannot give us one.
var deferred_music: bool = false
var deferred_step: int = 0

# --------------------------------------------------------------------------- #
# Synthesis helpers
# --------------------------------------------------------------------------- #

static func shape_at(shape: int, phase: float, rng: RandomNumberGenerator) -> float:
	match shape:
		1: return fposmod(phase, 1.0) * 2.0 - 1.0
		2: return 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		3: return rng.randf_range(-1.0, 1.0)
		4: return fposmod(phase, 1.0) * 2.0 - 1.0 + (fposmod(phase * 1.005, 1.0) * 2.0 - 1.0)
	return sin(phase * TAU)

static func add_tone(buffer: PackedFloat32Array, rate: int, at: float, duration: float,
		freq: float, amp: float, shape: int, decay: float, rng: RandomNumberGenerator,
		sweep: float = 1.0, attack: float = 0.002) -> void:
	var start := int(at * rate)
	var count := int(duration * rate)
	var size := buffer.size()
	var phase := 0.0
	for i in range(count):
		var index := start + i
		if index < 0:
			continue
		if index >= size:
			return
		var t := float(i) / float(rate)
		var progress := t / maxf(duration, 0.0001)
		phase += (freq * lerpf(1.0, sweep, progress)) / float(rate)
		var level := exp(-t * decay)
		if t < attack:
			level *= t / attack
		buffer[index] += shape_at(shape, phase, rng) * amp * level

static func low_pass(buffer: PackedFloat32Array, amount: float, from: int = 0, to: int = -1) -> void:
	var last := buffer.size() if to < 0 else mini(to, buffer.size())
	var state := 0.0
	for index in range(from, last):
		state += (buffer[index] - state) * amount
		buffer[index] = state

static func render(buffer: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	var data := PackedByteArray()
	data.resize(buffer.size() * 2)
	for index in range(buffer.size()):
		# Soft clip, so layered hits glue instead of crackling.
		var value: float = buffer[index]
		value = value / (1.0 + absf(value) * 0.55)
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 30000.0))
	sound.data = data
	if loop:
		sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound.loop_begin = 0
		sound.loop_end = buffer.size()
	return sound

static func blank(seconds: float, rate: int) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * rate))
	buffer.fill(0.0)
	return buffer

# --------------------------------------------------------------------------- #
# Effect bank
# --------------------------------------------------------------------------- #

static func bank() -> Dictionary:
	if not _bank.is_empty():
		return _bank
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	# Main gun: a body-hitting thump under a sharp crack.
	var gun := blank(0.65, RATE)
	add_tone(gun, RATE, 0.0, 0.55, 128.0, 0.85, 0, 9.0, rng, 0.34)
	add_tone(gun, RATE, 0.0, 0.16, 320.0, 0.35, 3, 26.0, rng)
	add_tone(gun, RATE, 0.0, 0.4, 62.0, 0.7, 0, 7.0, rng, 0.5)
	low_pass(gun, 0.42)
	_bank["gun"] = render(gun, RATE)

	# Shell striking steel: metallic clang plus a muffled detonation.
	var strike := blank(0.5, RATE)
	for partial: float in [1.0, 1.58, 2.31, 3.02]:
		add_tone(strike, RATE, 0.0, 0.34, 430.0 * partial, 0.24 / partial, 0, 15.0, rng)
	add_tone(strike, RATE, 0.0, 0.1, 900.0, 0.4, 3, 40.0, rng)
	add_tone(strike, RATE, 0.005, 0.3, 95.0, 0.5, 0, 12.0, rng, 0.6)
	_bank["strike"] = render(strike, RATE)

	# The shooter tick that tells you the round connected.
	var marker := blank(0.09, RATE)
	add_tone(marker, RATE, 0.0, 0.07, 2050.0, 0.55, 0, 55.0, rng, 1.15, 0.0008)
	add_tone(marker, RATE, 0.0, 0.05, 3100.0, 0.3, 0, 70.0, rng, 1.1, 0.0008)
	_bank["marker"] = render(marker, RATE)

	# Component destroyed: the same tick, answered an octave down.
	var kill := blank(0.5, RATE)
	add_tone(kill, RATE, 0.0, 0.09, 1650.0, 0.5, 0, 40.0, rng, 1.0, 0.001)
	add_tone(kill, RATE, 0.07, 0.24, 1100.0, 0.42, 0, 18.0, rng)
	add_tone(kill, RATE, 0.14, 0.3, 740.0, 0.36, 0, 13.0, rng)
	_bank["kill"] = render(kill, RATE)

	# Detonations, near and distant.
	_bank["blast"] = render(rumble(2.1, 46.0, 2.6, rng), RATE)
	_bank["blast_small"] = render(rumble(0.9, 78.0, 6.5, rng), RATE)

	# Missile leaving the rail.
	var launch := blank(1.5, RATE)
	add_tone(launch, RATE, 0.0, 1.3, 240.0, 0.55, 3, 3.2, rng)
	add_tone(launch, RATE, 0.0, 0.9, 70.0, 0.6, 0, 4.0, rng, 2.6)
	low_pass(launch, 0.3)
	_bank["launch"] = render(launch, RATE)

	# CIWS: a saw-toothed buzz rather than individual rounds.
	var buzz := blank(0.28, RATE)
	add_tone(buzz, RATE, 0.0, 0.26, 92.0, 0.5, 2, 5.0, rng)
	add_tone(buzz, RATE, 0.0, 0.26, 1300.0, 0.2, 3, 9.0, rng)
	low_pass(buzz, 0.55)
	_bank["ciws"] = render(buzz, RATE)

	# Rotor loop for direct helicopter flight.
	var blades := blank(0.55, MUSIC_RATE)
	for beat in range(5):
		add_tone(blades, MUSIC_RATE, float(beat) * 0.11, 0.1, 58.0, 0.5, 0, 18.0, rng, 0.8)
		add_tone(blades, MUSIC_RATE, float(beat) * 0.11, 0.08, 520.0, 0.09, 3, 26.0, rng)
	low_pass(blades, 0.5)
	_bank["rotor"] = render(blades, MUSIC_RATE, true)

	# Wave klaxon and the all-clear.
	var klaxon := blank(1.6, RATE)
	for repeat in range(2):
		var at := float(repeat) * 0.62
		add_tone(klaxon, RATE, at, 0.5, 262.0, 0.4, 2, 4.5, rng, 1.0, 0.02)
		add_tone(klaxon, RATE, at, 0.5, 350.0, 0.28, 2, 4.5, rng, 1.0, 0.02)
	low_pass(klaxon, 0.35)
	_bank["alarm"] = render(klaxon, RATE)

	var cleared := blank(1.4, RATE)
	var chord: Array[float] = [392.0, 523.25, 659.25, 784.0]
	for step in range(chord.size()):
		add_tone(cleared, RATE, float(step) * 0.1, 1.0, chord[step], 0.3, 0, 3.2, rng, 1.0, 0.01)
	_bank["cleared"] = render(cleared, RATE)

	# Hull warning.
	var warn := blank(0.7, RATE)
	add_tone(warn, RATE, 0.0, 0.28, 620.0, 0.34, 2, 6.0, rng, 1.0, 0.01)
	add_tone(warn, RATE, 0.34, 0.28, 466.0, 0.34, 2, 6.0, rng, 1.0, 0.01)
	_bank["warn"] = render(warn, RATE)

	# Rockets and cannon from the helicopter.
	var rocket := blank(0.5, RATE)
	add_tone(rocket, RATE, 0.0, 0.45, 300.0, 0.4, 3, 8.0, rng)
	add_tone(rocket, RATE, 0.0, 0.3, 110.0, 0.45, 0, 9.0, rng, 2.2)
	low_pass(rocket, 0.4)
	_bank["rocket"] = render(rocket, RATE)

	# Missile inbound. A missile-warning receiver, not a klaxon: three short
	# urgent pips that carry over the guns without smothering them.
	var vampire := blank(1.1, RATE)
	for pip in range(3):
		var at := float(pip) * 0.17
		add_tone(vampire, RATE, at, 0.12, 1180.0, 0.30, 2, 26.0, rng, 1.08, 0.003)
		add_tone(vampire, RATE, at, 0.12, 1770.0, 0.16, 0, 30.0, rng, 1.08, 0.003)
	low_pass(vampire, 0.62)
	_bank["vampire"] = render(vampire, RATE)

	# Crate collected: a bright rising pair.
	var pickup := blank(0.7, RATE)
	add_tone(pickup, RATE, 0.0, 0.2, 784.0, 0.34, 0, 9.0, rng, 1.0, 0.004)
	add_tone(pickup, RATE, 0.09, 0.42, 1174.0, 0.32, 0, 6.0, rng, 1.0, 0.004)
	add_tone(pickup, RATE, 0.09, 0.42, 1568.0, 0.18, 0, 6.0, rng, 1.0, 0.004)
	_bank["pickup"] = render(pickup, RATE)

	# --- radio ------------------------------------------------------------- #
	# A voice net has three sounds and none of them is speech: the click as the
	# handset keys, the hiss of an open carrier, and the squelch tail when it
	# unkeys. Together they say "someone is talking to you" without a word.
	var open_net := blank(0.42, RATE)
	# Relay click.
	add_tone(open_net, RATE, 0.0, 0.018, 1850.0, 0.5, 3, 180.0, rng, 1.0, 0.0004)
	add_tone(open_net, RATE, 0.0, 0.03, 620.0, 0.34, 0, 90.0, rng, 0.7, 0.0006)
	# Carrier catching, then settling into a steady hiss.
	add_tone(open_net, RATE, 0.02, 0.34, 4200.0, 0.18, 3, 7.0, rng)
	add_tone(open_net, RATE, 0.02, 0.30, 1400.0, 0.10, 3, 5.0, rng)
	# The band-limited, slightly resonant colour of a comms speaker.
	low_pass(open_net, 0.42, int(0.02 * RATE))
	add_tone(open_net, RATE, 0.03, 0.2, 980.0, 0.06, 0, 9.0, rng, 1.02)
	_bank["radio_open"] = render(open_net, RATE)

	# Unkeying: the carrier drops and the squelch snaps shut behind it.
	var close_net := blank(0.3, RATE)
	add_tone(close_net, RATE, 0.0, 0.09, 3600.0, 0.16, 3, 26.0, rng)
	low_pass(close_net, 0.4)
	add_tone(close_net, RATE, 0.07, 0.02, 1500.0, 0.34, 3, 200.0, rng, 1.0, 0.0004)
	add_tone(close_net, RATE, 0.07, 0.04, 520.0, 0.22, 0, 70.0, rng, 0.6, 0.0006)
	_bank["radio_close"] = render(close_net, RATE)

	# Held under the line while it types: quiet open-carrier hiss, looped.
	var carrier := blank(0.55, RATE)
	add_tone(carrier, RATE, 0.0, 0.55, 3800.0, 0.052, 3, 0.0, rng)
	add_tone(carrier, RATE, 0.0, 0.55, 1250.0, 0.030, 3, 0.0, rng)
	low_pass(carrier, 0.38)
	_bank["radio_carrier"] = render(carrier, RATE, true)

	return _bank

static func rumble(duration: float, bass: float, decay: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buffer := blank(duration, RATE)
	var filtered := 0.0
	var count := buffer.size()
	for i in range(count):
		var t := float(i) / float(RATE)
		filtered = lerpf(filtered, rng.randf_range(-1, 1), 0.19)
		var value := (filtered * 0.75 + sin(t * TAU * bass) * 0.4) * exp(-t * decay)
		buffer[i] = value * minf(1.0, t * 220.0)
	return buffer

# --------------------------------------------------------------------------- #
# Music
# --------------------------------------------------------------------------- #

static func music(name: String) -> AudioStreamWAV:
	if _music.has(name):
		return _music[name]
	_music[name] = build_track(name == "combat")
	return _music[name]

static func build_track(hot: bool) -> AudioStreamWAV:
	## Eight bars of driving minor-key action, looped. The calm variant drops
	## the drums and the lead so the two can be crossfaded between waves.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bpm := 138.0
	var beat := 60.0 / bpm
	var step := beat * 0.25          # sixteenth
	var bar := beat * 4.0
	var bars := 8
	var buffer := blank(bar * float(bars) + 0.6, MUSIC_RATE)

	# i - VI - III - VII in D minor, two bars each.
	var roots: Array[float] = [73.42, 58.27, 87.31, 65.41]
	var triads: Array = [
		[293.66, 349.23, 440.00],
		[233.08, 293.66, 349.23],
		[349.23, 440.00, 523.25],
		[261.63, 329.63, 392.00]]
	var kick_steps: Array[int] = [0, 6, 10]
	var snare_steps: Array[int] = [4, 12]

	for bar_index in range(bars):
		var chord := (bar_index / 2) % 4
		var root: float = roots[chord]
		var triad: Array = triads[chord]
		var bar_at := float(bar_index) * bar

		if hot:
			for s: int in kick_steps:
				add_tone(buffer, MUSIC_RATE, bar_at + float(s) * step, 0.22, 118.0, 0.85, 0, 22.0, rng, 0.36)
			if bar_index % 4 == 3:
				add_tone(buffer, MUSIC_RATE, bar_at + 14.0 * step, 0.18, 118.0, 0.7, 0, 24.0, rng, 0.38)
			for s: int in snare_steps:
				var at := bar_at + float(s) * step
				add_tone(buffer, MUSIC_RATE, at, 0.2, 1500.0, 0.3, 3, 24.0, rng)
				add_tone(buffer, MUSIC_RATE, at, 0.16, 205.0, 0.28, 0, 20.0, rng, 0.75)
			for s in range(0, 16, 2):
				var accent: float = 0.12 if s % 4 == 0 else 0.07
				add_tone(buffer, MUSIC_RATE, bar_at + float(s) * step, 0.06, 7200.0, accent, 3, 70.0, rng)

		# Bass: eighth-note pulse with a fifth lift in the second half.
		for s in range(0, 16, 2):
			var note := root
			if s >= 10 and s % 4 == 2:
				note = root * 1.5
			add_tone(buffer, MUSIC_RATE, bar_at + float(s) * step, 0.24, note,
				0.5 if hot else 0.34, 1, 7.0, rng)

		# Pad: the triad held under everything.
		for note: float in triad:
			add_tone(buffer, MUSIC_RATE, bar_at, bar * 1.02, note * 0.5,
				0.075 if hot else 0.1, 4, 0.5, rng, 1.0, 0.35)

		if hot:
			# Sixteenth arpeggio riding on top.
			for s in range(16):
				if s % 2 == 1 and s % 8 != 3:
					continue
				var note: float = triad[(s / 2) % triad.size()]
				if bar_index % 2 == 1 and s >= 8:
					note *= 2.0
				add_tone(buffer, MUSIC_RATE, bar_at + float(s) * step, 0.2, note, 0.13, 2, 11.0, rng)

	low_pass(buffer, 0.55 if hot else 0.3)
	return render(buffer, MUSIC_RATE, true)

# --------------------------------------------------------------------------- #
# Playback
# --------------------------------------------------------------------------- #

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if muted:
		# Headless runs skip synthesis entirely; it is the slowest part of load.
		return
	bank()
	for index in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		voices.append(player)
	calm = AudioStreamPlayer.new()
	calm.volume_db = -60.0
	add_child(calm)
	combat = AudioStreamPlayer.new()
	combat.volume_db = -60.0
	add_child(combat)
	# Rendering the two loops costs about a second, so it happens off the main
	# thread and the tracks fade in whenever they are ready.
	#
	# The web build may have no threads at all: a browser only grants them with
	# COOP/COEP headers, and a single-threaded export has none. Rather than
	# stall the first second of play there, the music is rendered a slice at a
	# time from _process and fades in when it is ready.
	if _music.has("calm") and _music.has("combat"):
		start_music()
	elif OS.get_name() == "Web":
		set_process(true)
		deferred_music = true
	else:
		music_thread = Thread.new()
		music_thread.start(render_music)
	rotor = AudioStreamPlayer.new()
	rotor.stream = _bank["rotor"]
	rotor.volume_db = -60.0
	add_child(rotor)
	rotor.play()
	# Open-carrier hiss, held under a radio line for as long as it is on screen.
	carrier = AudioStreamPlayer.new()
	carrier.stream = _bank["radio_carrier"]
	carrier.volume_db = -60.0
	add_child(carrier)
	carrier.play()

func render_music() -> void:
	music("calm")
	music("combat")
	call_deferred("start_music")

func start_music() -> void:
	if music_thread != null and music_thread.is_started():
		music_thread.wait_to_finish()
		music_thread = null
	if calm == null or not _music.has("calm"):
		return
	calm.stream = _music["calm"]
	combat.stream = _music["combat"]
	calm.play()
	combat.play()

func _notification(what: int) -> void:
	# The synthesised streams live in static caches so a restart does not pay to
	# render them again — but that outlives the object database, which reports
	# them as leaks at shutdown. Release them when the window is actually closing.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		release()
		_bank.clear()
		_music.clear()

func _exit_tree() -> void:
	if music_thread != null and music_thread.is_started():
		music_thread.wait_to_finish()
		music_thread = null
	release()

func release() -> void:
	## Drop the playbacks. The rendered streams stay in the static cache so a
	## restart does not pay for the synthesis again.
	Comms.release()
	Vfx.release()
	for player: AudioStreamPlayer in [calm, combat, rotor, carrier] + voices:
		if player != null:
			player.stop()
			player.stream = null

func set_silenced(value: bool) -> void:
	silenced = value
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, silenced)


func toggle_silence() -> bool:
	set_silenced(not silenced)
	return silenced

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if muted or silenced or not _bank.has(name):
		return
	var player := voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	player.stream = _bank[name]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

func play_at(name: String, point: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	## Distance-attenuated, but still a plain stereo voice: spatial players are
	## overkill for a camera that is always looking down at the action.
	if muted or silenced or not _bank.has(name):
		return
	var listener: Vector3 = get_parent().camera_focus if get_parent().camera != null else Vector3.ZERO
	var distance := listener.distance_to(point)
	if distance > 2200.0:
		return
	play(name, volume_db - clampf(distance / 26.0, 0.0, 34.0), pitch)

func set_intensity(value: float) -> void:
	target_intensity = clampf(value, 0.0, 1.0)

func set_rotor(value: float) -> void:
	rotor_level = clampf(value, 0.0, 1.0)

func set_carrier(value: float) -> void:
	## How open the net is, 0..1. Comms fades this up while a line is on air.
	carrier_level = clampf(value, 0.0, 1.0)

func key_radio() -> void:
	play("radio_open", -9.0, randf_range(0.94, 1.06))

func unkey_radio() -> void:
	play("radio_close", -12.0, randf_range(0.94, 1.06))

func _process(delta: float) -> void:
	if deferred_music:
		# One track per frame, so the hitch is two short ones rather than a
		# second-long freeze the moment the game starts.
		match deferred_step:
			0: music("calm")
			1: music("combat")
			2:
				start_music()
				deferred_music = false
		deferred_step += 1
		return
	if muted or calm == null or calm.stream == null:
		return
	intensity = move_toward(intensity, target_intensity, delta * 0.7)
	calm.volume_db = linear_to_db(clampf((1.0 - intensity) * 0.5, 0.0005, 1.0)) - 6.0
	combat.volume_db = linear_to_db(clampf(intensity * 0.62, 0.0005, 1.0)) - 6.0
	rotor.volume_db = linear_to_db(clampf(rotor_level * 0.5, 0.0005, 1.0)) - 6.0
	if carrier != null:
		carrier.volume_db = linear_to_db(clampf(carrier_level * 0.34, 0.0005, 1.0)) - 6.0

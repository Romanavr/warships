# 3DGame — Littoral

### ▶ **[Play in your browser — warships.romanavr.com](https://warships.romanavr.com/)**

Or download for **[macOS or Windows](https://github.com/Romanavr/warships/releases/latest)**.

---

A single-player 3D naval game in Godot 4.7.2, using GDScript. Original ships,
aircraft, ocean and effects; no external assets or plugins — every mesh,
material, texture and sound is generated at runtime or built from the Blender
scripts in `tools/`.

It is built around one idea: **you shoot at parts of a ship, not at the ship.**
Every module — the forward gun, the funnel, the radar, the launchers, the
steering gear — has a place on the hull, health of its own and a consequence for
losing it. The HUD exists to make choosing between them a decision rather than a
guess: point at a module and it tells you what killing it would cost her.

## Play

**In the browser:** <https://warships.romanavr.com/>

**From source:** double-click **Play.command**, or

```sh
godot --path . -- --start-paused
```

The game opens on a choice of two:

- **Campaign** — four scripted levels in the Strait of Hormuz. It starts by
  teaching the mechanic: stop a merchant by destroying her engine room, without
  sinking her. Then missile-armed patrol craft, a gunship duel you fly yourself,
  and a corvette that outranges you.
- **Duel** — one corvette against one. No orders, no escorts, everything
  released from the first second.

English and Russian, switchable on the menu.

### Controls

| | |
|---|---|
| `W A S D` | helm |
| `LMB` | guns, at the pointer |
| `X` | anti-ship missile at the designated contact |
| `T` | designate the next contact, nearest first |
| `TAB` | swap between the ship and the gunship |
| `MMB` drag | orbit the camera · `Shift` to slide it |
| `Esc` | pause — which lists all of the above |

Press **Tab** at any time to leave the bridge and fly the gunship yourself; the
AI crew takes the helm while you are away, and Tab brings you back. A hostile
stops counting once its weapons are gone — you do not have to sink every hull.

**Supply crates** float in the sector: two are dropped within reach at the start
of every wave, and every hostile you destroy leaves one behind. Green crates
repair the hull, fight fires and pump out flooding; gold crates reload anti-ship
missiles and top up the CIWS and SAM racks. Drive over one to take it — whatever
you are controlling at the time is what gets resupplied.
Open **SYSTEMS** for component damage and a couple of sandbox spawn buttons.

## Current build

### Art and rendering

- **Authored corvette hull.** `assets/models/kestrel.glb` — a Blender-built
  54 m hull, imported and driven directly: `bow`/`mid`/`stern` compartments,
  `gunPivot`/`aft_gunPivot`/`CiwsPivot`/`RadarPivot` mounts, `CellLid0-3` and
  `SamLid0-3` hatches, and barrels sitting at the same z = -3.5 rest position
  the recoil code already used. Hostile hulls get a warm overlay wash so they
  read as a different navy. The wash **multiplies** rather than mixing: a mix
  blend paints a flat colour over the hull and takes the panel detail with it,
  while multiplying darkens and shifts the hue with every bit of relative
  contrast surviving underneath. The
  procedural hull below is still in the project and is used automatically if the
  model is missing.
- **Procedural fallback hull.** Generated from a station table with real sheer,
  bow flare, a bilge turn and a transom, split into bow/citadel/stern surfaces so
  each compartment can char and shed plating independently. Boot topping and
  antifouling are painted in by vertex colour, and the pennant number is drawn
  onto the flare of the bow plating.
- **Authored superstructure.** Faceted low-observable deckhouse and gun houses,
  raked bridge glazing with bridge wings, a raked tripod mast, a rotating search
  radar, a funnel with shielded uptakes, a Phalanx-style CIWS with radome and
  barrel cluster, vertical launch modules with hinged hatches, railings,
  liferaft canisters, bollards, a RIB in a davit bay and a marked flight deck.
  The 28 m Tern gets a compact single-level variant of the same kit.
- **Batched geometry.** `NavalGeometry.Builder` accumulates every primitive into
  one surface per material, so a fully detailed corvette is about a dozen draw
  calls rather than two hundred.
- **Plated-steel materials.** A procedural normal map with weld seams plus a
  weathering roughness map, triplanar-mapped so no UVs are needed. Armoured
  glazing is a separate low-roughness material that mirrors the sky; navigation
  lights are unshaded and bloom through the environment glow.
- **Gerstner ocean.** Five incommensurate swell waves with horizontal crest
  displacement, over a seven-octave wind-wave spectrum built from gradient noise
  with analytic derivatives — each octave rotated and drifting at its own rate,
  so the surface never resolves into a grid. Water is treated as a mirror rather
  than a coloured surface: a dark body colour, Fresnel-weighted sky reflection,
  light scattering through lifted crests, and a very tight specular lobe riding
  the fine normals that produces the sun-glitter path. Foam appears where the
  Gerstner Jacobian shows the swell folding in on itself, plus animated surf
  keyed to the island footprints. CPU buoyancy inverts the same displacement, so
  hulls sit on the crest that is actually drawn.
- **Effect budgets.** Alpha-blended smoke is paid for in overdraw, so it is
  rationed: a hull shows at most three burning compartments at once (the worst
  three), one-shot bursts are capped at 64 live emitters, and every emitter uses
  few, dense, short-lived particles rather than many large faint ones. A
  deliberately overloaded sector — every hull on the board fully ablaze — runs at
  ~134 fps with a 17 ms worst frame on an M5 Pro (`tests/perf.gd`).
- **Fire in six layers.** A wide, slow seat of fire hugging the deck; an
  alpha-blended flame body that gives the fire mass and a dark edge; a white-hot
  core; additive tongues stretched along their own velocity
  (`TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY`, so they rise as licks rather
  than tumbling blobs); embers carried up the column; and smoke that leaves the
  flame lit before it cools to soot. Purely additive fire blows out against a
  bright sky and has no mass — the alpha pass under the additive ones is what
  makes it read as burning rather than glowing.
- **Effects are GPU particles.** `Vfx` generates its own sprite sheet — soft
  glow, cloud, ragged flame, spark and tracer streak — and builds the emitters
  from it: rolling fireballs with an HDR white-hot-to-soot colour ramp, rising
  smoke columns, thrown embers, spray columns, barrel-blast smoke and rocket
  efflux. Damaged compartments each keep a persistent `FireSource` (flame,
  smoke column, flickering glow) whose output tracks the fire value, so a
  burning ship smokes continuously instead of puffing.
- **Rockets and missiles leave a mark.** Helicopter rockets carry a motor plume
  and a fat smoke trail that hangs in the air behind them; anti-ship missiles and
  SAMs lay a heavier trail still, lit by a glow at the nozzle, and the smoke is
  detached to drift on after the warhead goes off.
- **Oil is part of the water, not a decal on it.** A sinking hull hands the
  ocean shader a list of slicks — `(x, z, radius, strength)` — and the film is
  shaded as part of the sea surface, so it rides the same waves and takes the
  same light. Drawn as separate quads it always read as a sticker, because a
  flat plane floating above the swell has none of the water's shape.

  Three things make it read as oil. It **damps the short waves**, which is the
  strongest cue of all — the ripple detail is cut inside the footprint and the
  roughness drops to 0.018, so the patch goes glassy and mirrors the sky.
  **Thin-film interference** gives the rainbow: an optical path length from film
  thickness, sampled against three wavelengths, banded so a real sheen is silver
  where the film is thinnest, iridescent through a middle band, and brown where
  it is heavy enough to stop interfering. And **domain-warped noise** breaks the
  footprints into meandering ribbons with frayed edges and holes — one warp
  evaluation shapes every slick at once, so the cost does not scale with how
  many are on the water.
- **CIWS reads as 20 mm, not as gun shells.** Thin red tracers rather than the
  fat orange streaks of the main battery, and rounds that miss **self-destruct
  at the end of their run** in a shower of sparks — the burst you see at the far
  end of a real CIWS engagement. It fires twenty times a second per mount, so
  most rounds get a sprite flash and only some get particles.
- **Visible ordnance.** Shells and CIWS rounds are drawn as a hot unshaded core
  wrapped in crossed additive glow strips, long enough to read as a continuous
  streak between frames, with a travelling light on main-gun rounds. Guns get a
  flash, a light and blast smoke down the barrel line; missiles and SAMs carry a
  live exhaust plume that lays a smoke trail and leaves it hanging after the
  warhead goes off.
- **Sky and light.** A procedural sky shader with two drifting cloud decks, a
  sun disc and aureole; ACES tonemapping, sky-sourced ambient and reflections,
  screen-space reflections, SSAO, depth fog with aerial perspective, and a
  three-light rig (warm key, cool anti-sun fill, weak sea bounce).
- **Gunships.** Two airframes from one parts kit, lofted through station tables
  like the hulls. The heavy variant follows the Mi-24 layout: stepped tandem
  bubble canopies over a fat troop cabin with portholes, a chin gatling turret,
  anhedral stub wings on heavy pylons with end plates, rocket pods and wingtip
  launch tubes, engine nacelles with dust-filter intakes and canted exhausts, a
  five-blade head over a mast fairing, and a port-side tail rotor. The light
  variant is a slimmer tandem-seat machine on four blades. Both carry a faint
  rotor disc so the head reads as turning rather than strobing.
- **Wakes.** Diverging shoulder waves and a churned propeller trail drawn as soft
  foam decals that ride the swell instead of flat plates.

### Interface

- **Look-ahead camera in direct control.** The view leads along your course in
  proportion to speed and peeks toward the cursor, and pulls back a little at
  speed, so you are looking at the water you are steering into rather than at
  your own wake. It eases in and out, so a course change swings the view across
  instead of snapping. Orbit, tilt, zoom and middle-drag pan all still override
  it, and RTS mode is unchanged.
- Tactical HUD drawn procedurally: clipped-corner panels with accent stripes,
  letter-spaced headings, segmented readouts and reload dials.
- **Condition is one line under the reticle**: a hull bar and a percentage,
  directly above the ammunition row where your eye already is. Flooding, fire
  and the damage-control cooldown only take up room when they are actually
  happening. The bottom-left corner carries only identity — who you are, what
  you are doing, how fast you are going — with the gunship's card above it.
- **Readouts are pictures, not squares.** Ammunition is drawn as the thing it
  actually is — missile silhouettes for anti-ship and SAM racks and helicopter
  stores, shells for gun rounds, rocket bodies for pods, starbursts for flares, a
  muzzle-and-cone for the CIWS, a shield for hull, a droplet for flooding and a
  flame for fire. Spent rounds stay as dim outlines of the same shape.
- Mission panel with objective, elapsed clock and a live force count; a fading
  event feed underneath.
- **Radar** centred on the unit you are controlling and rotated to match the
  camera, so up on the display is forward on screen. Labelled range rings, the
  camera's view wedge shaded in, a rotating north needle, your own hull as a
  chevron pointing where the bow is, supply crates as squares, inbound missiles
  as pulsing diamonds, and contacts past the 2.4 km edge riding the rim as
  wedges rather than disappearing.
- **Off-screen contact arrows** around the edge of the play area: every hostile
  and every supply crate that is not currently in frame gets an arrow pointing
  at it with its range, including contacts behind the camera. On-screen hostiles
  carry a range readout of their own.
- **SYSTEMS** opens damage control: per-component health, fire indicators, and a
  line under each module saying what losing it actually costs — the same effects
  apply to a hostile hull, which is what makes choosing an aim point a decision
  rather than a guess.

### Display and performance

Performance is measured **fullscreen at the display's native resolution**, not
in a window — on a Retina panel a 1280x800 window is under a seventh of the
pixels, so a windowed number says nothing about how the game actually runs.

The 2D stretch mode that keeps the HUD the right physical size on a Retina panel
also sizes the root viewport well above the window's true pixel count. Left
alone that had the 3D supersampling itself: **43 Mpx of rendering for a 7.5 Mpx
display.** `patrol.gd` pins `Viewport.scaling_3d_scale` so the 3D buffer matches
the window's real pixel count, which touches only the 3D pass and leaves the HUD
crisp. The root render target changes on resize, fullscreen and display moves,
and not all of those notify before the texture is resized, so the scale is
watched directly each frame rather than driven off a signal.

On a 3456x2234 MacBook panel, fullscreen, with the sector deliberately
overloaded — every hull ablaze and two of them sinking and laying oil:

| | 3D pixels | avg | worst | fps |
| --- | --- | --- | --- | --- |
| Before | 43.0 Mpx | 19.4 ms | 23.9 ms | 51 |
| Render scale fixed | 7.5 Mpx | 6.0 ms | 9.0 ms | 167 |
| + TAA, 4x MSAA, 16x aniso, FSR | 7.5 Mpx | 7.5 ms | 14.8 ms | **134** |

Image quality on top of that: **TAA**, 4x MSAA and 16x anisotropic filtering.
The ocean's fine wind-wave octaves and the water's specular are both sub-pixel
at native resolution, and no amount of MSAA touches shader aliasing — TAA is
what stops the sea crawling. Because the 3D buffer is upscaled into the
oversized root before the display downsamples it again, the upscale uses **FSR**
rather than a plain bilinear stretch, for the sharpening pass that survives that
round trip. Together those cost about 20% of frame time and are what took the
picture from noisy to sharp.

**F11** toggles fullscreen and **RENDER** cycles the 3D resolution (100 / 85 /
70 / 55%) if you ever want more headroom; both are saved to
`user://settings.cfg` alongside the mute setting and restored next launch.

```sh
godot --path . --script tests/perf_fullscreen.gd   # the number that matters
godot --path . --script tests/perf.gd              # quick windowed check
```

### Sound

- **Mute on M**, or the ♪ button in the toolbar. Saved with the display
  settings and restored next launch; headless runs never read or write the
  settings file, so a test run cannot leave the game silent.
- **Everything is synthesised at load**, like the art: gun report, shell strike,
  the reticle tick, a destroyed-component two-tone, detonations, rocket and
  missile efflux, the CIWS buzz, a rotor loop, klaxon and all-clear.
- **Two music loops**, eight bars each of driving minor-key action built from a
  kick/snare/hat kit, a saw bass, a held pad and a sixteenth arpeggio. The calm
  and combat mixes crossfade with the state of the fight. Rendering them costs
  about a second, so it runs on a worker thread and fades in when ready.

### Simulation

- Direct control of the corvette at all times, with a gunship you can take over
  with Tab; the unit you leave is flown by its AI crew.
- Three scripted waves with a briefing countdown, a wave banner, live hostile
  count and a full repair and rearm before the corvette duel.
- Smaller 28 m Tern patrol boats: higher speed, much lower component durability,
  one gun and two anti-ship missiles. **No CIWS and no SAM** — fitted with a
  close-in mount they swat the player's missiles and end up harder to sink than
  the corvette they escort. Restoring it is a difficulty setting, written up in
  `docs/ROADMAP.md`.
- Helicopters choose air or surface threats autonomously, using distance, incoming
  aggression, air-defense capability and remaining ammunition. Each also carries two
  IR air-to-air missiles and a finite cannon magazine.
- Detached gun assemblies, radar and bridge wreckage tumble and splash into the sea.
  Hull breaches shed plates. Explosions finish with cooling, gravity-driven sparks;
  CIWS has layered tracer streaks, muzzle flashes and impact sparks.
- Larger **54 m corvettes** in a 3.6 km sector, with forward and aft guns (600 m range,
  3.2/3.6 second reload).
- **Four anti-ship missiles** per ship, 1,400 m range, eight seconds between launches.
  Physical VLS cells open individually; fired launch structures remain.
- **CIWS** with 120 rounds, tracking, dispersion, cooling breaks and actual intercepting
  tracers. Prioritizes incoming missiles within 190 m; engages helicopters within 150 m
  with weaker, dispersed fire.
- **Four IR SAMs** per ship, 850 m range and eight-second reload, launched automatically
  from a separate deck battery.
- **Collision covers the hull you can see.** The compartment boxes run keel to
  deck edge, not keel to waterline. They used to stop at y = 2.8 while the guns
  aimed at 3.3, so a perfectly aimed shell flew over every box and passed
  through the ship without registering — `tests/player.gd` now rakes the hull
  with rays at deck height and fails if any band is uncovered.
- **Magazine detonation.** A hit into a loaded launch bank has a small chance
  of taking the magazine with it — scaled by the weight of the hit and how many
  cells are still live. The ship is gone instantly, a ring of blast races out
  across the water, and anything within 190 m takes serious damage. It is the
  one place in the build with an expanding shockwave ring, because it is the one
  place that earns it. It can happen to you too.
- **13 independently damaged components:** three hull compartments, two guns, engine,
  steering, bridge, radar, two VLS banks, CIWS and SAM battery.
- Damaging fires, compartment spread, leaks, flooding, progressive sinking and irregular
  secondary explosions.
- **Missile doctrine.** A crew that empties four cells into a working CIWS
  learns nothing. Enemy ships send a couple of missiles and *wait* to see
  whether they arrive. If they are being swatted, the crew stops launching and
  puts its guns on the mount doing the swatting — aiming at the CIWS
  specifically rather than centre of mass — and resumes missile fire once it is
  gone. If the probes get through, the rest follow. Learning resets on a new
  contact.
- **Breaking up.** A hull lost to a catastrophic hit comes apart: mounts cook
  off and go over the side one after another, the bridge and radar are carried
  away, a ring of blast rolls out across the water, and secondary explosions
  walk along the hull as she goes down. The ring is visual only — the one that
  reaches other ships is a magazine detonation, and it earns that by being rare.
- Surface AI switches away from ships without usable offensive weapons. Losing propulsion
  alone does not remove a threat. Helicopters also recognize functioning ship air defenses
  as threats.
- Apache- and Hind-inspired AI helicopters with **four guided air-to-surface missiles,
  eight rockets and three flare packs** each. Physical weapon hardpoints, animated rotors,
  evasive turns and falling wrecks. Flares can divert IR seekers but do not guarantee survival.

## Controls

Arcade *weapons*, honest *handling*: a hostile is always designated so a missile
always has somewhere to go — but the ship is
still a ship. The wheel is an order to the rudder, not to the bow: the rudder
takes about half a second to swing hard over, it only bites once water is moving
past it, and the hull carries its own momentum so a turn skids before the ship
follows. Dead in the water you cannot steer at all. Get way on before you need
to manoeuvre.

The four handling constants sit at the top of `scripts/boat.gd`: `HELM_RATE`
(how fast the rudder swings), `TURN_RATE` (how hard it bites), `FLOW_SPEED` (how
much way you need for full rudder authority) and `DRIFT_RESPONSE` (how much the
hull skids through a turn).

| Input | Ship | Gunship |
| --- | --- | --- |
| W / S | Throttle ahead / astern | Forward / back |
| A / D | Helm to port / starboard | Turn |
| Mouse | Aim the guns | Aim rockets |
| LMB | Fire both mounts | Rockets, or cannon against a locked aircraft |
| RMB or X | Launch an anti-ship missile | Launch a guided missile |
| Space / Shift | — | Climb / descend |
| Z | — | Flares |
| Tab | Take the gunship | Return to the ship |
| T | Designate the next contact | Designate the next contact |
| C | Damage control party | — |
| M | Mute / unmute all sound | Mute / unmute all sound |
| F11 | Fullscreen / windowed | Fullscreen / windowed |
| H | Send the gunship at your designated contact, or release it to escort | — |
| I | CIWS free / held | — |
| Q / E, Up / Down | Orbit and tilt camera | Orbit and tilt camera |
| Wheel / middle drag | Zoom / pan | Zoom / pan |
| V / F1 | Camera preset / hide HUD | Camera preset / hide HUD |
| Esc or P / R | Pause / restart | Pause / restart |
| G / F | Watch the designated contact / recentre | Watch / recentre |

**You choose the aim point, including which part of a hull to hit.** The pointer
is raycast into the world, so aiming at the CIWS mount puts the shell on the
CIWS mount. The only help given is lead: the shot is displaced by however far the
target will travel while the shell is in the air, so travel time is not something
to fight, but picking the bridge over the waterline still is. Whatever you shoot
at becomes the designated contact automatically.

SAMs and the CIWS fight for themselves; the SYSTEMS panel shows what is broken
and what is on fire.

## What each module does

The same rules apply to you and to them, so the panel doubles as a target list.

| Module | Losing it costs |
| --- | --- |
| Bow / citadel / stern hull | Leaks below half strength; all three gone and she sinks |
| Forward gun / aft gun | That mount stops firing |
| Engine room | Speed falls with its health — and with no way on, no steering either |
| Steering gear | Rudder authority falls with its health |
| **Bridge** | Helm authority down to a third, and fires burn noticeably longer |
| Search radar | No anti-ship missile launches at all |
| Port / stbd VLS | Two missile cells offline each |
| CIWS mount | No missile interception and no close-in air defence |
| IR SAM bank | No air-defence missiles |

A hull with no working gun, no working aft gun and no radar-plus-missiles stops
counting as a threat and the wave clears — you never have to sink anything.
Against a corvette, the radar and the CIWS are usually the two worth taking off
first: the radar stops it shooting back with missiles, and the CIWS stops it
swatting yours.

## Missile inbound

A hostile anti-ship missile launched at you raises a **blinking rocket icon**
high on screen — nose down, exhaust trailing, with a count beside it when there
is more than one — plus three short urgent pips and a pulsing diamond on the
radar for every missile in the air. No text: it has to be noticed without being
read. The blink is deliberately slow and it sits well clear of the action, so it
registers without becoming noise in the middle of a gun action. Your CIWS is
already trying to kill them; the alert is there so you can turn to open the CIWS
arc or break away.

## Damage control

Fire is a fight you can win. A blaze damages the component it is on, and a fire
kept alight — a hull taking repeated hits in the same place — will still destroy
a mount. But left alone the crew smothers it: fires decay steadily, faster with
an intact bridge, and burn out in something like fifteen seconds. Press **C** to
send the damage-control party away: it knocks every fire down hard and shores up
flooding, then needs sixteen seconds to reform. The status panel shows the worst
fire aboard and the party's cooldown under it.

A repair crate makes the ship whole: every compartment and every module back to
full, fires out, water pumped, wrecked mounts back online with the charring
cleared. Anything less reads as a crate that did nothing, because the thing the
player actually lost is still dead. It does not touch the magazines — that is
what the ordnance crate is for.

**Flooding works the same way.** A sound hull pumps minor flooding back out on
its own, so light damage is not a one-way ratchet — but the pumps cannot keep up
with a hull that has been opened up. The damage-control party pumps hard while
it is away, and a repair crate is also a damage-control kit: it patches the hull
and gets almost all the water out. A wrecked bridge slows both the pumping and
the firefighting.



Rounds that strike a module which is already wrecked are not absorbed by the
scrap: they carry through into the compartment behind it, and once that
compartment is opened up too, further hits let the sea in instead. Nothing you
shoot is ever inert.

## Feedback

Every round that connects answers back, and the weight of the answer scales with
the weight of the hit:

- **On the target**: a hard white flash, a short fireball, a spray of sparks and
  torn plating, and soot left hanging. The module you struck glows white-hot,
  and the compartment around it lights up more faintly — so the hit is legible
  even when the module is small or hidden behind the deckhouse.
- **On the reticle**: four ticks that snap outward and fade, larger and ringed
  when the hit destroyed something, plus a floating damage number sized by the
  damage and a kick of camera shake.
- **Named results**: any module coming off any hull floats a callout where it
  died — `CIWS MOUNT DISABLED`, `SEARCH RADAR DISABLED`, `AFT GUN DISABLED`.
  Theirs in red as a result, **yours in amber as a warning**, with a warning
  tone, so losing a mount is as legible as taking one off them. It is raised
  where the module dies rather than where a round lands, so a mount lost to fire
  is called out the same way as one lost to a shell.
- **In the mix**: a light tick for a hit, a heavier two-tone for a component
  destroyed, and a metallic strike at the impact point.

Rounds that only scratch paint (cannon and CIWS calibre) are deliberately silent
in the reticle so the confirmation stays meaningful. Taking hits yourself pulses
a red vignette.

## Art pipeline

The corvette is an imported `.glb`; everything else is generated at runtime by
`NavalGeometry.Builder`. Its workhorse for anything shaped like a vehicle is
`beam()`, which builds a hexahedron between two cross-sections taken
perpendicular to the line joining their centres — so the same call shapes a
fuselage segment, a drooping wing panel or an upright fin, whatever axis it runs
along.

Blender is not installed on this machine, so the gunships are built in GDScript
rather than modelled and exported. If Blender is available, the corvette's build
script in the sibling project (`tools/build_corvette.py`) is the pattern to
follow for an authored `.glb`, and `ShipModel.build_imported` shows the node
contract an imported hull has to satisfy.

## Tuning and architecture

`ships/kestrel.tres`, `ships/tern.tres` and `scripts/ship_loadout.gd` hold shared weapon ranges, speed, ammunition and component-health tuning. Each ship has independent runtime `ShipSystem` instances.

`geometry.gd` is the art foundation: procedural detail textures, the material
family (plated steel, glazing, lamps, charred), and `NavalGeometry.Builder`, a
batching mesh builder with boxes, tapered frusta, free hexahedra, wedges, domes,
cylinders and tubes. `ship_model.gd` lofts the hull from its station table and
assembles the topside; `heli_model.gd` does the same for aircraft. Both return
the named meshes and mount nodes the simulation scripts drive, so gameplay code
never touches geometry.

Triangle winding follows one rule everywhere: list a face so that
`(b - a) x (c - a)` points **outward**, and the builder handles Godot's
clockwise front-face convention.

`vfx.gd` owns every effect asset and emitter. Two Godot behaviours it works
around, both of which silently produce nothing rather than an error:
`billboard_mode = BILLBOARD_PARTICLES` discards the per-particle scale unless
`billboard_keep_scale` is also set, and `ParticleProcessMaterial.turbulence`
scatters emitters of this size until almost no particle stays visible. Motion
comes from per-particle spin and the noise baked into the sprites instead.

`audio.gd` synthesises the effect bank and both music loops; `patrol.gd` owns
the wave campaign and hands hit confirmations to the HUD.

`boat.gd` handles ship movement, AI and damage; `helicopter.gd` handles aircraft. Separate scripts implement shells, anti-ship missiles, SAMs, flares, CIWS rounds and blasts. `patrol.gd` owns the mission, world and environment; `hud.gd` presents state. The ocean shader and buoyancy share wave parameters and simulation time.

This is game tuning, not real weapon or flight performance. Ships and helicopters are original silhouettes, not accurate replicas; direct flight uses simplified assisted controls. Hull damage uses component hitboxes and predefined break states, not arbitrary mesh fracture. Debris is visual; there is no full fluid simulation, player damage control, rearming, campaign or global AI pathfinding. The starting encounter includes both surface and air combat. Windows performance is unverified.

## Validation

Run from this directory:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/smoke.gd --fixed-fps 60
godot --headless --path . --script tests/missiles.gd --fixed-fps 60
godot --headless --path . --script tests/defense.gd --fixed-fps 60
godot --headless --path . --script tests/air_defense.gd --fixed-fps 60
godot --headless --path . --script tests/combined.gd --fixed-fps 60
godot --headless --path . --script tests/player.gd --fixed-fps 60
godot --headless --path . --script tests/boot.gd --fixed-fps 60
godot --headless --path . --script tests/battle.gd --fixed-fps 60
```

These check component damage and fire, AI threat switching, missile guidance and lifetime, ammunition, CIWS interception, SAM hits, flare diversion, helicopter weapons, the arcade control model, the wave campaign and its resupply, supply crates, hit confirmation, and a full unattended run of all three waves. `boot.gd` boots the scene and closes it, and should print no leaked-instance warning. Tests call `world.setup_sandbox()` to halt the campaign and lay out a fixed two-a-side engagement. Visual captures:

```sh
godot --path . -- --capture
godot --path . --script tests/capture_v2.gd --fixed-fps 60
godot --path . --script tests/capture_air.gd --fixed-fps 60
godot --path . --script tests/capture_model.gd --fixed-fps 60
godot --path . --script tests/capture_wake.gd --fixed-fps 60
godot --path . --script tests/capture_effects.gd --fixed-fps 60
godot --path . --script tests/capture_camera.gd --fixed-fps 60
godot --path . --script tests/capture_arcade.gd --fixed-fps 60
```

Frame-time probe with the sector deliberately overloaded:

```sh
godot --path . --script tests/perf.gd
```

Screenshots go to `artifacts/`. The strike capture uses a real missile impact, then explicitly triggers sinking to inspect wreck effects. `capture_model` renders clean elevations of both hulls with the HUD hidden, which is the fastest way to review a geometry change.

## Gunship role

The gunship is your second angle on the fight. Left alone it keeps station off
the ship's quarter and engages what threatens you. Press **H** to send it at
whatever you have designated, and **H** again with nothing designated to release
it back to escort; the card above your status panel shows what it is doing.
Press **Tab** to fly it yourself — it reaches supply crates far faster than the
ship, it can attack from bearings your guns cannot train on, and its rockets hurt
patrol boats badly. The ship keeps fighting under its AI crew while you are away.

## Roadmap

Work that is worth doing but not done — including the authored enemy hull, which
needs Blender installed — lives in `docs/ROADMAP.md`.

## Running in a browser

Not yet, and it is a port rather than a checkbox. The blocker is the renderer:
this build targets **Forward+**, and Godot's web export runs the
**Compatibility** renderer (WebGL 2), which does not have the screen-space
reflections and SSAO the ocean and hulls are currently lit with. Getting there
means a compatibility pass — swapping those out, retuning glow and tonemapping
for GLES3, checking the ocean shader's seven-octave noise is affordable on a
browser GPU, confirming GPU particles behave, and adding a single-threaded
fallback for the music synthesis (web threads need a page served with COOP/COEP
headers). The export templates are not installed here either, so nothing can be
built or measured yet. Say the word and I will do it as its own pass.

## Windows

A Windows Desktop x86-64 export preset is included. Install Godot export templates matching 4.7.2, then export from Project → Export. No Windows binary has been built or tested here.

The physical folder stays `2DGame`; the application is **3DGame — Littoral**. Development currently uses Godot's CLI; no MCP integration is configured. See `docs/DESIGN.md`.

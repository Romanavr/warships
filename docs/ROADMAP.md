# Roadmap

Work that is worth doing but not done. Ordered roughly by value, not by effort.

## Art

### Authored hulls — **done**

All four classes are now authored in Blender and rebuilt by scripts in `tools/`,
so they diff and rebuild rather than living in a `.blend`:

| Script | Output | Surfaces | Triangles |
|---|---|---|---|
| `build_saar6.py` | `saar6.glb` — Sa'ar 6-style corvette, both sides | 29 | 806 |
| `build_tern.py` | `tern.glb` — 28 m fast attack craft | 29 | 648 |
| `build_helicopters.py` | `mi24.glb`, `apache.glb` | 7 each | 1560 / 1312 |

The cargo ship stayed procedural (`ShipModel.build_cargo()`): it is built from
the same primitives as everything else and there was no reason to move it.

Three things cost real time here and are written up at the top of each script,
because every one of them fails *silently*:

1. **`matrix_parent_inverse` does not survive glTF.** Blender stores a
   parent-inverse per child; glTF has only a local transform per node. Parent
   with one and the export drops it, scattering every grouped part.
2. **Blender evaluates matrices lazily.** A parent created moments earlier still
   reports an identity `matrix_world`, so a child computed against it gets its
   world coordinates as a local transform and the offset lands twice. Fixing (1)
   without fixing (2) reproduces the exact same symptom.
3. **One object per part is one draw call per part.** The first airframes came
   out at 66 surfaces each. `batch()` welds everything the game does not move,
   hide or shed into the assembly it sits on.

Each script validates the node contract before exporting and fails loudly, so a
half-finished model cannot quietly fall back to the procedural hull.

What is left: the player's corvette and the enemy's are the same hull wearing a
colour wash, which was a deliberate choice but leaves the two sides reading
alike at range. A second warship silhouette is the obvious next model.

### Smaller art jobs

- Deck crew and helicopter operations on the flight deck.
- Damage decals on the plating rather than only charring and detached parts.
- A night or dawn lighting preset.

## Gameplay

### Difficulty settings

Wave one is currently tuned by removing capability outright rather than by
scaling it, which is the right call for a default but the wrong one to leave
permanent. The player should choose.

What was taken away, and should come back at higher settings:

- **Fast attack craft carry no CIWS.** Fitted, a Tern swats the player's
  anti-ship missiles, and a 28 m boat ends up harder to sink than the corvette
  it escorts. `offline_by_design` in `scripts/boat.gd` is where it is removed;
  `ships/tern.tres` still carries the range and the mount, so restoring it is
  putting `ciws_rounds` back and dropping `"ciws"` from that list.
- **Tern component health is about a third of what it was.** The numbers live in
  `ships/tern.tres`.
- **Nobody but a corvette carries anti-ship missiles.** Guided rounds hit hard
  and that is the point of them, so the answer to "too many" was to cut the
  number of launch platforms rather than to weaken the weapon. Helicopters lost
  theirs outright (`scripts/helicopter.gd` has no `missiles` at all now, and the
  pylons carry a second rocket pod instead); fast attack craft keep the launcher
  in the model but `"launcher_port"` is in `offline_by_design`, with
  `ships/tern.tres` holding the mount at 1 hp. Restoring either is undoing those
  two lines.

What a difficulty setting should reach, roughly in order of how much it matters:

1. Whether hostile fast attack craft are fitted with CIWS at all.
2. Whether anything below corvette size carries anti-ship missiles.
3. Component health multipliers per hostile class.
4. How aggressive the hostile missile doctrine is — how many probes before
   judging, how long the crew waits, whether it suppresses the CIWS at all
   (`should_launch_at` in `scripts/boat.gd`).
5. Damage taken by the player's hull.
6. Wave composition: numbers, and whether contacts arrive together.

Implementation shape: a difficulty resource holding multipliers and fitted-kit
flags, chosen on a start screen and applied at `spawn_boat` time, with the
current values as the middle setting. The loadouts are already `.tres`
resources, so most of this is picking between them rather than new machinery.

### The pre-mission briefing

`scripts/briefing.gd` opens the mission with a call from the hostile commander:
portrait, name, one typed line, then the first wave. Two things are worth
knowing about it:

- The speaker was once a **real living person** by name. He is now Admiral
  Ronald J. Grump of Task Group Tremendous — unmistakably the reference, and
  not the man. The name lives in the `SPEAKER` constant and the artwork at
  `assets/portraits/enemy.png`; nothing else in the game reads either.
- It is skipped whenever `test_mode` is set, on headless runs, and under
  `--capture` or `--no-briefing`. It opens one frame late (`call_deferred`) so a
  harness that flips `test_mode` right after `instantiate()` still wins the race
  — every capture and benchmark script depends on that.

More calls would fit: one per wave, and a closing line when the sector is clear.

### Tests

Every script in `tests/` extends `TestHarness` (`tests/harness.gd`) and defines
`run()`. The base owns `_initialize`, so a test never wires its own entry point,
and — the reason it exists — it arms a wall-clock watchdog first.

A script error inside an awaited `run()` aborts the coroutine without reaching
`quit()`. The scene tree stays up and the headless process spins forever at a
tenth of a core with nothing to say it has failed. Three of those once
accumulated over a working day and quietly skewed every frame-time benchmark
taken alongside them. The watchdog exits with code **2**, kept distinct from 1 so
a hang is never read as an ordinary assertion failure. Override `deadline()` in a
test that legitimately runs longer than five minutes; `battle.gd` does.

`battle.gd` is the unattended soak, and it starts at **level two**. Level one
asks for a scripted module kill — the merchant's engine room, without sinking
her — and an AI aims at the middle of a hull, so it can neither satisfy the
objective nor fail it. Started at level one the soak sits there for its whole
budget and reports a failure that says nothing about the game.

### Other gameplay work

- Rearming between waves beyond the wave-three resupply.
- More wave types: multiple simultaneous contacts, a submarine, a shore battery.
- A second sector with different island layout and weather.

## Platform

### Web export

It will run in a browser. It will **not** be the same build — the web target
cannot be, and it is worth being precise about why rather than discovering it
during a port.

Godot's web platform runs on WebGL 2, which means the **Compatibility**
renderer. This project is `forward_plus` and leans on it:

| Used today | On the web |
|---|---|
| `ssr_enabled` — screen-space reflections | **Not implemented.** The sea loses reflected sky and hulls. |
| `ssao_enabled` — ambient occlusion | **Not implemented.** Superstructure loses its contact shadows. |
| `use_taa` — temporal anti-aliasing | **Not available.** Falls back to MSAA/FXAA; the ocean's high-frequency detail will crawl. |
| `SCALING_3D_MODE_FSR` | **Not available.** The Retina fix is bilinear scaling instead. |
| `GPUParticles3D` | Works, but every effect needs re-checking — fire, smoke, tracers, splashes, the lot. |
| `Thread` for music synthesis | Needs COOP/COEP headers on the host, or a single-threaded fallback. |
| `glow_enabled` | Works, but tonemapping and glow both want retuning for GLES3. |

The ocean shader is the real question: 262 lines with a seven-octave wind
spectrum, domain warping and twelve oil-slick evaluations per pixel. That is
comfortable on an M-series GPU at 7.5 Mpx and may not be on a laptop iGPU
through WebGL. Expect to need a reduced-octave path.

So: a browser version is perfectly achievable, but it is a **port with a
downgraded look**, not the same binary. Budget for a compatibility pass, not a
checkbox. Export templates are not installed here either.
- Windows: a preset exists, nothing has been built or tested.

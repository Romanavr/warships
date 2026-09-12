# Design direction

Fight a modern naval action from the bridge of one ship, with a gunship you can
take over whenever you want a different angle on the fight. Single-player macOS
first, Windows next. The current build is a three-wave engagement; the longer
vision is more waves, more hull classes and a coastal campaign around them.

Weapons are arcade, handling is not. A ship that pivots on the spot is a tank,
and the moment the hull starts behaving like one the whole fantasy goes. So the
rudder takes time to swing, it only bites with water moving past it, and the
hull skids through a turn — while the guns, the lock-on and the reloads stay
generous. The player should feel like they are commanding weight, not driving a
cursor.

Handling is arcade, damage is not. The ship answers the helm in a couple of
seconds and the guns track the pointer, but underneath it is still thirteen
independently damaged components, fire that spreads, flooding that sinks you and
weapons that run out. The fantasy is a fast, readable warship duel — not a
simulator, and not a twin-stick shooter either.

Feedback is the other half of that. A round that connects has to be felt: spark
burst, reticle tick, damage number, and a distinct sound for a component
destroyed. Hits that do not matter stay quiet so the ones that do keep meaning.

The visual direction combines readable angular models, muted naval greys,
reflective moving water and visible weapon flight. Carrier Command 2 and Sea
Power inform atmosphere and readability; all art is original procedural work
generated at runtime — no imported meshes, textures or fonts.

Art rules that keep the fleet coherent:

- Silhouette first. A hull must be readable at tactical zoom from its sheer line,
  deckhouse mass and mast, before any surface detail matters.
- Three value bands per ship: light topside, mid deckhouse, dark deck and
  fittings. Weapons and sensors are the lightest accents; masts and glazing the
  darkest. Team identity is a hue shift, never a brightness change.
- Detail comes from geometry that a crew would actually use — railings, rafts,
  bollards, hatches, davits — not from noise. Procedural texture only supplies
  plate seams and weathering.
- Everything batches. New topside parts go into an existing `Builder` surface
  unless they move or take damage separately.
- Readouts are pictures of the thing they count. A row of missile silhouettes
  needs no caption; a row of squares needs one.
- The HUD is instrumentation, not decoration: hairline borders, letter-spaced
  capitals, segmented readouts, and colour reserved for state (mint friendly,
  red hostile, gold caution, cyan air and player attention).
- A mark in the world says "this one" and nothing else. Names, ranges, bearings
  and condition go in a panel at the edge of the screen, where they can be read
  without covering the ship they describe. The target bracket used to carry all
  four and hid the hull it was pointing at.
- The map shows the fight, not the sector. Its range is set from gun and missile
  envelopes, so contacts spread across the display instead of huddling in the
  middle third; anything further out is a rim arrow. Class is carried by shape —
  a hull points where its bow points, a merchant is a box, an aircraft is a rotor
  disc — because six identical dots in the same colour is not a display.
- Furniture competes with contacts. Every ring, grid line, needle and caption on
  a readout has to earn its place against the thing the player is looking for.
- The pointer is the gunsight, so the system cursor is hidden while the game is
  being played and the HUD draws its own arrow over panels. Hidden, never
  captured: capture pins the pointer to the middle of the window, which is the
  one thing aiming needs it not to do.
- A readout for module damage should be a picture of the ship. Module targeting
  is what this game is about; a row of three-letter abbreviations can say *that*
  a mount is gone but not that the mount was forward, and where it was is half
  the decision.
- Say what a shot would cost before it is fired. The pointer names the module it
  is resting on and what losing it does to the other ship, because "aim at the
  bridge rather than the waterline" is only a choice if the player knows what
  the bridge does.
- A scripted beat must not race the simulation. If a level hands the player a
  set piece four lines of dialogue later, the simulation has to be held for those
  four lines — otherwise the ship's own air defence resolves the duel while the
  player is still reading about it.
- A panel with nothing to say is not drawn. A permanent NO AIR SUPPORT in the
  corner is an apology occupying screen, not information.
- Finishing a level well and merely surviving it must not look the same. The
  debrief card between levels states rounds fired, rounds on target, modules
  knocked out and damage taken — figures, not a score, because one number
  invites optimising the number and four honest ones invite shooting differently.
- Islands are terrain, not scenery. A sea-skimmer flies at six metres and looks
  along its own nose, so putting a headland between hull and seeker breaks the
  track; the AI will not spend a missile it could never guide, and the target
  panel says MASKED so the player can use the same trick deliberately.
- Replenishment between levels is a full repair. `repair()` takes any fraction
  and a partial one was tried, but across four levels arriving at the last one
  already worn down punishes the player for the level they just won. The lever
  is there if the campaign ever gets long enough to want it.
- Ships show running lights. Red to port, green to starboard, white at the
  masthead and on the transom, and an anti-collision beacon flashing on its own
  offset so a division does not blink in unison. They come off the hull's module
  boxes, not a second table, and they go out when she does.
- Fire must be losable, not fatal. A blaze the player cannot answer is a
  punishment, not a mechanic; one that always burns out is set dressing. So the
  crew wins slowly on their own, the damage-control party wins fast on a
  cooldown, and a fire fed by fresh hits still takes the mount.
- Nothing the player shoots is inert. A wrecked module is a hole, not armour:
  rounds carry through into the compartment behind it, and an opened compartment
  floods. Shooting a blackened section must always do something.
- Supplies are a reason to move. Crates put hull and missiles back, but they sit
  out on the water, so topping up means breaking off and driving somewhere while
  a contact closes. Repair crates deliberately do not fix destroyed mounts —
  only the between-wave resupply does that.
- Effects are sized to the hull. A missile warhead makes a fireball about a
  quarter of a corvette's length, not one that swallows the ship. Tracers are
  long enough to read as a continuous streak between frames at 60 fps, because a
  weapon the player cannot see firing may as well not exist.
- Smoke is rationed, not free. Overdraw is the budget that actually binds, so a
  hull burns in at most three places and every emitter prefers few dense
  particles over many faint ones.
- Oil is a mirror too, and a brighter one than the sea. The instinct to draw a
  slick as a dark stain is exactly backwards: a fuel film damps the ripples, so
  it reflects more sky than the water beside it. Getting that inversion right
  matters more than the rainbow does — and so does shading it *as* the water
  rather than as a plane floating over it. Anything laid on the sea as a
  separate flat surface will read as a sticker no matter how good its texture
  is, because it has none of the water's shape.
- The player should never have to guess what they just lost. Damage to us gets
  the same named, located callout that damage to them does, in a colour that
  says which it was.
- Water is a mirror, not a blue surface. Its brightness comes from reflected sky
  and sun glitter; the body colour stays dark. Foam is earned by wave geometry
  (a folding crest, a shoaling beach), never scattered as decoration.

## Combat and damage

The current hull is a 54 m corvette with two guns, four anti-ship VLS cells, a CIWS mount and four IR SAM cells. Thirteen components have independent health. Engine damage affects speed, steering damage affects turning, and destroyed weapon systems stop firing. Fires damage components over time and spread locally. Hull damage introduces flooding; neutralization and sinking are separate states.

Surface AI considers a ship neutralized when its guns and usable missile capability are gone, and switches to another armed opponent. Reloading or propulsion loss does not make an armed ship harmless. Helicopters also consider functioning air defenses.

CIWS prioritizes incoming missiles and only engages helicopters nearby, with dispersion, small per-hit damage, cooling pauses and finite ammunition. SAMs provide the longer-range air defense layer. These are short-range infrared seekers so flares have a coherent gameplay role. A flare pack offers a chance to divert a seeker; it does not guarantee a miss.

Apache- and Hind-inspired helicopters carry limited guided air-to-surface missiles and unguided rockets, fly autonomously, evade after deploying flares and withdraw when weapons are exhausted. Their loadouts, durability and performance are fictional game values. Helicopters support player move/attack orders, holding a waypoint and optional assisted direct flight.

## Effects

Missile impacts create brief flashes, irregular flame jets, cooling debris and longer-lived soot. Explosive sinking can produce spaced secondary blasts. There are no expanding shockwave rings. Damage is based on compartment hitboxes and distance from the impact on the struck ship; fragments are visual, not a structural physics simulation.

## The gunship's job

Air support has to be legible without an RTS layer. It gets exactly one verb —
send it at what you have designated, or release it — and a visible task line, so
the player always knows what it is doing and how to change it. The rest of its
value is positional: it is fast, it reaches crates the ship cannot, and it can
attack from a bearing the ship's guns cannot train on.

## Campaign shape

Three waves, escalating in kind rather than in number: two fast attack craft,
then an air contact, then a matching corvette. The player is repaired and
rearmed before the last one, so the duel is fought on even terms and the run
ends on a fight rather than on attrition. A hostile is cleared once its weapons
are gone; sinking is optional, which keeps the pace up.

## Collision follows the art

Every time the hull model changed, the collision boxes stayed where they were —
and they were authored against a waterline-height hull. The guns aim at the
superstructure, so shells flew over the boxes entirely. The rule is that
collision has to cover what the player can see and shoot at, and there is a test
that rakes the hull with rays at deck height to keep it that way.

## Measuring performance honestly

The target is 60+ fps **fullscreen at native resolution on a Retina MacBook**.
Any frame-time number taken in a small window is close to meaningless there: the
panel has seven times the pixels, and almost everything expensive in this build
— the ocean's per-pixel noise, the alpha-blended smoke and oil, SSR, SSAO, glow
— is paid per pixel. Measure fullscreen or do not bother measuring.

## Laptop readability and controls

Direct control uses a look-ahead camera in the style of Foxhole: the focus
slides along the craft's course in proportion to speed and leans toward the
cursor, and the camera eases back slightly at speed. The lead is capped at a
fraction of the current zoom so the craft you are flying or conning never leaves
a comfortable part of the frame. The pointer term reads the cursor's position on
screen rather than the point it lands on in the world — using the world point
makes the camera chase its own movement.


The default perspective camera is closer and steeper with a narrower field of view. Haze is reduced, aircraft are enlarged and the friendly formation starts within a readable opening view. Ship dimensions remain distinct. Click or box-select friendlies, Shift-click to add, right-click to issue formation moves or attacks, and use the roster or minimap to navigate. C toggles direct control. WASD pans in RTS mode and controls the selected craft in direct mode.

## Next playtest priorities

1. Tune encounter duration and the missile/CIWS ammunition economy.
2. Check helicopter survivability against multiple ships and improve attack routes.
3. Improve module breakage and fire readability from the tactical camera.
4. Test Windows rendering, input and frame time.
5. Add rearming and player damage control, then a second exploration mission.
6. Art follow-ups: a separately lofted Tern hull rather than a scaled corvette,
   deck crew and helicopter operations on the flight deck, damage decals on the
   plating, and a night/dawn lighting preset.

The opening force on each side is one corvette, one smaller patrol boat and one helicopter. The compact default HUD keeps the ocean visible; SYSTEMS opens damage bars and sandbox controls. Helicopters now select air and surface targets and have finite air-to-air missiles and cannon ammunition. Guns and major components detach as ballistic visual wreckage, with water impacts and eventual cleanup. Global routing, realistic sensor uncertainty, ground forces, base building and campaign progression remain future work.

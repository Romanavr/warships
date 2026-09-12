"""Builds the Sa'ar 6-style corvette hull and exports assets/models/saar6.glb.

Run headless, from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_saar6.py

The model lives here rather than in a .blend so it rebuilds reproducibly and
the diffs are readable. Two things it has to get right or the game quietly
falls back to the procedural hull:

* **Orientation.** The glTF exporter maps Blender +Y to -Z, and the game wants
  the bow at -Z. So the bow is built toward +Y, with the waterline at z = 0.
* **The node contract** in `ShipModel.build_imported()`. Every name in
  CONTRACT below must exist, the gun pivots each need a child whose name starts
  with "Barrel", and a missing one makes the import warn and bail.

The module meshes are also the damage model's: the game hides and chars them
individually, so `gun`, `bridge`, `engine` and the rest have to be separate
objects rather than one merged hull.
"""
import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(PROJECT, "assets", "models", "saar6.glb")

CONTRACT = (
    ["bow", "mid", "stern", "gun", "aft_gun", "engine", "rudder", "bridge",
     "radar", "launcher_port", "launcher_starboard", "ciws", "sam",
     "gunPivot", "aft_gunPivot", "CiwsPivot", "RadarPivot"]
    + ["CellLid%d" % i for i in range(4)] + ["CellMuzzle%d" % i for i in range(4)]
    + ["SamLid%d" % i for i in range(4)] + ["SamMuzzle%d" % i for i in range(4)]
)

# [y, deck half, deck z, knuckle half, knuckle z, waterline half, keel z, rake]
# `rake` shifts the lower points aft of the deck point: that is what makes a
# stem a stem rather than a wall. The deck also rises 1.5 m from transom to
# stem, and the deck half-beam exceeds the waterline half forward — flare, and
# most of what makes a warship bow read as one.
STATIONS = [
    (27.0, 0.16, 5.00, 0.13, 2.60, 0.09, -1.10, 0.90),
    (24.5, 1.25, 4.86, 0.90, 2.35, 0.50, -1.95, 0.72),
    (21.5, 2.50, 4.66, 1.85, 2.05, 1.15, -2.55, 0.52),
    (17.5, 3.75, 4.38, 2.95, 1.75, 2.25, -3.00, 0.30),
    (12.0, 4.65, 4.08, 3.95, 1.50, 3.40, -3.25, 0.14),
    (6.0, 5.00, 3.86, 4.55, 1.35, 4.15, -3.35, 0.05),
    (0.0, 5.08, 3.72, 4.72, 1.28, 4.48, -3.38, 0.0),
    (-6.0, 5.05, 3.62, 4.72, 1.22, 4.50, -3.36, 0.0),
    (-12.0, 4.88, 3.54, 4.62, 1.20, 4.38, -3.28, 0.0),
    (-18.0, 4.50, 3.48, 4.34, 1.18, 4.05, -3.05, 0.0),
    (-23.0, 4.12, 3.44, 4.00, 1.16, 3.68, -2.65, 0.0),
    (-27.0, 3.86, 3.42, 3.78, 1.15, 3.38, -2.20, 0.0),
]

PALETTE = {
    "Hull grey": ((0.132, 0.152, 0.168), 0.58, 0.22),
    "Superstructure": ((0.255, 0.283, 0.298), 0.56, 0.16),
    "Non-slip deck": ((0.088, 0.100, 0.110), 0.90, 0.04),
    "Boot topping": ((0.038, 0.042, 0.048), 0.72, 0.08),
    "Bridge glazing": ((0.030, 0.052, 0.062), 0.10, 0.85),
    "Bare metal": ((0.400, 0.420, 0.420), 0.40, 0.80),
    "Shadow": ((0.055, 0.065, 0.072), 0.55, 0.25),
}


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for item in list(block):
            if getattr(item, "users", 0) == 0:
                block.remove(item)
    for name, (rgb, rough, metal) in PALETTE.items():
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value = (*rgb, 1.0)
        shader.inputs["Roughness"].default_value = rough
        shader.inputs["Metallic"].default_value = metal


def adopt(name, bm, material, parent=None, location=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.data.materials.append(bpy.data.materials[material])
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def profile(index):
    """Half a section, deck edge down to the keel."""
    y, dh, dz, kh, kz, wh, gz, rake = STATIONS[index]

    def at(half, z):
        return Vector((half, y - rake * (dz - z), z))

    return [at(dh, dz), at(kh, kz), at(wh, 0.0), at(wh * 0.70, gz * 0.55), at(0.22, gz)]


def loft(name, first, last, transom=False):
    bm = bmesh.new()
    ring = {}

    def vert(i, k, side):
        key = (i, k, side)
        if key not in ring:
            point = profile(i)[k]
            ring[key] = bm.verts.new((point.x * side, point.y, point.z))
        return ring[key]

    for i in range(first, last):
        for k in range(4):
            for side in (1, -1):
                quad = (vert(i, k, side), vert(i + 1, k, side),
                        vert(i + 1, k + 1, side), vert(i, k + 1, side))
                bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
        bm.faces.new((vert(i, 0, -1), vert(i, 0, 1), vert(i + 1, 0, 1), vert(i + 1, 0, -1)))
    if transom:
        for k in range(4):
            bm.faces.new((vert(last, k, 1), vert(last, k, -1),
                          vert(last, k + 1, -1), vert(last, k + 1, 1)))
    return adopt(name, bm, "Hull grey")


def block(name, sections, material, parent=None, location=(0, 0, 0)):
    """Faceted solid through horizontal rectangles.

    Sections are (z, half_fwd, half_aft, y_fwd, y_aft). Everything above the
    deck on this class is one of these: slab sides, tumblehome, no curves.
    """
    bm = bmesh.new()
    rings = []
    for z, half_f, half_a, y_f, y_a in sections:
        rings.append([bm.verts.new(p) for p in (
            (half_f, y_f, z), (-half_f, y_f, z), (-half_a, y_a, z), (half_a, y_a, z))])
    for lower, upper in zip(rings, rings[1:]):
        for k in range(4):
            n = (k + 1) % 4
            bm.faces.new((lower[k], lower[n], upper[n], upper[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return adopt(name, bm, material, parent, location)


def slab(name, x, y, z, sx, sy, sz, material, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=(sx, sy, sz))
    return adopt(name, bm, material, parent, (x, y, z))


def barrel(name, radius, length, parent, location):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12,
                          radius1=radius, radius2=radius, depth=length)
    # Lay it along +Y, which is forward. The game runs it back on recoil and
    # returns it to Godot z = -3.5, so it rests at Blender y = +3.5.
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return adopt(name, bm, "Bare metal", parent, location)


def empty(name, location):
    node = bpy.data.objects.new(name, None)
    node.empty_display_size = 0.6
    bpy.context.collection.objects.link(node)
    node.location = location
    return node


def build():
    reset()
    for name, first, last, transom in (("bow", 0, 4, False), ("mid", 4, 8, False),
                                       ("stern", 8, 11, True)):
        loft(name, first, last, transom)

    # The game's collision boxes already exist and shells hit those, not the
    # mesh — so each module is built inside its box, or the ship you aim at is
    # not the ship you hit. Godot -Z is Blender +Y throughout.
    block("bridge", [(3.90, 4.30, 4.80, 11.4, -1.6), (5.90, 3.80, 4.40, 10.6, -1.2),
                     (7.50, 3.25, 3.85, 9.4, -0.6), (8.80, 2.65, 3.20, 7.8, 0.2)],
          "Superstructure")
    block("radar", [(8.80, 2.40, 2.50, 5.2, -0.2), (10.60, 1.80, 1.85, 4.4, 0.4),
                    (12.10, 1.15, 1.20, 3.6, 1.0), (13.00, 0.58, 0.60, 3.0, 1.4)],
          "Superstructure")
    block("engine", [(3.55, 3.30, 3.05, -6.6, -15.0), (4.90, 2.95, 2.70, -6.9, -14.6),
                     (5.85, 2.30, 2.10, -7.4, -14.0)], "Superstructure")

    block("gun", [(2.90, 1.55, 1.75, 20.4, 15.8), (4.30, 1.30, 1.50, 19.9, 16.2),
                  (5.10, 0.85, 0.95, 19.4, 16.8)], "Superstructure")
    gun_pivot = empty("gunPivot", (0.0, 18.0, 4.20))
    block("GunHouse", [(-0.85, 1.25, 1.45, 2.2, -2.0), (0.45, 1.05, 1.25, 1.9, -1.7),
                       (1.05, 0.70, 0.80, 1.5, -1.3)], "Superstructure", gun_pivot)
    barrel("Barrel", 0.20, 7.0, gun_pivot, (0.0, 3.5, 0.45))

    block("aft_gun", [(3.40, 1.30, 1.45, -19.2, -22.6), (4.50, 1.10, 1.20, -19.5, -22.3),
                      (5.10, 0.75, 0.82, -19.9, -21.9)], "Superstructure")
    aft_pivot = empty("aft_gunPivot", (0.0, -21.0, 4.30))
    block("AftGunHouse", [(-0.80, 1.05, 1.20, 1.8, -1.7), (0.35, 0.88, 1.00, 1.5, -1.4),
                          (0.85, 0.60, 0.68, 1.2, -1.1)], "Superstructure", aft_pivot)
    barrel("BarrelAft", 0.15, 5.2, aft_pivot, (0.0, 3.5, 0.35))

    block("ciws", [(5.85, 1.35, 1.45, -10.6, -13.4), (6.60, 1.15, 1.25, -10.8, -13.2)],
          "Superstructure")
    ciws_pivot = empty("CiwsPivot", (0.0, -12.0, 6.60))
    block("CiwsDrum", [(0.00, 1.00, 1.05, 1.2, -1.2), (1.30, 0.85, 0.90, 1.0, -1.0),
                       (1.90, 0.55, 0.58, 0.8, -0.8)], "Superstructure", ciws_pivot)
    slab("CiwsMuzzle", 0.0, 1.5, 1.1, 0.5, 1.8, 0.5, "Bare metal", ciws_pivot)

    for side, name in ((-2.8, "launcher_port"), (2.8, "launcher_starboard")):
        block(name, [(3.30, 1.05, 1.05, -1.2, -6.6), (4.55, 0.95, 0.95, -1.4, -6.4)],
              "Superstructure", location=(side, 0, 0))
    # Cells 0-1 to port, 2-3 to starboard, matching the game's cell banks.
    for index, (cx, cy) in enumerate([(-2.8, -2.4), (-2.8, -5.4), (2.8, -2.4), (2.8, -5.4)]):
        slab("CellLid%d" % index, cx, cy, 4.62, 1.7, 2.3, 0.12, "Shadow")
        empty("CellMuzzle%d" % index, (cx, cy, 4.70))

    block("sam", [(3.70, 1.00, 1.00, -1.4, -4.6), (5.30, 0.85, 0.85, -1.6, -4.4)],
          "Superstructure")
    for index in range(4):
        sx = -0.55 + (index % 2) * 1.10
        sy = -2.2 - (index // 2) * 1.6
        slab("SamLid%d" % index, sx, sy, 5.36, 0.85, 1.3, 0.10, "Shadow")
        empty("SamMuzzle%d" % index, (sx, sy, 5.44))

    block("rudder", [(-2.60, 0.30, 0.28, -23.8, -26.2), (0.40, 0.26, 0.24, -24.0, -26.0)],
          "Hull grey")

    radar_pivot = empty("RadarPivot", (0.0, 3.0, 13.10))
    slab("ScannerBar", 0.0, 0.0, 0.25, 4.60, 0.22, 0.55, "Bare metal", radar_pivot)
    slab("ScannerHub", 0.0, 0.0, -0.10, 0.85, 0.85, 0.40, "Shadow", radar_pivot)

    slab("Breakwater", 0.0, 13.6, 4.55, 7.20, 0.35, 1.10, "Hull grey")
    slab("FlightDeck", 0.0, -21.5, 3.47, 7.60, 9.0, 0.10, "Non-slip deck")
    for side in (-1, 1):
        slab("Rib%d" % (side + 1), side * 3.55, -8.5, 4.30, 1.10, 3.40, 1.10, "Shadow")
    slab("Glazing", 0.0, 11.05, 7.10, 6.40, 0.35, 0.95, "Bridge glazing")
    for side in (-1, 1):
        slab("GlazingWing%d" % (side + 1), side * 3.50, 9.0, 7.05, 0.35, 3.60, 0.85,
             "Bridge glazing")

    bulwark()
    boot_topping()
    fittings()
    pennant("341")
    paint_decks()

    for obj in bpy.data.objects:
        if obj.type == "MESH":
            for poly in obj.data.polygons:
                poly.use_smooth = False


def deck_y(y):
    """Deck height at a station, interpolated — fittings must sit on the sheer."""
    for lower, upper in zip(STATIONS, STATIONS[1:]):
        if upper[0] <= y <= lower[0]:
            span = (y - upper[0]) / max(0.001, lower[0] - upper[0])
            return upper[2] + (lower[2] - upper[2]) * span
    return STATIONS[-1][2]


def deck_half(y):
    for lower, upper in zip(STATIONS, STATIONS[1:]):
        if upper[0] <= y <= lower[0]:
            span = (y - upper[0]) / max(0.001, lower[0] - upper[0])
            return upper[1] + (lower[1] - upper[1]) * span
    return STATIONS[-1][1]


def side_half(y, z):
    """Half-beam of the shell plating at a given height.

    The deck edge is not the ship's side: this hull flares, so the plating at
    3 m above the water is a long way inboard of the deck above it. Painting
    anything on the side has to use this, not `deck_half`, or it hangs in the
    air off the bow.
    """
    for lower, upper in zip(STATIONS, STATIONS[1:]):
        if upper[0] <= y <= lower[0]:
            span = (y - upper[0]) / max(0.001, lower[0] - upper[0])
            deck = upper[1] + (lower[1] - upper[1]) * span
            deck_z = upper[2] + (lower[2] - upper[2]) * span
            knuckle = upper[3] + (lower[3] - upper[3]) * span
            knuckle_z = upper[4] + (lower[4] - upper[4]) * span
            if z >= deck_z:
                return deck
            if z <= knuckle_z:
                return knuckle
            rise = (z - knuckle_z) / max(0.001, deck_z - knuckle_z)
            return knuckle + (deck - knuckle) * rise
    return STATIONS[-1][1]


def railing(name, first_y, last_y, posts):
    """Stanchions and two wires along the deck edge.

    A warship without guardrails reads as a toy. This is the single cheapest
    thing that makes the scale legible — it gives the eye something human-sized
    to measure the hull against.
    """
    step = (last_y - first_y) / float(posts - 1)
    for index in range(posts):
        y = first_y + step * index
        half = deck_half(y) - 0.16
        for side in (-1, 1):
            slab("%s_post%d_%d" % (name, index, side + 1), side * half, y,
                 deck_y(y) + 0.52, 0.07, 0.07, 1.04, "Bare metal")
    # The wires run post to post rather than bow to stern in one piece: the deck
    # edge curves and the sheer rises, and a single straight slab floats off the
    # side of the ship the moment the hull starts to narrow.
    for index in range(posts - 1):
        near = first_y + step * index
        far = first_y + step * (index + 1)
        mid = (near + far) * 0.5
        half = (deck_half(near) + deck_half(far)) * 0.5 - 0.16
        top = (deck_y(near) + deck_y(far)) * 0.5
        for wire, height in ((0, 0.52), (1, 0.98)):
            for side in (-1, 1):
                slab("%s_wire%d_%d_%d" % (name, wire, index, side + 1),
                     side * half, mid, top + height,
                     0.045, abs(far - near) + 0.04, 0.045, "Bare metal")


def fittings():
    """Deck furniture. None of it is load-bearing; all of it is what the eye
    uses to decide whether a grey shape is a model or a ship."""
    # Guardrails: forecastle, waist, and around the flight deck.
    railing("rail_fwd", 21.0, 14.0, 6)
    railing("rail_waist", 12.5, 1.0, 9)
    railing("rail_aft", -16.0, -25.0, 7)

    # Ground tackle. Anchors sit in pockets in the flare, where they belong.
    for side in (-1, 1):
        slab("anchor%d" % (side + 1), side * (deck_half(22.0) - 0.15), 22.0, 2.55,
             0.16, 1.30, 1.05, "Shadow")
        slab("hawse%d" % (side + 1), side * (deck_half(23.2) - 0.10), 23.2, 3.15,
             0.14, 0.46, 0.40, "Shadow")
        slab("capstan%d" % (side + 1), side * 1.55, 19.2, deck_y(19.2) + 0.30,
             0.70, 0.70, 0.60, "Bare metal")
        slab("bollard%d" % (side + 1), side * 2.60, 17.0, deck_y(17.0) + 0.28,
             0.24, 0.72, 0.56, "Bare metal")

    # A rigid inflatable in a recess amidships, under its davit.
    for side in (-1, 1):
        slab("rhib_hull%d" % (side + 1), side * 4.15, -3.2, 4.55, 0.95, 4.30, 0.70,
             "Shadow")
        slab("rhib_tube%d" % (side + 1), side * 4.15, -3.2, 4.90, 1.15, 4.10, 0.34,
             "Superstructure")
        slab("davit%d" % (side + 1), side * 3.75, -1.2, 5.60, 0.16, 0.16, 2.10,
             "Bare metal")
        slab("davit_arm%d" % (side + 1), side * 4.05, -2.4, 6.55, 0.14, 2.60, 0.14,
             "Bare metal")
        # Liferaft canisters against the citadel.
        for index in range(2):
            slab("raft%d_%d" % (index, side + 1), side * 3.95, 6.0 - index * 1.7, 4.55,
                 0.72, 1.35, 0.72, "Superstructure")

    # Satcom radomes and a navigation aerial on the mast platform.
    for side in (-1, 1):
        slab("radome%d" % (side + 1), side * 1.55, 2.4, 9.55, 1.05, 1.05, 1.05,
             "Superstructure")
    slab("aerial", 0.0, 0.6, 10.9, 0.10, 0.10, 2.20, "Bare metal")
    slab("yardarm", 0.0, 1.2, 11.4, 3.20, 0.10, 0.10, "Bare metal")

    # Panel breaks down the citadel sides. Shadow-coloured recesses, so the flat
    # tumblehome catches a line instead of reading as one unbroken sheet.
    for index in range(4):
        y = 9.4 - index * 2.9
        for side in (-1, 1):
            slab("panel%d_%d" % (index, side + 1), side * 4.42, y, 5.60,
                 0.06, 0.16, 3.00, "Shadow")
    # Watertight doors, one a side, at deck level.
    for side in (-1, 1):
        slab("door%d" % (side + 1), side * 4.44, 0.4, 5.05, 0.06, 0.90, 1.90, "Shadow")

    # Exhaust uptakes in the hull side aft, the way this class actually vents.
    for side in (-1, 1):
        for index in range(3):
            slab("uptake%d_%d" % (index, side + 1), side * (deck_half(-9.0) - 0.05),
                 -8.0 - index * 1.5, 2.35, 0.10, 0.85, 0.60, "Shadow")

    # Flight deck markings: touchdown circle and the lineup stripe.
    for index in range(16):
        angle = math.tau * index / 16.0
        slab("circle%d" % index, math.sin(angle) * 2.45, -21.5 + math.cos(angle) * 2.45,
             3.54, 0.42, 0.42, 0.03, "Non-slip deck")
    slab("lineup", 0.0, -21.5, 3.54, 0.26, 7.60, 0.03, "Bare metal")


def pennant(number):
    """The hull number, painted on both bows.

    Seven-segment digits built from slabs: crude up close, and at the range this
    game is played at it is the detail that says "this is a real ship" louder
    than anything else on the hull.
    """
    segments = {
        "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
        "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    }
    # (dx, dz, width, height) in digit-local space, digit is 1.0 x 1.7.
    strokes = {
        "a": (0.0, 0.80, 0.86, 0.15), "b": (0.44, 0.42, 0.15, 0.78),
        "c": (0.44, -0.40, 0.15, 0.78), "d": (0.0, -0.80, 0.86, 0.15),
        "e": (-0.44, -0.40, 0.15, 0.78), "f": (-0.44, 0.42, 0.15, 0.78),
        "g": (0.0, 0.0, 0.86, 0.15),
    }
    scale = 0.78
    step = 1.05 * scale
    # Far enough aft that the plating is full, and low enough to sit under the
    # deck edge the way a real pennant does.
    first = 18.6
    centre_z = 2.55
    # The two sides are mirror images about the middle of the block. Laid out
    # identically on both, one side reads backwards — a reversed 3 is an E, which
    # is exactly what the first attempt painted on the port bow.
    centre_y = first - (len(number) - 1) * 0.5 * step
    for position, digit in enumerate(number):
        for key in segments.get(digit, ""):
            dx, dz, width, height = strokes[key]
            y = first - position * step - dx * scale
            z = centre_z + dz * scale
            for side in (-1, 1):
                place = y if side < 0 else (2.0 * centre_y - y)
                slab("pennant%d%s%d" % (position, key, side + 1),
                     side * (side_half(place, z) - 0.04), place, z,
                     0.06, width * scale, height * scale, "Bare metal")


def bulwark():
    bm = bmesh.new()
    ring = {}

    def vert(i, side, up):
        key = (i, side, up)
        if key not in ring:
            y, dh, dz = STATIONS[i][0], STATIONS[i][1], STATIONS[i][2]
            half = dh - 0.10 - (0.22 if up else 0.0)
            ring[key] = bm.verts.new((half * side, y, dz + (1.05 if up else 0.0)))
        return ring[key]

    for i in range(4):
        for side in (1, -1):
            quad = (vert(i, side, False), vert(i + 1, side, False),
                    vert(i + 1, side, True), vert(i, side, True))
            bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
    adopt("Bulwark", bm, "Hull grey")


def boot_topping():
    """A dark strake at the waterline.

    Without it she reads as one flat grey shape resting on the sea rather than
    sitting in it — this is the cheapest single thing that fixes that.
    """
    bm = bmesh.new()
    ring = {}

    def vert(i, side, up):
        key = (i, side, up)
        if key not in ring:
            y, _, dz, _, _, wh, _, rake = STATIONS[i]
            z = 0.62 if up else -0.95
            half = wh * (1.012 if up else 0.90) + 0.03
            ring[key] = bm.verts.new((half * side, y - rake * (dz - z), z))
        return ring[key]

    for i in range(len(STATIONS) - 1):
        for side in (1, -1):
            quad = (vert(i, side, False), vert(i + 1, side, False),
                    vert(i + 1, side, True), vert(i, side, True))
            bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
    adopt("BootTop", bm, "Boot topping")


def paint_decks():
    """The weather deck is the dark non-slip value, not hull grey.

    The game is played looking down, so without this the whole topside is one
    tone from the angle that matters most.
    """
    deck = bpy.data.materials["Non-slip deck"]
    for name in ("bow", "mid", "stern"):
        obj = bpy.data.objects[name]
        obj.data.materials.append(deck)
        index = len(obj.data.materials) - 1
        for poly in obj.data.polygons:
            if poly.normal.z > 0.9:
                poly.material_index = index


def merge(target_name, source_names):
    """Join decoration into one surface.

    Every separate MeshInstance3D is a draw call, and these hulls came out at 46
    of them each — which cost about a third of the frame rate. Only what the
    game moves, hides or chars independently earns its own mesh; the rest is
    welded onto the compartment it sits on.
    """
    target = bpy.data.objects.get(target_name)
    if target is None:
        return
    bpy.ops.object.select_all(action="DESELECT")
    joined = 0
    for source in source_names:
        obj = bpy.data.objects.get(source)
        if obj is not None and obj is not target and obj.type == "MESH":
            obj.select_set(True)
            joined += 1
    if joined == 0:
        return
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


def batch():
    """Weld the fittings onto the compartments they stand on.

    The module meshes stay separate because the damage model hides and chars
    them one at a time; the launch lids stay separate because they open; the
    pivots' children stay separate because they turn. Everything else is scenery.
    """
    modules = {"bow", "mid", "stern", "gun", "aft_gun", "engine", "rudder", "bridge",
               "radar", "launcher_port", "launcher_starboard", "ciws", "sam"}
    moving = {"GunHouse", "AftGunHouse", "Barrel", "BarrelAft", "CiwsDrum", "CiwsMuzzle",
              "ScannerBar", "ScannerHub"}
    moving |= {"CellLid%d" % i for i in range(4)} | {"SamLid%d" % i for i in range(4)}
    everything = [o.name for o in bpy.data.objects if o.type == "MESH"]
    scenery = [n for n in everything if n not in modules and n not in moving]

    def matching(*prefixes):
        return [n for n in scenery if n.startswith(prefixes)]

    forward = ["Bulwark", "Breakwater"] + matching(
        "rail_fwd", "anchor", "hawse", "capstan", "bollard", "pennant")
    aft = ["FlightDeck", "Rib0", "Rib2", "Exhaust0", "Exhaust2"] + matching(
        "rail_aft", "circle", "lineup", "uptake")
    house = ["Glazing", "GlazingWing0", "GlazingWing2"] + matching(
        "panel", "door", "radome", "aerial", "yardarm")
    merge("bow", forward)
    merge("stern", aft)
    merge("bridge", house)
    merge("mid", ["BootTop"] + matching("rail_waist", "rhib", "davit", "raft"))
    print("batched to %d surfaces" % len([o for o in bpy.data.objects if o.type == "MESH"]))


def export():
    batch()
    missing = [name for name in CONTRACT if name not in bpy.data.objects]
    if missing:
        raise SystemExit("node contract not satisfied, missing: %s" % missing)
    for pivot in ("gunPivot", "aft_gunPivot"):
        children = [c.name for c in bpy.data.objects[pivot].children
                    if c.name.startswith("Barrel")]
        if not children:
            raise SystemExit("%s has no Barrel child" % pivot)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_cameras=False,
                              export_lights=False, export_extras=False)
    triangles = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
    print("saar6.glb written: %d bytes, %d triangles" % (os.path.getsize(OUTPUT), triangles))


build()
export()

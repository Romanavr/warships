"""Builds the Tern-class fast attack craft and exports assets/models/tern.glb.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_tern.py

Same conventions as tools/build_saar6.py — bow toward +Y, waterline at z = 0,
and the node contract in `ShipModel.build_imported()` validated before export.

The point of this hull is that it is *not* the corvette. It used to be exactly
that: `visuals.scale` shrank the 54 m corvette to 52%, which gave a toy version
of the player's own ship rather than a boat. This is 28 m of low, open, hard-
chined planing hull with one gun forward and a pilothouse you could touch the
roof of, and it reads as a different class at any range.

Because it is no longer the corvette scaled, its collision boxes no longer come
along for free — `ShipLayout` derives a "fac" layout from the corvette's at
28/54, so a shell that used to land on its bridge still lands on its bridge.
"""
import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(PROJECT, "assets", "models", "tern.glb")

CONTRACT = (
    ["bow", "mid", "stern", "gun", "aft_gun", "engine", "rudder", "bridge",
     "radar", "launcher_port", "launcher_starboard", "ciws", "sam",
     "gunPivot", "aft_gunPivot", "CiwsPivot", "RadarPivot"]
    + ["CellLid%d" % i for i in range(4)] + ["CellMuzzle%d" % i for i in range(4)]
    + ["SamLid%d" % i for i in range(4)] + ["SamMuzzle%d" % i for i in range(4)]
)

# [y, deck half, deck z, chine half, chine z, keel half, keel z, rake]
# A planing hull: the hard chine is carried well forward and the run aft is
# nearly flat. That chine is the whole character of the type.
STATIONS = [
    (14.0, 0.12, 2.90, 0.10, 1.05, 0.06, -0.55, 0.85),
    (12.6, 0.72, 2.82, 0.55, 0.85, 0.22, -0.95, 0.70),
    (10.8, 1.42, 2.70, 1.15, 0.62, 0.55, -1.20, 0.52),
    (8.0, 2.28, 2.52, 1.98, 0.34, 1.05, -1.38, 0.32),
    (4.0, 2.82, 2.34, 2.58, 0.16, 1.55, -1.48, 0.14),
    (0.0, 2.92, 2.22, 2.74, 0.08, 1.80, -1.50, 0.05),
    (-4.0, 2.90, 2.14, 2.76, 0.04, 1.88, -1.48, 0.0),
    (-8.0, 2.80, 2.08, 2.70, 0.02, 1.86, -1.42, 0.0),
    (-11.5, 2.62, 2.04, 2.56, 0.00, 1.78, -1.30, 0.0),
    (-14.0, 2.48, 2.02, 2.44, 0.00, 1.70, -1.18, 0.0),
]

PALETTE = {
    "Hull grey": ((0.150, 0.170, 0.185), 0.58, 0.20),
    "Superstructure": ((0.255, 0.283, 0.298), 0.56, 0.16),
    "Non-slip deck": ((0.085, 0.096, 0.105), 0.90, 0.04),
    "Boot topping": ((0.038, 0.042, 0.048), 0.72, 0.08),
    "Bridge glazing": ((0.030, 0.052, 0.062), 0.10, 0.85),
    "Bare metal": ((0.400, 0.420, 0.420), 0.40, 0.80),
    "Shadow": ((0.055, 0.065, 0.072), 0.55, 0.25),
}


def reset():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block_type in (bpy.data.meshes, bpy.data.materials):
        for item in list(block_type):
            if item.users == 0:
                block_type.remove(item)
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
    y, dh, dz, ch, cz, kh, kz, rake = STATIONS[index]

    def at(half, z):
        return Vector((half, y - rake * (dz - z), z))

    return [at(dh, dz), at(ch, cz), at(kh * 1.02, kz * 0.45), at(0.16, kz)]


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
        for k in range(3):
            for side in (1, -1):
                quad = (vert(i, k, side), vert(i + 1, k, side),
                        vert(i + 1, k + 1, side), vert(i, k + 1, side))
                bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
        bm.faces.new((vert(i, 0, -1), vert(i, 0, 1), vert(i + 1, 0, 1), vert(i + 1, 0, -1)))
    if transom:
        for k in range(3):
            bm.faces.new((vert(last, k, 1), vert(last, k, -1),
                          vert(last, k + 1, -1), vert(last, k + 1, 1)))
    return adopt(name, bm, "Hull grey")


def block(name, sections, material, parent=None, location=(0, 0, 0)):
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
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10,
                          radius1=radius, radius2=radius, depth=length)
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return adopt(name, bm, "Bare metal", parent, location)


def empty(name, location):
    node = bpy.data.objects.new(name, None)
    node.empty_display_size = 0.4
    bpy.context.collection.objects.link(node)
    node.location = location
    return node


def build():
    reset()
    for name, first, last, transom in (("bow", 0, 3, False), ("mid", 3, 6, False),
                                       ("stern", 6, 9, True)):
        loft(name, first, last, transom)

    # A pilothouse, not a citadel — this is the silhouette cue that separates
    # her from the corvette at any range.
    block("bridge", [(2.30, 1.75, 1.95, 3.4, -3.6), (3.45, 1.52, 1.70, 3.0, -3.2),
                     (4.25, 1.18, 1.32, 2.4, -2.6)], "Superstructure")
    slab("Glazing", 0.0, 3.05, 3.55, 2.60, 0.22, 0.62, "Bridge glazing")
    for side in (-1, 1):
        slab("GlazingWing%d" % (side + 1), side * 1.45, 1.4, 3.50, 0.22, 2.20, 0.55,
             "Bridge glazing")

    # An open mast would be a lattice and far too many triangles for what it is,
    # so it is a tapered fin carrying the scanner.
    block("radar", [(4.25, 0.42, 0.46, 1.4, -1.2), (5.60, 0.26, 0.28, 1.0, -0.8),
                    (6.30, 0.14, 0.15, 0.7, -0.5)], "Superstructure")
    radar_pivot = empty("RadarPivot", (0.0, -0.8, 6.35))
    slab("ScannerBar", 0.0, 0.0, 0.16, 2.10, 0.13, 0.30, "Bare metal", radar_pivot)
    slab("ScannerHub", 0.0, 0.0, -0.08, 0.42, 0.42, 0.24, "Shadow", radar_pivot)

    block("engine", [(2.10, 1.55, 1.35, -4.4, -9.2), (2.70, 1.35, 1.18, -4.6, -9.0)],
          "Superstructure")
    for side in (-1, 1):
        slab("Exhaust%d" % (side + 1), side * 1.15, -8.6, 2.55, 0.40, 1.30, 0.55, "Shadow")

    block("gun", [(2.55, 0.82, 0.92, 9.4, 7.2), (3.25, 0.70, 0.78, 9.1, 7.5)],
          "Superstructure")
    gun_pivot = empty("gunPivot", (0.0, 8.3, 3.25))
    block("GunHouse", [(-0.45, 0.62, 0.72, 1.1, -1.0), (0.35, 0.52, 0.60, 0.9, -0.8),
                       (0.70, 0.34, 0.38, 0.7, -0.6)], "Superstructure", gun_pivot)
    barrel("Barrel", 0.10, 3.4, gun_pivot, (0.0, 1.75, 0.22))

    # The rest of the fit exists but ships offline on this class: the game hides
    # whatever `offline_by_design` lists, and the import contract still wants
    # every node present.
    block("aft_gun", [(2.10, 0.60, 0.66, -10.4, -12.2), (2.70, 0.50, 0.55, -10.6, -12.0)],
          "Superstructure")
    aft_pivot = empty("aft_gunPivot", (0.0, -11.3, 2.70))
    block("AftGunHouse", [(-0.40, 0.48, 0.54, 0.9, -0.8), (0.30, 0.40, 0.45, 0.7, -0.6)],
          "Superstructure", aft_pivot)
    barrel("BarrelAft", 0.08, 2.6, aft_pivot, (0.0, 1.75, 0.18))

    block("ciws", [(2.70, 0.60, 0.64, -5.2, -6.8), (3.20, 0.50, 0.53, -5.3, -6.7)],
          "Superstructure")
    ciws_pivot = empty("CiwsPivot", (0.0, -6.0, 3.20))
    block("CiwsDrum", [(0.00, 0.46, 0.48, 0.55, -0.55), (0.62, 0.38, 0.40, 0.45, -0.45)],
          "Superstructure", ciws_pivot)
    slab("CiwsMuzzle", 0.0, 0.7, 0.52, 0.24, 0.85, 0.24, "Bare metal", ciws_pivot)

    # Deck canisters angled outboard, the way this type carries them — not the
    # corvette's flush cells.
    for side, name in ((-1.35, "launcher_port"), (1.35, "launcher_starboard")):
        block(name, [(2.25, 0.50, 0.50, -0.4, -3.4), (3.05, 0.46, 0.46, -0.5, -3.3)],
              "Superstructure", location=(side, 0, 0))
    for index, (cx, cy) in enumerate([(-1.35, -1.1), (-1.35, -2.7), (1.35, -1.1), (1.35, -2.7)]):
        slab("CellLid%d" % index, cx, cy, 3.10, 0.80, 1.25, 0.08, "Shadow")
        empty("CellMuzzle%d" % index, (cx, cy, 3.16))

    block("sam", [(2.20, 0.45, 0.45, -3.8, -5.4), (2.95, 0.38, 0.38, -3.9, -5.3)],
          "Superstructure")
    for index in range(4):
        sx = -0.26 + (index % 2) * 0.52
        sy = -4.1 - (index // 2) * 0.8
        slab("SamLid%d" % index, sx, sy, 2.99, 0.40, 0.62, 0.06, "Shadow")
        empty("SamMuzzle%d" % index, (sx, sy, 3.04))

    block("rudder", [(-1.20, 0.16, 0.15, -12.4, -13.8), (0.20, 0.14, 0.13, -12.5, -13.7)],
          "Hull grey")
    slab("Breakwater", 0.0, 6.2, 2.72, 3.90, 0.20, 0.55, "Hull grey")
    for side in (-1, 1):
        slab("Rib%d" % (side + 1), side * 1.95, -2.0, 2.45, 0.55, 1.70, 0.55, "Shadow")

    boot_topping()
    paint_decks()
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            for poly in obj.data.polygons:
                poly.use_smooth = False


def boot_topping():
    bm = bmesh.new()
    ring = {}

    def vert(i, side, up):
        key = (i, side, up)
        if key not in ring:
            y, _, dz, ch, _, _, _, rake = STATIONS[i]
            z = 0.34 if up else -0.48
            half = ch * (1.01 if up else 0.94) + 0.015
            ring[key] = bm.verts.new((half * side, y - rake * (dz - z), z))
        return ring[key]

    for i in range(len(STATIONS) - 1):
        for side in (1, -1):
            quad = (vert(i, side, False), vert(i + 1, side, False),
                    vert(i + 1, side, True), vert(i, side, True))
            bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
    adopt("BootTop", bm, "Boot topping")


def paint_decks():
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
    forward = ["Bulwark", "Breakwater"]
    aft = ["FlightDeck", "Rib0", "Rib2", "Exhaust0", "Exhaust2"]
    house = ["Glazing", "GlazingWing0", "GlazingWing2"]
    merge("bow", forward)
    merge("stern", aft)
    merge("bridge", house)
    merge("mid", ["BootTop"])
    print("batched to %d surfaces" % len([o for o in bpy.data.objects if o.type == "MESH"]))


def export():
    batch()
    missing = [name for name in CONTRACT if name not in bpy.data.objects]
    if missing:
        raise SystemExit("node contract not satisfied, missing: %s" % missing)
    for pivot in ("gunPivot", "aft_gunPivot"):
        if not [c for c in bpy.data.objects[pivot].children if c.name.startswith("Barrel")]:
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
    print("tern.glb written: %d bytes, %d triangles" % (os.path.getsize(OUTPUT), triangles))


build()
export()

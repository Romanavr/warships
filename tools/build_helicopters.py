"""Builds both gunship airframes and exports them to assets/models/.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_helicopters.py

Writes mi24.glb (the heavy, hostile-flown Hind) and apache.glb (the slim tandem
machine). Same conventions as the ship scripts: nose toward +Y, +Z up, and the
glTF exporter maps that to the game's -Z forward.

**Do not use `matrix_parent_inverse`.** Blender stores a parent-inverse matrix
per child; glTF has no such concept, only a local transform per node. Parent an
object with a parent-inverse and the export silently drops it, which scatters
every grouped part across the scene. Set `matrix_local` from the world matrix
instead — `reparent()` below is the only sanctioned way to attach anything.

The grouping is load-bearing rather than tidiness: the game tears these aircraft
apart when they die — blades shed and autorotate, the tail boom shears, the
canopy is jettisoned, the crew eject — and `HelicopterModel.build_imported()`
wants one node per assembly. A missing group means the import warns and falls
back to the procedural airframe, losing the whole effect.
"""
import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTRACT = (["Rotor", "TailRotor", "Blades", "Canopy", "Boom"]
            + ["Mount%d" % i for i in range(4)] + ["AirStore%d" % i for i in range(2)])

PALETTES = {
    "mi24": {
        "Airframe": ((0.320, 0.352, 0.372), 0.64, 0.06),
        "Panel": ((0.128, 0.150, 0.172), 0.66, 0.06),
        "Canopy": ((0.022, 0.040, 0.050), 0.09, 0.88),
        "Shadow": ((0.048, 0.056, 0.062), 0.52, 0.22),
        "Rotor": ((0.088, 0.096, 0.104), 0.50, 0.30),
        "Bare metal": ((0.380, 0.400, 0.400), 0.38, 0.80),
    },
    "apache": {
        "Airframe": ((0.148, 0.162, 0.150), 0.68, 0.06),
        "Panel": ((0.222, 0.238, 0.222), 0.64, 0.06),
        "Canopy": ((0.020, 0.036, 0.042), 0.09, 0.88),
        "Shadow": ((0.044, 0.050, 0.050), 0.52, 0.22),
        "Rotor": ((0.082, 0.088, 0.090), 0.50, 0.30),
        "Bare metal": ((0.372, 0.388, 0.388), 0.38, 0.80),
    },
}


def reset(palette):
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block_type in (bpy.data.meshes, bpy.data.materials):
        for item in list(block_type):
            if item.users == 0:
                block_type.remove(item)
    for name, (rgb, rough, metal) in palette.items():
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value = (*rgb, 1.0)
        shader.inputs["Roughness"].default_value = rough
        shader.inputs["Metallic"].default_value = metal


def adopt(name, bm, material, location=(0, 0, 0), rotation=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    obj.data.materials.append(bpy.data.materials[material])
    return obj


def reparent(obj, parent):
    """Attach without a parent-inverse, so the transform survives glTF.

    The view-layer update is not optional. Blender evaluates matrices lazily, so
    a parent created moments ago still reports an identity `matrix_world`; the
    child then gets its world coordinates as a local transform and the parent
    offset is applied a second time on export. That is what scattered the first
    two attempts at this across the scene.
    """
    bpy.context.view_layer.update()
    keep = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse.identity()
    obj.matrix_local = parent.matrix_world.inverted() @ keep


def lathe(name, sections, material, sides=8):
    bm = bmesh.new()
    rings = []
    for y, half, low, high in sections:
        centre, radius = (low + high) * 0.5, (high - low) * 0.5
        rings.append([bm.verts.new((math.sin(math.tau * i / sides) * half, y,
                                    centre + math.cos(math.tau * i / sides) * radius))
                      for i in range(sides)])
    for lower, upper in zip(rings, rings[1:]):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((lower[k], lower[n], upper[n], upper[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return adopt(name, bm, material)


def box(name, x, y, z, sx, sy, sz, material, rotation=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=(sx, sy, sz))
    return adopt(name, bm, material, (x, y, z), rotation)


def tube(name, radius, length, material, location=(0, 0, 0), rotation=(0, 0, 0), seg=8):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg,
                          radius1=radius, radius2=radius, depth=length)
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return adopt(name, bm, material, location, rotation)


def empty(name, location):
    node = bpy.data.objects.new(name, None)
    node.empty_display_size = 0.5
    bpy.context.collection.objects.link(node)
    node.location = location
    return node


def rotor_head(mast_y, mast_z, hub_z, blades, reach, chord):
    tube("Mast", 0.20, 0.80, "Bare metal", location=(0, mast_y, mast_z), seg=10)
    rotor = empty("Rotor", (0.0, mast_y, hub_z))
    head = tube("Head", 0.30, 0.32, "Rotor", location=(0, mast_y, hub_z), seg=12)
    reparent(head, rotor)
    group = empty("Blades", (0.0, mast_y, hub_z))
    reparent(group, rotor)
    for index in range(blades):
        angle = math.tau * index / blades
        blade = box("Blade%d" % index,
                    math.sin(angle) * reach * 0.5 + 0.0,
                    math.cos(angle) * reach * 0.5 + mast_y,
                    hub_z - 0.06, chord, reach, 0.08, "Rotor", rotation=(0, 0, -angle))
        cuff = box("Cuff%d" % index, math.sin(angle) * 0.50,
                   math.cos(angle) * 0.50 + mast_y, hub_z,
                   chord * 0.58, 0.70, 0.17, "Shadow", rotation=(0, 0, -angle))
        reparent(blade, group)
        reparent(cuff, group)
    return rotor


def tail_rotor(name_prefix, x, y, z, blades, span):
    node = empty("TailRotor", (x, y, z))
    hub = tube("TailHub", 0.15, 0.22, "Rotor", location=(x, y, z),
               rotation=(0, math.radians(90), 0), seg=8)
    reparent(hub, node)
    for index in range(blades):
        angle = math.tau * index / blades
        blade = box("%sTailBlade%d" % (name_prefix, index), x,
                    y + math.cos(angle) * span, z + math.sin(angle) * span,
                    0.09, span * 1.9, 0.21, "Rotor", rotation=(-angle, 0, 0))
        reparent(blade, node)
    return node


def stores(mounts, store_x, store_y, store_z, radius, length):
    for index, (x, y, z) in enumerate(mounts):
        empty("Mount%d" % index, (x, y, z))
    for index, side in enumerate((-1, 1)):
        tube("AirStore%d" % index, radius, length, "Bare metal",
             location=(side * store_x, store_y, store_z), seg=8)


def merge(target_name, source_names):
    """Join decoration into one surface.

    Every separate MeshInstance3D is a draw call, and these airframes came out
    at 66 of them each — which cost about a third of the frame rate. Only what
    the game moves, hides or sheds independently earns its own mesh; everything
    else is welded to the nearest thing that does.
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


def batch(name):
    """Weld each assembly down to a single surface."""
    everything = [o.name for o in bpy.data.objects if o.type == "MESH"]
    keep_apart = {"AirStore0", "AirStore1"}

    def under(parent_name):
        parent = bpy.data.objects.get(parent_name)
        if parent is None:
            return []
        return [c.name for c in parent.children_recursive if c.type == "MESH"]

    blades = under("Blades")
    canopy = under("Canopy")
    tail_rotor = under("TailRotor")
    boom = [n for n in under("Boom") if n not in tail_rotor]
    grouped = set(blades + canopy + boom + tail_rotor) | keep_apart

    merge(blades[0] if blades else "", blades[1:])
    merge(canopy[0] if canopy else "", canopy[1:])
    merge(boom[0] if boom else "", boom[1:])
    merge(tail_rotor[0] if tail_rotor else "", tail_rotor[1:])
    # The airframe itself: hull, wings, nacelles, gear, the lot.
    body = [n for n in everything if n not in grouped and n != "Fuselage"]
    merge("Fuselage", body)
    remaining = len([o for o in bpy.data.objects if o.type == "MESH"])
    print("%s: batched to %d surfaces" % (name, remaining))


def finish(name):
    batch(name)
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            for poly in obj.data.polygons:
                poly.use_smooth = False
    missing = [n for n in CONTRACT if n not in bpy.data.objects]
    if missing:
        raise SystemExit("%s: node contract not satisfied, missing %s" % (name, missing))
    path = os.path.join(PROJECT, "assets", "models", "%s.glb" % name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_cameras=False,
                              export_lights=False, export_extras=False)
    triangles = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
    print("%s.glb written: %d bytes, %d triangles" % (name, os.path.getsize(path), triangles))


def build_mi24():
    reset(PALETTES["mi24"])
    body = lathe("Fuselage", [
        (6.40, 0.18, -0.30, 0.12), (5.90, 0.46, -0.62, 0.44), (5.15, 0.62, -0.80, 0.78),
        (4.25, 0.74, -0.88, 0.96), (3.35, 0.82, -0.94, 1.34), (2.15, 0.94, -1.00, 1.50),
        (0.60, 1.04, -1.04, 1.56), (-1.10, 1.02, -1.00, 1.52), (-2.35, 0.76, -0.68, 1.20),
        (-3.45, 0.52, -0.44, 0.90), (-4.65, 0.38, -0.28, 0.72), (-6.00, 0.30, -0.18, 0.62),
    ], "Airframe")

    # Stepped tandem bubbles, gunner low and forward. Get this wrong and it is
    # just a helicopter; get it right and it is unmistakably a Hind.
    canopy = empty("Canopy", (0.0, 4.0, 1.4))
    for part in (lathe("CanopyGunner", [(5.60, 0.42, 0.16, 0.86), (5.00, 0.62, 0.20, 1.22),
                                        (4.32, 0.70, 0.22, 1.34)], "Canopy"),
                 lathe("CanopyPilot", [(4.14, 0.66, 1.02, 2.00), (3.45, 0.80, 1.00, 2.16),
                                       (2.60, 0.78, 0.92, 2.02)], "Canopy"),
                 box("CanopyStep", 0.0, 4.22, 1.14, 1.52, 0.16, 0.90, "Panel"),
                 box("CanopyArch", 0.0, 3.48, 2.24, 1.56, 0.14, 0.14, "Shadow"),
                 box("CanopyBrow", 0.0, 4.92, 1.30, 1.30, 0.60, 0.12, "Panel")):
        reparent(part, canopy)

    tube("ChinTurret", 0.34, 0.44, "Shadow", location=(0, 5.45, -0.92),
         rotation=(math.radians(90), 0, 0), seg=10)
    for index in range(4):
        angle = math.tau * index / 4.0
        tube("Gatling%d" % index, 0.05, 1.10, "Bare metal",
             location=(math.sin(angle) * 0.08, 6.10, -0.98 + math.cos(angle) * 0.08), seg=6)
    for side in (-1, 1):
        tube("Sensor%d" % (side + 1), 0.22, 0.26, "Shadow",
             location=(side * 0.34, 5.95, -0.56), rotation=(math.radians(90), 0, 0), seg=8)
        # Anhedral read from a step rather than a rotation, so the panels stay flat.
        box("WingInner%d" % (side + 1), side * 1.05, 0.32, 0.22, 1.35, 2.05, 0.26, "Airframe")
        box("WingOuter%d" % (side + 1), side * 2.25, 0.42, -0.12, 1.20, 1.70, 0.22, "Airframe")
        box("EndPlate%d" % (side + 1), side * 2.90, 0.42, -0.02, 0.14, 1.50, 0.92, "Panel")
        tube("Pod%d" % (side + 1), 0.32, 1.95, "Panel", location=(side * 2.30, 0.50, -0.55), seg=10)
        tube("PodFace%d" % (side + 1), 0.29, 0.07, "Shadow",
             location=(side * 2.30, 1.47, -0.55), seg=10)
        tube("Rail%d" % (side + 1), 0.13, 1.55, "Bare metal",
             location=(side * 1.35, 0.35, -0.34), seg=6)
        box("Pylon%d" % (side + 1), side * 1.35, 0.35, 0.02, 0.12, 0.70, 0.52, "Panel")
        box("Nacelle%d" % (side + 1), side * 0.46, 0.35, 1.76, 0.68, 2.55, 0.66, "Airframe")
        tube("Intake%d" % (side + 1), 0.30, 0.34, "Shadow",
             location=(side * 0.46, 1.62, 1.82), rotation=(math.radians(90), 0, 0), seg=10)
        tube("Exhaust%d" % (side + 1), 0.28, 0.50, "Shadow",
             location=(side * 0.62, -0.95, 1.80),
             rotation=(math.radians(90), 0, math.radians(side * 22)), seg=10)
        box("Sponson%d" % (side + 1), side * 1.05, -0.85, -0.92, 0.55, 1.45, 0.50, "Airframe")
        tube("Leg%d" % (side + 1), 0.08, 0.85, "Shadow", location=(side * 1.18, -0.85, -1.42),
             rotation=(0, math.radians(12 * side), 0), seg=6)
        tube("Wheel%d" % (side + 1), 0.30, 0.22, "Shadow", location=(side * 1.28, -0.85, -1.82),
             rotation=(0, math.radians(90), 0), seg=10)
    box("Spine", 0.0, 0.0, 1.72, 0.88, 3.10, 0.48, "Panel")
    tube("NoseLeg", 0.07, 0.75, "Shadow", location=(0, 4.30, -1.30), seg=6)
    tube("NoseWheel", 0.22, 0.18, "Shadow", location=(0, 4.30, -1.62),
         rotation=(0, math.radians(90), 0), seg=10)

    rotor_head(0.10, 2.28, 2.78, 5, 5.85, 0.34)

    boom = empty("Boom", (0.0, -7.4, 0.4))
    for part in (lathe("TailBoom", [(-5.90, 0.30, -0.18, 0.60), (-7.40, 0.26, -0.12, 0.52),
                                    (-8.60, 0.22, -0.06, 0.46)], "Airframe"),
                 box("Fin", 0.0, -8.30, 1.30, 0.20, 1.85, 1.95, "Airframe",
                     rotation=(math.radians(-16), 0, 0)),
                 box("FinRoot", 0.0, -7.70, 0.72, 0.22, 1.40, 0.85, "Airframe"),
                 box("VentralFin", 0.0, -8.55, -0.62, 0.16, 1.05, 0.95, "Panel",
                     rotation=(math.radians(18), 0, 0)),
                 box("Stabiliser0", -0.62, -7.85, 0.30, 1.25, 0.85, 0.12, "Airframe"),
                 box("Stabiliser2", 0.62, -7.85, 0.30, 1.25, 0.85, 0.12, "Airframe"),
                 tail_rotor("", -0.34, -8.45, 2.15, 3, 0.80)):
        reparent(part, boom)

    stores([(-2.30, 1.4, -0.55), (-1.35, 1.2, -0.34), (1.35, 1.2, -0.34), (2.30, 1.4, -0.55)],
           2.92, 0.55, 0.42, 0.12, 1.45)
    finish("mi24")


def build_apache():
    reset(PALETTES["apache"])
    # Half the Hind's girth — that narrowness is the whole difference at range.
    lathe("Fuselage", [
        (6.10, 0.16, -0.24, 0.10), (5.55, 0.36, -0.48, 0.48), (4.80, 0.50, -0.58, 0.86),
        (3.90, 0.58, -0.62, 1.06), (2.70, 0.64, -0.66, 1.26), (1.20, 0.68, -0.68, 1.34),
        (-0.50, 0.64, -0.62, 1.30), (-2.00, 0.46, -0.44, 1.02), (-3.40, 0.32, -0.30, 0.78),
        (-5.00, 0.24, -0.20, 0.62), (-6.60, 0.20, -0.14, 0.54),
    ], "Airframe")

    canopy = empty("Canopy", (0.0, 3.8, 1.3))
    for part in (lathe("CanopyFront", [(5.25, 0.38, 0.30, 1.00), (4.65, 0.48, 0.34, 1.34),
                                       (4.05, 0.50, 0.34, 1.42)], "Canopy", sides=6),
                 lathe("CanopyRear", [(3.90, 0.48, 1.10, 1.88), (3.20, 0.56, 1.06, 2.02),
                                      (2.45, 0.54, 1.00, 1.90)], "Canopy", sides=6),
                 box("CanopyStep", 0.0, 3.98, 1.20, 1.10, 0.14, 0.86, "Panel"),
                 box("CanopyRail", 0.0, 3.24, 2.10, 1.14, 0.12, 0.12, "Shadow")):
        reparent(part, canopy)

    tube("ChinTurret", 0.26, 0.36, "Shadow", location=(0, 5.10, -0.72),
         rotation=(math.radians(90), 0, 0), seg=10)
    tube("Cannon", 0.07, 1.40, "Bare metal", location=(0, 5.85, -0.80), seg=6)
    box("NoseSight", 0.0, 5.90, -0.10, 0.60, 0.70, 0.46, "Shadow")
    for side in (-1, 1):
        box("Wing%d" % (side + 1), side * 1.55, 0.40, 0.52, 2.30, 1.70, 0.22, "Airframe")
        box("WingTip%d" % (side + 1), side * 2.75, 0.40, 0.50, 0.20, 1.25, 0.60, "Panel")
        tube("Pod%d" % (side + 1), 0.28, 1.70, "Panel", location=(side * 2.05, 0.42, 0.06), seg=10)
        tube("PodFace%d" % (side + 1), 0.25, 0.06, "Shadow",
             location=(side * 2.05, 1.27, 0.06), seg=10)
        tube("Rail%d" % (side + 1), 0.11, 1.35, "Bare metal",
             location=(side * 1.15, 0.40, 0.14), seg=6)
        box("Pylon%d" % (side + 1), side * 1.15, 0.40, 0.34, 0.10, 0.60, 0.42, "Panel")
        box("Nacelle%d" % (side + 1), side * 0.66, 0.15, 1.42, 0.56, 2.30, 0.60, "Panel")
        tube("Intake%d" % (side + 1), 0.24, 0.28, "Shadow",
             location=(side * 0.66, 1.30, 1.46), rotation=(math.radians(90), 0, 0), seg=10)
        tube("Exhaust%d" % (side + 1), 0.22, 0.46, "Shadow",
             location=(side * 0.76, -1.02, 1.52),
             rotation=(math.radians(74), 0, math.radians(side * 26)), seg=10)
        tube("Leg%d" % (side + 1), 0.07, 1.05, "Shadow", location=(side * 0.92, 0.55, -1.10),
             rotation=(0, math.radians(16 * side), 0), seg=6)
        tube("Wheel%d" % (side + 1), 0.26, 0.18, "Shadow", location=(side * 1.06, 0.55, -1.58),
             rotation=(0, math.radians(90), 0), seg=10)

    rotor_head(0.35, 1.92, 2.34, 4, 5.30, 0.30)

    boom = empty("Boom", (0.0, -7.2, 0.3))
    for part in (lathe("TailBoom", [(-6.50, 0.20, -0.14, 0.52), (-7.80, 0.17, -0.10, 0.46),
                                    (-8.80, 0.14, -0.06, 0.40)], "Airframe"),
                 box("Fin", 0.0, -8.60, 1.05, 0.16, 1.55, 1.75, "Airframe",
                     rotation=(math.radians(-22), 0, 0)),
                 box("VentralFin", 0.0, -8.95, -0.55, 0.14, 0.90, 0.80, "Panel"),
                 box("Stabiliser0", -0.72, -8.05, 0.22, 1.40, 0.80, 0.11, "Airframe"),
                 box("Stabiliser2", 0.72, -8.05, 0.22, 1.40, 0.80, 0.11, "Airframe"),
                 tube("TailLeg", 0.05, 0.55, "Shadow", location=(0, -7.60, -0.42), seg=6),
                 tube("TailWheel", 0.16, 0.12, "Shadow", location=(0, -7.60, -0.70),
                      rotation=(0, math.radians(90), 0), seg=8),
                 tail_rotor("", 0.30, -8.70, 1.70, 4, 0.68)):
        reparent(part, boom)

    stores([(-2.05, 1.2, 0.06), (-1.15, 1.0, 0.14), (1.15, 1.0, 0.14), (2.05, 1.2, 0.06)],
           2.78, 0.45, 0.18, 0.11, 1.30)
    finish("apache")


build_mi24()
build_apache()

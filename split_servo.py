#!/usr/bin/env python3
"""Auto-split each OP3 link STL into servo vs frame and export a .glb with two
named objects ('servo' black, 'frame' silver). Servo is detected by its
Dynamixel XM-430 signature (~28.5 x 34 x 46.5 mm, volume ~43000 mm3)."""
import trimesh, numpy as np, os, sys
from trimesh.visual.material import PBRMaterial

SRC = "ROBOTIS-OP3-Common/op3_description/meshes"
DST = "assets/op3_meshes"
SCALE = 0.001   # mm -> m (sama seperti stl2obj)

def is_servo(c):
    v = abs(c.volume)                 # mm^3
    e = sorted(c.extents)            # mm, ascending
    return 32000 < v < 60000 and 24 < e[0] < 33 and 43 < e[2] < 52

def mat(name, rgb, metal, rough):
    return PBRMaterial(name=name,
        baseColorFactor=[rgb[0], rgb[1], rgb[2], 1.0],
        metallicFactor=metal, roughnessFactor=rough)

SERVO_MAT = mat("servo", (0.10, 0.10, 0.12), 0.6, 0.45)
FRAME_MAT = mat("frame", (0.55, 0.56, 0.60), 0.85, 0.34)

links = [os.path.splitext(f)[0] for f in sorted(os.listdir(SRC)) if f.endswith(".stl")]
for name in links:
    if name == "base":
        continue
    m = trimesh.load(os.path.join(SRC, name + ".stl"), force="mesh")
    try:
        comps = m.split(only_watertight=False)
    except Exception:
        comps = [m]
    if len(comps) == 0:
        comps = [m]
    servo_parts = [c for c in comps if is_servo(c)]
    frame_parts = [c for c in comps if not is_servo(c)]
    scene = trimesh.Scene()
    if servo_parts:
        s = trimesh.util.concatenate(servo_parts); s.apply_scale(SCALE)
        s.visual = trimesh.visual.TextureVisuals(material=SERVO_MAT)
        scene.add_geometry(s, node_name="servo", geom_name="servo")
    if frame_parts:
        fr = trimesh.util.concatenate(frame_parts); fr.apply_scale(SCALE)
        fr.visual = trimesh.visual.TextureVisuals(material=FRAME_MAT)
        scene.add_geometry(fr, node_name="frame", geom_name="frame")
    out = os.path.join(DST, name + ".glb")
    scene.export(out)
    sv = sum(len(c.faces) for c in servo_parts)
    fr = sum(len(c.faces) for c in frame_parts)
    print(f"{name:6s} comps={len(comps):3d}  servo_faces={sv:6d}  frame_faces={fr:6d}  {'(no servo)' if not servo_parts else ''}")
print("done")

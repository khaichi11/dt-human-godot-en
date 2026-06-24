# OP3 Digital Twin (dt-human-godot-en)

A real-time **digital twin** of the [ROBOTIS OP3](https://emanual.robotis.com/docs/en/platform/op3/introduction/)
humanoid robot, built with the **Godot Engine 4.6**. The application shows a
left-hand telemetry dashboard (battery, IMU, per-joint status) next to a 3D
viewport containing the **official OP3 mesh**, fully rigged to 20 degrees of
freedom. Each joint can be inspected and driven directly from the interface, and
the same control path is designed to forward commands to a physical robot.

The 3D model is assembled from the official per-link meshes published by ROBOTIS
in the `op3_description` package (see [Acknowledgements](#acknowledgements)); the
joint hierarchy, origins and rotation axes are taken verbatim from the official
URDF, so the on-screen kinematics match the real robot.

---

## Features

- **Accurate 20-DOF rig** — torso, head (2), arms (2×3) and legs (2×6) built
  from the official ROBOTIS meshes, with joint origins/axes parsed from the
  `op3_description` URDF.
- **Interactive joint control**
  - Click a servo in the 3D view, or pick a joint from the side panel, to select
    it. A rotation ring appears around the joint axis.
  - Drag to rotate. Motion **snaps to 5° detents** for repeatable positioning.
  - Forward kinematics: rotating a joint moves every downstream link while the
    parent chain stays fixed.
  - Per-joint sliders in the dashboard, kept in sync with the 3D gizmo.
- **CAD-style camera**
  - Orbit / pan / zoom (left-drag, right-drag or Shift+left-drag, mouse wheel).
  - A clickable **orientation cube** (ViewCube) in the corner.
  - Preset buttons: Front, Back, Left, Right, Top, Bottom, Iso.
  - Keyboard: numpad `1/3/7/9` for views, arrow keys to orbit.
- **Two operating modes**
  - **Atur (Edit)** — the operator drives the joints from the UI.
  - **Live** — the robot is driven by incoming data; the UI becomes read-only.
    A mock walking gait is provided as a placeholder for a real data feed.
- **Clean, minimalist white UI** using the open-source **Inter** typeface.

---

## Requirements

- [Godot Engine **4.6**](https://godotengine.org/download) or newer (standard
  build; no C# / .NET required).
- Python 3 — only needed if you want to regenerate the meshes (see below).

No other dependencies. Everything required to run is contained in this
repository.

---

## Quick start

```bash
git clone https://github.com/khaichi11/dt-human-godot-en.git
cd dt-human-godot-en
```

1. Open **Godot 4.6**, choose **Import**, and select `project.godot`.
2. Let Godot import the assets on first open (meshes and font). This happens
   automatically and only once.
3. Press **F5** (or the Play button) to run.

> If you ever pull new mesh files and the model looks faceted, force a clean
> reimport: close Godot, delete the `.godot/imported/` folder, and reopen the
> project.

---

## Project structure

```
dt-human-godot-en/
├── project.godot                 # Godot project configuration
├── icon.svg
├── stl2obj.py                    # STL -> OBJ mesh converter (offline tool)
├── scenes/
│   └── Main.tscn                 # entry scene (UI is built in code)
├── assets/
│   ├── op3_meshes/*.obj          # 21 per-link OP3 meshes (used at runtime)
│   └── fonts/Inter.ttf
└── scripts/
    ├── Main.gd                   # layout, theme, lighting, modes, wiring
    ├── SensorPanel.gd            # left dashboard + per-joint sliders
    ├── OP3Robot.gd               # builds the rig from the URDF data + meshes
    ├── JointManipulator.gd       # 3D joint selection + rotation gizmo
    ├── CameraOrbit.gd            # orbit camera + view presets
    └── ViewCube.gd               # corner orientation cube
```

The `ROBOTIS-OP3*` source repositories are intentionally **not** committed (they
are large and only used offline to extract meshes/URDF). They are listed in
`.gitignore`.

---

## Controls

### Joints / servos

| Action | Result |
| --- | --- |
| Click a servo in 3D, or a joint name in the panel | Select the joint (ring shown) |
| Drag the ring / servo | Rotate the joint (snaps every 5°) |
| Drag a panel slider | Rotate the joint numerically |
| `Esc` | Deselect |

### Camera

| Action | Result |
| --- | --- |
| Left-drag (empty space) | Orbit |
| Right-drag, or Shift + left-drag | Pan |
| Mouse wheel | Zoom |
| Preset buttons / ViewCube faces | Jump to a fixed view |
| Numpad `1` / `3` / `7` / `9` | Front / Right / Top / Back |
| Arrow keys | Orbit in steps |

### Modes

Toggle **MODE: ATUR / LIVE** in the top toolbar. In *Atur* the joints are
operator-driven; in *Live* they follow the incoming data stream.

---

## How it works

- **Meshes** — the 21 OP3 link meshes (`body`, `h1/h2`, `la1–3`, `ra1–3`,
  `ll1–6`, `rl1–6`) are converted from the official binary STL files into OBJ
  with `stl2obj.py`. The converter rescales millimetres to metres and rebuilds
  smooth normals with an angle-based crease (30°) and area weighting, so flat
  panels stay flat and curved surfaces stay smooth.
- **Kinematics** — `OP3Robot.gd` builds one `Node3D` per joint, placed at the
  exact URDF `origin` and storing the URDF rotation `axis`. Because every URDF
  joint uses `rpy = 0`, the link frames are axis-aligned, which keeps the
  forward-kinematics math simple.
- **Coordinate system** — the URDF/ROS convention (Z-up, X-forward, millimetres)
  is converted to Godot (Y-up, −Z-forward, metres) by a single rotation applied
  to the model root.
- **Default pose** — the robot starts in a natural standing pose (arms down).
  This is applied once and is overwritten per joint as soon as control input or
  live data arrives.

---

## Connecting a real robot

The control path is centralised on one method:

```gdscript
robot.set_joint_angle("l_knee", deg_to_rad(45.0))   # set a joint (radians)
var rad := robot.get_joint_angle("head_pan")         # read a joint
```

To drive the twin from a physical OP3, replace `Main._drive_live()` with a node
that reads the robot's joint states (for example the ROS topic
`/robotis/present_joint_states`, or a direct OpenCR / CM-740 serial link) and
calls `set_joint_angle()` each frame. Switch the UI to **Live** mode so the
sliders become read-only mirrors of the real hardware. The reverse direction
(sending operator edits back to the robot) uses the same `set_joint_angle`
values as the command source.

---

## Regenerating the meshes

The committed OBJ meshes are sufficient to run the app. If you need to rebuild
them from the official STL files, fetch `op3_description` (see Acknowledgements)
and run:

```bash
python3 stl2obj.py path/to/op3_description/meshes assets/op3_meshes
```

Then reopen the project so Godot reimports the new files.

---

## OP3 joint reference (20 DOF)

| ID | Joint | ID | Joint |
| -- | ----- | -- | ----- |
| 01 | r_sho_pitch | 11 | r_hip_pitch |
| 02 | l_sho_pitch | 12 | l_hip_pitch |
| 03 | r_sho_roll  | 13 | r_knee |
| 04 | l_sho_roll  | 14 | l_knee |
| 05 | r_el        | 15 | r_ank_pitch |
| 06 | l_el        | 16 | l_ank_pitch |
| 07 | r_hip_yaw   | 17 | r_ank_roll |
| 08 | l_hip_yaw   | 18 | l_ank_roll |
| 09 | r_hip_roll  | 19 | head_pan |
| 10 | l_hip_roll  | 20 | head_tilt |

---

## Acknowledgements

This project would not exist without the open-source work published by
**ROBOTIS** on GitHub:

- **ROBOTIS-OP3-Common** — URDF and per-link meshes (`op3_description`):
  <https://github.com/ROBOTIS-GIT/ROBOTIS-OP3-Common>
- **ROBOTIS-OP3** — controller modules and servo configuration
  (`op3_manager`, `dxl_init_OP3.yaml`, etc.):
  <https://github.com/ROBOTIS-GIT/ROBOTIS-OP3>
- **ROBOTIS-OP3-msgs** — ROS message/service definitions:
  <https://github.com/ROBOTIS-GIT/ROBOTIS-OP3-msgs>

The 3D meshes and URDF are © ROBOTIS Co., Ltd. and distributed under the
Apache License 2.0. ROBOTIS OP3 is a robot platform by ROBOTIS.

The **Inter** font is © The Inter Project Authors, licensed under the SIL Open
Font License 1.1.

## License

The application code in this repository is released under the MIT License.
Third-party assets (ROBOTIS meshes/URDF, Inter font) remain under their
respective licenses noted above.

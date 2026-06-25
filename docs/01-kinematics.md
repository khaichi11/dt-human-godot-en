# Kinematics — OP3 Digital Twin

This document explains how the twin positions and orients the 20-DOF OP3 in 3D,
the coordinate conversion from ROS/URDF to Godot, and (for reference) the
analytical inverse kinematics of the OP3 legs.

## 1. Forward Kinematics (what the twin uses)

The twin **mirrors** the robot's joint state, so it only needs **forward
kinematics (FK)**: given each joint angle, compute where every link is.

The rig (`OP3Robot.gd`) builds one `Node3D` per joint, placed at the joint's
URDF `origin` and storing the URDF rotation `axis`. A link's world transform is
the product of its ancestors' transforms:

```
T_link = T_root · Π_i [ Translate(origin_i) · Rotate(axis_i, θ_i) ]
```

where the product runs over every joint `i` from the root (torso) down to the
link, `origin_i` is the fixed joint offset from the URDF, `axis_i` is the joint
axis, and `θ_i` is the current joint angle (radians).

Because every OP3 URDF joint has `rpy = 0`, the link frames are axis-aligned and
each `Rotate(axis_i, θ_i)` is a single-axis rotation — `set_joint_angle()` does
exactly `node.basis = Basis(axis, θ)`.

## 2. Coordinate conversion ROS/URDF → Godot

| | ROS / URDF | Godot |
|---|---|---|
| Up axis | +Z | +Y |
| Forward | +X | −Z |
| Units | metres (mesh STL in mm) | metres |

A single fixed rotation (`ROS_TO_GODOT`) is applied to the model root so the
whole chain lives in Godot space while the per-joint axes/origins stay in their
original URDF values. Meshes are scaled mm→m (×0.001) at conversion time
(`stl2obj.py`).

Joint angles are identical in both worlds (radians, same sign as
`/robotis/present_joint_states`), which is why live data from the robot can be
fed straight into `set_joint_angle()` without remapping.

## 3. Floor grounding

The twin has no floating-base odometry, so the base height is derived visually:
each frame the lowest vertex of the combined mesh AABB is pinned to `y = 0`
(`_ground_to_floor()`). This keeps the robot on the floor for any pose
(standing, crouch, push-up) without a physics solver.

## 4. Inverse Kinematics (reference — not used to drive the twin)

The twin does not solve IK (it follows measured joint states). For completeness,
OP3's leg IK (see `op3_kinematics_dynamics` upstream) is **analytical** per leg:

Given the desired foot position `p = (x, y, z)` relative to the hip and thigh /
shin lengths `L1`, `L2`:

```
d        = ‖p‖                              # hip→ankle distance
cosKnee  = (L1² + L2² − d²) / (2·L1·L2)
knee     = π − acos(clamp(cosKnee, −1, 1))  # knee flexion

α        = acos( (L1² + d² − L2²) / (2·L1·d) )
pitch    = atan2(x, −z) ∓ α                 # hip_pitch / ankle_pitch share α
roll     = atan2(y, −z)                     # hip_roll / ankle_roll
```

`hip_yaw` is set from the desired foot yaw. The two-link law-of-cosines gives the
knee; the remaining angles distribute the hip→ankle direction between hip and
ankle so the foot stays flat. If end-effector control is added later, this is
the formula set to implement in `OP3Robot.gd`.

See also: [02-connection.md](02-connection.md), [04-servos-health.md](04-servos-health.md).

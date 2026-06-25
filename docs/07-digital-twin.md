# The Digital Twin — definition & how this app applies it

This project is not "a 3D viewer with sensors". It is a **digital twin (DT)** of
the ROBOTIS OP3. This page states the definition we use and shows, concretely,
where each part of the definition lives in the app — so the concept is not just
named but *applied*.

## What a digital twin is

> A digital twin is a *set of virtual information constructs that fully describe
> a potential or actual physical product, mirrored from real-time sensor data*,
> so the virtual model behaves as the physical system does, in real time.
> — Grieves & Vickers; Sharma et al., *Digital Twins: State of the art theory
> and practice* (2022).

> "A digital representation of a physical model utilizing real-time data from the
> sensors … that works as the physical equivalent does in real time by mimicking
> its working process." — Singh & Ray, *A physical–virtual based digital twin
> robotic hand* (2024).

The load-bearing word is **real-time link**. That is what separates a DT from its
weaker cousins:

| Concept | Physical→Virtual data | Virtual→Physical data | This app |
| --- | --- | --- | --- |
| Digital **Model** | manual | manual | — |
| Digital **Shadow** | automatic | manual | — |
| **Digital Twin** | automatic | automatic (bi-directional) | **what we build** |
| Simulation | none (no live asset) | none | the **SIMULATION** fallback state |

So when the live link is down, the app is honest about it: it shows
**SIMULATION**, not "twin". A twin only exists while it is synchronized.

## The three layers (Singh & Ray, Fig. 7) — and where they are in the code

```
   PHYSICAL  ───────────►  INTERFACING  ───────────►  VIRTUAL
   asset                   (real-time link)            asset / twin
   OP3 · 20× Dynamixel     rosbridge WebSocket         this Godot app
   XM-430 · Intel NUC      ROS 2 topics                3D rig + dashboard
        ▲                                                   │
        └──────────────  goal poses (deploy)  ◄─────────────┘
```

| Layer | Real component | In this app |
| --- | --- | --- |
| **Physical** | OP3 robot, Dynamixel servos, NUC | `OP3Robot` mirrors its state; `SERVO_ID`, `SERVO_MODEL`, joint limits |
| **Interfacing** | rosbridge / ROS 2 | `RosBridge.gd`; `/robotis/present_joint_states`, `/dt/servo_health` |
| **Virtual** | — | the Godot twin: 3D rig, dashboard, pose authoring |

The DT hero card at the top of the panel renders exactly this flow
(`PHYSICAL → LINK → VIRTUAL`) and a live **SYNCHRONIZED / SIMULATION** badge.

## Synchronization — the property made visible

`SensorPanel.set_sync_state(connected, latency_ms)` is called by `Main.gd` every
time a joint packet arrives over rosbridge (`_on_ros_joints`) and when the socket
closes (`_on_ros_status`). Each packet is evidence the twin is mirroring the
physical asset, so the hero card shows **SYNCHRONIZED · latency N ms**. With no
packets it falls back to **SIMULATION** (virtual model only). This is the
paper's DT-vs-simulation distinction, surfaced in the UI.

## Information flow is bi-directional

- **Physical → Virtual (MIMIC):** in LIVE mode the twin applies the robot's real
  joint angles and servo health every frame — it *mimics* the robot.
- **Virtual → Physical (AUTHOR):** in ATUR mode you pose the virtual model
  (arm a servo, rotate its ring), capture steps, and that scene is what gets
  deployed back to the physical robot. The editor banner names the current
  direction so the operator always knows which way data is flowing.

## PHM — the headline DT advantage

Prognostics & Health Management is, per both papers, the main practical payoff of
a DT. Here it is concrete:

- `/dt/servo_health` drives per-servo **OK / WARN / FAULT** state.
- Fault red blinks **only on the servo sub-mesh** (see `docs/06-texturing.md`),
  so the alert lands on the actual XM-430 that is degrading.
- The servo popup (click a servo) shows load, temperature and a fatigue estimate,
  Dynamixel-Wizard style — health you can act on.

## DT performance / evaluation

The btop-style **System · Intel NUC** card and the **Twin FPS / Latency** read-
outs are the DT's own performance instrumentation: compute load, memory, link
latency and render rate — the metrics a DT needs to prove it is keeping up with
the physical asset in real time.

## App flow (alur)

1. **Connect** the twin to the robot (rosbridge URL → Connect). Link state
   becomes **SYNCHRONIZED**.
2. **MIMIC (LIVE):** watch the twin mirror the robot — joints, IMU, battery,
   servo health, NUC load.
3. **Diagnose (PHM):** a degrading servo blinks red on its body; click it for
   load/temperature/fatigue.
4. **AUTHOR (ATUR):** switch mode, arm a servo, rotate it, capture steps, save a
   scene.
5. **Deploy:** push the authored scene back to the physical robot (Virtual →
   Physical), closing the bi-directional loop.

## References

- M. Singh & A. Ray, "A physical–virtual based digital twin robotic hand,"
  *Int. J. Interact. Des. Manuf.*, 2024. doi:10.1007/s12008-024-01773-7
- A. Sharma et al., "Digital Twins: State of the art theory and practice,
  challenges, and open research questions," 2022. (Grieves & Vickers DT
  definition; DT vs Digital Shadow vs Digital Model.)

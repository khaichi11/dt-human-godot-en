# Servos & Health Monitoring

## Servo map (Dynamixel ID → joint → body part)

All 20 joints use **Dynamixel XM-430-W350** (Protocol 2.0).

| ID | Joint | Part | ID | Joint | Part |
|----|-------|------|----|-------|------|
| 1 | r_sho_pitch | Arm R | 11 | r_hip_pitch | Leg R |
| 2 | l_sho_pitch | Arm L | 12 | l_hip_pitch | Leg L |
| 3 | r_sho_roll | Arm R | 13 | r_knee | Leg R |
| 4 | l_sho_roll | Arm L | 14 | l_knee | Leg L |
| 5 | r_el | Arm R | 15 | r_ank_pitch | Leg R |
| 6 | l_el | Arm L | 16 | l_ank_pitch | Leg L |
| 7 | r_hip_yaw | Leg R | 17 | r_ank_roll | Leg R |
| 8 | l_hip_yaw | Leg L | 18 | l_ank_roll | Leg L |
| 9 | r_hip_roll | Leg R | 19 | head_pan | Head |
| 10 | l_hip_roll | Leg L | 20 | head_tilt | Head |

`OP3Robot.SERVO_ID` / `get_servo_part()` hold this; the joint panel shows the ID
and a tooltip per row.

## Health visualization

`set_servo_health(joint, "ok"|"warn"|"fault")`:

- **ok** — normal matte-black metal.
- **warn** — link pulses amber (slow).
- **fault** — link blinks **red ↔ black** (fast, emissive). The panel row dot
  also turns red.

Health arrives over `/dt/servo_health` (see
[02-connection.md](02-connection.md)). A **Self-Test** button previews it
without a robot.

## Reading health on the robot (DT-Human tools)

The robot-side reader (DT-Human `tools/servo_checker.py`, `servo_monitor.py`)
uses the Dynamixel SDK to poll each servo and classify it, then publishes
`{name, level}` to `/dt/servo_health`.

Recommended port/bus settings (match Dynamixel Wizard 2.0):

- **Protocol 2.0**
- **Baudrate 2 000 000** (2 Mbps)
- Pick the U2D2 port explicitly (e.g. `/dev/ttyUSB0`) — when Bluetooth/extra
  serial ports are open, do **not** auto-grab the first port; filter by the FTDI
  device. One bus master at a time (U2D2 *or* OpenCR, not both).

Fault sources to map to `level`:

- `2` (fault): non-zero **Hardware Error Status** (reg 70), over-temperature,
  over-load, or no response.
- `1` (warn): temperature/load near limits, large position error.
- `0` (ok): otherwise.

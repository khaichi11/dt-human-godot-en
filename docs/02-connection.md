# Connection — Twin ↔ Real Robot

The twin talks to a physical OP3 over **rosbridge** (WebSocket + JSON), so Godot
needs no ROS installation. Client: `scripts/RosBridge.gd`.

## Why rosbridge (vs Webots/Gazebo)

- The twin is a *viewer/operator console*, not a physics simulator. It only needs
  joint states + diagnostics, which rosbridge streams as compact JSON.
- WebSocket works the same on Windows/macOS/Linux and through plain networking —
  no SSH, no ROS on the operator machine.
- Lower overhead than running a full Gazebo/Webots scene just to mirror angles.

## Robot side (ROS 2)

```bash
sudo apt install ros-$ROS_DISTRO-rosbridge-suite
ros2 launch rosbridge_server rosbridge_websocket_launch.xml   # ws://<ip>:9090
```

## Operator side (this app)

1. Enter `ws://<robot-ip>:9090` in the toolbar, click **Connect**.
2. Status dot: amber = connecting, teal = connected, red = lost (auto-reconnect).
3. On connect the app switches to **LIVE** mode (UI read-only, robot drives twin).

## Topics & messages

| Direction | Topic | Type | Payload |
|---|---|---|---|
| robot → twin | `/robotis/present_joint_states` | `sensor_msgs/msg/JointState` | `name[]`, `position[]` (rad) |
| robot → twin | `/dt/servo_health` | `std_msgs/msg/String` (JSON) or custom | `{name:[...], level:[0\|1\|2]}` |
| twin → robot | `/robotis/set_joint_states` | `sensor_msgs/msg/JointState` | operator edits (optional) |

`level`: 0 = ok, 1 = warn, 2 = fault. A faulty servo's link blinks red on the
3D model and its row dot turns red (see [04-servos-health.md](04-servos-health.md)).

## Alternative transport (lower latency)

For a direct, ROS-free link the robot-side reader (DT-Human `servo_*` tools) can
push the same JSON over a UDP/TCP socket; swap `RosBridge.gd`'s WebSocket for a
`PacketPeerUDP`/`StreamPeerTCP` and keep the same `joints_received` /
`health_received` signals — the rest of the app is unchanged.

extends Node
# ============================================================================
# RosBridge.gd
# Klien WebSocket untuk rosbridge_suite (ROS 2). Menghubungkan digital twin ke
# robot OP3 asli tanpa perlu ROS di sisi Godot.
#
# Di robot:  ros2 launch rosbridge_server rosbridge_websocket_launch.xml
# Lalu Godot connect ke ws://<ip-robot>:9090 dan subscribe JointState.
#
# Alur:
#   - subscribe topic present_joint_states (sensor_msgs/msg/JointState)
#   - tiap pesan publish -> emit joints_received({nama: radian})
#   - Main menerapkannya ke robot saat mode Live.
#
# Arah balik (kirim perintah operator ke robot) tersedia lewat publish_joints().
# ============================================================================

signal status_changed(state: String)          # "connecting" | "open" | "closed"
signal joints_received(joints: Dictionary)     # nama_joint -> radian

const SUB_TOPIC := "/robotis/present_joint_states"
const SUB_TYPE  := "sensor_msgs/msg/JointState"
const CMD_TOPIC := "/robotis/set_joint_states"
const CMD_TYPE  := "sensor_msgs/msg/JointState"
const RECONNECT_SEC := 3.0

var url := "ws://127.0.0.1:9090"
var _ws := WebSocketPeer.new()
var _want := false
var _subscribed := false
var _cmd_advertised := false
var _reconnect_t := 0.0
var _last_state := WebSocketPeer.STATE_CLOSED


func start(u: String) -> void:
	url = u
	_want = true
	_subscribed = false
	_cmd_advertised = false
	_reconnect_t = 0.0
	emit_signal("status_changed", "connecting")
	_ws.connect_to_url(url)


func stop() -> void:
	_want = false
	_ws.close()
	emit_signal("status_changed", "closed")


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(delta: float) -> void:
	if not _want:
		return
	_ws.poll()
	var state := _ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _subscribed:
				_send({"op": "subscribe", "topic": SUB_TOPIC, "type": SUB_TYPE})
				_subscribed = true
				emit_signal("status_changed", "open")
			while _ws.get_available_packet_count() > 0:
				_handle_message(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _last_state != WebSocketPeer.STATE_CLOSED:
				emit_signal("status_changed", "closed")
			_subscribed = false
			# auto-reconnect selama masih diminta tersambung
			_reconnect_t += delta
			if _reconnect_t >= RECONNECT_SEC:
				_reconnect_t = 0.0
				emit_signal("status_changed", "connecting")
				_ws.connect_to_url(url)
	_last_state = state


func _send(obj: Dictionary) -> void:
	_ws.send_text(JSON.stringify(obj))


# Dipisah agar bisa diuji headless tanpa server (panggil langsung dgn teks JSON)
func _handle_message(text: String) -> void:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.get("op", "") != "publish" or data.get("topic", "") != SUB_TOPIC:
		return
	var msg: Dictionary = data.get("msg", {})
	var names: Array = msg.get("name", [])
	var pos: Array = msg.get("position", [])
	var out := {}
	for i in range(min(names.size(), pos.size())):
		out[String(names[i])] = float(pos[i])
	if not out.is_empty():
		emit_signal("joints_received", out)


# Kirim perintah joint ke robot (arah operator -> robot).
func publish_joints(joints: Dictionary) -> void:
	if not is_open():
		return
	if not _cmd_advertised:
		_send({"op": "advertise", "topic": CMD_TOPIC, "type": CMD_TYPE})
		_cmd_advertised = true
	var names := []
	var positions := []
	for k in joints:
		names.append(k)
		positions.append(joints[k])
	_send({
		"op": "publish", "topic": CMD_TOPIC,
		"msg": {"name": names, "position": positions},
	})

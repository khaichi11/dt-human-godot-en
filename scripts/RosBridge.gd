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
signal health_received(health: Dictionary)     # nama_joint -> "ok"|"warn"|"fault"
signal vision_received(detections: Array)      # [{label, conf, rect:Rect2 0..1}]
signal camera_received(tex: Texture2D)         # frame kamera kepala (JPEG decode)

const SUB_TOPIC := "/robotis/present_joint_states"
const SUB_TYPE  := "sensor_msgs/msg/JointState"
# Topik diagnostik servo (robot-side: baca hardware_error_status / suhu / load
# dari Dynamixel Protocol 2.0 lalu publish). msg: {name:[...], level:[0|1|2]}.
const HEALTH_TOPIC := "/dt/servo_health"
const HEALTH_TYPE  := "std_msgs/msg/String"   # JSON di field data, atau name/level
# Computer vision: node YOLO di robot publish hasil deteksi (JSON) + frame kamera
# terkompresi. Twin meng-overlay box-nya secara realtime di panel CV.
const VISION_TOPIC := "/dt/vision/detections"  # std_msgs/String JSON:
#   {"w":640,"h":480,"det":[{"label":"ball","conf":0.94,"rect":[x,y,w,h]}]}  (rect ternormalisasi 0..1)
const VISION_TYPE  := "std_msgs/msg/String"
const CAM_TOPIC := "/usb_cam/image_raw/compressed"
const CAM_TYPE  := "sensor_msgs/msg/CompressedImage"  # field data = base64 JPEG
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
				_send({"op": "subscribe", "topic": HEALTH_TOPIC, "type": HEALTH_TYPE})
				_send({"op": "subscribe", "topic": VISION_TOPIC, "type": VISION_TYPE})
				_send({"op": "subscribe", "topic": CAM_TOPIC, "type": CAM_TYPE})
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
	if data.get("op", "") != "publish":
		return
	var topic: String = data.get("topic", "")
	if topic == HEALTH_TOPIC:
		_handle_health(data.get("msg", {}))
		return
	if topic == VISION_TOPIC:
		_handle_vision(data.get("msg", {}))
		return
	if topic == CAM_TOPIC:
		_handle_camera(data.get("msg", {}))
		return
	if topic != SUB_TOPIC:
		return
	var msg: Dictionary = data.get("msg", {})
	var names: Array = msg.get("name", [])
	var pos: Array = msg.get("position", [])
	var out := {}
	for i in range(min(names.size(), pos.size())):
		out[String(names[i])] = float(pos[i])
	if not out.is_empty():
		emit_signal("joints_received", out)


func _handle_health(msg: Dictionary) -> void:
	# Dukung dua bentuk: std_msgs/String (field "data" = JSON) atau name/level langsung.
	if msg.has("data"):
		var parsed = JSON.parse_string(String(msg["data"]))
		if typeof(parsed) == TYPE_DICTIONARY:
			msg = parsed
	var names: Array = msg.get("name", [])
	var level: Array = msg.get("level", [])      # 0=ok, 1=warn, 2=fault
	var out := {}
	for i in range(min(names.size(), level.size())):
		var lv := int(level[i])
		out[String(names[i])] = "fault" if lv >= 2 else ("warn" if lv == 1 else "ok")
	if not out.is_empty():
		emit_signal("health_received", out)


# Hasil deteksi YOLO (std_msgs/String, field data = JSON). rect ternormalisasi.
func _handle_vision(msg: Dictionary) -> void:
	var payload = msg
	if msg.has("data"):
		var parsed = JSON.parse_string(String(msg["data"]))
		if typeof(parsed) == TYPE_DICTIONARY:
			payload = parsed
	var det_in: Array = payload.get("det", [])
	var out: Array = []
	for d in det_in:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var r: Array = d.get("rect", [])
		if r.size() < 4:
			continue
		out.append({
			"label": String(d.get("label", "obj")),
			"conf": float(d.get("conf", 0.0)),
			"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
		})
	emit_signal("vision_received", out)


# Frame kamera terkompresi (sensor_msgs/CompressedImage). field data = base64 JPEG.
func _handle_camera(msg: Dictionary) -> void:
	var b64 := String(msg.get("data", ""))
	if b64.is_empty():
		return
	var bytes := Marshalls.base64_to_raw(b64)
	if bytes.is_empty():
		return
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		return
	emit_signal("camera_received", ImageTexture.create_from_image(img))


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

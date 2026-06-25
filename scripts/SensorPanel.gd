extends Control
# ============================================================================
# SensorPanel.gd
# Panel kiri dashboard. Berisi mockup data:
#   - Status header (mode, koneksi, uptime)
#   - Baterai (LiPo 3-cell, voltage, current, capacity)
#   - IMU sensor (gyro xyz, accel xyz, orientation RPY)
#   - 20 Joint status (angle aktual, suhu, status)
#   - Info sistem (FPS, latency, CPU usage)
# ============================================================================

# Daftar 20 joint OP3 sesuai konvensi ROBOTIS
const JOINT_NAMES := [
	"r_sho_pitch",  "l_sho_pitch",
	"r_sho_roll",   "l_sho_roll",
	"r_el",         "l_el",
	"r_hip_yaw",    "l_hip_yaw",
	"r_hip_roll",   "l_hip_roll",
	"r_hip_pitch",  "l_hip_pitch",
	"r_knee",       "l_knee",
	"r_ank_pitch",  "l_ank_pitch",
	"r_ank_roll",   "l_ank_roll",
	"head_pan",     "head_tilt",
]

# Grafik garis ringan (inner class — tanpa file baru)
class Sparkline extends Control:
	var values := PackedFloat32Array()
	var cap := 140
	var line_col := Color(0.55, 0.45, 0.86)
	var vmin := -180.0
	var vmax := 180.0
	var filled := false                     # btop-style area fill under the line
	var grid_col := Color(0.90, 0.88, 0.94)
	var zone_color := false                  # tint line green/amber/red by level

	func push(v: float) -> void:
		values.append(v)
		if values.size() > cap:
			values.remove_at(0)
		queue_redraw()

	func _line_color() -> Color:
		if not zone_color or values.is_empty():
			return line_col
		var t := (values[values.size() - 1] - vmin) / (vmax - vmin)
		if t >= 0.85: return Color(0.90, 0.33, 0.33)
		if t >= 0.60: return Color(0.95, 0.70, 0.25)
		return Color(0.35, 0.75, 0.45)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# horizontal gridlines (0/25/50/75/100%)
		for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var gy: float = h * float(f)
			draw_line(Vector2(0, gy), Vector2(w, gy), grid_col, 1.0)
		# faint vertical gridlines (btop column feel)
		var cols := 6
		for c in range(1, cols):
			var gx: float = w * float(c) / float(cols)
			draw_line(Vector2(gx, 0), Vector2(gx, h), Color(grid_col, 0.5), 1.0)
		if values.size() < 2:
			return
		var pts := PackedVector2Array()
		for i in values.size():
			var x := w * float(i) / float(cap - 1)
			var t := (values[i] - vmin) / (vmax - vmin)
			var y := h * (1.0 - clampf(t, 0.0, 1.0))
			pts.append(Vector2(x, y))
		var lc := _line_color()
		if filled:
			# build a closed polygon down to the baseline and fill translucently
			var poly := PackedVector2Array(pts)
			poly.append(Vector2(pts[pts.size() - 1].x, h))
			poly.append(Vector2(pts[0].x, h))
			draw_colored_polygon(poly, Color(lc, 0.16))
		draw_polyline(pts, lc, 2.0, true)


# Camera viewport with a YOLO-style detection overlay. Renders a real frame
# (`tex`) + real boxes (`detections`) when fed by the robot; otherwise animates
# a soccer-field demo with a tracked ball so the look can be previewed live.
class VisionFeed extends Control:
	var tex: Texture2D = null
	var detections: Array = []          # [{label, conf, rect:Rect2 normalized 0..1}]
	var demo := true
	var _t := 0.0
	var _ball := Vector2(0.5, 0.5)      # normalized ball centre

	func _process(delta: float) -> void:
		if not demo:
			return
		_t += delta
		# ball wanders the pitch (lissajous) — looks like live tracking
		_ball.x = 0.50 + 0.34 * sin(_t * 0.7)
		_ball.y = 0.56 + 0.20 * sin(_t * 1.13 + 1.0)
		var conf := 0.86 + 0.10 * absf(sin(_t * 2.0))
		var bw := 0.16 + 0.015 * sin(_t * 3.0)
		var bh: float = bw * (size.x / max(size.y, 1.0))
		detections = [{
			"label": "ball",
			"conf": conf,
			"rect": Rect2(_ball.x - bw * 0.5, _ball.y - bh * 0.5, bw, bh),
		}]
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0 or h <= 0:
			return
		# --- background: real frame, else a green "pitch" so demo reads as a feed
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.42, 0.22))
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.20, 0.50, 0.26), false, 2.0)
			# centre line + circle (football field cue)
			draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), Color(1, 1, 1, 0.25), 1.0)
			draw_arc(Vector2(w * 0.5, h * 0.5), min(w, h) * 0.16, 0, TAU, 32, Color(1, 1, 1, 0.22), 1.0)
			if demo:
				# draw the ball itself (orange) at its tracked spot
				var bc := Vector2(_ball.x * w, _ball.y * h)
				draw_circle(bc, min(w, h) * 0.05, Color(0.98, 0.55, 0.12))
				draw_arc(bc, min(w, h) * 0.05, 0, TAU, 20, Color(0.6, 0.25, 0.05), 1.5)

		# --- YOLO detection boxes + labels
		var font := ThemeDB.fallback_font
		for d in detections:
			var r: Rect2 = d.get("rect", Rect2())
			var px := Rect2(r.position.x * w, r.position.y * h, r.size.x * w, r.size.y * h)
			var col := Color(0.20, 0.95, 0.55)          # YOLO green
			draw_rect(px, col, false, 2.0)
			# label chip
			var txt := "%s %d%%" % [d.get("label", "?"), int(d.get("conf", 0.0) * 100.0)]
			var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var lbl_bg := Rect2(px.position - Vector2(0, 15), Vector2(ts.x + 8, 15))
			draw_rect(lbl_bg, col)
			draw_string(font, px.position + Vector2(4, -3), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.12, 0.06))

		# --- HUD: crosshair + REC dot so it reads as a vision system
		draw_line(Vector2(w * 0.5 - 8, h * 0.5), Vector2(w * 0.5 + 8, h * 0.5), Color(1, 1, 1, 0.3), 1.0)
		draw_line(Vector2(w * 0.5, h * 0.5 - 8), Vector2(w * 0.5, h * 0.5 + 8), Color(1, 1, 1, 0.3), 1.0)
		var live := demo or tex != null
		draw_circle(Vector2(12, 12), 4, Color(0.95, 0.25, 0.25) if live else Color(0.5, 0.5, 0.5))
		draw_string(ThemeDB.fallback_font, Vector2(22, 16),
			"LIVE" if live else "NO SIGNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1, 1, 1, 0.8))


var graph_spark: Sparkline
var graph_lbl: Label
var sys_cpu_graph: Sparkline   # btop-style CPU history area graph

# Computer-vision (head camera + YOLO) panel
var cv_feed: VisionFeed
var cv_model_lbl: Label
var cv_res_lbl: Label
var cv_fps_lbl: Label
var cv_det_lbl: Label
var cv_demo_btn: Button

# Referensi node yang dibuat dinamis agar bisa di-update tiap frame
var battery_bar: ProgressBar
var battery_voltage_lbl: Label
var battery_current_lbl: Label
var battery_status_lbl: Label

var imu_gyro_lbls := {}     # "x"/"y"/"z" => Label
var imu_accel_lbls := {}
var imu_orient_lbls := {}   # "roll"/"pitch"/"yaw"

var joint_angle_lbls := {}  # joint_name => Label
var joint_temp_lbls := {}   # joint_name => Label (kosong jika tak ditampilkan)
var joint_sliders := {}     # joint_name => HSlider
var joint_name_btns := {}   # joint_name => Button
var joint_health_dots := {} # joint_name => Panel (indikator health)

# Gerakan/pose (diekstrak dari data ROBOTIS) — nama => {hold, steps:[...]}
var motions_data := {}
var motion_option: OptionButton
var play_btn: Button
var stop_btn: Button

# Editor pose/scene — batas seperti ROBOTIS: 7 step/scene, 256 scene tersimpan.
const MAX_STEPS := 7
const MAX_SCENES := 256
const USER_SCENES := "user://op3_scenes.json"
var _edit_steps: Array = []
var scene_name_edit: LineEdit
var step_count_lbl: Label
var _steps_box: VBoxContainer
var _edit_banner: Label        # mode banner di editor (AUTHOR vs MIMIC)

# Kontrol: referensi robot 3D + manipulator (di-set Main lewat bind_controls)
var _robot_ref: Node3D
var _manip_ref: Node
var _updating_ui := false    # cegah feedback loop slider<->robot
var _active_slider := ""     # joint yang slidernya sedang diseret user
var _sel_joint := ""         # joint terpilih (untuk highlight)

# Popup detail servo (ala Dynamixel Wizard) — muncul saat servo diklik di 3D
var _servo_popup: PopupPanel
var _popup_joint := ""
var _popup_lbls := {}        # key => Label nilai
var _popup_title: Label
var _popup_arm_btn: Button

var fps_lbl: Label
var latency_lbl: Label
var uptime_lbl: Label

# Digital-Twin synchronization state (hero card). A DT is distinguished from a
# plain simulation/virtual model by a LIVE, real-time link to the physical asset
# (Grieves; Sharma et al. 2022). We surface that link explicitly.
var _dt_state_lbl: Label       # SYNCHRONIZED / SIMULATION
var _dt_state_dot: Panel
var _dt_link_lbl: Label        # data-flow / freshness line
var _dt_mode_lbl: Label        # operational mode (mimic / author)
var _dt_synced := false
var _dt_latency_ms := 0.0
var _dt_last_data_ms := 0      # Time.get_ticks_msec at last physical packet

# btop-style system monitor (Intel NUC onboard). Bars + per-core strip. Values
# are mocked with believable NUC dynamics; if /dt/system arrives over rosbridge
# call set_system_stats() to drive them from the real machine.
const NUC_CORES := 8
const NUC_RAM_GB := 16.0
const NUC_DISK_GB := 256.0
var sys_cpu_bar: ProgressBar
var sys_cpu_lbl: Label
var sys_core_bars: Array = []          # per-core ProgressBar
var sys_ram_bar: ProgressBar
var sys_ram_lbl: Label
var sys_disk_bar: ProgressBar
var sys_disk_lbl: Label
var sys_cputemp_lbl: Label
var sys_net_lbl: Label
var sys_nuc_uptime_lbl: Label
var _sys_external := false              # true once real /dt/system data arrives
var _sys := {                          # live values (mocked until external)
	"cpu": 22.0, "cores": [], "ram": 38.0, "disk": 47.0,
	"cputemp": 52.0, "net_rx": 1.2, "net_tx": 0.4, "nuc_uptime": 0,
}

# State mockup
var _start_time_ms := 0
var _battery_pct := 87.0
var _temp_base := 38.0  # Celsius


func _ready() -> void:
	_start_time_ms = Time.get_ticks_msec()
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build()


# ----------------------------------------------------------------------------
# BUILD
# ----------------------------------------------------------------------------
func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	# Padding container — ScrollContainer hanya boleh punya satu child
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	# Order follows the digital-twin flow: MONITOR the physical asset
	# (vision, compute, power, sensors, joints, trend) -> CONTROL/author.
	col.add_child(_section_label("MONITORING — physical asset"))
	col.add_child(_build_stat_strip())
	col.add_child(_build_vision_section())             # head camera + YOLO
	col.add_child(_build_system_section())
	col.add_child(_build_battery_section())
	col.add_child(_build_imu_section())
	col.add_child(_build_joints_section())
	col.add_child(_build_graph_section())
	col.add_child(_section_label("CONTROL — drive & author the twin"))
	col.add_child(_build_poses_section())
	col.add_child(_build_editor_section())


# ----------------------------------------------------------------------------
# Helper: bikin "card" (panel dengan judul)
# ----------------------------------------------------------------------------
var _bold_cache: FontVariation

func _bold_font() -> FontVariation:
	if _bold_cache == null:
		var base := get_theme_default_font()
		if base:
			_bold_cache = FontVariation.new()
			_bold_cache.base_font = base
			_bold_cache.variation_opentype = {"wght": 600}
	return _bold_cache


const PAS_PURPLE := Color(0.62, 0.52, 0.92)
const PAS_MINT   := Color(0.42, 0.70, 0.60)
const PAS_SKY    := Color(0.46, 0.71, 0.94)
const PAS_PEACH  := Color(0.98, 0.68, 0.58)
const PAS_AMBER  := Color(0.97, 0.80, 0.46)
const PAS_PINK   := Color(0.93, 0.58, 0.78)


var stat_batt: Label
var stat_temp: Label
var stat_active: Label
var stat_fps: Label

func _build_stat_strip() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_batt   = _stat_chip(row, "BATERAI", "87%", PAS_MINT)
	stat_temp   = _stat_chip(row, "SUHU MAX", "38°", PAS_PEACH)
	stat_active = _stat_chip(row, "JOINT OK", "20/20", PAS_PURPLE)
	stat_fps    = _stat_chip(row, "FPS", "60", PAS_SKY)
	return row


func _stat_chip(parent: HBoxContainer, caption: String, value: String, accent: Color) -> Label:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1)
	sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	sb.border_color = Color(0.91, 0.89, 0.95)
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top = 1; sb.border_width_bottom = 1
	sb.shadow_color = Color(0.55, 0.50, 0.70, 0.10)
	sb.shadow_size = 4; sb.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 9)
	cap.add_theme_color_override("font_color", Color(0.53, 0.51, 0.63))
	vb.add_child(cap)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 17)
	val.add_theme_color_override("font_color", accent)
	var bf := _bold_font()
	if bf:
		val.add_theme_font_override("font", bf)
	vb.add_child(val)

	parent.add_child(p)
	return val


func _make_card(title: String, badge := PAS_PURPLE) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0)
	sb.border_color = Color(0.91, 0.89, 0.95)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0.55, 0.50, 0.70, 0.12)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	# Badge bulat pastel per-seksi
	var badge_p := Panel.new()
	badge_p.custom_minimum_size = Vector2(18, 18)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = badge
	bsb.corner_radius_top_left = 6
	bsb.corner_radius_top_right = 6
	bsb.corner_radius_bottom_left = 6
	bsb.corner_radius_bottom_right = 6
	badge_p.add_theme_stylebox_override("panel", bsb)
	header.add_child(badge_p)

	var title_lbl := Label.new()
	title_lbl.text = title.to_upper()
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.40, 0.38, 0.50))
	var bf := _bold_font()
	if bf:
		title_lbl.add_theme_font_override("font", bf)
	header.add_child(title_lbl)

	vb.add_child(header)

	# Wrapper utk konten user
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	vb.add_child(content)

	# Tambahkan card panel ke parent dan kembalikan content holder
	# Trik: kita bungkus panel agar parent tinggal add_child(_make_card(...).get_parent())
	# Tapi lebih bersih: kita pakai metadata
	content.set_meta("card_panel", panel)
	return content


func _add_card_to(_parent: Container, _content: VBoxContainer) -> void:
	# Deprecated: tiap _build_*_section sudah me-return panel langsung,
	# parent tinggal add_child pada hasil return. Helper ini disisakan
	# kosong untuk kompatibilitas.
	pass


# ----------------------------------------------------------------------------
# 1) STATUS HEADER
# ----------------------------------------------------------------------------
# Small all-caps divider between the MONITOR and CONTROL groups.
func _section_label(text: String) -> Control:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.58, 0.55, 0.68))
	var bf := _bold_font()
	if bf: l.add_theme_font_override("font", bf)
	l.add_theme_constant_override("line_spacing", 0)
	return l


# ----------------------------------------------------------------------------
# COMPUTER VISION — head-camera feed with live YOLO ball detection overlay.
# Shows real frames + boxes when the robot's vision node publishes them; runs a
# realistic demo otherwise so the operator can preview how detection looks live.
# ----------------------------------------------------------------------------
func _build_vision_section() -> PanelContainer:
	var content := _make_card("Computer Vision · YOLO Ball Detection", PAS_SKY)

	# the camera "screen" — a video panel with the detection overlay on top
	var screen := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.09, 0.10, 0.12)
	ssb.set_corner_radius_all(8)
	ssb.content_margin_left = 0; ssb.content_margin_right = 0
	ssb.content_margin_top = 0; ssb.content_margin_bottom = 0
	screen.add_theme_stylebox_override("panel", ssb)
	cv_feed = VisionFeed.new()
	cv_feed.custom_minimum_size = Vector2(0, 188)   # ~4:3 inside the panel
	cv_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.add_child(cv_feed)
	content.add_child(screen)

	# status row: model · resolution · FPS · topic
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 12)
	cv_model_lbl = _cv_tag(st, "YOLOv8-n")
	cv_res_lbl   = _cv_tag(st, "640×480")
	cv_fps_lbl   = _cv_tag(st, "— fps")
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(sp)
	cv_demo_btn = Button.new()
	cv_demo_btn.text = "Demo ON"
	cv_demo_btn.focus_mode = Control.FOCUS_NONE
	cv_demo_btn.tooltip_text = "Pratinjau tampilan deteksi YOLO secara realtime (tanpa robot)"
	cv_demo_btn.pressed.connect(_on_cv_demo_toggle)
	st.add_child(cv_demo_btn)
	content.add_child(st)

	# detection readout line (what YOLO sees right now)
	cv_det_lbl = Label.new()
	cv_det_lbl.text = "Detections: —"
	cv_det_lbl.add_theme_font_size_override("font_size", 11)
	cv_det_lbl.add_theme_color_override("font_color", Color(0.40, 0.38, 0.50))
	content.add_child(cv_det_lbl)

	var topic := Label.new()
	topic.text = "topic: /usb_cam/image_raw  ·  /dt/vision/detections"
	topic.add_theme_font_size_override("font_size", 9)
	topic.add_theme_color_override("font_color", Color(0.58, 0.56, 0.66))
	content.add_child(topic)

	return content.get_meta("card_panel")


func _cv_tag(parent: HBoxContainer, txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.45, 0.43, 0.55))
	parent.add_child(l)
	return l


func _on_cv_demo_toggle() -> void:
	if cv_feed == null:
		return
	cv_feed.demo = not cv_feed.demo
	cv_demo_btn.text = "Demo ON" if cv_feed.demo else "Demo OFF"


# Real wiring: call these from Main when the robot publishes camera + YOLO data.
# tex = decoded camera frame; dets = [{label, conf, rect:Rect2 (normalized)}].
func set_camera_frame(tex: Texture2D) -> void:
	if cv_feed:
		cv_feed.tex = tex
		cv_feed.demo = false
		if cv_demo_btn: cv_demo_btn.text = "Demo OFF"

func set_detections(dets: Array) -> void:
	if cv_feed:
		cv_feed.detections = dets
		cv_feed.demo = false

# Update CV status labels (called from the per-frame update loop).
func _refresh_vision() -> void:
	if cv_feed == null:
		return
	cv_fps_lbl.text = "%d fps" % int(Engine.get_frames_per_second())
	var n := cv_feed.detections.size()
	if n == 0:
		cv_det_lbl.text = "Detections: none"
		cv_det_lbl.add_theme_color_override("font_color", Color(0.55, 0.53, 0.62))
	else:
		var d: Dictionary = cv_feed.detections[0]
		var r: Rect2 = d.get("rect", Rect2())
		var cx := r.position.x + r.size.x * 0.5
		var cy := r.position.y + r.size.y * 0.5
		cv_det_lbl.text = "%s  %d%%  @ (%.2f, %.2f)" % [
			d.get("label", "?"), int(d.get("conf", 0.0) * 100.0), cx, cy]
		cv_det_lbl.add_theme_color_override("font_color", Color(0.20, 0.62, 0.42))


# Called by Main on connection/data changes. connected = live link to physical.
func set_sync_state(connected: bool, latency_ms: float) -> void:
	_dt_synced = connected
	_dt_latency_ms = latency_ms
	if connected:
		_dt_last_data_ms = Time.get_ticks_msec()
	_apply_sync_visuals()


func _apply_sync_visuals() -> void:
	if _dt_state_lbl == null:
		return
	if _dt_synced:
		_dt_state_lbl.text = "SYNCHRONIZED"
		_dt_state_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 0.55))
		_set_dot_color(_dt_state_dot, Color(0.30, 0.90, 0.45))
		_dt_link_lbl.text = "Physical → Virtual link active · latency %.0f ms" % _dt_latency_ms
	else:
		_dt_state_lbl.text = "SIMULATION"
		_dt_state_lbl.add_theme_color_override("font_color", Color(0.97, 0.75, 0.35))
		_set_dot_color(_dt_state_dot, Color(0.75, 0.78, 0.82))
		_dt_link_lbl.text = "No physical link — virtual model only (connect a robot to twin it)"
	_update_dt_mode_lbl()


func _update_dt_mode_lbl() -> void:
	if _dt_mode_lbl == null:
		return
	# Reuse joint-slider editability as the proxy for ATUR(author) vs LIVE(mimic)
	var authoring := false
	for jn in joint_sliders:
		authoring = (joint_sliders[jn] as HSlider).editable
		break
	if authoring:
		_dt_mode_lbl.text = "Mode: AUTHOR — you pose the virtual model (Physical follows on deploy)"
	else:
		_dt_mode_lbl.text = "Mode: MIMIC — virtual mirrors the physical robot in real time"


func _update_edit_banner(editable: bool) -> void:
	if _edit_banner == null:
		return
	if editable:
		_edit_banner.text = "● AUTHOR MODE — servo editing enabled. Arm a servo to change its angle."
		_edit_banner.add_theme_color_override("font_color", Color(0.42, 0.70, 0.45))
	else:
		_edit_banner.text = "○ MIMIC MODE — editing locked while mirroring the robot. Switch to ATUR to author poses."
		_edit_banner.add_theme_color_override("font_color", Color(0.85, 0.55, 0.25))


# ----------------------------------------------------------------------------
# 2) BATTERY SECTION
# ----------------------------------------------------------------------------
func _build_poses_section() -> PanelContainer:
	var content := _make_card("Gerakan & Pose (data ROBOTIS)")
	_load_motions()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	motion_option = OptionButton.new()
	motion_option.focus_mode = Control.FOCUS_NONE
	motion_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mname in motions_data.keys():
		motion_option.add_item(mname)
	row.add_child(motion_option)

	play_btn = Button.new()
	play_btn.text = "▶ Play"
	play_btn.focus_mode = Control.FOCUS_NONE
	play_btn.custom_minimum_size = Vector2(64, 0)
	play_btn.pressed.connect(_on_play)
	row.add_child(play_btn)

	stop_btn = Button.new()
	stop_btn.text = "■"
	stop_btn.focus_mode = Control.FOCUS_NONE
	stop_btn.custom_minimum_size = Vector2(32, 0)
	stop_btn.pressed.connect(_on_stop)
	row.add_child(stop_btn)

	content.add_child(row)

	var hint := Label.new()
	hint.text = "Jalan/gerak mengikuti robot asli saat mode LIVE tersambung."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.53, 0.51, 0.63))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	return content.get_meta("card_panel")


# ----------------------------------------------------------------------------
# EDITOR POSE/SCENE — rekam pose robot sbg step (maks 7), simpan jadi scene
# bernama (maks 256). Tersimpan ke user:// dan muncul di daftar gerakan.
# ----------------------------------------------------------------------------
func _build_editor_section() -> PanelContainer:
	var content := _make_card("Pose / Scene Editor", PAS_PINK)

	# Mode banner — pose authoring only works in AUTHOR (Atur) mode
	_edit_banner = Label.new()
	_edit_banner.add_theme_font_size_override("font_size", 10)
	_edit_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_edit_banner)

	# Numbered flow so the authoring sequence is unambiguous
	var flow := Label.new()
	flow.text = "1· Pilih servo (klik di 3D)   2· Tekan ARM di popup   3· Putar ring / geser slider   4· + Step   5· Simpan Scene"
	flow.add_theme_font_size_override("font_size", 10)
	flow.add_theme_color_override("font_color", Color(0.53, 0.51, 0.63))
	flow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(flow)

	scene_name_edit = LineEdit.new()
	scene_name_edit.placeholder_text = "Nama scene (mis. Scene 1)"
	scene_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scene_name_edit)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var add_btn := Button.new()
	add_btn.text = "+ Step"
	add_btn.tooltip_text = "Atur pose robot dulu, lalu rekam sbg step (maks 7)"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_capture_step)
	btns.add_child(add_btn)

	var prev_btn := Button.new()
	prev_btn.text = "▶ Pratinjau"
	prev_btn.tooltip_text = "Mainkan urutan step yang sudah direkam"
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.pressed.connect(_on_preview_steps)
	btns.add_child(prev_btn)

	content.add_child(btns)

	step_count_lbl = Label.new()
	step_count_lbl.add_theme_font_size_override("font_size", 10)
	step_count_lbl.add_theme_color_override("font_color", Color(0.53, 0.51, 0.63))
	content.add_child(step_count_lbl)

	# Daftar step yang direkam (Step 1, Step 2, …) — bisa dihapus per-step
	_steps_box = VBoxContainer.new()
	_steps_box.add_theme_constant_override("separation", 2)
	content.add_child(_steps_box)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	var save_btn := Button.new()
	save_btn.text = "Simpan Scene"
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_scene)
	save_row.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Muat"
	load_btn.tooltip_text = "Muat scene terpilih (di daftar Gerakan) ke editor untuk diubah"
	load_btn.focus_mode = Control.FOCUS_NONE
	load_btn.pressed.connect(_on_load_to_editor)
	save_row.add_child(load_btn)
	var clr_btn := Button.new()
	clr_btn.text = "Reset"
	clr_btn.focus_mode = Control.FOCUS_NONE
	clr_btn.pressed.connect(_on_clear_scene)
	save_row.add_child(clr_btn)
	content.add_child(save_row)

	_update_step_count()
	_rebuild_step_list()
	_update_edit_banner(true)
	return content.get_meta("card_panel")


func _rebuild_step_list() -> void:
	if _steps_box == null:
		return
	for c in _steps_box.get_children():
		c.queue_free()
	for i in _edit_steps.size():
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = "Step %d  ·  pose terekam" % (i + 1)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(lbl)
		var del := Button.new()
		del.text = "✕"
		del.focus_mode = Control.FOCUS_NONE
		del.custom_minimum_size = Vector2(26, 0)
		del.pressed.connect(_remove_step.bind(i))
		r.add_child(del)
		_steps_box.add_child(r)


func _remove_step(idx: int) -> void:
	if idx >= 0 and idx < _edit_steps.size():
		_edit_steps.remove_at(idx)
		_update_step_count()
		_rebuild_step_list()


func _on_preview_steps() -> void:
	if _robot_ref and _robot_ref.has_method("play_motion") and not _edit_steps.is_empty():
		_robot_ref.play_motion(_edit_steps.duplicate(true), false)


func _on_load_to_editor() -> void:
	# Muat scene terpilih di daftar Gerakan ke editor (untuk diubah step-nya)
	if motion_option == null:
		return
	var nm := motion_option.get_item_text(motion_option.selected)
	if not motions_data.has(nm):
		return
	_edit_steps = motions_data[nm].get("steps", []).duplicate(true)
	scene_name_edit.text = nm
	_update_step_count()
	_rebuild_step_list()


func _capture_pose() -> Dictionary:
	var j := {}
	if _robot_ref and _robot_ref.has_method("get_joint_angle"):
		for jn in JOINT_NAMES:
			j[jn] = round(rad_to_deg(_robot_ref.get_joint_angle(jn)) * 10.0) / 10.0
	return {"t": 0.6, "p": 0.2, "j": j}


func _on_capture_step() -> void:
	if _edit_steps.size() >= MAX_STEPS:
		_flash_count("Maks %d step!" % MAX_STEPS)
		return
	_edit_steps.append(_capture_pose())
	_update_step_count()
	_rebuild_step_list()


func _on_clear_scene() -> void:
	_edit_steps.clear()
	_update_step_count()
	_rebuild_step_list()


func _on_save_scene() -> void:
	var nm := scene_name_edit.text.strip_edges()
	if nm == "" or _edit_steps.is_empty():
		_flash_count("Isi nama & minimal 1 step")
		return
	var user_count := 0
	for k in motions_data:
		if motions_data[k].get("user", false):
			user_count += 1
	if user_count >= MAX_SCENES and not motions_data.has(nm):
		_flash_count("Maks %d scene tersimpan" % MAX_SCENES)
		return
	motions_data[nm] = {"hold": true, "user": true, "steps": _edit_steps.duplicate(true)}
	_save_user_scenes()
	if motion_option:
		_refresh_motion_options()
	_edit_steps.clear()
	_update_step_count()
	_rebuild_step_list()
	_flash_count("Tersimpan: %s" % nm)


func _refresh_motion_options() -> void:
	var cur := motion_option.get_item_text(motion_option.selected) if motion_option.item_count > 0 else ""
	motion_option.clear()
	for mname in motions_data.keys():
		motion_option.add_item(mname)
	for i in motion_option.item_count:
		if motion_option.get_item_text(i) == cur:
			motion_option.select(i)


func _update_step_count() -> void:
	if step_count_lbl:
		step_count_lbl.text = "Step terekam: %d/%d" % [_edit_steps.size(), MAX_STEPS]


func _flash_count(msg: String) -> void:
	if step_count_lbl:
		step_count_lbl.text = msg


func _save_user_scenes() -> void:
	var out := {}
	for k in motions_data:
		if motions_data[k].get("user", false):
			out[k] = motions_data[k]
	var f := FileAccess.open(USER_SCENES, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))
		f.close()


func _load_user_scenes() -> void:
	if not FileAccess.file_exists(USER_SCENES):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(USER_SCENES))
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			motions_data[k] = parsed[k]


func _load_motions() -> void:
	if not FileAccess.file_exists("res://assets/motions.json"):
		return
	var txt := FileAccess.get_file_as_string("res://assets/motions.json")
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		motions_data = parsed
	_load_user_scenes()    # scene buatan user (user://) ikut muncul di daftar


func _on_play() -> void:
	if _robot_ref == null or motion_option == null:
		return
	var mname := motion_option.get_item_text(motion_option.selected)
	if not motions_data.has(mname):
		return
	var m: Dictionary = motions_data[mname]
	var steps: Array = m.get("steps", [])
	var hold: bool = m.get("hold", true)
	if _robot_ref.has_method("play_motion"):
		_robot_ref.play_motion(steps, not hold)   # gestur (hold=false) balik ke default


func _on_stop() -> void:
	if _robot_ref == null:
		return
	if _robot_ref.has_method("stop_motion"):
		_robot_ref.stop_motion()
	if _robot_ref.has_method("go_default"):
		_robot_ref.go_default()


func _on_reset_joint(jname: String) -> void:
	# Kembalikan satu servo ke nilai default-nya
	if _robot_ref and _robot_ref.has_method("reset_joint"):
		_robot_ref.reset_joint(jname)
		if _manip_ref and _manip_ref.has_method("select_joint"):
			_manip_ref.select_joint(jname)
			_highlight_selected(jname)


func _on_reset_pose() -> void:
	# Kembalikan semua servo ke pose default (walk-ready), beranimasi halus
	if _robot_ref == null:
		return
	if _robot_ref.has_method("stop_motion"):
		_robot_ref.stop_motion()
	if _robot_ref.has_method("go_default"):
		_robot_ref.go_default()


func _build_graph_section() -> PanelContainer:
	var content := _make_card("Tren Sudut Joint", PAS_SKY)

	graph_lbl = Label.new()
	graph_lbl.text = "— (pilih joint)"
	graph_lbl.add_theme_font_size_override("font_size", 11)
	graph_lbl.add_theme_color_override("font_color", Color(0.40, 0.38, 0.50))
	content.add_child(graph_lbl)

	graph_spark = Sparkline.new()
	graph_spark.custom_minimum_size = Vector2(0, 64)
	graph_spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(graph_spark)

	return content.get_meta("card_panel")


func _build_battery_section() -> PanelContainer:
	var content := _make_card("Battery · LiPo 3S", PAS_MINT)

	# Bar besar
	battery_bar = ProgressBar.new()
	battery_bar.min_value = 0
	battery_bar.max_value = 100
	battery_bar.value = _battery_pct
	battery_bar.show_percentage = false
	battery_bar.custom_minimum_size = Vector2(0, 22)
	content.add_child(battery_bar)

	var pct_row := HBoxContainer.new()
	battery_voltage_lbl = Label.new()
	battery_voltage_lbl.text = "11.7 V"
	battery_voltage_lbl.add_theme_font_size_override("font_size", 22)
	battery_voltage_lbl.add_theme_color_override("font_color", Color(0.22, 0.20, 0.32))
	pct_row.add_child(battery_voltage_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pct_row.add_child(spacer)

	battery_status_lbl = Label.new()
	battery_status_lbl.text = "%.0f%%" % _battery_pct
	battery_status_lbl.add_theme_font_size_override("font_size", 22)
	battery_status_lbl.add_theme_color_override("font_color", Color(0.16, 0.56, 0.47))
	pct_row.add_child(battery_status_lbl)
	content.add_child(pct_row)

	# Detail grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)

	battery_current_lbl = _add_kv(grid, "Current", "1.42 A")
	_add_kv(grid, "Cells", "3S (3.90 V/cell)")
	_add_kv(grid, "Capacity", "1800 mAh")
	_add_kv(grid, "Est. Runtime", "≈ 34 min")

	return content.get_meta("card_panel")


# Helper utk grid key-value
func _add_kv(grid: GridContainer, key: String, value: String) -> Label:
	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", Color(0.45, 0.49, 0.55))
	k.add_theme_font_size_override("font_size", 11)
	grid.add_child(k)

	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", Color(0.13, 0.15, 0.18))
	v.add_theme_font_size_override("font_size", 12)
	grid.add_child(v)
	return v


# ----------------------------------------------------------------------------
# 3) IMU SECTION
# ----------------------------------------------------------------------------
func _build_imu_section() -> PanelContainer:
	var content := _make_card("IMU Sensor · MPU-9250", PAS_SKY)

	# Tiga sub-grup: Gyro / Accel / Orientation
	content.add_child(_build_imu_subgroup("Gyroscope (°/s)", imu_gyro_lbls,
		Color(1.0, 0.45, 0.45), Color(0.16, 0.56, 0.47), Color(0.55, 0.45, 0.86)))
	content.add_child(_build_imu_subgroup("Accelerometer (m/s²)", imu_accel_lbls,
		Color(1.0, 0.45, 0.45), Color(0.16, 0.56, 0.47), Color(0.55, 0.45, 0.86)))
	content.add_child(_build_imu_orientation_group())

	return content.get_meta("card_panel")


func _build_imu_subgroup(title: String, target_dict: Dictionary,
		col_x: Color, col_y: Color, col_z: Color) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", Color(0.45, 0.49, 0.55))
	t.add_theme_font_size_override("font_size", 11)
	vb.add_child(t)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)

	for axis in ["x", "y", "z"]:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 1.0, 1.0)
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", sb)

		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		cell.add_child(inner)

		var ax := Label.new()
		ax.text = axis.to_upper()
		var col: Color = col_x
		if axis == "y": col = col_y
		elif axis == "z": col = col_z
		ax.add_theme_color_override("font_color", col)
		ax.add_theme_font_size_override("font_size", 10)
		inner.add_child(ax)

		var val := Label.new()
		val.text = "0.00"
		val.add_theme_color_override("font_color", Color(0.13, 0.15, 0.18))
		val.add_theme_font_size_override("font_size", 13)
		inner.add_child(val)

		target_dict[axis] = val
		hb.add_child(cell)

	return vb


func _build_imu_orientation_group() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	var t := Label.new()
	t.text = "Orientation (deg)"
	t.add_theme_color_override("font_color", Color(0.45, 0.49, 0.55))
	t.add_theme_font_size_override("font_size", 11)
	vb.add_child(t)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)

	for kv in [["Roll", "roll"], ["Pitch", "pitch"], ["Yaw", "yaw"]]:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 1.0, 1.0)
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", sb)

		var inner := VBoxContainer.new()
		cell.add_child(inner)

		var lab := Label.new()
		lab.text = kv[0]
		lab.add_theme_color_override("font_color", Color(0.55, 0.45, 0.86))
		lab.add_theme_font_size_override("font_size", 10)
		inner.add_child(lab)

		var val := Label.new()
		val.text = "0.0°"
		val.add_theme_color_override("font_color", Color(0.13, 0.15, 0.18))
		val.add_theme_font_size_override("font_size", 13)
		inner.add_child(val)
		imu_orient_lbls[kv[1]] = val

		hb.add_child(cell)

	return vb


# ----------------------------------------------------------------------------
# 4) JOINTS SECTION (20 DOF)
# ----------------------------------------------------------------------------
func _build_joints_section() -> PanelContainer:
	var content := _make_card("Joints · 20 DOF — klik nama, geser slider", PAS_PEACH)

	# Tombol kembalikan semua joint ke pose default (walk-ready)
	var reset_row := HBoxContainer.new()
	var reset_btn := Button.new()
	reset_btn.text = "↺ Kembalikan Pose Default"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.tooltip_text = "Kembalikan semua servo ke pose walk-ready"
	reset_btn.pressed.connect(_on_reset_pose)
	reset_row.add_child(reset_btn)
	content.add_child(reset_row)

	# Baris-baris joint: [nama (tombol)] [slider] [sudut]
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(rows)

	for i in JOINT_NAMES.size():
		var jname: String = JOINT_NAMES[i]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Titik health servo (hijau=ok, kuning=warn, merah=fault)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_set_dot_color(dot, Color(0.42, 0.70, 0.60))
		joint_health_dots[jname] = dot
		row.add_child(dot)

		# Nama + ID servo (tombol untuk memilih joint)
		var sid := i + 1                       # ID Dynamixel = urutan 1..20
		var name_btn := Button.new()
		name_btn.text = "%02d  %s" % [sid, jname]
		name_btn.flat = true
		name_btn.focus_mode = Control.FOCUS_NONE
		name_btn.custom_minimum_size = Vector2(104, 0)
		name_btn.add_theme_font_size_override("font_size", 11)
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.add_theme_color_override("font_color", Color(0.20, 0.23, 0.28))
		name_btn.pressed.connect(_on_joint_clicked.bind(jname))
		joint_name_btns[jname] = name_btn
		row.add_child(name_btn)

		# Slider kontrol sudut (-180..180 derajat)
		var sl := HSlider.new()
		sl.min_value = -180.0
		sl.max_value = 180.0
		sl.step = 1.0
		sl.value = 0.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(70, 0)
		sl.value_changed.connect(_on_slider_changed.bind(jname))
		sl.drag_started.connect(func(): _active_slider = jname)
		sl.drag_ended.connect(func(_v): _active_slider = "")
		joint_sliders[jname] = sl
		row.add_child(sl)

		# Nilai sudut
		var angle_lbl := Label.new()
		angle_lbl.text = "+0.0°"
		angle_lbl.add_theme_color_override("font_color", Color(0.55, 0.45, 0.86))
		angle_lbl.add_theme_font_size_override("font_size", 11)
		angle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		angle_lbl.custom_minimum_size = Vector2(48, 0)
		joint_angle_lbls[jname] = angle_lbl
		row.add_child(angle_lbl)

		# Tombol kembalikan servo ini ke default-nya
		var rb := Button.new()
		rb.text = "↺"
		rb.focus_mode = Control.FOCUS_NONE
		rb.flat = true
		rb.custom_minimum_size = Vector2(22, 0)
		rb.tooltip_text = "Kembalikan %s ke default" % jname
		rb.pressed.connect(_on_reset_joint.bind(jname))
		row.add_child(rb)

		rows.add_child(row)

	return content.get_meta("card_panel")


# ----------------------------------------------------------------------------
# Kontrol joint — dipanggil Main lewat bind_controls()
# ----------------------------------------------------------------------------
func bind_controls(robot: Node3D, manipulator: Node) -> void:
	_robot_ref = robot
	_manip_ref = manipulator
	if manipulator and manipulator.has_signal("joint_rotated"):
		manipulator.joint_rotated.connect(_on_manip_rotated)
	if manipulator and manipulator.has_signal("servo_clicked"):
		manipulator.servo_clicked.connect(_on_servo_clicked)
	_build_servo_popup()

	# Set rentang + nilai awal tiap slider (guard agar tak menulis balik ke robot)
	if robot and robot.has_method("get_joint_limit"):
		_updating_ui = true
		for jname in joint_sliders:
			var lim: Vector2 = robot.get_joint_limit(jname)
			var sl: HSlider = joint_sliders[jname]
			sl.min_value = rad_to_deg(lim.x)
			sl.max_value = rad_to_deg(lim.y)
			sl.value = rad_to_deg(robot.get_joint_angle(jname))
			sl.tooltip_text = "%s: %.0f° … %.0f°" % [jname, sl.min_value, sl.max_value]
		_updating_ui = false

	# Tooltip nama joint: model servo + ID Dynamixel + bagian tubuh
	if robot and robot.has_method("get_servo_id"):
		for jname in joint_name_btns:
			joint_name_btns[jname].tooltip_text = "Dynamixel %s · ID %d · %s" % [
				robot.SERVO_MODEL, robot.get_servo_id(jname), robot.get_servo_part(jname)]


# Mode Atur (true): slider aktif. Mode Live (false): slider mati, panel hanya
# menampilkan data joint yang masuk dari robot.
func set_editable(editable: bool) -> void:
	for jname in joint_sliders:
		joint_sliders[jname].editable = editable
		joint_sliders[jname].mouse_filter = (Control.MOUSE_FILTER_STOP if editable
			else Control.MOUSE_FILTER_IGNORE)
	for jname in joint_name_btns:
		joint_name_btns[jname].disabled = not editable
	if play_btn:
		play_btn.disabled = not editable
	if stop_btn:
		stop_btn.disabled = not editable
	if motion_option:
		motion_option.disabled = not editable
	_update_dt_mode_lbl()
	_update_edit_banner(editable)


func _set_dot_color(dot: Panel, c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	dot.add_theme_stylebox_override("panel", sb)


# Status health servo dari robot (nama_joint -> "ok"|"warn"|"fault")
func set_servo_health(health: Dictionary) -> void:
	for jname in health:
		if not joint_health_dots.has(jname):
			continue
		match String(health[jname]):
			"fault": _set_dot_color(joint_health_dots[jname], Color(0.93, 0.20, 0.20))
			"warn":  _set_dot_color(joint_health_dots[jname], Color(0.97, 0.75, 0.20))
			_:       _set_dot_color(joint_health_dots[jname], Color(0.42, 0.70, 0.60))


func _on_joint_clicked(jname: String) -> void:
	if _manip_ref and _manip_ref.has_method("select_joint"):
		_manip_ref.select_joint(jname)
	_highlight_selected(jname)


# ----------------------------------------------------------------------------
# Popup detail servo (ala Dynamixel Wizard)
# ----------------------------------------------------------------------------
const POPUP_ROWS := [
	["pos",   "Present Position"],
	["goal",  "Goal Position"],
	["temp",  "Present Temperature"],
	["load",  "Present Load (torque)"],
	["fatig", "Fatigue (duty est.)"],
	["volt",  "Present Voltage"],
	["err",   "Hardware Error"],
	["move",  "Moving"],
	["health","Health"],
]

func _build_servo_popup() -> void:
	if _servo_popup:
		return
	_servo_popup = PopupPanel.new()
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.13, 0.14, 0.18)
	pb.border_color = Color(0.30, 0.85, 0.95)
	pb.set_border_width_all(1)
	pb.set_corner_radius_all(10)
	pb.set_content_margin_all(14)
	_servo_popup.add_theme_stylebox_override("panel", pb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(248, 0)
	_servo_popup.add_child(vb)

	_popup_title = Label.new()
	_popup_title.add_theme_font_size_override("font_size", 14)
	_popup_title.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	var bf := _bold_font()
	if bf: _popup_title.add_theme_font_override("font", bf)
	vb.add_child(_popup_title)

	var sub := Label.new()
	sub.name = "sub"
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	vb.add_child(sub)

	var sep := HSeparator.new()
	vb.add_child(sep)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	vb.add_child(grid)
	for row in POPUP_ROWS:
		var k := Label.new()
		k.text = row[1]
		k.add_theme_font_size_override("font_size", 11)
		k.add_theme_color_override("font_color", Color(0.66, 0.70, 0.78))
		grid.add_child(k)
		var v := Label.new()
		v.text = "—"
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_font_size_override("font_size", 11)
		v.add_theme_color_override("font_color", Color(0.90, 0.93, 0.97))
		grid.add_child(v)
		_popup_lbls[row[0]] = v

	var sep2 := HSeparator.new()
	vb.add_child(sep2)

	# baris tombol: ARM (point) + Reset
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	vb.add_child(btns)

	_popup_arm_btn = Button.new()
	_popup_arm_btn.focus_mode = Control.FOCUS_NONE
	_popup_arm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup_arm_btn.tooltip_text = "Tekan dulu untuk meng-ARM servo ini sebelum sudutnya bisa diubah (anti salah ubah)"
	_popup_arm_btn.pressed.connect(_on_popup_arm)
	btns.add_child(_popup_arm_btn)

	var reset_b := Button.new()
	reset_b.text = "↺ Reset"
	reset_b.focus_mode = Control.FOCUS_NONE
	reset_b.tooltip_text = "Kembalikan servo ini ke pose default"
	reset_b.pressed.connect(func():
		if _popup_joint != "" and _robot_ref and _robot_ref.has_method("reset_joint"):
			_robot_ref.reset_joint(_popup_joint))
	btns.add_child(reset_b)

	add_child(_servo_popup)


func _on_servo_clicked(jname: String) -> void:
	_popup_joint = jname
	_highlight_selected(jname)
	_refresh_servo_popup()
	_refresh_arm_btn()
	_servo_popup.reset_size()
	# tempatkan dekat kursor tapi tetap di dalam layar
	var mp := get_viewport().get_mouse_position()
	_servo_popup.position = Vector2i(mp + Vector2(18, 12))
	_servo_popup.popup()


func _on_popup_arm() -> void:
	if _manip_ref == null or _popup_joint == "":
		return
	# pastikan joint ini yang terpilih, lalu toggle arm
	if _manip_ref.has_method("select_joint") and _manip_ref.get_selected() != _popup_joint:
		_manip_ref.select_joint(_popup_joint)
	var now := false
	if _manip_ref.has_method("is_armed"):
		now = _manip_ref.is_armed()
	if _manip_ref.has_method("set_armed"):
		_manip_ref.set_armed(not now)
	_refresh_arm_btn()


func _refresh_arm_btn() -> void:
	if _popup_arm_btn == null:
		return
	var armed := false
	if _manip_ref and _manip_ref.has_method("is_armed") \
			and _manip_ref.get_selected() == _popup_joint:
		armed = _manip_ref.is_armed()
	if armed:
		_popup_arm_btn.text = "● ARMED — bisa diputar"
		_popup_arm_btn.add_theme_color_override("font_color", Color(0.30, 0.95, 0.45))
	else:
		_popup_arm_btn.text = "○ ARM EDIT (tekan)"
		_popup_arm_btn.add_theme_color_override("font_color", Color(0.97, 0.80, 0.46))


func _refresh_servo_popup() -> void:
	if _servo_popup == null or not _servo_popup.visible or _popup_joint == "":
		return
	var jn := _popup_joint
	var r := _robot_ref
	var deg := 0.0
	if r and r.has_method("get_joint_angle"):
		deg = rad_to_deg(r.get_joint_angle(jn))
	var tick := int(round(deg * 4096.0 / 360.0)) + 2048
	var sid := 0
	var part := ""
	if r and r.has_method("get_servo_id"): sid = r.get_servo_id(jn)
	if r and r.has_method("get_servo_part"): part = r.get_servo_part(jn)
	_popup_title.text = "ID %d · %s" % [sid, jn]
	var sub: Label = _servo_popup.get_child(0).get_node("sub")
	if sub:
		sub.text = "Dynamixel %s · %s" % [
			(r.SERVO_MODEL if r else "XM-430-W350"), part]

	# mock telemetri yang masuk akal (hingga /dt ada datanya betulan)
	var t := Time.get_ticks_msec() / 1000.0
	var idx := float(JOINT_NAMES.find(jn))
	var temp := _temp_base + sin(t * 0.3 + idx * 0.2) * 2.5
	var loadp := clampf(absf(deg) * 0.35 + sin(t * 1.2 + idx) * 6.0, 0.0, 100.0)
	var fatig := clampf(absf(deg) * 0.5 + (idx * 1.7), 0.0, 100.0)
	var volt := 11.7 + sin(t * 0.5 + idx) * 0.15
	var health := "ok"
	if r and r.has_method("get_servo_health"): health = r.get_servo_health(jn)
	var err := "None (0x00)"
	if health == "fault": err = "Overload/Temp (0x20)"
	elif health == "warn": err = "Near limit"

	_popup_lbls["pos"].text   = "%+.1f°  (%d)" % [deg, tick]
	_popup_lbls["goal"].text  = "%+.1f°" % deg
	_popup_lbls["temp"].text  = "%.0f °C" % temp
	_popup_lbls["load"].text  = "%.0f %%" % loadp
	_popup_lbls["fatig"].text = "%.0f %%" % fatig
	_popup_lbls["volt"].text  = "%.2f V" % volt
	_popup_lbls["err"].text   = err
	_popup_lbls["move"].text  = "Yes" if (r and r.has_method("get_joint_angle")) else "No"
	_popup_lbls["health"].text = health.to_upper()

	# warnai nilai kritis
	_color_val(_popup_lbls["temp"], temp, 45.0, 55.0)
	_color_val(_popup_lbls["load"], loadp, 60.0, 85.0)
	_color_val(_popup_lbls["fatig"], fatig, 60.0, 85.0)
	_popup_lbls["health"].add_theme_color_override("font_color",
		Color(0.95, 0.30, 0.30) if health == "fault" else
		(Color(0.97, 0.75, 0.20) if health == "warn" else Color(0.40, 0.90, 0.55)))


func _color_val(lbl: Label, v: float, warn: float, crit: float) -> void:
	lbl.add_theme_color_override("font_color",
		Color(0.95, 0.30, 0.30) if v >= crit else
		(Color(0.97, 0.75, 0.20) if v >= warn else Color(0.90, 0.93, 0.97)))


func _on_slider_changed(value: float, jname: String) -> void:
	if _updating_ui:
		return
	if _robot_ref and _robot_ref.has_method("set_joint_angle"):
		_robot_ref.set_joint_angle(jname, deg_to_rad(value))
	# memutar via slider juga memilih joint (tampilkan ring di 3D)
	if _manip_ref and _manip_ref.has_method("select_joint") and _sel_joint != jname:
		_manip_ref.select_joint(jname)
		_highlight_selected(jname)


func _on_manip_rotated(jname: String, radians: float) -> void:
	# joint diputar via ring 3D -> update slider + highlight
	if joint_sliders.has(jname):
		_updating_ui = true
		joint_sliders[jname].value = rad_to_deg(radians)
		_updating_ui = false
	if _sel_joint != jname:
		_highlight_selected(jname)


func _highlight_selected(jname: String) -> void:
	if _sel_joint != "" and joint_name_btns.has(_sel_joint):
		joint_name_btns[_sel_joint].add_theme_color_override("font_color", Color(0.20, 0.23, 0.28))
	_sel_joint = jname
	if joint_name_btns.has(jname):
		joint_name_btns[jname].add_theme_color_override("font_color", Color(0.16, 0.56, 0.47))


func _make_th(parent: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.50, 0.54, 0.60))
	l.add_theme_font_size_override("font_size", 10)
	parent.add_child(l)


# ----------------------------------------------------------------------------
# 5) SYSTEM SECTION
# ----------------------------------------------------------------------------
func _build_system_section() -> PanelContainer:
	var content := _make_card("System · Intel NUC (btop)", PAS_AMBER)

	# --- CPU total + per-core strip --------------------------------------
	var cpu_head := HBoxContainer.new()
	cpu_head.add_theme_constant_override("separation", 8)
	var cpu_cap := Label.new()
	cpu_cap.text = "CPU"
	cpu_cap.add_theme_font_size_override("font_size", 11)
	cpu_cap.add_theme_color_override("font_color", Color(0.45, 0.43, 0.55))
	cpu_cap.custom_minimum_size = Vector2(42, 0)
	cpu_head.add_child(cpu_cap)
	sys_cpu_bar = _mk_bar(PAS_SKY)
	sys_cpu_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpu_head.add_child(sys_cpu_bar)
	sys_cpu_lbl = _mk_val("22%")
	cpu_head.add_child(sys_cpu_lbl)
	content.add_child(cpu_head)

	# CPU history area graph (btop signature)
	sys_cpu_graph = Sparkline.new()
	sys_cpu_graph.custom_minimum_size = Vector2(0, 52)
	sys_cpu_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sys_cpu_graph.vmin = 0.0
	sys_cpu_graph.vmax = 100.0
	sys_cpu_graph.filled = true
	sys_cpu_graph.zone_color = true
	sys_cpu_graph.line_col = Color(0.46, 0.71, 0.94)
	content.add_child(sys_cpu_graph)

	# per-core mini bars (btop signature)
	var cores := GridContainer.new()
	cores.columns = 4
	cores.add_theme_constant_override("h_separation", 6)
	cores.add_theme_constant_override("v_separation", 4)
	for i in NUC_CORES:
		var cb := _mk_bar(PAS_PURPLE)
		cb.custom_minimum_size = Vector2(0, 7)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sys_core_bars.append(cb)
		cores.add_child(cb)
		_sys["cores"].append(18.0 + i * 3.0)
	content.add_child(cores)

	# --- RAM -------------------------------------------------------------
	content.add_child(_mk_usage_row("RAM", PAS_MINT, func(b, l):
		sys_ram_bar = b; sys_ram_lbl = l))
	# --- Disk ------------------------------------------------------------
	content.add_child(_mk_usage_row("Disk", PAS_AMBER, func(b, l):
		sys_disk_bar = b; sys_disk_lbl = l))

	# --- numeric grid ----------------------------------------------------
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	sys_cputemp_lbl   = _add_kv(grid, "CPU temp", "52°C")
	sys_net_lbl       = _add_kv(grid, "Net ↓↑", "1.2 / 0.4 MB/s")
	sys_nuc_uptime_lbl = _add_kv(grid, "NUC uptime", "00:00:00")
	fps_lbl     = _add_kv(grid, "Twin FPS", "60")
	latency_lbl = _add_kv(grid, "Latency", "8.2 ms")
	uptime_lbl  = _add_kv(grid, "Twin uptime", "00:00:00")
	_add_kv(grid, "Health topic", "/dt/servo_health")

	var st := Button.new()
	st.text = "Self-Test Servo"
	st.focus_mode = Control.FOCUS_NONE
	st.tooltip_text = "Pratinjau indikator health (simulasi: 1 fault, 1 warn)"
	st.pressed.connect(_on_self_test)
	content.add_child(st)

	return content.get_meta("card_panel")


# progress bar mungil bergaya btop (tanpa teks bawaan)
func _mk_bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0; bar.max_value = 100; bar.value = 20
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.92, 0.91, 0.95)
	bg.corner_radius_top_left = 6; bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6; bg.corner_radius_bottom_right = 6
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.corner_radius_top_left = 6; fg.corner_radius_top_right = 6
	fg.corner_radius_bottom_left = 6; fg.corner_radius_bottom_right = 6
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _mk_val(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.custom_minimum_size = Vector2(54, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.40, 0.38, 0.50))
	return l


func _mk_usage_row(caption: String, fill: Color, bind: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", Color(0.45, 0.43, 0.55))
	cap.custom_minimum_size = Vector2(42, 0)
	row.add_child(cap)
	var bar := _mk_bar(fill)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var lbl := _mk_val("")
	row.add_child(lbl)
	bind.call(bar, lbl)
	return row


# Dipanggil dari Main saat data sistem nyata tiba (/dt/system over rosbridge).
# d: {cpu, cores:[..], ram, disk, cputemp, net_rx, net_tx, nuc_uptime}
func set_system_stats(d: Dictionary) -> void:
	_sys_external = true
	for k in d:
		_sys[k] = d[k]


func _on_self_test() -> void:
	# Pratinjau visual health saat belum ada robot. Tandai 1 fault + 1 warn,
	# lalu kembali normal setelah 5 detik.
	var demo := {"r_knee": "fault", "l_sho_roll": "warn"}
	_apply_health_demo(demo)
	await get_tree().create_timer(5.0).timeout
	_apply_health_demo({"r_knee": "ok", "l_sho_roll": "ok"})


func _apply_health_demo(h: Dictionary) -> void:
	set_servo_health(h)
	if _robot_ref and _robot_ref.has_method("set_servo_health"):
		for jn in h:
			_robot_ref.set_servo_health(jn, h[jn])


# ============================================================================
# UPDATE LOOP — dipanggil dari Main.gd
# ============================================================================
func update_from_robot(robot: Node3D) -> void:
	# 1. Update sudut joint dari robot 3D
	if robot.has_method("get_joint_angle"):
		for jname in JOINT_NAMES:
			var rad: float = robot.get_joint_angle(jname)
			var deg := rad2deg(rad)
			if joint_angle_lbls.has(jname):
				var lbl: Label = joint_angle_lbls[jname]
				lbl.text = "%+.1f°" % deg
				# Warna gradient hijau (idle) -> kuning (>30°) -> merah (>60°)
				var abs_deg := absf(deg)
				if abs_deg > 60.0:
					lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
				elif abs_deg > 30.0:
					lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
				else:
					lbl.add_theme_color_override("font_color", Color(0.55, 0.45, 0.86))
				# Slider mengikuti sudut robot (kecuali yang sedang diseret user)
				if joint_sliders.has(jname) and _active_slider != jname:
					_updating_ui = true
					joint_sliders[jname].value = deg
					_updating_ui = false

	# 1b. Grafik tren joint terpilih (atau r_knee default)
	if graph_spark:
		var gj := _sel_joint if _sel_joint != "" else "r_knee"
		if robot.has_method("get_joint_angle"):
			graph_spark.push(rad_to_deg(robot.get_joint_angle(gj)))
			if graph_lbl:
				graph_lbl.text = "%s  (°)" % gj

	# 2. Mockup IMU (digerakkan dari sin/cos waktu agar kelihatan hidup)
	var t := Time.get_ticks_msec() / 1000.0
	imu_gyro_lbls["x"].text  = "%+6.2f" % (sin(t * 1.7) * 12.0)
	imu_gyro_lbls["y"].text  = "%+6.2f" % (cos(t * 1.3) * 8.0)
	imu_gyro_lbls["z"].text  = "%+6.2f" % (sin(t * 0.9) * 4.5)
	imu_accel_lbls["x"].text = "%+6.2f" % (sin(t * 0.5) * 0.8)
	imu_accel_lbls["y"].text = "%+6.2f" % (-9.81 + cos(t * 0.7) * 0.3)
	imu_accel_lbls["z"].text = "%+6.2f" % (cos(t * 0.4) * 0.6)
	imu_orient_lbls["roll"].text  = "%+6.1f°" % (sin(t * 0.6) * 5.0)
	imu_orient_lbls["pitch"].text = "%+6.1f°" % (cos(t * 0.5) * 3.5)
	imu_orient_lbls["yaw"].text   = "%+6.1f°" % (sin(t * 0.2) * 30.0)

	# 3. Mockup baterai (drain pelan-pelan)
	_battery_pct = max(0.0, _battery_pct - 0.0008)
	battery_bar.value = _battery_pct
	battery_status_lbl.text = "%.0f%%" % _battery_pct

	# Voltage approx LiPo 3S: 9.0V (empty) -> 12.6V (full)
	var voltage := 9.0 + (_battery_pct / 100.0) * 3.6
	battery_voltage_lbl.text = "%.2f V" % voltage

	# Warna progress bar berdasarkan persen
	var fill_sb: StyleBoxFlat = battery_bar.get_theme_stylebox("fill").duplicate()
	if _battery_pct < 20.0:
		fill_sb.bg_color = Color(0.95, 0.30, 0.30)
		battery_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.30, 0.30))
	elif _battery_pct < 50.0:
		fill_sb.bg_color = Color(0.95, 0.70, 0.20)
		battery_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.70, 0.20))
	else:
		fill_sb.bg_color = Color(0.16, 0.56, 0.47)
		battery_status_lbl.add_theme_color_override("font_color", Color(0.16, 0.56, 0.47))
	battery_bar.add_theme_stylebox_override("fill", fill_sb)

	# Current draw (sedikit ber-fluktuasi)
	battery_current_lbl.text = "%.2f A" % (1.4 + sin(t * 2.0) * 0.15)

	# 4. System info (Twin process)
	fps_lbl.text = "%d" % Engine.get_frames_per_second()
	latency_lbl.text = "%.1f ms" % (1000.0 / max(1, Engine.get_frames_per_second()))

	# 4b. btop-style NUC monitor. Mock realistic drift unless real data arrives.
	if not _sys_external:
		_mock_system(t)
	_refresh_system_bars()
	_refresh_vision()

	# 4c. Popup detail servo tetap hidup selama terbuka
	if _servo_popup and _servo_popup.visible:
		_refresh_servo_popup()
		_refresh_arm_btn()

	# Stat strip atas
	if stat_batt:
		stat_batt.text = "%.0f%%" % _battery_pct
		stat_fps.text = "%d" % Engine.get_frames_per_second()
		var ok := 0
		for jn in JOINT_NAMES:
			if not _robot_ref or not _robot_ref.has_method("get_servo_health") \
					or _robot_ref.get_servo_health(jn) == "ok":
				ok += 1
		stat_active.text = "%d/20" % ok
		stat_active.add_theme_color_override("font_color",
			PAS_PURPLE if ok == 20 else Color(0.93, 0.20, 0.20))
		stat_temp.text = "%.0f°" % (_temp_base + 6.0)
	@warning_ignore("integer_division")
	var elapsed_s := (Time.get_ticks_msec() - _start_time_ms) / 1000
	@warning_ignore("integer_division")
	var hh := elapsed_s / 3600
	@warning_ignore("integer_division")
	var mm := (elapsed_s / 60) % 60
	var ss := elapsed_s % 60
	uptime_lbl.text = "%02d:%02d:%02d" % [hh, mm, ss]

	# 5. Joint temperature mockup (sedikit naik kalau gerak banyak)
	for jname in JOINT_NAMES:
		if joint_temp_lbls.has(jname):
			var temp := _temp_base + sin(t * 0.3 + JOINT_NAMES.find(jname) * 0.2) * 2.5
			var lbl: Label = joint_temp_lbls[jname]
			lbl.text = "%.0f°C" % temp
			if temp > 55.0:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
			elif temp > 45.0:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			else:
				lbl.add_theme_color_override("font_color", Color(0.16, 0.56, 0.47))


# Mock NUC telemetry — believable drift (load couples to robot motion a bit).
func _mock_system(t: float) -> void:
	# how busy the robot is right now nudges CPU/temp up
	var motion := 0.0
	if _robot_ref and _robot_ref.has_method("get_joint_angle"):
		for jn in JOINT_NAMES:
			motion += absf(_robot_ref.get_joint_angle(jn))
	var busy: float = clampf(motion * 0.4, 0.0, 35.0)
	_sys["cpu"] = clampf(20.0 + sin(t * 0.7) * 6.0 + busy, 3.0, 99.0)
	for i in _sys["cores"].size():
		var base: float = _sys["cpu"]
		_sys["cores"][i] = clampf(base + sin(t * (1.1 + i * 0.3) + i) * 22.0, 1.0, 100.0)
	_sys["ram"] = clampf(36.0 + sin(t * 0.15) * 4.0, 5.0, 95.0)
	_sys["disk"] = 47.0
	_sys["cputemp"] = clampf(48.0 + busy * 0.5 + sin(t * 0.4) * 2.5, 35.0, 95.0)
	_sys["net_rx"] = 1.0 + absf(sin(t * 1.3)) * 1.8
	_sys["net_tx"] = 0.3 + absf(cos(t * 0.9)) * 0.6
	_sys["nuc_uptime"] = int(Time.get_unix_time_from_system()) % 86400


func _refresh_system_bars() -> void:
	if sys_cpu_bar == null:
		return
	var cpu: float = _sys["cpu"]
	sys_cpu_bar.value = cpu
	sys_cpu_lbl.text = "%.0f%%" % cpu
	_tint_bar(sys_cpu_bar, sys_cpu_lbl, cpu, PAS_SKY)
	if sys_cpu_graph:
		sys_cpu_graph.push(cpu)
	for i in mini(sys_core_bars.size(), _sys["cores"].size()):
		var cv: float = _sys["cores"][i]
		sys_core_bars[i].value = cv
		_tint_bar(sys_core_bars[i], null, cv, PAS_PURPLE)

	var ram: float = _sys["ram"]
	sys_ram_bar.value = ram
	sys_ram_lbl.text = "%.1f/%.0f GB" % [ram / 100.0 * NUC_RAM_GB, NUC_RAM_GB]
	_tint_bar(sys_ram_bar, null, ram, PAS_MINT)

	var disk: float = _sys["disk"]
	sys_disk_bar.value = disk
	sys_disk_lbl.text = "%.0f/%.0f GB" % [disk / 100.0 * NUC_DISK_GB, NUC_DISK_GB]
	_tint_bar(sys_disk_bar, null, disk, PAS_AMBER)

	var ct: float = _sys["cputemp"]
	sys_cputemp_lbl.text = "%.0f°C" % ct
	sys_cputemp_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.30, 0.30) if ct > 80.0 else
		(Color(0.95, 0.65, 0.20) if ct > 70.0 else Color(0.40, 0.38, 0.50)))
	sys_net_lbl.text = "%.1f / %.1f MB/s" % [_sys["net_rx"], _sys["net_tx"]]
	var us: int = int(_sys["nuc_uptime"])
	@warning_ignore("integer_division")
	sys_nuc_uptime_lbl.text = "%02d:%02d:%02d" % [us / 3600, (us / 60) % 60, us % 60]


# warnai fill bar: hijau<60, kuning<85, merah>=85
func _tint_bar(bar: ProgressBar, lbl, v: float, normal: Color) -> void:
	var c: Color = normal
	if v >= 85.0:
		c = Color(0.95, 0.30, 0.30)
	elif v >= 60.0:
		c = Color(0.95, 0.65, 0.20)
	var fg: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if fg and fg.bg_color != c:
		fg = fg.duplicate()
		fg.bg_color = c
		bar.add_theme_stylebox_override("fill", fg)
	if lbl:
		lbl.add_theme_color_override("font_color", c if v >= 60.0 else Color(0.40, 0.38, 0.50))


# Helper konversi (Godot punya rad_to_deg di 4.x, tapi kita pakai versi manual
# agar kompatibel dengan versi Godot 4 lama)
func rad2deg(r: float) -> float:
	return r * 57.29577951308232

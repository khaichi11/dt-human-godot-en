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

	func push(v: float) -> void:
		values.append(v)
		if values.size() > cap:
			values.remove_at(0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# grid garis tengah + atas/bawah
		var grid := Color(0.90, 0.88, 0.94)
		draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), grid, 1.0)
		draw_line(Vector2(0, h - 1), Vector2(w, h - 1), grid, 1.0)
		draw_line(Vector2(0, 1), Vector2(w, 1), grid, 1.0)
		if values.size() < 2:
			return
		var pts := PackedVector2Array()
		for i in values.size():
			var x := w * float(i) / float(cap - 1)
			var t := (values[i] - vmin) / (vmax - vmin)
			var y := h * (1.0 - clampf(t, 0.0, 1.0))
			pts.append(Vector2(x, y))
		draw_polyline(pts, line_col, 2.0, true)


var graph_spark: Sparkline
var graph_lbl: Label

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

# Gerakan/pose (diekstrak dari data ROBOTIS) — nama => {hold, steps:[...]}
var motions_data := {}
var motion_option: OptionButton
var play_btn: Button
var stop_btn: Button

# Kontrol: referensi robot 3D + manipulator (di-set Main lewat bind_controls)
var _robot_ref: Node3D
var _manip_ref: Node
var _updating_ui := false    # cegah feedback loop slider<->robot
var _active_slider := ""     # joint yang slidernya sedang diseret user
var _sel_joint := ""         # joint terpilih (untuk highlight)

var fps_lbl: Label
var latency_lbl: Label
var uptime_lbl: Label
var mode_lbl: Label

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

	col.add_child(_build_status_header())
	col.add_child(_build_poses_section())
	col.add_child(_build_battery_section())
	col.add_child(_build_graph_section())
	col.add_child(_build_imu_section())
	col.add_child(_build_joints_section())
	col.add_child(_build_system_section())


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
const PAS_MINT   := Color(0.42, 0.78, 0.65)
const PAS_SKY    := Color(0.46, 0.71, 0.94)
const PAS_PEACH  := Color(0.98, 0.68, 0.58)
const PAS_AMBER  := Color(0.97, 0.80, 0.46)


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
func _build_status_header() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.96, 0.99)
	sb.border_color = Color(0.84, 0.80, 0.93)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	var line1 := HBoxContainer.new()
	var dot := ColorRect.new()
	dot.color = Color(0.0, 0.68, 0.40)
	dot.custom_minimum_size = Vector2(8, 8)
	line1.add_child(dot)

	var space := Control.new()
	space.custom_minimum_size = Vector2(8, 0)
	line1.add_child(space)

	var name_lbl := Label.new()
	name_lbl.text = "OP3-001 · ONLINE"
	name_lbl.add_theme_color_override("font_color", Color(0.0, 0.68, 0.40))
	name_lbl.add_theme_font_size_override("font_size", 14)
	line1.add_child(name_lbl)
	vb.add_child(line1)

	mode_lbl = Label.new()
	mode_lbl.text = "Mode: WALKING_READY · Comm: 1 Mbps · Loss: 0.0%"
	mode_lbl.add_theme_color_override("font_color", Color(0.45, 0.49, 0.55))
	mode_lbl.add_theme_font_size_override("font_size", 11)
	vb.add_child(mode_lbl)

	return panel


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
	return content.get_meta("card_panel")


func _load_motions() -> void:
	if not FileAccess.file_exists("res://assets/motions.json"):
		return
	var txt := FileAccess.get_file_as_string("res://assets/motions.json")
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		motions_data = parsed


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
	battery_voltage_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	pct_row.add_child(battery_voltage_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pct_row.add_child(spacer)

	battery_status_lbl = Label.new()
	battery_status_lbl.text = "%.0f%%" % _battery_pct
	battery_status_lbl.add_theme_font_size_override("font_size", 22)
	battery_status_lbl.add_theme_color_override("font_color", Color(0.0, 0.60, 0.35))
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
		Color(1.0, 0.45, 0.45), Color(0.0, 0.62, 0.35), Color(0.55, 0.45, 0.86)))
	content.add_child(_build_imu_subgroup("Accelerometer (m/s²)", imu_accel_lbls,
		Color(1.0, 0.45, 0.45), Color(0.0, 0.62, 0.35), Color(0.55, 0.45, 0.86)))
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

		# Nama + ID servo (tombol untuk memilih joint)
		var sid := i + 1                       # ID Dynamixel = urutan 1..20
		var name_btn := Button.new()
		name_btn.text = "%02d  %s" % [sid, jname]
		name_btn.flat = true
		name_btn.focus_mode = Control.FOCUS_NONE
		name_btn.custom_minimum_size = Vector2(118, 0)
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


func _on_joint_clicked(jname: String) -> void:
	if _manip_ref and _manip_ref.has_method("select_joint"):
		_manip_ref.select_joint(jname)
	_highlight_selected(jname)


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
		joint_name_btns[jname].add_theme_color_override("font_color", Color(0.0, 0.62, 0.35))


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
	var content := _make_card("System", PAS_AMBER)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)

	fps_lbl     = _add_kv(grid, "FPS", "60")
	latency_lbl = _add_kv(grid, "Latency", "8.2 ms")
	uptime_lbl  = _add_kv(grid, "Uptime", "00:00:00")
	_add_kv(grid, "ROS Topic", "/op3/all_joints")

	return content.get_meta("card_panel")


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
		fill_sb.bg_color = Color(0.0, 0.60, 0.35)
		battery_status_lbl.add_theme_color_override("font_color", Color(0.0, 0.60, 0.35))
	battery_bar.add_theme_stylebox_override("fill", fill_sb)

	# Current draw (sedikit ber-fluktuasi)
	battery_current_lbl.text = "%.2f A" % (1.4 + sin(t * 2.0) * 0.15)

	# 4. System info
	fps_lbl.text = "%d" % Engine.get_frames_per_second()
	latency_lbl.text = "%.1f ms" % (1000.0 / max(1, Engine.get_frames_per_second()))
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
				lbl.add_theme_color_override("font_color", Color(0.0, 0.60, 0.35))


# Helper konversi (Godot punya rad_to_deg di 4.x, tapi kita pakai versi manual
# agar kompatibel dengan versi Godot 4 lama)
func rad2deg(r: float) -> float:
	return r * 57.29577951308232

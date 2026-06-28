extends Control
# ============================================================================
# Main.gd
# Dashboard utama OP3 Digital Twin.
# Layout: HSplitContainer => kiri = SensorPanel, kanan = 3D Viewport (OP3 Robot)
# ============================================================================

const SensorPanelScript = preload("res://scripts/SensorPanel.gd")
const OP3RobotScript    = preload("res://scripts/OP3Robot.gd")
const CameraOrbitScript = preload("res://scripts/CameraOrbit.gd")
const JointManipScript  = preload("res://scripts/JointManipulator.gd")
const ViewCubeScript    = preload("res://scripts/ViewCube.gd")
const RosBridgeScript   = preload("res://scripts/RosBridge.gd")
const RingGaugeScript   = preload("res://scripts/RingGauge.gd")

# --- Palet "Daylight" clean-pastel (selaras design-system/ds.css) -----------
# Aksen dipakai tipis (status/kategori), bukan membanjiri layar. Bayangan
# sangat halus + radius lebih kecil = kesan clean (bukan pastel soft-shadow).
const COL_BG       := Color(0.961, 0.965, 0.984)  # #f5f6fb cool soft-white
const COL_PANEL    := Color(1.0, 1.0, 1.0)        # #ffffff kartu/panel
const COL_BORDER   := Color(0.902, 0.914, 0.953)  # #e6e9f3 hairline
const COL_TEXT     := Color(0.165, 0.184, 0.235)  # #2a2f3c slate
const COL_MUTED    := Color(0.424, 0.451, 0.518)  # #6c7384 teks sekunder
const COL_ACCENT   := Color(0.435, 0.482, 0.941)  # #6f7bf0 indigo (primary)
const COL_VIEW_BG  := Color(0.933, 0.945, 0.973)  # #eef1f8 latar viewport 3D

# Aksen per-seksi (badge) — versi clean/muted, tiap kategori 1 hue
const PAS_PURPLE := Color(0.435, 0.482, 0.941)   # indigo
const PAS_MINT   := Color(0.184, 0.722, 0.541)   # #2fb88a mint
const PAS_SKY    := Color(0.231, 0.714, 0.769)   # #3bb6c4 teal
const PAS_PEACH  := Color(0.937, 0.416, 0.416)   # #ef6a6a coral
const PAS_AMBER  := Color(0.878, 0.604, 0.208)   # #e09a35 amber
const PAS_PINK   := Color(0.608, 0.482, 0.941)   # #9b7bf0 lilac

var sensor_panel: Control
var robot: Node3D
var sub_viewport: SubViewport
var orbit_camera: Camera3D
var manipulator: Node3D
var view_cube: Control
var mode_btn: Button
var control_mode := true       # true = Atur (edit), false = Live (terima data)
var live_driver: Node          # penggerak joint mock saat mode Live
var ros_bridge: Node           # klien rosbridge WebSocket
var ros_url_edit: LineEdit
var ros_status_dot: Panel
var ros_connect_btn: Button
var _live_connected := false   # true bila data joint asli sedang masuk

func _ready() -> void:
	_apply_dark_theme()
	_build_layout()
	_show_loading()


# ----------------------------------------------------------------------------
# LOADING / LANDING — splash singkat saat start. App tetap jalan offline
# (tanpa robot); koneksi bisa dilakukan kapan saja lewat toolbar.
# ----------------------------------------------------------------------------
func _show_loading() -> void:
	var ov := ColorRect.new()
	ov.color = COL_BG
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	ov.add_child(box)

	var logo := Panel.new()
	logo.custom_minimum_size = Vector2(64, 64)
	var lsb := _rounded(COL_ACCENT, 18)
	logo.add_theme_stylebox_override("panel", lsb)
	var logo_wrap := CenterContainer.new()
	logo_wrap.add_child(logo)
	box.add_child(logo_wrap)

	var title := Label.new()
	title.text = "OP3 DIGITAL TWIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_TEXT)
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Memuat… · mode offline, hubungkan robot kapan saja"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(sub)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 6)
	bar.show_percentage = false
	bar.value = 0
	box.add_child(bar)

	# animasi bar lalu fade-out
	var tw := create_tween()
	tw.tween_property(bar, "value", 100.0, 0.9)
	tw.tween_interval(0.2)
	tw.tween_property(ov, "modulate:a", 0.0, 0.4)
	tw.tween_callback(ov.queue_free)


# ----------------------------------------------------------------------------
# THEME
# ----------------------------------------------------------------------------
var font_bold: FontVariation

func _apply_dark_theme() -> void:
	# Tema putih minimalis
	var t := Theme.new()
	t.default_font_size = 13

	# Font open-source Inter (UI dashboard yang bersih & jelas)
	var inter := load("res://assets/fonts/Inter.ttf")
	if inter:
		t.default_font = inter
		font_bold = FontVariation.new()
		font_bold.base_font = inter
		font_bold.variation_opentype = {"wght": 600}

	# Panel/kartu putih: border hairline + elevasi SANGAT halus (clean, bukan
	# soft-shadow tebal). Radius 12 = lebih tegas/rapi dari 14.
	var panel_sb := _rounded(COL_PANEL, 12)
	panel_sb.border_width_left = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_bottom = 1
	panel_sb.border_color = COL_BORDER
	panel_sb.shadow_color = Color(0.110, 0.129, 0.251, 0.05)
	panel_sb.shadow_size = 3
	panel_sb.shadow_offset = Vector2(0, 1)
	t.set_stylebox("panel", "PanelContainer", panel_sb)
	t.set_stylebox("panel", "Panel", _rounded(COL_PANEL, 12))

	t.set_color("font_color", "Label", COL_TEXT)

	# ProgressBar
	t.set_stylebox("background", "ProgressBar", _rounded(Color(0.90, 0.92, 0.94), 4))
	t.set_stylebox("fill", "ProgressBar", _rounded(COL_ACCENT, 4))
	t.set_color("font_color", "ProgressBar", COL_TEXT)

	# Tombol clean: putih + border tipis; hover = tint indigo; pressed lebih dalam
	var btn_n := _rounded(COL_PANEL, 9)
	btn_n.border_width_bottom = 1; btn_n.border_width_top = 1
	btn_n.border_width_left = 1; btn_n.border_width_right = 1
	btn_n.border_color = Color(0.839, 0.859, 0.922)    # #d6dbeb line-2
	var btn_h := _rounded(Color(0.933, 0.941, 1.0), 9) # #eef0ff indigo-bg
	btn_h.border_width_bottom = 1; btn_h.border_width_top = 1
	btn_h.border_width_left = 1; btn_h.border_width_right = 1
	btn_h.border_color = COL_ACCENT
	var btn_p := _rounded(Color(0.886, 0.898, 0.992), 9)
	t.set_stylebox("normal", "Button", btn_n)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", COL_ACCENT)
	t.set_color("font_pressed_color", "Button", COL_ACCENT)

	# LineEdit
	var le := _rounded(Color(0.98, 0.99, 1.0), 5)
	le.border_width_left = 1; le.border_width_right = 1
	le.border_width_top = 1; le.border_width_bottom = 1
	le.border_color = COL_BORDER
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_color("caret_color", "LineEdit", COL_ACCENT)

	# HSlider
	t.set_stylebox("slider", "HSlider", _rounded(Color(0.88, 0.90, 0.93), 3))
	t.set_stylebox("grabber_area", "HSlider", _rounded(COL_ACCENT, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _rounded(COL_ACCENT, 3))

	# HSplitContainer
	t.set_stylebox("split_bar_background", "HSplitContainer", _rounded(COL_BORDER, 0))

	theme = t


func _rounded(c: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


# ----------------------------------------------------------------------------
# LAYOUT
# ----------------------------------------------------------------------------
func _build_layout() -> void:
	# Background container
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Top toolbar (header)
	var toolbar := _build_toolbar()
	add_child(toolbar)

	# Split container utama
	var split := HSplitContainer.new()
	split.anchor_top = 0.0
	split.anchor_left = 0.0
	split.anchor_right = 1.0
	split.anchor_bottom = 1.0
	split.offset_top = 56  # ruang untuk toolbar
	split.offset_left = 8
	split.offset_right = -8
	split.offset_bottom = -8
	split.split_offset = 470  # lebar nav-rail + panel kiri
	add_child(split)

	# === KIRI: nav-rail minimalis + halaman konten (Overview/Action/Logs) ===
	var left_host := HBoxContainer.new()
	left_host.add_theme_constant_override("separation", 8)
	left_host.custom_minimum_size = Vector2(470, 0)
	split.add_child(left_host)

	left_host.add_child(_build_nav_rail())

	nav_content = Control.new()
	nav_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_host.add_child(nav_content)

	# Halaman: Overview (SensorPanel)
	var sp_wrap := PanelContainer.new()
	sp_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_content.add_child(sp_wrap)
	sensor_panel = Control.new()
	sensor_panel.set_script(SensorPanelScript)
	sp_wrap.add_child(sensor_panel)
	nav_pages["monitor"] = sp_wrap

	# Halaman: Action Editor
	var ae_wrap := _build_action_editor()
	ae_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_content.add_child(ae_wrap)
	nav_pages["action"] = ae_wrap

	# Halaman: Logs
	var log_wrap := _build_logs_page()
	log_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_content.add_child(log_wrap)
	nav_pages["logs"] = log_wrap

	_nav_select("monitor")

	# === KANAN: 3D Viewport + kolom info (gauges · inspector · joints) ===
	var right_area := HBoxContainer.new()
	right_area.add_theme_constant_override("separation", 8)
	split.add_child(right_area)

	var right_wrapper := PanelContainer.new()
	right_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_area.add_child(right_wrapper)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 4)
	right_wrapper.add_child(right_vbox)

	# Header viewport
	var viewport_header := _build_viewport_header()
	right_vbox.add_child(viewport_header)

	# Pembungkus viewport (agar ViewCube bisa di-overlay di pojok)
	var vp_wrap := Control.new()
	vp_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_wrap.clip_contents = true
	right_vbox.add_child(vp_wrap)

	# SubViewportContainer + SubViewport
	var sv_container := SubViewportContainer.new()
	sv_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	sv_container.stretch = true
	vp_wrap.add_child(sv_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(1024, 768)
	sub_viewport.handle_input_locally = true
	sub_viewport.msaa_3d = Viewport.MSAA_4X
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv_container.add_child(sub_viewport)

	_build_3d_scene()

	# ViewCube overlay (pojok kanan atas viewport)
	view_cube = ViewCubeScript.new()
	view_cube.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	view_cube.position = Vector2(-118, 12)
	vp_wrap.add_child(view_cube)
	view_cube.setup(orbit_camera)

	# Kolom info kanan (sesuai mockup: ring gauge + inspector + joints)
	var info_col := _build_info_column()
	right_area.add_child(info_col)


func _build_toolbar() -> Control:
	var bar := PanelContainer.new()
	bar.anchor_left = 0
	bar.anchor_right = 1.0
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	bar.offset_bottom = 48

	var sb := _rounded(COL_PANEL, 8)
	sb.border_color = COL_BORDER
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	bar.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)

	# Status indicator (titik hijau)
	var status_dot := _make_status_dot()
	hb.add_child(status_dot)

	# Title
	var title := Label.new()
	title.text = "ROBOTIS OP3 — DIGITAL TWIN"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COL_TEXT)
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	hb.add_child(title)

	var sep := Control.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sep)

	# --- Koneksi robot (rosbridge) ---
	var ros_lbl := Label.new()
	ros_lbl.text = "ROBOT"
	ros_lbl.add_theme_color_override("font_color", COL_MUTED)
	hb.add_child(ros_lbl)

	ros_status_dot = Panel.new()
	ros_status_dot.custom_minimum_size = Vector2(10, 10)
	_set_ros_dot(Color(0.75, 0.78, 0.82))     # abu = belum konek
	hb.add_child(ros_status_dot)

	ros_url_edit = LineEdit.new()
	ros_url_edit.text = "ws://127.0.0.1:9090"
	ros_url_edit.custom_minimum_size = Vector2(170, 28)
	ros_url_edit.tooltip_text = "Alamat rosbridge_server di robot (ROS 2)"
	hb.add_child(ros_url_edit)

	ros_connect_btn = Button.new()
	ros_connect_btn.text = "Connect"
	ros_connect_btn.focus_mode = Control.FOCUS_NONE
	ros_connect_btn.custom_minimum_size = Vector2(86, 28)
	ros_connect_btn.pressed.connect(_on_ros_connect)
	hb.add_child(ros_connect_btn)

	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(12, 0)
	hb.add_child(sep2)

	# Tombol kalibrasi IMU (orientasi badan)
	var imu_btn := Button.new()
	imu_btn.text = "IMU"
	imu_btn.focus_mode = Control.FOCUS_NONE
	imu_btn.custom_minimum_size = Vector2(60, 30)
	imu_btn.tooltip_text = "Kalibrasi & aktifkan orientasi IMU badan"
	imu_btn.pressed.connect(_open_imu_popup)
	hb.add_child(imu_btn)

	# Tombol aktivasi robot (torque-on → ini_pose → enable module)
	var act_btn := Button.new()
	act_btn.text = "Activate"
	act_btn.focus_mode = Control.FOCUS_NONE
	act_btn.custom_minimum_size = Vector2(82, 30)
	act_btn.tooltip_text = "Aktifkan robot: torque-on → pose ready → pilih module"
	act_btn.pressed.connect(_open_activate_popup)
	hb.add_child(act_btn)

	# Tombol mode (Atur / Live)
	mode_btn = Button.new()
	mode_btn.focus_mode = Control.FOCUS_NONE
	mode_btn.custom_minimum_size = Vector2(150, 30)
	mode_btn.pressed.connect(_toggle_mode)
	hb.add_child(mode_btn)
	_refresh_mode_btn()

	# E-Stop (merah, terisolasi) — torque OFF semua + stop motion
	var estop := Button.new()
	estop.text = "■ E-STOP"
	estop.focus_mode = Control.FOCUS_NONE
	estop.custom_minimum_size = Vector2(94, 30)
	estop.tooltip_text = "Hentikan darurat: torque OFF semua servo"
	var esb := _rounded(Color(0.992, 0.922, 0.922), 9)
	esb.border_color = Color(0.957, 0.761, 0.761)
	esb.border_width_left = 1; esb.border_width_right = 1
	esb.border_width_top = 1; esb.border_width_bottom = 1
	estop.add_theme_stylebox_override("normal", esb)
	estop.add_theme_color_override("font_color", Color(0.937, 0.416, 0.416))
	estop.pressed.connect(_on_estop)
	hb.add_child(estop)

	var build_label := Label.new()
	build_label.text = "v0.2 · 20 DOF"
	build_label.add_theme_color_override("font_color", COL_MUTED)
	hb.add_child(build_label)

	return bar


func _toggle_mode() -> void:
	control_mode = not control_mode
	_refresh_mode_btn()
	if manipulator and manipulator.has_method("set_editable"):
		manipulator.set_editable(control_mode)
	if sensor_panel and sensor_panel.has_method("set_editable"):
		sensor_panel.set_editable(control_mode)


func _refresh_mode_btn() -> void:
	if mode_btn == null:
		return
	if control_mode:
		mode_btn.text = "● MODE: ATUR"
		mode_btn.add_theme_color_override("font_color", COL_ACCENT)
	else:
		mode_btn.text = "● MODE: LIVE"
		mode_btn.add_theme_color_override("font_color", Color(0.16, 0.56, 0.47))


# ----------------------------------------------------------------------------
# IMU — orientasi badan dari /robotis/open_cr/imu + popup kalibrasi.
# ----------------------------------------------------------------------------
var imu_popup: PopupPanel
var imu_enable_chk: CheckBox
var imu_sliders := {}
var imu_val_lbls := {}

func _on_ros_imu(orientation: Quaternion, gyro: Vector3, accel: Vector3) -> void:
	if robot and robot.has_method("set_imu_orientation"):
		robot.set_imu_orientation(orientation)
	if sensor_panel and sensor_panel.has_method("set_imu_data"):
		var rpy := Vector3.ZERO
		if robot and robot.has_method("get_imu_euler_deg"):
			rpy = robot.get_imu_euler_deg()
		sensor_panel.set_imu_data(rpy, gyro, accel)


func _open_imu_popup() -> void:
	if imu_popup == null:
		_build_imu_popup()
	imu_popup.popup_centered(Vector2i(360, 320))


func _build_imu_popup() -> void:
	imu_popup = PopupPanel.new()
	var pb := _rounded(COL_PANEL, 12)
	pb.border_color = COL_BORDER
	pb.border_width_left = 1; pb.border_width_right = 1
	pb.border_width_top = 1; pb.border_width_bottom = 1
	pb.content_margin_left = 16; pb.content_margin_right = 16
	pb.content_margin_top = 14; pb.content_margin_bottom = 14
	imu_popup.add_theme_stylebox_override("panel", pb)
	add_child(imu_popup)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	vb.custom_minimum_size = Vector2(328, 0)
	imu_popup.add_child(vb)

	var title := Label.new()
	title.text = "IMU & Orientasi Badan"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COL_TEXT)
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	vb.add_child(title)

	var note := Label.new()
	note.text = "Slider memutar BADAN robot (roll/pitch/yaw) — berlaku juga offline / saat nyambung. Pitch ~±90° untuk membaringkan ke pose push-up. 'Zero now' jadikan orientasi IMU sekarang sebagai tegak."
	note.add_theme_color_override("font_color", COL_MUTED)
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	vb.add_child(note)

	imu_enable_chk = CheckBox.new()
	imu_enable_chk.text = "Aktifkan orientasi IMU pada model"
	imu_enable_chk.add_theme_color_override("font_color", COL_TEXT)
	imu_enable_chk.toggled.connect(_on_imu_enable)
	vb.add_child(imu_enable_chk)

	var settle_chk := CheckBox.new()
	settle_chk.text = "Auto-settle kontak (eksperimen — ratakan tumpuan)"
	settle_chk.button_pressed = false
	settle_chk.add_theme_color_override("font_color", COL_TEXT)
	settle_chk.toggled.connect(_on_auto_settle)
	vb.add_child(settle_chk)

	var zero_btn := Button.new()
	zero_btn.text = "⟲  Zero now (tangkap pose tegak)"
	zero_btn.focus_mode = Control.FOCUS_NONE
	zero_btn.pressed.connect(_on_imu_zero)
	vb.add_child(zero_btn)

	for ax in ["roll", "pitch", "yaw"]:
		vb.add_child(_imu_slider_row(ax))


func _imu_slider_row(ax: String) -> Control:
	var row := VBoxContainer.new()
	var hb := HBoxContainer.new()
	var nm := Label.new()
	nm.text = ax.capitalize() + " offset"
	nm.add_theme_color_override("font_color", COL_MUTED)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(nm)
	var val := Label.new()
	val.text = "+0.0°"
	val.add_theme_color_override("font_color", COL_ACCENT)
	hb.add_child(val)
	imu_val_lbls[ax] = val
	row.add_child(hb)
	var s := HSlider.new()
	s.min_value = -180.0
	s.max_value = 180.0
	s.step = 1.0
	s.value = 0.0
	s.custom_minimum_size = Vector2(0, 18)
	s.value_changed.connect(_on_imu_slider)
	imu_sliders[ax] = s
	row.add_child(s)
	return row


func _on_imu_enable(on: bool) -> void:
	if robot and robot.has_method("set_imu_enabled"):
		robot.set_imu_enabled(on)


func _on_auto_settle(on: bool) -> void:
	if robot and robot.has_method("set_auto_settle"):
		robot.set_auto_settle(on)


func _on_imu_zero() -> void:
	if robot and robot.has_method("imu_zero"):
		robot.imu_zero()


func _on_imu_slider(_v: float) -> void:
	var r: float = imu_sliders["roll"].value
	var p: float = imu_sliders["pitch"].value
	var y: float = imu_sliders["yaw"].value
	imu_val_lbls["roll"].text = "%+.1f°" % r
	imu_val_lbls["pitch"].text = "%+.1f°" % p
	imu_val_lbls["yaw"].text = "%+.1f°" % y
	if robot and robot.has_method("set_imu_manual_offset"):
		robot.set_imu_manual_offset(r, p, y)


# ----------------------------------------------------------------------------
# AKTIVASI ROBOT — urutan resmi op3_manager: torque-on → ini_pose → enable module.
# Lihat docs/digital-twin-alur-operasi.md (state [2] → [3]).
# ----------------------------------------------------------------------------
var activate_popup: PopupPanel
var activate_status_lbl: Label
var activate_module_opt: OptionButton

func _open_activate_popup() -> void:
	if activate_popup == null:
		_build_activate_popup()
	activate_popup.popup_centered(Vector2i(380, 340))


func _build_activate_popup() -> void:
	activate_popup = PopupPanel.new()
	var pb := _rounded(COL_PANEL, 12)
	pb.border_color = COL_BORDER
	pb.border_width_left = 1; pb.border_width_right = 1
	pb.border_width_top = 1; pb.border_width_bottom = 1
	pb.content_margin_left = 16; pb.content_margin_right = 16
	pb.content_margin_top = 14; pb.content_margin_bottom = 14
	activate_popup.add_theme_stylebox_override("panel", pb)
	add_child(activate_popup)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(348, 0)
	activate_popup.add_child(vb)

	var title := Label.new()
	title.text = "Aktivasi Robot"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COL_TEXT)
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	vb.add_child(title)

	var note := Label.new()
	note.text = "Urutan: torque-on semua servo → ke pose ready (ini_pose) → pilih control module. Pastikan robot tertopang."
	note.add_theme_color_override("font_color", COL_MUTED)
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	vb.add_child(note)

	var mrow := HBoxContainer.new()
	var mlbl := Label.new()
	mlbl.text = "Control module"
	mlbl.add_theme_color_override("font_color", COL_MUTED)
	mlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mlbl)
	activate_module_opt = OptionButton.new()
	activate_module_opt.add_item("none")
	activate_module_opt.add_item("direct_control_module")
	activate_module_opt.add_item("action_module")
	activate_module_opt.add_item("walking_module")
	activate_module_opt.select(1)   # direct_control: DT bisa atur joint
	mrow.add_child(activate_module_opt)
	vb.add_child(mrow)

	var b1 := Button.new(); b1.text = "1 · Torque ON"; b1.focus_mode = Control.FOCUS_NONE
	b1.pressed.connect(_act_torque_on); vb.add_child(b1)
	var b2 := Button.new(); b2.text = "2 · Ini Pose (ready)"; b2.focus_mode = Control.FOCUS_NONE
	b2.pressed.connect(_act_ini_pose); vb.add_child(b2)
	var b3 := Button.new(); b3.text = "3 · Set module terpilih"; b3.focus_mode = Control.FOCUS_NONE
	b3.pressed.connect(_act_set_module); vb.add_child(b3)

	var one := Button.new()
	one.text = "⚡ Activate (1 → 2 → 3)"
	one.focus_mode = Control.FOCUS_NONE
	var ob := _rounded(Color(0.933, 0.941, 1.0), 9)
	ob.border_color = COL_ACCENT
	ob.border_width_left = 1; ob.border_width_right = 1
	ob.border_width_top = 1; ob.border_width_bottom = 1
	one.add_theme_stylebox_override("normal", ob)
	one.add_theme_color_override("font_color", COL_ACCENT)
	one.pressed.connect(_act_sequence)
	vb.add_child(one)

	var off := Button.new()
	off.text = "Torque OFF (semua) — lemaskan"
	off.focus_mode = Control.FOCUS_NONE
	off.add_theme_color_override("font_color", Color(0.937, 0.416, 0.416))
	off.pressed.connect(_act_torque_off)
	vb.add_child(off)

	activate_status_lbl = Label.new()
	activate_status_lbl.text = "Status: —"
	activate_status_lbl.add_theme_color_override("font_color", COL_MUTED)
	activate_status_lbl.add_theme_font_size_override("font_size", 11)
	activate_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activate_status_lbl.custom_minimum_size = Vector2(320, 0)
	vb.add_child(activate_status_lbl)


func _act_joint_names() -> Array:
	return robot.get_joint_names() if robot and robot.has_method("get_joint_names") else []


func _act_ready() -> bool:
	if ros_bridge and ros_bridge.is_open():
		return true
	_set_act_status("Belum konek ke robot.")
	return false


func _set_act_status(s: String) -> void:
	if activate_status_lbl:
		activate_status_lbl.text = "Status: " + s


func _act_torque_on() -> void:
	if not _act_ready(): return
	ros_bridge.send_torque(_act_joint_names(), true)
	_set_act_status("Torque ON dikirim.")


func _act_torque_off() -> void:
	if not _act_ready(): return
	ros_bridge.send_torque(_act_joint_names(), false)
	_set_act_status("Torque OFF (robot lemas).")


func _act_ini_pose() -> void:
	if not _act_ready(): return
	ros_bridge.send_ini_pose()
	_set_act_status("Ke pose ready (ini_pose)…")


func _act_set_module() -> void:
	if not _act_ready(): return
	var m := activate_module_opt.get_item_text(activate_module_opt.selected)
	ros_bridge.enable_ctrl_module(m)
	_set_act_status("Set module: %s" % m)


func _act_sequence() -> void:
	if not _act_ready(): return
	_set_flow_state(2)
	ros_bridge.send_torque(_act_joint_names(), true)
	_set_act_status("Torque ON…")
	await get_tree().create_timer(0.5).timeout
	ros_bridge.send_ini_pose()
	_set_act_status("Ke pose ready (ini_pose)…")
	await get_tree().create_timer(1.4).timeout
	var m := activate_module_opt.get_item_text(activate_module_opt.selected)
	ros_bridge.enable_ctrl_module(m)
	_set_act_status("Aktif · module: %s" % m)
	_set_flow_state(3)


func _on_robot_status(level: int, module_name: String, text: String) -> void:
	_log("[%s] %s" % [module_name, text])
	if activate_status_lbl == null:
		return
	var c := COL_MUTED
	if level >= 3:
		c = Color(0.937, 0.416, 0.416)
	elif level == 2:
		c = Color(0.878, 0.604, 0.208)
	activate_status_lbl.add_theme_color_override("font_color", c)
	activate_status_lbl.text = "Status: [%s] %s" % [module_name, text]


# ----------------------------------------------------------------------------
# STRIP ALUR — Connect → Activate → Ready → Action Editor (state terlihat).
# ----------------------------------------------------------------------------
var _flow_state := 0
var flow_chips := []
var flow_lbls := []
const FLOW_STEPS := ["1 · Connect", "2 · Activate", "3 · Ready", "4 · Action Editor"]

func _build_flow_strip() -> Control:
	var bar := PanelContainer.new()
	bar.anchor_left = 0; bar.anchor_right = 1.0
	bar.offset_left = 8; bar.offset_right = -8
	bar.offset_top = 58; bar.offset_bottom = 92
	var sb := _rounded(COL_PANEL, 8)
	sb.border_color = COL_BORDER
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top = 1; sb.border_width_bottom = 1
	bar.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	bar.add_child(hb)
	var lead := Label.new()
	lead.text = "ALUR"
	lead.add_theme_color_override("font_color", COL_MUTED)
	if font_bold:
		lead.add_theme_font_override("font", font_bold)
	hb.add_child(lead)
	for i in range(FLOW_STEPS.size()):
		var chip := PanelContainer.new()
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_left", 12)
		mc.add_theme_constant_override("margin_right", 12)
		mc.add_theme_constant_override("margin_top", 3)
		mc.add_theme_constant_override("margin_bottom", 3)
		var cl := Label.new()
		cl.text = FLOW_STEPS[i]
		cl.add_theme_font_size_override("font_size", 12)
		mc.add_child(cl)
		chip.add_child(mc)
		hb.add_child(chip)
		flow_chips.append(chip)
		flow_lbls.append(cl)
		if i < FLOW_STEPS.size() - 1:
			var ar := Label.new()
			ar.text = "›"
			ar.add_theme_color_override("font_color", COL_MUTED)
			hb.add_child(ar)
	_refresh_flow()
	return bar


func _set_flow_state(s: int) -> void:
	s = clampi(s, 0, 3)
	if s == _flow_state:
		return
	_flow_state = s
	_refresh_flow()


func _refresh_flow() -> void:
	for i in range(flow_chips.size()):
		var active: bool = i == _flow_state
		var done: bool = i < _flow_state
		var col := COL_MUTED
		var bg := COL_BG
		if active:
			col = COL_ACCENT
			bg = Color(0.933, 0.941, 1.0)
		elif done:
			col = Color(0.184, 0.722, 0.541)
			bg = Color(0.902, 0.965, 0.937)
		var cs := _rounded(bg, 7)
		if active:
			cs.border_color = COL_ACCENT
			cs.border_width_left = 1; cs.border_width_right = 1
			cs.border_width_top = 1; cs.border_width_bottom = 1
		flow_chips[i].add_theme_stylebox_override("panel", cs)
		flow_lbls[i].add_theme_color_override("font_color", col)
		flow_lbls[i].text = ("✓ " + FLOW_STEPS[i]) if done else FLOW_STEPS[i]


func _on_estop() -> void:
	if ros_bridge and ros_bridge.is_open():
		ros_bridge.send_torque(robot.get_joint_names() if robot else [], false)
	if robot and robot.has_method("stop_motion"):
		robot.stop_motion()
	_set_flow_state(1 if (ros_bridge and ros_bridge.is_open()) else 0)


# ----------------------------------------------------------------------------
# KOLOM INFO KANAN — ring gauge + inspector + daftar joints (sesuai mockup).
# ----------------------------------------------------------------------------
var info_gauges := {}
var insp_lbls := {}
var joints_list_box: VBoxContainer
var joints_rows := {}

func _build_info_column() -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(300, 0)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(sc)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 12)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(mc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	mc.add_child(vb)

	vb.add_child(_info_section("OVERVIEW"))
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 8)
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(_gauge_cell("drive", "DRIVE"))
	grow.add_child(_gauge_cell("thermal", "THERMAL"))
	grow.add_child(_gauge_cell("power", "POWER"))
	vb.add_child(grow)

	vb.add_child(_hsep())
	vb.add_child(_info_section("INSPECTOR — JOINT TERPILIH"))
	var nm := Label.new()
	nm.text = "—"
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", COL_TEXT)
	if font_bold:
		nm.add_theme_font_override("font", font_bold)
	vb.add_child(nm)
	insp_lbls["name"] = nm
	var idl := Label.new()
	idl.text = "klik servo di 3D untuk memilih"
	idl.add_theme_font_size_override("font_size", 11)
	idl.add_theme_color_override("font_color", COL_MUTED)
	vb.add_child(idl)
	insp_lbls["id"] = idl
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	insp_lbls["pos"] = _kv(grid, "POSITION", "—")
	insp_lbls["goal"] = _kv(grid, "GOAL", "—")
	vb.add_child(grid)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 6)
	var home := Button.new()
	home.text = "⌂ Home"
	home.focus_mode = Control.FOCUS_NONE
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(_info_home)
	arow.add_child(home)
	var cal := Button.new()
	cal.text = "⚙ Calibrate"
	cal.focus_mode = Control.FOCUS_NONE
	cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cal.tooltip_text = "(menyusul) offset tuning per-servo"
	arow.add_child(cal)
	vb.add_child(arow)

	return wrap


func _info_section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", COL_MUTED)
	return l


func _hsep() -> Control:
	var s := ColorRect.new()
	s.color = COL_BORDER
	s.custom_minimum_size = Vector2(0, 1)
	return s


func _gauge_cell(key: String, label: String) -> Control:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := RingGaugeScript.new()
	g.custom_minimum_size = Vector2(60, 60)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(g)
	info_gauges[key] = g
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", COL_MUTED)
	cell.add_child(l)
	return cell


func _kv(grid: GridContainer, k: String, v: String) -> Label:
	var cell := VBoxContainer.new()
	var kl := Label.new()
	kl.text = k
	kl.add_theme_font_size_override("font_size", 9)
	kl.add_theme_color_override("font_color", COL_MUTED)
	cell.add_child(kl)
	var vl := Label.new()
	vl.text = v
	vl.add_theme_font_size_override("font_size", 14)
	vl.add_theme_color_override("font_color", COL_TEXT)
	cell.add_child(vl)
	grid.add_child(cell)
	return vl


func _info_home() -> void:
	if robot == null or manipulator == null:
		return
	var sel: String = manipulator.get_selected() if manipulator.has_method("get_selected") else ""
	if sel != "" and robot.has_method("reset_joint"):
		robot.reset_joint(sel)


func _ensure_joint_rows() -> void:
	if not joints_rows.is_empty() or joints_list_box == null or robot == null:
		return
	if not robot.has_method("get_joint_names"):
		return
	for jn in robot.get_joint_names():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.add_theme_stylebox_override("panel", _rounded(Color(0.184, 0.722, 0.541), 4))
		var dc := CenterContainer.new()
		dc.add_child(dot)
		row.add_child(dc)
		var nm := Label.new()
		nm.text = jn
		nm.add_theme_font_size_override("font_size", 11)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var val := Label.new()
		val.text = "0°"
		val.add_theme_font_size_override("font_size", 11)
		val.add_theme_color_override("font_color", COL_MUTED)
		row.add_child(val)
		joints_list_box.add_child(row)
		joints_rows[jn] = {"val": val}


func _update_info_column() -> void:
	if robot == null:
		return
	var is_open: bool = ros_bridge != null and ros_bridge.is_open()
	if is_open and _flow_state == 0:
		_set_flow_state(1)
	elif not is_open and _flow_state != 0:
		_set_flow_state(0)
	if info_gauges.has("drive"):
		info_gauges["drive"].set_gauge(0.42, "42%", Color(0.435, 0.482, 0.941))
		info_gauges["thermal"].set_gauge(0.55, "44°", Color(0.878, 0.604, 0.208))
		info_gauges["power"].set_gauge(0.87, "87%", Color(0.184, 0.722, 0.541))
	var sel: String = manipulator.get_selected() if (manipulator and manipulator.has_method("get_selected")) else ""
	if sel != "" and robot.joints.has(sel):
		insp_lbls["name"].text = sel
		if robot.has_method("get_servo_id"):
			insp_lbls["id"].text = "ID %02d · %s" % [robot.get_servo_id(sel), robot.get_servo_part(sel)]
		insp_lbls["pos"].text = "%+.1f°" % rad_to_deg(robot.get_joint_angle(sel))
		insp_lbls["goal"].text = "%+.1f°" % robot.get_default_angle_deg(sel)


# ----------------------------------------------------------------------------
# NAV-RAIL (kiri) — minimalis: ikon + label, item aktif = pill indigo halus.
# Pindah halaman konten: Overview (monitor) / Action (editor) / Logs.
# ----------------------------------------------------------------------------
var nav_content: Control
var nav_pages := {}
var nav_buttons := {}
const NAV_ITEMS := [["monitor", "Overview", "⌂"], ["action", "Action", "✎"], ["logs", "Logs", "≣"]]

func _build_nav_rail() -> Control:
	var rail := PanelContainer.new()
	rail.custom_minimum_size = Vector2(84, 0)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 12)
	rail.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	mc.add_child(vb)
	var logo := Panel.new()
	logo.custom_minimum_size = Vector2(44, 44)
	logo.add_theme_stylebox_override("panel", _rounded(COL_ACCENT, 22))
	var lw := CenterContainer.new()
	lw.add_child(logo)
	vb.add_child(lw)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	vb.add_child(sp)
	for item in NAV_ITEMS:
		vb.add_child(_nav_item(item[0], item[1], item[2]))
	return rail


func _nav_item(key: String, label: String, icon: String) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 60)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_nav_select.bind(key))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Label.new()
	ic.text = icon
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.add_theme_font_size_override("font_size", 20)
	var lb := Label.new()
	lb.text = label
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 10)
	box.add_child(ic)
	box.add_child(lb)
	b.add_child(box)
	nav_buttons[key] = {"btn": b, "ic": ic, "lb": lb}
	return b


func _nav_select(key: String) -> void:
	for k in nav_pages:
		nav_pages[k].visible = k == key
	for k in nav_buttons:
		var active: bool = k == key
		var col := COL_ACCENT if active else COL_MUTED
		var sb := _rounded(Color(0.933, 0.941, 1.0) if active else COL_PANEL, 12)
		nav_buttons[k]["btn"].add_theme_stylebox_override("normal", sb)
		nav_buttons[k]["btn"].add_theme_stylebox_override("hover", _rounded(Color(0.965, 0.969, 0.992), 12))
		nav_buttons[k]["btn"].add_theme_stylebox_override("pressed", sb)
		nav_buttons[k]["ic"].add_theme_color_override("font_color", col)
		nav_buttons[k]["lb"].add_theme_color_override("font_color", col)


# ----------------------------------------------------------------------------
# ACTION EDITOR — Page → Steps(scene) + 3 mode atur pose + preview.
# ----------------------------------------------------------------------------
var ae_steps := []
var _ae_sel := -1
var ae_steps_box: VBoxContainer
var ae_mode_opt: OptionButton
var ae_mode_hint: Label
var ae_name_edit: LineEdit

func _build_action_editor() -> Control:
	var panel := PanelContainer.new()
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_right", 14)
	mc.add_theme_constant_override("margin_top", 14)
	mc.add_theme_constant_override("margin_bottom", 14)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(mc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	mc.add_child(vb)

	var ttl := Label.new()
	ttl.text = "Action Editor"
	ttl.add_theme_font_size_override("font_size", 15)
	if font_bold:
		ttl.add_theme_font_override("font", font_bold)
	ttl.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(ttl)

	vb.add_child(_info_section("MODE ATUR POSE"))
	ae_mode_opt = OptionButton.new()
	ae_mode_opt.add_item("(a) Virtual — atur di DT")
	ae_mode_opt.add_item("(b) Hand-pose — lemaskan servo")
	ae_mode_opt.add_item("(c) Live-sync — DT & robot bareng")
	ae_mode_opt.item_selected.connect(_ae_mode_changed)
	vb.add_child(ae_mode_opt)
	ae_mode_hint = Label.new()
	ae_mode_hint.add_theme_color_override("font_color", COL_MUTED)
	ae_mode_hint.add_theme_font_size_override("font_size", 10)
	ae_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(ae_mode_hint)

	vb.add_child(_info_section("PAGE"))
	ae_name_edit = LineEdit.new()
	ae_name_edit.text = "motion_baru"
	vb.add_child(ae_name_edit)

	vb.add_child(_info_section("STEPS / SCENE"))
	ae_steps_box = VBoxContainer.new()
	ae_steps_box.add_theme_constant_override("separation", 3)
	vb.add_child(ae_steps_box)

	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	var cap := Button.new()
	cap.text = "+ Capture Step"
	cap.focus_mode = Control.FOCUS_NONE
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.pressed.connect(_ae_capture)
	r1.add_child(cap)
	var del := Button.new()
	del.text = "Hapus"
	del.focus_mode = Control.FOCUS_NONE
	del.pressed.connect(_ae_delete)
	r1.add_child(del)
	vb.add_child(r1)

	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	var play := Button.new()
	play.text = "▶ Preview di DT"
	play.focus_mode = Control.FOCUS_NONE
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(_ae_play)
	r2.add_child(play)
	var tryb := Button.new()
	tryb.text = "Coba di robot"
	tryb.focus_mode = Control.FOCUS_NONE
	tryb.tooltip_text = "Kirim pose step terpilih ke robot asli untuk verifikasi"
	tryb.pressed.connect(_ae_try_on_robot)
	r2.add_child(tryb)
	vb.add_child(r2)

	_ae_mode_changed(0)
	_ae_refresh_steps()
	return panel


func _ae_mode_changed(idx: int) -> void:
	if ae_mode_hint == null:
		return
	match idx:
		1:
			ae_mode_hint.text = "Pilih servo di 3D → torque-OFF → gerakkan fisik → Capture. (butuh robot konek)"
		2:
			ae_mode_hint.text = "Saat geser di DT, perintah dialirkan ke robot real-time. Siapkan E-Stop."
		_:
			ae_mode_hint.text = "Atur pose di DT (gizmo/slider), lalu Capture jadi scene. Aman — robot tak bergerak."


func _ae_refresh_steps() -> void:
	if ae_steps_box == null:
		return
	for c in ae_steps_box.get_children():
		c.queue_free()
	if ae_steps.is_empty():
		var e := Label.new()
		e.text = "(belum ada scene — tekan + Capture Step)"
		e.add_theme_color_override("font_color", COL_MUTED)
		e.add_theme_font_size_override("font_size", 11)
		ae_steps_box.add_child(e)
		return
	for i in range(ae_steps.size()):
		var b := Button.new()
		b.text = "  Scene %d   ·   t = %.1fs" % [i + 1, ae_steps[i]["time"]]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == _ae_sel:
			var sb := _rounded(Color(0.933, 0.941, 1.0), 8)
			sb.border_color = COL_ACCENT
			sb.border_width_left = 1; sb.border_width_right = 1
			sb.border_width_top = 1; sb.border_width_bottom = 1
			b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(_ae_select_step.bind(i))
		ae_steps_box.add_child(b)


func _ae_select_step(i: int) -> void:
	_ae_sel = i
	_ae_refresh_steps()
	if robot and i >= 0 and i < ae_steps.size():
		for jn in ae_steps[i]["pose"]:
			robot.set_joint_angle(jn, deg_to_rad(ae_steps[i]["pose"][jn]))


func _ae_capture() -> void:
	if robot == null or not robot.has_method("get_joint_names"):
		return
	var pose := {}
	for jn in robot.get_joint_names():
		pose[jn] = rad_to_deg(robot.get_joint_angle(jn))
	ae_steps.append({"pose": pose, "time": 0.5, "pause": 0.0})
	_ae_sel = ae_steps.size() - 1
	_ae_refresh_steps()
	_log("Action: capture Scene %d" % ae_steps.size())


func _ae_delete() -> void:
	if _ae_sel >= 0 and _ae_sel < ae_steps.size():
		ae_steps.remove_at(_ae_sel)
		_ae_sel = -1
		_ae_refresh_steps()


func _ae_play() -> void:
	if robot == null or ae_steps.is_empty() or not robot.has_method("play_motion"):
		return
	var steps := []
	for s in ae_steps:
		steps.append({"j": s["pose"], "t": s["time"], "p": s["pause"]})
	robot.play_motion(steps, false)
	_log("Action: preview %d scene di DT" % ae_steps.size())


func _ae_try_on_robot() -> void:
	if ros_bridge == null or not ros_bridge.is_open():
		_log("Coba di robot gagal — belum konek")
		return
	if _ae_sel < 0 or _ae_sel >= ae_steps.size():
		return
	var pose_rad := {}
	for jn in ae_steps[_ae_sel]["pose"]:
		pose_rad[jn] = deg_to_rad(ae_steps[_ae_sel]["pose"][jn])
	ros_bridge.publish_joints(pose_rad)
	_log("Action: kirim Scene %d ke robot" % (_ae_sel + 1))


# ----------------------------------------------------------------------------
# LOGS — event log sederhana (prepend, maks 60 baris).
# ----------------------------------------------------------------------------
var _log_box: VBoxContainer

func _build_logs_page() -> Control:
	var panel := PanelContainer.new()
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_right", 14)
	mc.add_theme_constant_override("margin_top", 14)
	mc.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	mc.add_child(vb)
	var ttl := Label.new()
	ttl.text = "Event Log"
	ttl.add_theme_font_size_override("font_size", 15)
	if font_bold:
		ttl.add_theme_font_override("font", font_bold)
	ttl.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(ttl)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 3)
	sc.add_child(_log_box)
	_log("Aplikasi siap — mode offline")
	return panel


func _log(text: String) -> void:
	if _log_box == null:
		return
	var l := Label.new()
	l.text = "%s   %s" % [Time.get_time_string_from_system(), text]
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", COL_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_box.add_child(l)
	_log_box.move_child(l, 0)
	while _log_box.get_child_count() > 60:
		_log_box.get_child(_log_box.get_child_count() - 1).queue_free()


# ----------------------------------------------------------------------------
# Koneksi robot (rosbridge WebSocket, ROS 2)
# ----------------------------------------------------------------------------
func _set_ros_dot(c: Color) -> void:
	if ros_status_dot == null:
		return
	var sb := _rounded(c, 5)
	ros_status_dot.add_theme_stylebox_override("panel", sb)


func _on_ros_connect() -> void:
	if ros_bridge == null:
		return
	if ros_bridge.is_open() or ros_bridge._want:
		ros_bridge.stop()
		ros_connect_btn.text = "Connect"
		_set_ros_dot(Color(0.75, 0.78, 0.82))
		_live_connected = false
	else:
		ros_bridge.start(ros_url_edit.text.strip_edges())
		ros_connect_btn.text = "Disconnect"
		# masuk mode Live otomatis saat menyambung
		if control_mode:
			_toggle_mode()


func _on_ros_status(state: String) -> void:
	match state:
		"connecting": _set_ros_dot(Color(0.95, 0.70, 0.20))   # kuning
		"open":       _set_ros_dot(Color(0.16, 0.56, 0.47))     # hijau
		"closed":
			_set_ros_dot(Color(0.90, 0.30, 0.30))              # merah
			_live_connected = false
			if sensor_panel and sensor_panel.has_method("set_sync_state"):
				sensor_panel.set_sync_state(false, 0.0)


var _last_joint_ms := 0

func _on_ros_joints(joints: Dictionary) -> void:
	# Data joint asli dari robot -> terapkan ke twin (hanya saat mode Live).
	# Tiap paket = bukti link real-time hidup (twin tersinkron dgn fisik).
	_live_connected = true
	var now := Time.get_ticks_msec()
	var dt_ms := float(now - _last_joint_ms) if _last_joint_ms > 0 else 0.0
	_last_joint_ms = now
	if sensor_panel and sensor_panel.has_method("set_sync_state"):
		sensor_panel.set_sync_state(true, clampf(dt_ms, 0.0, 999.0))
	if control_mode or robot == null:
		return
	for jname in joints:
		robot.set_joint_angle(jname, joints[jname])


func _on_ros_vision(detections: Array) -> void:
	# Hasil YOLO dari robot -> overlay box realtime di panel CV
	if sensor_panel and sensor_panel.has_method("set_detections"):
		sensor_panel.set_detections(detections)


func _on_ros_camera(tex: Texture2D) -> void:
	# Frame kamera kepala -> tampilkan di panel CV
	if sensor_panel and sensor_panel.has_method("set_camera_frame"):
		sensor_panel.set_camera_frame(tex)


func _on_ros_health(health: Dictionary) -> void:
	# Status servo dari robot -> kedipkan link yang bermasalah + tandai di panel
	if robot:
		for jname in health:
			robot.set_servo_health(jname, health[jname])
	if sensor_panel and sensor_panel.has_method("set_servo_health"):
		sensor_panel.set_servo_health(health)


func _make_status_dot() -> Control:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.66, 0.56)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	dot.add_theme_stylebox_override("panel", sb)
	return dot


func _build_viewport_header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = "  3D VIEW"
	lbl.add_theme_color_override("font_color", COL_MUTED)
	hb.add_child(lbl)

	var sep := Control.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sep)

	# Navigasi kamera lewat ViewCube (pojok kanan atas): klik sisi = pindah,
	# dobel-klik = hadap depan, klik-kanan = menu (termasuk isometrik).
	var hint := Label.new()
	hint.text = "Klik servo / pilih di panel · drag = putar · kubus = pindah pandangan  "
	hint.add_theme_color_override("font_color", COL_MUTED)
	hb.add_child(hint)

	return hb


# ----------------------------------------------------------------------------
# 3D SCENE
# ----------------------------------------------------------------------------
func _build_3d_scene() -> void:
	# World environment — sky lembut pastel untuk refleksi metal + ambient merata
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.93, 0.92, 0.97)
	sky_mat.sky_horizon_color = Color(0.88, 0.90, 0.95)
	sky_mat.ground_horizon_color = Color(0.86, 0.88, 0.93)
	sky_mat.ground_bottom_color = Color(0.80, 0.82, 0.88)
	sky_mat.sky_energy_multiplier = 0.55     # redup supaya silver tak ter-blowout putih
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY  # metal memantulkan sky
	env.ssao_enabled = true
	env.ssao_intensity = 0.5
	env.ssao_radius = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	# Pencahayaan SEIMBANG dari 5 penjuru (tanpa shadow) supaya robot terbaca
	# bagus dari sudut manapun, tapi tidak terlalu terang (silver tetap silver).
	_add_dir_light(Vector3(-40, -35, 0),  0.28, Color(1.0, 0.99, 0.97))   # depan-kiri
	_add_dir_light(Vector3(-35, 145, 0),  0.24, Color(0.94, 0.96, 1.0))   # belakang
	_add_dir_light(Vector3(-30, 65, 0),   0.22, Color(1, 1, 1))           # kanan
	_add_dir_light(Vector3(-30, -120, 0), 0.22, Color(1, 1, 1))           # kiri
	_add_dir_light(Vector3(50, 20, 0),    0.16, Color(0.95, 0.97, 1.0))   # bawah-isi

	# Lantai grid
	var floor := _make_floor()
	sub_viewport.add_child(floor)

	# OP3 Robot
	robot = Node3D.new()
	robot.set_script(OP3RobotScript)
	sub_viewport.add_child(robot)

	# Orbit camera
	orbit_camera = Camera3D.new()
	orbit_camera.set_script(CameraOrbitScript)
	orbit_camera.current = true
	sub_viewport.add_child(orbit_camera)

	# Kontrol joint interaktif (ring di joint terpilih, dipilih dari panel kiri)
	manipulator = Node3D.new()
	manipulator.set_script(JointManipScript)
	sub_viewport.add_child(manipulator)
	# deferred: pastikan OP3Robot._ready (yang mengisi joints) sudah jalan
	manipulator.call_deferred("setup", robot, orbit_camera)

	# Hubungkan panel kiri ke robot + manipulator (slider & pilih joint)
	if sensor_panel and sensor_panel.has_method("bind_controls"):
		sensor_panel.bind_controls(robot, manipulator)
	# Sinkronkan state awal (mode + sync) ke panel & manipulator sekali di awal,
	# supaya banner DT (MIMIC/AUTHOR, SIMULATION) benar sebelum koneksi pertama.
	if manipulator and manipulator.has_method("set_editable"):
		manipulator.set_editable(control_mode)
	if sensor_panel and sensor_panel.has_method("set_editable"):
		sensor_panel.set_editable(control_mode)
	if sensor_panel and sensor_panel.has_method("set_sync_state"):
		sensor_panel.set_sync_state(false, 0.0)

	# Klien rosbridge (koneksi ke robot asli)
	ros_bridge = RosBridgeScript.new()
	ros_bridge.name = "RosBridge"
	add_child(ros_bridge)
	ros_bridge.status_changed.connect(_on_ros_status)
	ros_bridge.joints_received.connect(_on_ros_joints)
	ros_bridge.health_received.connect(_on_ros_health)
	ros_bridge.vision_received.connect(_on_ros_vision)
	ros_bridge.camera_received.connect(_on_ros_camera)
	ros_bridge.imu_received.connect(_on_ros_imu)
	ros_bridge.status_received.connect(_on_robot_status)


func _add_dir_light(rot_deg: Vector3, energy: float, color: Color, shadow := false) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_energy = energy
	l.light_color = color
	l.shadow_enabled = shadow
	sub_viewport.add_child(l)


func _make_floor() -> Node3D:
	var holder := Node3D.new()

	# Plane
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(6, 6)

	var plane_inst := MeshInstance3D.new()
	plane_inst.mesh = plane_mesh

	var plane_mat := StandardMaterial3D.new()
	plane_mat.albedo_color = Color(0.84, 0.86, 0.89)
	plane_mat.roughness = 0.95
	plane_mat.metallic = 0.0
	plane_inst.material_override = plane_mat
	holder.add_child(plane_inst)

	# Grid lines (procedural via ImmediateMesh)
	var grid_mesh := ImmediateMesh.new()
	var grid_mat := StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.albedo_color = Color(0.62, 0.66, 0.72, 0.7)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_mat)
	var size := 3.0
	var step := 0.25
	var v := -size
	while v <= size + 0.001:
		grid_mesh.surface_add_vertex(Vector3(-size, 0.001, v))
		grid_mesh.surface_add_vertex(Vector3(size, 0.001, v))
		grid_mesh.surface_add_vertex(Vector3(v, 0.001, -size))
		grid_mesh.surface_add_vertex(Vector3(v, 0.001, size))
		v += step
	grid_mesh.surface_end()

	var grid_inst := MeshInstance3D.new()
	grid_inst.mesh = grid_mesh
	holder.add_child(grid_inst)

	return holder


# ----------------------------------------------------------------------------
# UPDATE LOOP — kirim data sensor terbaru ke panel kiri
# ----------------------------------------------------------------------------
func _process(_delta: float) -> void:
	# Mode Live: kalau rosbridge tersambung (data joint asli masuk), pakai itu.
	# Kalau belum tersambung, jalankan gait mock sebagai demo.
	if not control_mode and robot and not _live_connected:
		_drive_live()

	if sensor_panel and robot:
		# Sinkronkan posisi joint ke panel (slider & angka ikut)
		if sensor_panel.has_method("update_from_robot"):
			sensor_panel.update_from_robot(robot)

	_update_info_column()


func _drive_live() -> void:
	# Simulasi data joint masuk dari robot asli (gait berjalan halus).
	var t := Time.get_ticks_msec() / 1000.0
	var sw := sin(t * 2.0)
	var sw2 := sin(t * 2.0 + PI)
	robot.set_joint_angle("l_hip_pitch", deg_to_rad(-15.0 + sw * 18.0))
	robot.set_joint_angle("r_hip_pitch", deg_to_rad(-15.0 + sw2 * 18.0))
	robot.set_joint_angle("l_knee", deg_to_rad(30.0 + max(0.0, sw) * 25.0))
	robot.set_joint_angle("r_knee", deg_to_rad(30.0 + max(0.0, sw2) * 25.0))
	robot.set_joint_angle("l_ank_pitch", deg_to_rad(-15.0 - max(0.0, sw) * 8.0))
	robot.set_joint_angle("r_ank_pitch", deg_to_rad(-15.0 - max(0.0, sw2) * 8.0))
	robot.set_joint_angle("l_sho_pitch", deg_to_rad(sw2 * 20.0))
	robot.set_joint_angle("r_sho_pitch", deg_to_rad(sw * 20.0))
	robot.set_joint_angle("head_pan", sin(t * 0.5) * 0.3)

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

# --- Palet pastel (dipakai bersama SensorPanel) -----------------------------
const COL_BG       := Color(0.95, 0.94, 0.98)   # lavender-white
const COL_PANEL    := Color(1.0, 1.0, 1.0)      # kartu/panel
const COL_BORDER   := Color(0.91, 0.89, 0.95)
const COL_TEXT     := Color(0.22, 0.20, 0.32)   # slate keunguan
const COL_MUTED    := Color(0.53, 0.51, 0.63)   # teks sekunder
const COL_ACCENT   := Color(0.55, 0.45, 0.86)   # pastel ungu (aksen utama)
const COL_VIEW_BG  := Color(0.92, 0.91, 0.96)   # latar viewport 3D

# Aksen pastel per-seksi (badge ikon)
const PAS_PURPLE := Color(0.62, 0.52, 0.92)
const PAS_MINT   := Color(0.42, 0.70, 0.60)
const PAS_SKY    := Color(0.46, 0.71, 0.94)
const PAS_PEACH  := Color(0.98, 0.68, 0.58)
const PAS_AMBER  := Color(0.97, 0.80, 0.46)
const PAS_PINK   := Color(0.93, 0.58, 0.78)

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

	# Panel/kartu putih dengan border halus + soft shadow pastel
	var panel_sb := _rounded(COL_PANEL, 14)
	panel_sb.border_width_left = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_bottom = 1
	panel_sb.border_color = COL_BORDER
	panel_sb.shadow_color = Color(0.55, 0.50, 0.70, 0.13)
	panel_sb.shadow_size = 7
	panel_sb.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "PanelContainer", panel_sb)
	t.set_stylebox("panel", "Panel", _rounded(COL_PANEL, 14))

	t.set_color("font_color", "Label", COL_TEXT)

	# ProgressBar
	t.set_stylebox("background", "ProgressBar", _rounded(Color(0.90, 0.92, 0.94), 4))
	t.set_stylebox("fill", "ProgressBar", _rounded(COL_ACCENT, 4))
	t.set_color("font_color", "ProgressBar", COL_TEXT)

	# Tombol (pill pastel)
	var btn_n := _rounded(Color(0.97, 0.96, 0.99), 9)
	btn_n.border_width_bottom = 1; btn_n.border_width_top = 1
	btn_n.border_width_left = 1; btn_n.border_width_right = 1
	btn_n.border_color = COL_BORDER
	var btn_h := _rounded(Color(0.93, 0.91, 0.99), 9)
	btn_h.border_width_bottom = 1; btn_h.border_width_top = 1
	btn_h.border_width_left = 1; btn_h.border_width_right = 1
	btn_h.border_color = COL_ACCENT
	var btn_p := _rounded(Color(0.88, 0.84, 0.98), 9)
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
	split.split_offset = 420  # lebar panel kiri (sensor)
	add_child(split)

	# === KIRI: Sensor Panel ===
	var left_wrapper := PanelContainer.new()
	left_wrapper.custom_minimum_size = Vector2(380, 0)
	split.add_child(left_wrapper)

	sensor_panel = Control.new()
	sensor_panel.set_script(SensorPanelScript)
	left_wrapper.add_child(sensor_panel)

	# === KANAN: 3D Viewport dengan OP3 Robot ===
	var right_wrapper := PanelContainer.new()
	split.add_child(right_wrapper)

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

	# Tombol mode (Atur / Live)
	mode_btn = Button.new()
	mode_btn.focus_mode = Control.FOCUS_NONE
	mode_btn.custom_minimum_size = Vector2(150, 30)
	mode_btn.pressed.connect(_toggle_mode)
	hb.add_child(mode_btn)
	_refresh_mode_btn()

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


func _on_ros_joints(joints: Dictionary) -> void:
	# Data joint asli dari robot -> terapkan ke twin (hanya saat mode Live)
	_live_connected = true
	if control_mode or robot == null:
		return
	for jname in joints:
		robot.set_joint_angle(jname, joints[jname])


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
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY  # metal memantulkan sky
	env.ssao_enabled = true
	env.ssao_intensity = 0.5
	env.ssao_radius = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	# Pencahayaan SEIMBANG dari 4 penjuru (tanpa shadow) supaya robot terbaca
	# bagus dari sudut manapun — tak ada sisi gelap / backlight yg ubah warna.
	_add_dir_light(Vector3(-40, -35, 0),  0.55, Color(1.0, 0.99, 0.97))   # depan-kiri
	_add_dir_light(Vector3(-35, 145, 0),  0.5,  Color(0.94, 0.96, 1.0))   # belakang
	_add_dir_light(Vector3(-30, 65, 0),   0.45, Color(1, 1, 1))           # kanan
	_add_dir_light(Vector3(-30, -120, 0), 0.45, Color(1, 1, 1))           # kiri
	_add_dir_light(Vector3(50, 20, 0),    0.3,  Color(0.95, 0.97, 1.0))   # bawah-isi

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

	# Klien rosbridge (koneksi ke robot asli)
	ros_bridge = RosBridgeScript.new()
	ros_bridge.name = "RosBridge"
	add_child(ros_bridge)
	ros_bridge.status_changed.connect(_on_ros_status)
	ros_bridge.joints_received.connect(_on_ros_joints)
	ros_bridge.health_received.connect(_on_ros_health)


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

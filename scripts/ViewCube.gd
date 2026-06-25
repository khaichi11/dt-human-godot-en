extends Control
# ============================================================================
# ViewCube.gd
# Kubus orientasi mini di pojok viewport (seperti Fusion/Blender). Kubus ikut
# berputar mengikuti kamera utama; klik salah satu sisi -> kamera pindah ke
# pandangan sisi tersebut.
#
# Dipasang Main: var vc = ViewCube; add_child; vc.setup(orbit_camera)
# ============================================================================

const SIZE := 104

# sisi: arah dunia (Godot) -> preset kamera. Robot menghadap -Z.
# Label F/B/L/R/U/D (standar software 3D) — jelas & muat di kubus kecil.
const FACES := [
	[Vector3(0, 0, -1), "depan",    "F"],
	[Vector3(0, 0, 1),  "belakang", "B"],
	[Vector3(1, 0, 0),  "kanan",    "R"],
	[Vector3(-1, 0, 0), "kiri",     "L"],
	[Vector3(0, 1, 0),  "atas",     "U"],
	[Vector3(0, -1, 0), "bawah",    "D"],
]
const MENU := [["Isometrik", "iso"], ["Depan", "depan"], ["Belakang", "belakang"],
	["Kiri", "kiri"], ["Kanan", "kanan"], ["Atas", "atas"], ["Bawah", "bawah"]]

var _main_cam: Camera3D
var _vp: SubViewport
var _cube: Node3D
var _vp_cam: Camera3D
var _menu: PopupMenu
var _press_pos: Vector2
var _dragging := false


func setup(main_cam: Camera3D) -> void:
	_main_cam = main_cam


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.custom_minimum_size = Vector2(SIZE, SIZE)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)

	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.disable_3d = false
	cont.add_child(_vp)

	# environment terang biar kubus jelas
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	_vp.add_child(light)

	_vp_cam = Camera3D.new()
	_vp_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp_cam.size = 3.1
	_vp_cam.position = Vector3(0, 0, 4)
	_vp.add_child(_vp_cam)

	_cube = Node3D.new()
	_vp.add_child(_cube)
	_build_cube()


func _build_cube() -> void:
	# badan kubus
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.98, 0.98, 0.98)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.85, 0.92)
	mat.metallic = 0.0
	mat.roughness = 0.75
	box.material_override = mat
	_cube.add_child(box)

	# rangka tepi kubus (biar bentuknya jelas)
	var edges := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(1.0, 1.0, 1.0)
	edges.mesh = em
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(0.45, 0.52, 0.62)
	emat.cull_mode = BaseMaterial3D.CULL_FRONT     # tampak seperti outline
	emat.grow = true
	emat.grow_amount = 0.012
	edges.material_override = emat
	_cube.add_child(edges)

	for f in FACES:
		var dir: Vector3 = f[0]
		var preset: String = f[1]
		var label: String = f[2]

		# collider sisi (untuk klik)
		var body := StaticBody3D.new()
		body.position = dir * 0.5
		body.set_meta("preset", preset)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz := Vector3(0.9, 0.9, 0.9)
		if absf(dir.x) > 0.5: sz.x = 0.12
		elif absf(dir.y) > 0.5: sz.y = 0.12
		else: sz.z = 0.12
		bs.size = sz
		cs.shape = bs
		body.add_child(cs)
		_cube.add_child(body)

		# teks sisi — billboard supaya selalu terbaca; depth-test agar sisi
		# belakang tertutup kubus
		var lbl := Label3D.new()
		lbl.text = label
		lbl.font_size = 96
		lbl.pixel_size = 0.0050
		lbl.modulate = Color(0.30, 0.26, 0.45)
		lbl.outline_size = 10
		lbl.outline_modulate = Color(1, 1, 1, 0.9)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = dir * 0.52
		_cube.add_child(lbl)


func _process(_delta: float) -> void:
	if _main_cam == null or _cube == null:
		return
	# kubus mengikuti orientasi kamera utama
	_cube.global_transform.basis = _main_cam.global_transform.basis.inverse()


func _gui_input(event: InputEvent) -> void:
	# Drag kubus = orbit kamera bebas; klik sisi = snap; dobel-klik = depan;
	# klik-kanan = menu.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					_apply("depan")
				else:
					_press_pos = event.position
					_dragging = false
			else:
				if not _dragging:
					_pick_face(event.position)   # klik tanpa geser = snap
				_dragging = false
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_menu(event.global_position)
			accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if event.position.distance_to(_press_pos) > 4.0:
			_dragging = true
		if _dragging and _main_cam and _main_cam.has_method("orbit_by"):
			_main_cam.orbit_by(-event.relative.x * 0.6, -event.relative.y * 0.6)
		accept_event()


func _show_menu(global_pos: Vector2) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		for i in MENU.size():
			_menu.add_item(MENU[i][0], i)
		_menu.id_pressed.connect(func(id: int): _apply(MENU[id][1]))
		add_child(_menu)
	_menu.reset_size()
	_menu.position = Vector2i(global_pos)
	_menu.popup()


func _apply(preset: String) -> void:
	if _main_cam and _main_cam.has_method("apply_view"):
		_main_cam.apply_view(preset)


func _pick_face(local_pos: Vector2) -> void:
	# Geometric ray-vs-box pick (no physics — the subviewport's own physics world
	# doesn't step, so intersect_ray never hit anything). Transform the click ray
	# into the cube's local space and slab-test the unit cube; the entry face's
	# local normal maps straight to a FACE preset.
	if _vp_cam == null or _main_cam == null or _cube == null:
		return
	var inv := _cube.global_transform.affine_inverse()
	var from: Vector3 = inv * _vp_cam.project_ray_origin(local_pos)
	var dir: Vector3 = (inv.basis * _vp_cam.project_ray_normal(local_pos)).normalized()

	const H := 0.5
	var tmin := -INF
	var tmax := INF
	var hit_axis := -1
	var hit_sign := 1.0
	for axis in 3:
		var o: float = from[axis]
		var d: float = dir[axis]
		if absf(d) < 1e-6:
			if o < -H or o > H:
				return            # parallel & outside this slab → miss
			continue
		var inv_d := 1.0 / d
		var t1 := (-H - o) * inv_d
		var t2 := (H - o) * inv_d
		var sgn := -1.0
		if t1 > t2:
			var tmp := t1; t1 = t2; t2 = tmp
			sgn = 1.0
		if t1 > tmin:
			tmin = t1
			hit_axis = axis
			hit_sign = sgn
		tmax = minf(tmax, t2)
	if hit_axis < 0 or tmin > tmax:
		return            # ray misses the cube
	var normal := Vector3.ZERO
	normal[hit_axis] = hit_sign
	# match entry normal to a face preset
	var best := ""
	var best_dot := 0.9
	for f in FACES:
		var d2: float = (f[0] as Vector3).dot(normal)
		if d2 > best_dot:
			best_dot = d2
			best = f[1]
	if best != "" and _main_cam.has_method("apply_view"):
		_main_cam.apply_view(best)

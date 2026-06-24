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
const FACES := [
	[Vector3(0, 0, -1), "depan",    "DEPAN"],
	[Vector3(0, 0, 1),  "belakang", "BLKG"],
	[Vector3(1, 0, 0),  "kanan",    "KA"],
	[Vector3(-1, 0, 0), "kiri",     "KI"],
	[Vector3(0, 1, 0),  "atas",     "ATAS"],
	[Vector3(0, -1, 0), "bawah",    "BWH"],
]

var _main_cam: Camera3D
var _vp: SubViewport
var _cube: Node3D
var _vp_cam: Camera3D


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
		lbl.font_size = 72
		lbl.pixel_size = 0.0036
		lbl.modulate = Color(0.10, 0.22, 0.40)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = dir * 0.52
		_cube.add_child(lbl)


func _process(_delta: float) -> void:
	if _main_cam == null or _cube == null:
		return
	# kubus mengikuti orientasi kamera utama
	_cube.global_transform.basis = _main_cam.global_transform.basis.inverse()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pick_face(event.position)
		accept_event()


func _pick_face(local_pos: Vector2) -> void:
	if _vp_cam == null or _main_cam == null:
		return
	var from := _vp_cam.project_ray_origin(local_pos)
	var dir := _vp_cam.project_ray_normal(local_pos)
	var space := _vp.world_3d.direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0)
	var hit := space.intersect_ray(params)
	if hit and hit.collider.has_meta("preset"):
		if _main_cam.has_method("apply_view"):
			_main_cam.apply_view(hit.collider.get_meta("preset"))

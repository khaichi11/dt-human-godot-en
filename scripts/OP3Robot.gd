extends Node3D
# ============================================================================
# OP3Robot.gd
# Membangun model 3D ROBOTIS OP3 dari MESH ASLI per-link (hasil ekspor resmi
# paket `op3_description`, dikonversi STL -> OBJ di res://assets/op3_meshes/).
#
# Hierarki joint 20 DOF + origin + axis diambil PERSIS dari URDF resmi
# (robotis_op3.structure.*.xacro). Tiap link adalah Node3D pada origin joint;
# mesh-nya ditempel sebagai anak. Memutar Node3D = forward kinematics.
#
# Konversi koordinat:
#   URDF/ROS  : x maju,  y kiri, z atas   (Z-up, milimeter di-skala ke meter)
#   Godot     : x kanan, y atas, z mundur (Y-up)
# Seluruh pohon dibangun dalam konvensi ROS lalu seluruh `model_root` diputar
# satu kali oleh ROS_TO_GODOT. Mesh OBJ sudah di-skala mm->m saat konversi.
#
# API publik (dipakai SensorPanel.gd):
#   set_joint_angle(name, radians)
#   get_joint_angle(name) -> radians
# ============================================================================

const MESH_DIR := "res://assets/op3_meshes/"
const PICK_LAYER := 2          # layer fisika khusus untuk klik joint di 3D

# ROS (x-maju, y-kiri, z-atas) -> Godot (x-kanan, y-atas, z-mundur).
# Kolom basis = bayangan sumbu ros x,y,z di ruang Godot.
const ROS_TO_GODOT := Basis(
	Vector3(0, 0, -1),   # ros +x (maju)  -> godot -z (maju)
	Vector3(-1, 0, 0),   # ros +y (kiri)  -> godot -x (kiri)
	Vector3(0, 1, 0)     # ros +z (atas)  -> godot +y (atas)
)

# Material rangka OP3 — matte (aluminium/plastik abu-abu). Sengaja TIDAK
# mengkilap: metallic tinggi membuat tiap riak normal memantul tajam sehingga
# permukaan rata terlihat "penyok". OP3 asli juga matte.
const COL_FRAME := Color(0.40, 0.43, 0.49)   # abu gelap (anodized) = kontras di latar terang

# --- Storage ---------------------------------------------------------------
# joint_name -> {"node": Node3D, "axis": Vector3 (sumbu rotasi lokal, frame ROS)}
var joints: Dictionary = {}
# joint_name -> sudut sekarang (radian) untuk pembacaan balik yang akurat
var joint_angles: Dictionary = {}
# link_name -> Node3D (untuk lookup parent saat membangun)
var _links: Dictionary = {}

var model_root: Node3D
var _frame_mat: StandardMaterial3D


func _ready() -> void:
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = COL_FRAME
	_frame_mat.metallic = 0.45
	_frame_mat.roughness = 0.42

	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	model_root.transform.basis = ROS_TO_GODOT
	add_child(model_root)

	_build()
	_apply_default_pose()
	_stand_on_floor()


# ============================================================================
# DATA URDF — [name, parent_link, origin(ROS,m), axis(ROS), mesh_basename]
# parent "body" = body_link (akar). Semua joint rpy=0 di URDF, jadi tak ada
# offset rotasi statis.
# ============================================================================
func _joint_table() -> Array:
	return [
		# --- kepala ---
		["head_pan",    "body",          Vector3(-0.001, 0.0,    0.1365),  Vector3(0, 0, 1),  "h1"],
		["head_tilt",   "head_pan",      Vector3( 0.010, 0.019,  0.0285),  Vector3(0, -1, 0), "h2"],
		# --- lengan kanan ---
		["r_sho_pitch", "body",          Vector3(-0.001, -0.06,  0.111),   Vector3(0, -1, 0), "ra1"],
		["r_sho_roll",  "r_sho_pitch",   Vector3( 0.019, -0.0285,-0.010),  Vector3(-1, 0, 0), "ra2"],
		["r_el",        "r_sho_roll",    Vector3( 0.0,   -0.0904,-0.0001), Vector3(1, 0, 0),  "ra3"],
		# --- lengan kiri ---
		["l_sho_pitch", "body",          Vector3(-0.001, 0.06,   0.111),   Vector3(0, 1, 0),  "la1"],
		["l_sho_roll",  "l_sho_pitch",   Vector3( 0.019, 0.0285, -0.010),  Vector3(-1, 0, 0), "la2"],
		["l_el",        "l_sho_roll",    Vector3( 0.0,   0.0904, -0.0001), Vector3(1, 0, 0),  "la3"],
		# --- kaki kanan ---
		["r_hip_yaw",   "body",          Vector3( 0.0,   -0.035, 0.0),     Vector3(0, 0, -1), "rl1"],
		["r_hip_roll",  "r_hip_yaw",     Vector3(-0.024, 0.0,    -0.0285), Vector3(-1, 0, 0), "rl2"],
		["r_hip_pitch", "r_hip_roll",    Vector3( 0.0241,-0.019, 0.0),     Vector3(0, -1, 0), "rl3"],
		["r_knee",      "r_hip_pitch",   Vector3( 0.0,   0.0,    -0.11015),Vector3(0, -1, 0), "rl4"],
		["r_ank_pitch", "r_knee",        Vector3( 0.0,   0.0,    -0.110),  Vector3(0, 1, 0),  "rl5"],
		["r_ank_roll",  "r_ank_pitch",   Vector3(-0.0241,0.019,  0.0),     Vector3(1, 0, 0),  "rl6"],
		# --- kaki kiri ---
		["l_hip_yaw",   "body",          Vector3( 0.0,   0.035,  0.0),     Vector3(0, 0, -1), "ll1"],
		["l_hip_roll",  "l_hip_yaw",     Vector3(-0.024, 0.0,    -0.0285), Vector3(-1, 0, 0), "ll2"],
		["l_hip_pitch", "l_hip_roll",    Vector3( 0.0241,0.019,  0.0),     Vector3(0, 1, 0),  "ll3"],
		["l_knee",      "l_hip_pitch",   Vector3( 0.0,   0.0,    -0.11015),Vector3(0, 1, 0),  "ll4"],
		["l_ank_pitch", "l_knee",        Vector3( 0.0,   0.0,    -0.110),  Vector3(0, -1, 0), "ll5"],
		["l_ank_roll",  "l_ank_pitch",   Vector3(-0.0241,-0.019, 0.0),     Vector3(1, 0, 0),  "ll6"],
	]


# ============================================================================
# BUILD
# ============================================================================
func _build() -> void:
	# Akar: body_link
	var body := Node3D.new()
	body.name = "body_link"
	model_root.add_child(body)
	_attach_mesh(body, "body", "")
	_links["body"] = body

	for spec in _joint_table():
		var jname: String   = spec[0]
		var parent: String  = spec[1]
		var origin: Vector3 = spec[2]
		var axis: Vector3   = (spec[3] as Vector3).normalized()
		var mesh_name: String = spec[4]

		var parent_node: Node3D = _links.get(parent)
		if parent_node == null:
			push_warning("OP3Robot: parent '%s' belum ada untuk joint '%s'" % [parent, jname])
			continue

		var joint := Node3D.new()
		joint.name = jname
		joint.position = origin
		parent_node.add_child(joint)
		_attach_mesh(joint, mesh_name, jname)

		_links[jname] = joint
		joints[jname] = {"node": joint, "axis": axis}
		joint_angles[jname] = 0.0


func _attach_mesh(parent: Node3D, mesh_basename: String, joint_name: String) -> void:
	var mesh := _load_mesh(mesh_basename)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = mesh_basename
	mi.mesh = mesh
	mi.material_override = _frame_mat
	parent.add_child(mi)

	# Collision (convex) supaya link bisa diklik di 3D untuk memilih jointnya
	if joint_name != "":
		var body := StaticBody3D.new()
		body.name = "pick_" + joint_name
		body.collision_layer = PICK_LAYER
		body.collision_mask = 0
		body.set_meta("joint_name", joint_name)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_convex_shape()
		body.add_child(shape)
		parent.add_child(body)


func _load_mesh(basename: String) -> Mesh:
	var path := MESH_DIR + basename + ".obj"
	if not ResourceLoader.exists(path):
		push_warning("OP3Robot: mesh belum ada/diimport: %s" % path)
		return null
	var res := load(path)
	if res is Mesh:
		return res
	if res is PackedScene:
		# fallback bila importer meng-import sebagai scene
		var inst := (res as PackedScene).instantiate()
		var found := _find_mesh(inst)
		inst.queue_free()
		return found
	push_warning("OP3Robot: tipe resource tak terduga untuk %s" % path)
	return null


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


# ============================================================================
# Letakkan robot di lantai: geser model_root agar titik terendah pada y=0
# ============================================================================
func _stand_on_floor() -> void:
	var aabb := _combined_aabb(model_root, global_transform.affine_inverse())
	if aabb.size == Vector3.ZERO:
		return
	model_root.position.y -= aabb.position.y


func _combined_aabb(node: Node, inv_root: Transform3D) -> AABB:
	var result := AABB()
	var has_any := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var box := (inv_root * mi.global_transform) * mi.get_aabb()
		result = box
		has_any = true
	for c in node.get_children():
		var sub := _combined_aabb(c, inv_root)
		if sub.size != Vector3.ZERO:
			result = result.merge(sub) if has_any else sub
			has_any = true
	return result


# ============================================================================
# LIMIT SUDUT PER-JOINT (derajat) — rentang kerja realistis OP3.
# Servo Dynamixel berputar simetris; mekanik sendi yang membatasi. URDF resmi
# memakai ±162 seragam, jadi nilai di bawah adalah rentang praktis tiap sendi
# (simetris -> aman terhadap konvensi tanda kiri/kanan).
# ============================================================================
const LIMITS_DEG := {
	"r_sho_pitch": [-165.0, 165.0], "l_sho_pitch": [-165.0, 165.0],
	"r_sho_roll":  [-95.0, 95.0],   "l_sho_roll":  [-95.0, 95.0],
	"r_el":        [-95.0, 95.0],   "l_el":        [-95.0, 95.0],
	"r_hip_yaw":   [-50.0, 50.0],   "l_hip_yaw":   [-50.0, 50.0],
	"r_hip_roll":  [-35.0, 35.0],   "l_hip_roll":  [-35.0, 35.0],
	"r_hip_pitch": [-95.0, 95.0],   "l_hip_pitch": [-95.0, 95.0],
	"r_knee":      [-150.0, 150.0], "l_knee":      [-150.0, 150.0],
	"r_ank_pitch": [-90.0, 90.0],   "l_ank_pitch": [-90.0, 90.0],
	"r_ank_roll":  [-35.0, 35.0],   "l_ank_roll":  [-35.0, 35.0],
	"head_pan":    [-90.0, 90.0],
	"head_tilt":   [-50.0, 48.0],
}


# Batas joint dalam radian (Vector2(min, max)). Default ±162 (URDF) bila tak ada.
func get_joint_limit(joint_name: String) -> Vector2:
	if LIMITS_DEG.has(joint_name):
		var l: Array = LIMITS_DEG[joint_name]
		return Vector2(deg_to_rad(l[0]), deg_to_rad(l[1]))
	return Vector2(-PI * 0.9, PI * 0.9)


# ============================================================================
# PUBLIC API
# ============================================================================
func set_joint_angle(joint_name: String, radians: float) -> void:
	if not joints.has(joint_name):
		return
	# Klamp ke batas servo (berlaku untuk slider, gizmo, maupun data live)
	var lim := get_joint_limit(joint_name)
	radians = clampf(radians, lim.x, lim.y)
	var j: Dictionary = joints[joint_name]
	var node: Node3D = j["node"]
	var axis: Vector3 = j["axis"]
	var t := node.transform
	t.basis = Basis(axis, radians)   # rotasi murni di sekitar origin joint
	node.transform = t
	joint_angles[joint_name] = radians


func get_joint_angle(joint_name: String) -> float:
	return joint_angles.get(joint_name, 0.0)


# ============================================================================
# POSE DEFAULT — berdiri natural (lengan turun ke sisi badan).
# Pose-nol URDF membuat lengan terentang horizontal; pose ini menurunkannya.
# Tanda/derajat ditentukan empiris terhadap axis URDF model ini.
# Saat integrasi data robot asli, panggil set_joint_angle() yang akan
# menimpa pose ini per joint.
# ============================================================================
const DEFAULT_POSE := {
	"r_sho_roll": -80.0, "l_sho_roll": 80.0,   # lengan turun ke samping badan
	"r_el": -25.0,       "l_el": 25.0,         # siku sedikit menekuk
	"head_tilt": 8.0,                          # kepala sedikit menunduk
}


func _apply_default_pose() -> void:
	for jname in DEFAULT_POSE.keys():
		set_joint_angle(jname, deg_to_rad(DEFAULT_POSE[jname]))

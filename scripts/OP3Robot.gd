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
const COL_FRAME := Color(0.10, 0.10, 0.12)   # hitam anodized (seperti OP3 asli)

# --- Storage ---------------------------------------------------------------
# joint_name -> {"node": Node3D, "axis": Vector3 (sumbu rotasi lokal, frame ROS)}
var joints: Dictionary = {}
# joint_name -> sudut sekarang (radian) untuk pembacaan balik yang akurat
var joint_angles: Dictionary = {}
# link_name -> Node3D (untuk lookup parent saat membangun)
var _links: Dictionary = {}

var model_root: Node3D
var _frame_mat: StandardMaterial3D
var _silver_mat: StandardMaterial3D
var _link_mats := {}            # joint_name -> StandardMaterial3D (per-link, OBJ)
var _link_base_col := {}        # joint_name -> Color (warna normal: hitam/silver)
var _hl_servo := {}             # joint_name -> MeshInstance3D (sub-mesh servo, GLB)
var _hl_servo_mat := {}         # joint_name -> StandardMaterial3D (overlay health)
var _health := {}               # joint_name -> "ok" | "warn" | "fault"

# Pembedaan servo vs besi yang akurat butuh mesh dipisah per-komponen (di
# Blender) — mesh OP3 per-link menyatukan servo+bracket. Default: hitam seragam.
# Saat file .glb hasil cat tersedia, materialnya dipakai apa adanya (lihat
# docs/06-texturing.md). SILVER_MESHES sengaja dikosongkan.
const SILVER_MESHES := {}
const COL_SILVER := Color(0.32, 0.34, 0.38)   # gunmetal (besi/bracket)


func _ready() -> void:
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = COL_FRAME
	_frame_mat.metallic = 0.65           # aluminium anodized hitam (mengkilap halus)
	_frame_mat.roughness = 0.40
	_frame_mat.metallic_specular = 0.55

	_silver_mat = StandardMaterial3D.new()
	_silver_mat.albedo_color = COL_SILVER
	_silver_mat.metallic = 0.30          # rangka/bracket aluminium (gunmetal, tak silau)
	_silver_mat.roughness = 0.55
	_silver_mat.metallic_specular = 0.4
	_frame_mat.rim_enabled = true        # rim halus mempertegas tepi/bentuk
	_frame_mat.rim = 0.3
	_frame_mat.rim_tint = 0.5

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
	var res := _load_link_resource(mesh_basename)
	if res == null:
		return
	# .blend/.glb hasil cat (multi-objek + material) -> pakai apa adanya;
	# .obj -> mesh tunggal + material kode (hitam/silver).
	if res is PackedScene:
		_attach_scene(parent, res as PackedScene, joint_name)
	elif res is Mesh:
		_attach_single_mesh(parent, res as Mesh, mesh_basename, joint_name)


func _attach_single_mesh(parent: Node3D, mesh: Mesh, mesh_basename: String, joint_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = mesh_basename
	mi.mesh = mesh
	if joint_name != "":
		var base: StandardMaterial3D = _silver_mat if SILVER_MESHES.has(mesh_basename) else _frame_mat
		var lm := base.duplicate()
		mi.material_override = lm
		_link_mats[joint_name] = lm
		_link_base_col[joint_name] = base.albedo_color
	else:
		mi.material_override = _frame_mat
	parent.add_child(mi)
	if joint_name != "":
		_add_pick_collision(parent, mesh, joint_name)


func _attach_scene(parent: Node3D, scene: PackedScene, joint_name: String) -> void:
	# .glb berisi sub-objek "servo" & "frame" dengan MATERIAL BAWAAN (hasil cat).
	# Material dipakai apa adanya -> bisa custom di Blender. Health (merah) hanya
	# meng-override sub-mesh "servo" saat fault, lalu dikembalikan saat ok.
	var inst := scene.instantiate()
	parent.add_child(inst)
	var mis: Array[MeshInstance3D] = []
	_collect_mesh_instances(inst, mis)
	var servo: MeshInstance3D = null
	for m in mis:
		if m.mesh == null:
			continue
		if servo == null and "servo" in m.name.to_lower():
			servo = m
		if joint_name != "":
			var body := StaticBody3D.new()
			body.collision_layer = PICK_LAYER
			body.collision_mask = 0
			body.set_meta("joint_name", joint_name)
			var cs := CollisionShape3D.new()
			cs.shape = m.mesh.create_convex_shape()
			body.add_child(cs)
			m.add_child(body)
	# Fallback: bila tak ada objek "servo", pakai sub-mesh pertama utk health.
	if servo == null and not mis.is_empty():
		servo = mis[0]
	if joint_name != "" and servo != null:
		_hl_servo[joint_name] = servo
		_hl_servo_mat[joint_name] = StandardMaterial3D.new()


func _add_pick_collision(parent: Node3D, mesh: Mesh, joint_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = "pick_" + joint_name
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("joint_name", joint_name)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_convex_shape()
	body.add_child(shape)
	parent.add_child(body)


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_mesh_instances(c, out)


func _load_link_resource(basename: String) -> Resource:
	# Prioritas: .blend (edit langsung di Blender) -> .glb (cat) -> .obj (default).
	for ext in [".blend", ".glb", ".obj"]:
		var path: String = MESH_DIR + basename + ext
		if ResourceLoader.exists(path):
			return load(path)
	push_warning("OP3Robot: mesh belum ada/diimport: %s" % basename)
	return null


# ============================================================================
# Grounding: jaga titik terendah robot selalu di lantai (y=0). Dipanggil tiap
# frame sehingga saat pose berubah (jongkok, push-up, gerakin joint) robot
# tetap menapak — mengikuti "gravitasi" visual, tidak melayang/menembus.
# ============================================================================
func _process(_delta: float) -> void:
	_ground_to_floor()
	_blink_health()


# ============================================================================
# SERVO HEALTH — servo bermasalah membuat link-nya kedip merah <-> hitam.
# state: "ok" (normal/metal), "warn" (kuning pelan), "fault" (merah kedip).
# Sumber state: pembaca Dynamixel (hardware_error_status, suhu, overload) via
# koneksi — lihat RosBridge / topic /dt/servo_health.
# ============================================================================
func set_servo_health(joint_name: String, state: String) -> void:
	if not (_link_mats.has(joint_name) or _hl_servo.has(joint_name)):
		return
	_health[joint_name] = state
	if state == "ok":
		if _link_mats.has(joint_name):             # OBJ: pulihkan material kode
			var m: StandardMaterial3D = _link_mats[joint_name]
			m.albedo_color = _link_base_col.get(joint_name, COL_FRAME)
			m.metallic = 0.65
			m.emission_enabled = false
		if _hl_servo.has(joint_name):              # GLB: lepas override -> cat asli
			(_hl_servo[joint_name] as MeshInstance3D).material_override = null


func get_servo_health(joint_name: String) -> String:
	return _health.get(joint_name, "ok")


func _blink_health() -> void:
	if _health.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for jname in _health:
		var state: String = _health[jname]
		if state == "ok":
			continue
		# Material dianimasikan: OBJ = material link; GLB = overlay yang dipasang
		# HANYA pada sub-mesh "servo" (besi/bracket tak ikut merah).
		var m: StandardMaterial3D = null
		if _link_mats.has(jname):
			m = _link_mats[jname]
		elif _hl_servo.has(jname):
			m = _hl_servo_mat[jname]
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			(_hl_servo[jname] as MeshInstance3D).material_override = m
		if m == null:
			continue
		m.metallic = 0.1
		m.emission_enabled = true
		if state == "fault":
			var s := (sin(t * 9.0) + 1.0) * 0.5
			m.albedo_color = Color(0.05, 0.02, 0.02).lerp(Color(0.95, 0.08, 0.08), s)
			m.emission = Color(0.9, 0.05, 0.05) * s
		else:   # warn — kuning berkedip pelan
			var s := (sin(t * 3.0) + 1.0) * 0.5
			m.albedo_color = Color(0.35, 0.30, 0.05).lerp(Color(0.95, 0.78, 0.15), s)
			m.emission = Color(0.9, 0.7, 0.1) * s * 0.6


func _stand_on_floor() -> void:
	_ground_to_floor()


func _ground_to_floor() -> void:
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
# METADATA SERVO — ID Dynamixel & bagian tubuh (sumber: op3_manager / DT-Human).
# Semua servo OP3 = Dynamixel XM-430-W350 (Protocol 2.0).
# ============================================================================
const SERVO_ID := {
	"r_sho_pitch": 1,  "l_sho_pitch": 2,  "r_sho_roll": 3,  "l_sho_roll": 4,
	"r_el": 5,         "l_el": 6,         "r_hip_yaw": 7,   "l_hip_yaw": 8,
	"r_hip_roll": 9,   "l_hip_roll": 10,  "r_hip_pitch": 11,"l_hip_pitch": 12,
	"r_knee": 13,      "l_knee": 14,      "r_ank_pitch": 15,"l_ank_pitch": 16,
	"r_ank_roll": 17,  "l_ank_roll": 18,  "head_pan": 19,   "head_tilt": 20,
}
const SERVO_MODEL := "XM-430-W350"


func get_servo_id(joint_name: String) -> int:
	return SERVO_ID.get(joint_name, 0)


func get_servo_part(joint_name: String) -> String:
	if joint_name.begins_with("head"):
		return "Kepala"
	if "sho" in joint_name or joint_name.ends_with("_el"):
		return "Lengan " + ("Kanan" if joint_name.begins_with("r") else "Kiri")
	return "Kaki " + ("Kanan" if joint_name.begins_with("r") else "Kiri")


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
# POSE DEFAULT / IDLE = "walk ready" resmi OP3 (ready_pose dari tune_pose.yaml).
# Sesuai kode asli: robot diam dalam pose walk-ready, dan tiap gerakan/gestur
# kembali ke sini (perilaku LinkToExit di motion module ROBOTIS).
# ============================================================================
const DEFAULT_POSE := {
	"r_sho_pitch": 15.0,  "l_sho_pitch": -15.0,
	"r_sho_roll": -45.0,  "l_sho_roll": 45.0,
	"r_el": 45.0,         "l_el": -45.0,
	"r_hip_yaw": 0.0,     "l_hip_yaw": 0.0,
	"r_hip_roll": 0.0,    "l_hip_roll": 0.0,
	"r_hip_pitch": 70.0,  "l_hip_pitch": -70.0,
	"r_knee": -142.0,     "l_knee": 142.0,
	"r_ank_pitch": -70.0, "l_ank_pitch": 70.0,
	"r_ank_roll": 0.0,    "l_ank_roll": 0.0,
	"head_pan": 0.0,      "head_tilt": -10.0,
}

var _playing := false


func _apply_default_pose() -> void:
	for jname in DEFAULT_POSE.keys():
		set_joint_angle(jname, deg_to_rad(DEFAULT_POSE[jname]))


# Nilai default (derajat) satu servo, dan reset satu servo ke default-nya.
func get_default_angle_deg(joint_name: String) -> float:
	return float(DEFAULT_POSE.get(joint_name, 0.0))


func reset_joint(joint_name: String) -> void:
	set_joint_angle(joint_name, deg_to_rad(get_default_angle_deg(joint_name)))


# ============================================================================
# PEMUTAR GERAKAN — menganimasikan twin lewat step-step motion ROBOTIS.
# steps: Array of {"j": {joint: derajat}, "t": detik (durasi), "p": detik (jeda)}
# return_default: kembali ke pose walk-ready setelah selesai (untuk gestur).
# ============================================================================
func play_motion(steps: Array, return_default: bool) -> void:
	stop_motion()
	await get_tree().process_frame
	_playing = true
	for step in steps:
		if not _playing:
			return
		await _tween_pose(step.get("j", {}), float(step.get("t", 0.4)))
		var pause := float(step.get("p", 0.0))
		if pause > 0.0 and _playing:
			await get_tree().create_timer(pause).timeout
	if _playing and return_default:
		await go_default()
	_playing = false


func go_default() -> float:
	await _tween_pose(_default_pose_deg(), 0.6)
	return 0.0


func stop_motion() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func _default_pose_deg() -> Dictionary:
	return DEFAULT_POSE


func _tween_pose(pose_deg: Dictionary, dur: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for jn in pose_deg:
		tw.tween_method(_tween_set.bind(jn), get_joint_angle(jn),
			deg_to_rad(float(pose_deg[jn])), maxf(dur, 0.05))
	await tw.finished


func _tween_set(radians: float, joint_name: String) -> void:
	set_joint_angle(joint_name, radians)

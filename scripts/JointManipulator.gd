extends Node3D
# ============================================================================
# JointManipulator.gd
# Gizmo rotasi untuk JOINT TERPILIH saja (bukan 20 titik sekaligus, supaya
# tidak menutupi layar & kamera tetap mudah diorbit).
#
#   - Joint dipilih dari panel kiri (SensorPanel) lewat select_joint(), atau
#     dengan klik langsung di dekat gizmo.
#   - Joint terpilih menampilkan ring (perpendikular ke sumbu rotasinya) +
#     marker + label sudut.
#   - Drag di dekat ring memutar joint di sumbunya (forward kinematics): link
#     di bawahnya ikut, di atasnya diam.
#   - Drag di area lain = orbit kamera (input tidak di-"handled").
#
# Sinyal joint_rotated dipakai SensorPanel untuk menyinkronkan slider.
# ============================================================================

signal joint_rotated(joint_name: String, radians: float)

const RING_RADIUS := 0.05
const MARKER_RADIUS := 0.009
const GRAB_PX := 85.0            # radius layar untuk menggenggam ring joint terpilih
const ANGLE_LIMIT := PI
const DETENT := deg_to_rad(5.0)  # putaran "ngeklik" tiap 5 derajat (penahan)
const PICK_LAYER := 2            # layer fisika collider link (set di OP3Robot)

const COL_RING   := Color(0.1, 0.85, 1.0)
const COL_MARKER := Color(0.18, 0.62, 0.54)

var _robot: Node3D
var _camera: Camera3D
var _selected: String = ""
var _dragging: bool = false
var _last_mouse: Vector2

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _marker: MeshInstance3D
var _label: Label3D
var _editable := true
var _drag_accum := 0.0          # akumulator sudut kontinu (sebelum di-detent)


func setup(robot: Node3D, camera: Camera3D) -> void:
	_robot = robot
	_camera = camera
	_make_gizmo()


# ----------------------------------------------------------------------------
# Gizmo visual (dibuat sekali, dipindah ke joint terpilih)
# ----------------------------------------------------------------------------
func _make_gizmo() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "JointRing"
	_ring.mesh = ImmediateMesh.new()
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = COL_RING
	_ring_mat.no_depth_test = true
	_ring_mat.render_priority = 3
	add_child(_ring)
	_ring.visible = false

	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	_marker = MeshInstance3D.new()
	_marker.name = "JointMarker"
	_marker.mesh = sphere
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = COL_MARKER
	mm.no_depth_test = true
	mm.render_priority = 4
	_marker.material_override = mm
	add_child(_marker)
	_marker.visible = false

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0006
	_label.modulate = COL_MARKER
	_label.outline_size = 8
	_label.font_size = 48
	add_child(_label)
	_label.visible = false


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------
func select_joint(jname: String) -> void:
	if _robot == null or not _robot.joints.has(jname):
		return
	_selected = jname
	var node: Node3D = _robot.joints[jname]["node"]
	if _ring.get_parent() != node:
		_ring.reparent(node, false)
		_marker.reparent(node, false)
	_ring.transform = Transform3D.IDENTITY
	_marker.transform = Transform3D.IDENTITY
	_build_ring(_robot.joints[jname]["axis"])
	_ring.visible = true
	_marker.visible = true
	_update_label()


func deselect() -> void:
	_selected = ""
	_dragging = false
	_ring.visible = false
	_marker.visible = false
	_label.visible = false


func set_editable(on: bool) -> void:
	_editable = on
	if not on:
		deselect()


func get_selected() -> String:
	return _selected


# ----------------------------------------------------------------------------
# Input — hanya genggam saat klik dekat ring joint terpilih
# ----------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if _robot == null or _camera == null or not _editable:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deselect()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 1) sudah ada joint terpilih & klik dekat ring -> langsung putar
			if _selected != "" and _near_selected(event.position):
				_begin_drag(event.position)
				get_viewport().set_input_as_handled()
			else:
				# 2) klik langsung di mesh servo -> pilih joint itu lalu putar
				var jn := _raycast_joint(event.position)
				if jn != "":
					select_joint(jn)
					_begin_drag(event.position)
					get_viewport().set_input_as_handled()
				# else: biarkan kamera orbit (tidak di-handle)
		else:
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		_rotate_selected(event.position)
		_last_mouse = event.position
		get_viewport().set_input_as_handled()


func _raycast_joint(mouse: Vector2) -> String:
	var world := _camera.get_world_3d()
	if world == null or world.direct_space_state == null:
		return ""
	var space := world.direct_space_state
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 8.0)
	params.collision_mask = PICK_LAYER
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit and hit.collider.has_meta("joint_name"):
		return hit.collider.get_meta("joint_name")
	return ""


func _begin_drag(mouse: Vector2) -> void:
	_dragging = true
	_last_mouse = mouse
	_drag_accum = _robot.get_joint_angle(_selected)   # mulai dari sudut sekarang


func _near_selected(mouse: Vector2) -> bool:
	var node: Node3D = _robot.joints[_selected]["node"]
	var wp := node.global_transform.origin
	if _camera.is_position_behind(wp):
		return false
	return _camera.unproject_position(wp).distance_to(mouse) < GRAB_PX


func _rotate_selected(mouse: Vector2) -> void:
	var node: Node3D = _robot.joints[_selected]["node"]
	var axis: Vector3 = _robot.joints[_selected]["axis"]
	var center := _camera.unproject_position(node.global_transform.origin)
	var prev := _last_mouse - center
	var cur := mouse - center
	if prev.length() < 3.0 or cur.length() < 3.0:
		return
	var d_screen := atan2(prev.x * cur.y - prev.y * cur.x, prev.x * cur.x + prev.y * cur.y)
	var world_axis := (node.global_transform.basis * axis).normalized()
	var to_cam := (_camera.global_position - node.global_transform.origin).normalized()
	var s := 1.0 if world_axis.dot(to_cam) > 0.0 else -1.0
	# Batas servo per-joint (default ±162 bila robot tak menyediakan)
	var lim := Vector2(-ANGLE_LIMIT, ANGLE_LIMIT)
	if _robot.has_method("get_joint_limit"):
		lim = _robot.get_joint_limit(_selected)
	# Akumulasi sudut kontinu lalu snap ke detent (gerakan kecil tak hilang)
	_drag_accum = clampf(_drag_accum - s * d_screen, lim.x, lim.y)
	var new_ang: float = clampf(round(_drag_accum / DETENT) * DETENT, lim.x, lim.y)
	if is_equal_approx(new_ang, _robot.get_joint_angle(_selected)):
		return
	_robot.set_joint_angle(_selected, new_ang)
	_update_label()
	joint_rotated.emit(_selected, new_ang)


# ----------------------------------------------------------------------------
func _build_ring(axis: Vector3) -> void:
	var a := (axis as Vector3).normalized()
	var ref := Vector3.UP if abs(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := a.cross(ref).normalized()
	var v := a.cross(u).normalized()
	var im := _ring.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _ring_mat)
	var seg := 56
	for i in seg + 1:
		var t := TAU * float(i) / float(seg)
		im.surface_add_vertex((u * cos(t) + v * sin(t)) * RING_RADIUS)
	im.surface_end()


func _update_label() -> void:
	if _selected == "":
		_label.visible = false
		return
	_label.visible = true
	_label.text = "%s\n%+.1f°" % [_selected, rad_to_deg(_robot.get_joint_angle(_selected))]


func _process(_delta: float) -> void:
	if _selected == "":
		return
	var wp: Vector3 = _robot.joints[_selected]["node"].global_transform.origin
	_label.global_position = wp + Vector3(0, 0.07, 0)

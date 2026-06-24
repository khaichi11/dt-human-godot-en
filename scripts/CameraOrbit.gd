extends Camera3D
# ============================================================================
# CameraOrbit.gd
# Kamera orbit standar untuk tampilan 3D digital twin:
#   - Drag tombol kiri  -> rotasi orbit (yaw + pitch)
#   - Drag tombol kanan -> pan (geser target)
#   - Scroll wheel      -> zoom (mendekat / menjauh)
#
# Kamera melihat ke `target` dengan jarak `radius`. Setiap input mengubah
# `yaw_deg`, `pitch_deg`, atau `radius`, lalu posisi kamera dihitung ulang.
# ============================================================================

@export var target: Vector3 = Vector3(0, 0.30, 0)  # fokus di torso OP3 (tinggi ~0.52 m)
@export var yaw_deg: float = 35.0
@export var pitch_deg: float = -10.0
@export var radius: float = 1.3

@export var min_radius: float = 0.4
@export var max_radius: float = 5.0
@export var min_pitch: float = -85.0
@export var max_pitch: float = 85.0

@export var rotate_sensitivity: float = 0.3
@export var pan_sensitivity: float = 0.0025
@export var zoom_sensitivity: float = 0.12

var _is_rotating: bool = false
var _is_panning: bool = false


func _ready() -> void:
	fov = 45.0
	near = 0.05
	far = 100.0
	apply_view("iso")          # pandangan default


func _unhandled_input(event: InputEvent) -> void:
	# Mouse buttons
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				# Shift + drag kiri = pan (seperti software 3D); biasa = orbit
				if mb.pressed:
					if mb.shift_pressed:
						_is_panning = true
					else:
						_is_rotating = true
				else:
					_is_rotating = false
					_is_panning = false
			MOUSE_BUTTON_MIDDLE:
				_is_rotating = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_is_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(-zoom_sensitivity)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(zoom_sensitivity)

	# Mouse motion
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_rotating:
			yaw_deg   -= mm.relative.x * rotate_sensitivity
			pitch_deg -= mm.relative.y * rotate_sensitivity
			pitch_deg = clamp(pitch_deg, min_pitch, max_pitch)
			_update_transform()
		elif _is_panning:
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			target -= right * mm.relative.x * pan_sensitivity * radius
			target += up * mm.relative.y * pan_sensitivity * radius
			_update_transform()

	# Keyboard: numpad untuk preset, panah untuk orbit halus
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_KP_1: apply_view("depan")
			KEY_KP_3: apply_view("kanan")
			KEY_KP_7: apply_view("atas")
			KEY_KP_9: apply_view("belakang")
			KEY_KP_5: apply_view("iso")
			KEY_LEFT:  _nudge(-12.0, 0.0)
			KEY_RIGHT: _nudge(12.0, 0.0)
			KEY_UP:    _nudge(0.0, 8.0)
			KEY_DOWN:  _nudge(0.0, -8.0)


func _nudge(dyaw: float, dpitch: float) -> void:
	yaw_deg += dyaw
	pitch_deg = clamp(pitch_deg + dpitch, min_pitch, max_pitch)
	_update_transform()


func _zoom(delta_factor: float) -> void:
	radius = clamp(radius * (1.0 + delta_factor), min_radius, max_radius)
	_update_transform()


# Preset arah pandang. Robot menghadap -Z (Godot), sisi kanannya di +X.
const VIEW_PRESETS := {
	"depan":    [180.0, -8.0],
	"belakang": [0.0,   -8.0],
	"kanan":    [90.0,  -8.0],
	"kiri":     [-90.0, -8.0],
	"atas":     [180.0, 85.0],
	"bawah":    [180.0, -85.0],
	"iso":      [35.0,  -12.0],
}


func apply_view(preset: String) -> void:
	if not VIEW_PRESETS.has(preset):
		return
	var p: Array = VIEW_PRESETS[preset]
	yaw_deg = p[0]
	pitch_deg = clamp(p[1], min_pitch, max_pitch)
	target = Vector3(0, 0.28, 0)
	radius = 1.0 if preset != "iso" else 1.2   # jarak nyaman: tak terlalu zoom/jauh
	_update_transform()


func _update_transform() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)

	var offset := Vector3(
		radius * cos(pitch) * sin(yaw),
		radius * sin(pitch),
		radius * cos(pitch) * cos(yaw)
	)

	var pos := target + offset
	look_at_from_position(pos, target, Vector3.UP)

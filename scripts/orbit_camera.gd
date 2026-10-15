extends RefCounted

# Avoid the world-up singularity while allowing an almost vertical view.
const PITCH_LIMIT := PI * 89.0 / 180.0
const Preferences = preload("res://scripts/camera_preferences.gd")

static func mouse_rotates(button: int) -> bool:
	return button==MOUSE_BUTTON_LEFT

static func clamp_pitch(value: float) -> float:
	return clampf(value, -PITCH_LIMIT, PITCH_LIMIT)

static func rotation_delta(relative: Vector2, height: float, touch := false) -> Vector2:
	var bounded := relative.limit_length(maxf(1,height)*0.06) if touch else relative
	var scale := 720.0/maxf(1,height)*0.55 if touch else 1.0
	return Vector2(bounded.x*0.006,bounded.y*0.004)*scale*float(Preferences.shared().values.rotation)

static func pan_delta(camera: Camera3D, distance: float, relative: Vector2, height: float, touch := false, vertical := false) -> Vector3:
	var bounded := relative.limit_length(maxf(1,height)*0.06) if touch else relative
	var scale := 2.0*distance*tan(deg_to_rad(camera.fov)*0.5)/maxf(1,height)
	var forward := Vector3(-camera.global_basis.z.x,0,-camera.global_basis.z.z).normalized()
	return (-camera.global_basis.x*bounded.x+(Vector3.UP if vertical else forward)*bounded.y)*scale*float(Preferences.shared().values.pan)*(0.7 if touch else 1.0)

static func lift_step(distance: float, delta: float) -> float:
	return clampf(distance*0.15,0.5,40.0)*float(Preferences.shared().values.pan)*clampf(delta,0,0.1)

static func lift_direction() -> float:
	if not DisplayServer.window_is_focused(): return 0.0
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_META): return 0.0
	return float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))

static func zoom_factor(ratio: float, touch := false) -> float:
	var prefs: Dictionary = Preferences.shared().values
	var exponent := clampf(log(maxf(0.001,ratio)),-0.14,0.14)*float(prefs.zoom)*(0.7 if touch else 1.0)
	return exp(-exponent if prefs.reverse_zoom else exponent)

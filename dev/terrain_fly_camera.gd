extends Camera3D

signal speed_changed(value: float)

var enabled := false
var turning := false
var base_speed := 8.0
var mouse_origin := Vector2.ZERO
var yaw := 0.0
var pitch := -0.5

func _ready() -> void:
	yaw = rotation.y
	pitch = rotation.x

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled: release_mouse()

func release_mouse() -> void:
	if not turning: return
	turning = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.window_is_focused(): get_viewport().warp_mouse(mouse_origin)

func begin_turn() -> void:
	if not enabled: return
	mouse_origin = get_viewport().get_mouse_position()
	turning = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func turn(relative: Vector2) -> void:
	if not turning: return
	yaw -= relative.x * 0.003
	pitch = clampf(pitch - relative.y * 0.003, -1.5, 1.5)
	rotation = Vector3(pitch, yaw, 0)

func change_speed(direction: float) -> void:
	base_speed = clampf(base_speed * pow(1.25, direction), 0.5, 64.0)
	speed_changed.emit(base_speed)

func _process(delta: float) -> void:
	if not enabled or not DisplayServer.window_is_focused(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox: return
	if not turning and get_viewport().gui_get_hovered_control() != null: return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction -= global_basis.z
	if Input.is_physical_key_pressed(KEY_S): direction += global_basis.z
	if Input.is_physical_key_pressed(KEY_A): direction -= global_basis.x
	if Input.is_physical_key_pressed(KEY_D): direction += global_basis.x
	if Input.is_physical_key_pressed(KEY_E): direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): direction -= Vector3.UP
	var multiplier := 1.0
	if Input.is_physical_key_pressed(KEY_SHIFT): multiplier *= 4.0
	if Input.is_physical_key_pressed(KEY_CTRL): multiplier *= 0.25
	position += direction.normalized() * base_speed * multiplier * delta

func _exit_tree() -> void:
	if turning: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

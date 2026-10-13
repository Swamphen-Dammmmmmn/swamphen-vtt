extends SceneTree

const Rules = preload("res://scripts/distance_rules.gd")
var failures := 0

func check(condition: bool, title: String) -> void:
	if not condition:
		failures += 1
		push_error(title)
	else:
		print("PASS: ", title)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for mode in range(3):
		check(is_equal_approx(Rules.feet(Vector2i.ZERO, Vector2i(3, 0), mode), 15.0), "3 orthogonal cells = 15 ft, mode %d" % mode)
	check(is_equal_approx(Rules.feet(Vector2i.ZERO, Vector2i(2, 2), 0), 10.0), "diagonal 5 ft mode")
	check(is_equal_approx(Rules.feet(Vector2i.ZERO, Vector2i(2, 2), 1), 15.0), "alternating diagonal mode")
	check(absf(Rules.feet(Vector2i.ZERO, Vector2i(2, 2), 2) - 14.1421356) < 0.0001, "straight diagonal mode")
	check(is_equal_approx(Rules.feet(Vector2i(5, 7), Vector2i(0, 4), 1), 30.0), "mixed negative direction")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	check(scene.tokens.size() == 4, "four test tokens")
	var origin: Vector2i = scene.tokens[0]["cell"]
	scene.selected = 0
	scene.target_cell = origin + Vector2i(3, 0)
	scene.pending = true
	scene._show_move_preview()
	check(scene.tokens[0]["cell"] == origin, "preview preserves original cell")
	scene._cancel_all()
	check(scene.tokens[0]["cell"] == origin and not scene.pending, "cancel preserves original position")
	scene.target_cell = origin + Vector2i(3, 0)
	scene.pending = true
	scene._confirm_move()
	check(scene.tokens[0]["cell"] == origin + Vector2i(3, 0), "confirm commits target")
	check(not scene.pending and scene.ghost == null, "confirm clears preview")
	var saved: Vector2i = scene.tokens[0]["cell"]
	scene._set_measure_mode(true)
	scene.measure_start = Vector2i(4, 4)
	scene.measure_end = Vector2i(6, 6)
	scene.measure_has_start = true
	scene._draw_measure()
	scene._change_algorithm(2)
	check(scene.distance_label.text == "14.14 英尺", "UI follows measurement algorithm")
	check(scene.tokens[0]["cell"] == saved, "measurement never moves token")
	scene._cancel_all()
	check(not scene.measure_has_start, "measurement clears")
	scene._reset_camera()
	check(is_equal_approx(scene.zoom, 44.0) and scene.focus == Vector3.ZERO, "camera resets")
	scene._set_measure_mode(false)
	var large_origin: Vector2i = scene.tokens[2]["cell"]
	var click: Vector2 = scene.camera.unproject_position(scene._cell_world(large_origin))
	scene._left_press(click)
	check(scene.selected == 2 and scene.dragging, "camera ray selects large token")
	var desired := large_origin + Vector2i(3, 0)
	scene._update_drag(scene.camera.unproject_position(scene._cell_world(desired)))
	check(scene.target_cell == desired, "mouse drag snaps to intended target")
	check(scene.tokens[2]["cell"] == large_origin, "mouse drag preserves original position")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(40, 150)
	scene._input(release)
	check(scene.pending and not scene.dragging and not scene.confirm_button.disabled, "release over UI ends drag and enables confirmation")
	scene._change_algorithm(0)
	check(scene.distance_label.text == "15 英尺", "mouse preview reports movement distance")
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	scene._input(enter)
	check(scene.tokens[2]["cell"] == desired, "Enter confirms mouse drag")
	scene._left_press(scene.camera.unproject_position(scene._cell_world(desired)))
	scene._update_drag(scene.camera.unproject_position(scene._cell_world(Vector2i(29, 29))))
	check(scene.target_cell == Vector2i(28, 28), "large token remains completely inside board")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	scene._input(escape)
	check(scene.tokens[2]["cell"] == desired and not scene.dragging, "Esc cancels active drag")
	scene._set_measure_mode(true)
	scene._left_press(scene.camera.unproject_position(scene._cell_world(Vector2i(10, 10))))
	scene._left_press(scene.camera.unproject_position(scene._cell_world(Vector2i(12, 12))))
	check(scene.measure_finished and scene.measure_end == Vector2i(12, 12), "two mouse clicks finish measurement")
	print("Phase 0 failures: ", failures)
	quit(1 if failures else 0)

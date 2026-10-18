extends Control

const LibraryPresentation = preload("res://ui/components/features/library/library_presentation.gd")

# Static layout review for library outer shell improvements
# Shows desktop and narrow width states with lightweight mock data
# Does not simulate user input or write to user data

const PageShell = preload("res://ui/components/page_shell.tscn")
const LibraryView = preload("res://ui/components/features/library/library_view.gd")

@export var review_width := 1280
@export var review_kind := "tokens"
@export var selection_mode := false

var _shell: Control
var _view: Control

func _ready() -> void:
	# 静态样板按逻辑1:1展示，不写入用户的界面缩放偏好。
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i(review_width, 900)
	get_window().content_scale_factor = 1.0
	get_window().size = Vector2i(review_width, 900)
	_create_layout()
	_populate_mock_data()
	_capture_initial_layout()

func _create_layout() -> void:
	_shell = PageShell.instantiate()
	add_child(_shell)
	var mode := LibraryPresentation.Mode.SELECT if selection_mode else LibraryPresentation.Mode.MANAGE
	_shell.configure_library("选择" + LibraryPresentation.noun(review_kind) if selection_mode else LibraryPresentation.noun(review_kind) + "库", review_kind, mode)
	_view = LibraryView.new()
	_view.library_kind = review_kind
	_view.mode = mode
	_view.management_text = "前往冒险库" if selection_mode and review_kind == "adventures" else ""
	_view.noun = LibraryPresentation.noun(review_kind)
	_view.primary_text = ("打开冒险" if review_kind == "adventures" else "添加") if selection_mode else "编辑"
	_view.controls_host = _shell
	_shell.content.add_child(_view)

func _populate_mock_data() -> void:
	var mock_records: Array = []
	for i in range(12):
		mock_records.append({
			"id": "mock_%d" % i,
			"title": "测试%s %d" % [LibraryPresentation.noun(review_kind), i+1],
			"summary": {"width_feet": 8, "length_feet": 12, "thickness_feet": 0.5, "platform_count": 12, "map_count": 4},
			"kind": "basic" if i % 3 == 0 else "advanced",
			"tags": ["战士"] if i % 2 == 0 else ["法师", "远程"]
		})
	_view.set_entries(mock_records, "", [])

func _capture_initial_layout() -> void:
	for frame in range(8): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var destination := "res://logs/library-shell-review-%d.png" % review_width
	var result := get_viewport().get_texture().get_image().save_png(destination)
	get_viewport().get_texture().get_image().save_png("res://logs/library-%s-%s-%d.png" % [review_kind, "select" if selection_mode else "manage", review_width])
	print("LibraryShellReview: initial viewport=", get_viewport_rect().size, "; capture=", result, "; path=", destination)

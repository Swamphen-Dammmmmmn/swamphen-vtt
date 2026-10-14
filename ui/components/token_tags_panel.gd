extends "res://ui/components/page_modal.gd"

func configure_token(title: String, kind: String, tags: Array) -> void:
	configure("棋子标签", title)
	var type_name := "基础棋子" if kind == "basic" else "高级棋子"
	content.add_child(Style.text("固定类型 · " + type_name, 16))
	if not tags.is_empty():
		content.add_child(Style.text("分类标签", 20))
		for tag in tags: content.add_child(Style.text(str(tag), 16))
	add_action("编辑标签 · 待开放", Callable(), false, false)
	add_action("关闭", dismiss)

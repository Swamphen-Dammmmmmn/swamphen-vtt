extends RefCounted

# Shared presentation context. No storage reads or writes belong here.
enum Mode { MANAGE, SELECT }

const KINDS := {
	"tokens": {"noun": "棋子", "route": "token_library"},
	"platforms": {"noun": "地台", "route": "platform_library"},
	"maps": {"noun": "地图", "route": "map_library"},
	"adventures": {"noun": "冒险", "route": "adventure_library"},
}

static func noun(kind: String) -> String:
	assert(KINDS.has(kind), "未知内容库类型：" + kind)
	return str(KINDS[kind].noun)

static func summary(kind: String, record: Dictionary) -> String:
	if record.get("pending", false): return "正在读取摘要"
	var data: Dictionary = record.get("summary", {})
	match kind:
		"platforms":
			return "%s × %s 英尺 · 厚 %s 英尺" % [str(data.get("width_feet", 0)), str(data.get("length_feet", 0)), str(data.get("thickness_feet", 0))]
		"maps": return "%d 块地台" % int(data.get("platform_count", 0))
		"adventures": return "%d 张地图" % int(data.get("map_count", 0))
	return ""

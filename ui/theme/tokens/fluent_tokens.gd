extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

# Fluent UI light tokens at f11fae6f; project dimensions are adapted for Chinese and touch.
const BACKGROUND := Color("fafafa")
const SURFACE := Color("ffffff")
const HOVER := Color("f5f5f5")
const PRESSED := Color("e0e0e0")
const FOREGROUND := Color("242424")
const SECONDARY := Color("616161")
const STROKE := Color("d1d1d1")
const DISABLED := Color("bdbdbd")
const BRAND := Color("0f6cbd")
const BRAND_HOVER := Color("115ea3")
const BRAND_PRESSED := Color("0c3b5e")
const DANGER := Color("b33c3c") # Existing product exit semantics.
const DANGER_HOVER := Color("a32f2f")
const DANGER_PRESSED := Color("942f2f")
const RADIUS := 10
const ENTRY_RADIUS := 12
const BODY_SIZE := Typography.BODY
const CAPTION_SIZE := Typography.CAPTION
const TITLE_SIZE := Typography.HERO
const COMPACT_TITLE_SIZE := Typography.COMPACT_HERO
const BUTTON_HEIGHT := 44
const ENTRY_HEIGHT := 112
const GAP := 16
const SECTION_GAP := 28
const CONTENT_WIDTH := 1280
const CONTENT_MARGIN := 48
const HOME_TOOL_HEIGHT := 88
const HOME_COMPACT_TOOL_HEIGHT := 72
const HOME_FOOTER_HEIGHT := 72
const HOME_HEADER_HEIGHT := 72
const HOME_ILLUSTRATION_RADIUS := 20
const NOTICE_BACKGROUND := Color("ebf3fc")
const NOTICE_STROKE := Color("b4d6fa")
const CATEGORY_GAP := 24
const CATEGORY_FOOTER_HEIGHT := 76
const CATEGORY_PREVIEW_RATIO := 0.48
const CATEGORY_COMPACT_PREVIEW_RATIO := 0.38
const CATEGORY_CONTENT_WIDTH := 1000
const CATEGORY_STATUS_HEIGHT := 20
const CATEGORY_VIEWPORT_INSET := 8
const LIBRARY_CARD_WIDTH := 272
const LIBRARY_PREVIEW_HEIGHT := 176
const LIBRARY_GAP := 24

# Shared join / connection settings form dimensions.
const FORM_WIDTH := 480.0
const FORM_PADDING := 20
const SETTINGS_COMPACT_WIDTH := 720.0
const SETTINGS_FIELD_COMPACT_WIDTH := 360.0
const DOCUMENT_WIDTH := 760.0
const DOCUMENT_HEIGHT := 560.0
const DOCUMENT_ACTION_WIDTH := 96.0

extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

# Fluent UI light tokens at f11fae6f; project dimensions are adapted for Chinese and touch.
const BACKGROUND := Color("fafafa")
const SURFACE := Color("ffffff")
const HOVER := Color("f5f5f5")
const PRESSED := Color("e0e0e0")
const FOREGROUND := Color("242424")
const SECONDARY := Color("616161")
const SUCCESS := Color("107c10")
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
const TOUCH_BUTTON_HEIGHT := 48
const TOOLBAR_BUTTON_HEIGHT := 40
const TOOLBAR_ICON_SIZE := 18
const TOOLBAR_PADDING_H := 12
const TOOLBAR_PADDING_V := 6
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
# Room for rounded focus antialiasing inside clipped modal bodies.
const MODAL_BODY_DRAW_INSET := 2
const UTILITY_PANEL_MIN_BODY_HEIGHT := 72.0
const SETTINGS_COMPACT_WIDTH := 720.0
const SETTINGS_FIELD_COMPACT_WIDTH := 360.0
const DOCUMENT_WIDTH := 760.0
const DOCUMENT_HEIGHT := 560.0
const DOCUMENT_ACTION_WIDTH := 96.0
const MODAL_MAX_HEIGHT := 640.0

# Shared pause menus (adventure and platform/map editors).
const PAUSE_MENU_WIDTH := 480.0
const PAUSE_MENU_PADDING_X := 24
const PAUSE_MENU_PADDING_Y := 20
const PAUSE_MENU_DESKTOP_INSET := 32.0
const PAUSE_MENU_MOBILE_INSET := 24.0
const PAUSE_TRIGGER_INSET := Vector2(20, 18)
const PAUSE_TRIGGER_SIZE := Vector2(120, 48)

# Shared select control (trigger + in-canvas list).
const SELECT_TRIGGER_RIGHT := 40
const SELECT_CHEVRON_SIZE := 16
const SELECT_PANEL_PADDING := 4
const SELECT_ITEM_GAP := 8
const SELECT_MARK_SIZE := 16
const SELECT_ROW_HEIGHT := 36.0
const SELECT_TOUCH_ROW_HEIGHT := 48.0
const SELECT_MAX_WIDTH := 480.0
const SELECT_EDGE_MARGIN := 16.0
const SELECT_GAP := 4.0
const SELECT_GROUP_RATIO := 0.8
const SELECT_RULE_HEIGHT := 9.0

# Shared color entry (forms/color_well.gd) and its picker popup (overlays/color_picker_popup.gd).
const COLOR_SWATCH_SIZE := 20.0
const COLOR_SWATCH_RADIUS := 4
const COLOR_SWATCH_GAP := 10
const COLOR_POPUP_WIDTH := 352.0
const COLOR_CONTROL_RADIUS := 6
const COLOR_POPUP_GAP := 8.0
# Native picker square and hue bar; the square shrinks toward the minimum on small windows.
const COLOR_SV_SIZE := 284.0
const COLOR_SV_MIN := 128.0
const COLOR_HUE_WIDTH := 24
const COLOR_LABEL_WIDTH := 16
const COLOR_ROW_GAP := 8
# Transparent room so rounded field focus rings are not clipped by the scrolling body.
const COLOR_PICKER_DRAW_INSET := 2

# Compact asset grid slot (embedded token palette / adventure tray).
const COMPACT_SLOT_RADIUS := 8

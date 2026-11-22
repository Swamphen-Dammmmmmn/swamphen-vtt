extends RefCounted
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")

# Adventure topbar layout tokens.
# Colors, fonts, and general button/field styles come from FluentTokens, Typography, and FluentTheme.

# Primary sticky bar at top of adventure board
const PRIMARY_MIN_HEIGHT := 54.0
const PRIMARY_PADDING_H := 16
const PRIMARY_PADDING_V := 6
const PRIMARY_GAP := 12
const CATEGORY_GAP := 4
const CATEGORY_BUTTON_HEIGHT := float(T.TOOLBAR_BUTTON_HEIGHT)
const GLOBAL_ACTION_GAP := 8
const MAP_BUTTON_MAX_WIDTH := 240.0
const MAP_BUTTON_MIN_WIDTH := 104.0

# Full-width secondary drawer (manual open/close, shrinks naturally to content)
const SECONDARY_PADDING_H := 18
const SECONDARY_PADDING_TOP := 8
const SECONDARY_PADDING_BOTTOM := 10
const SECONDARY_HEADER_GAP := 10
const SECONDARY_BODY_GAP := 8
const SECONDARY_GROUP_GAP := 16
const SECONDARY_BUTTON_GAP := 8
const DRAW_INSET := 2

# Active tool summary strip below secondary drawer (lightweight status + panel launcher)
const TOOL_STRIP_MIN_HEIGHT := 44.0
const TOOL_STRIP_PADDING_H := 18
const TOOL_STRIP_PADDING_V := 5
const TOOL_STRIP_GAP := 10
const COMPACT_HEIGHT := 34.0
const ICON_SIZE := T.TOOLBAR_ICON_SIZE

# Board floating safe margins when topbar replaces legacy left sidebar
const BOARD_EDGE_MARGIN := 16.0
const TOPBAR_FLOATING_GAP := 12.0

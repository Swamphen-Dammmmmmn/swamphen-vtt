extends RefCounted
# Editor-specific design tokens extending FluentTokens

const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")

# Re-export core Fluent tokens for convenience
const SURFACE = T.SURFACE
const FOREGROUND = T.FOREGROUND
const SECONDARY = T.SECONDARY
const DISABLED = T.DISABLED
const BRAND = T.BRAND
const DANGER = T.DANGER
const STROKE = T.STROKE
const RADIUS = T.RADIUS
const BUTTON_HEIGHT = T.BUTTON_HEIGHT

# Editor-specific sizing (compatible with existing layouts)
const SETTINGS_FIELD_COMPACT_WIDTH = T.SETTINGS_FIELD_COMPACT_WIDTH
const PADDING := 16.0
const GAP := 12
const ROW_GAP := 8
const LABEL_GAP := 6

# Field component spacing
const FIELD_SEPARATION := 6  # Space between label/input/error in field components
const SLIDER_HEADER_GAP := 8  # Gap between label and value in slider header

# Property panel layout
const PANEL_HEADER_HEIGHT := 44.0  # Property panel header row
const PANEL_HEADER_MARGIN_H := 16.0  # Header horizontal margins
const PANEL_HEADER_MARGIN_V := 16.0  # Header vertical margins
const PANEL_FOOTER_MARGIN_H := 16.0  # Footer horizontal margins
const PANEL_FOOTER_MARGIN_V := 8.0  # Footer vertical margins (different from horizontal)
const PANEL_CONTENT_MARGIN := 16.0  # Body content margins
const PANEL_CONTENT_GAP := 12.0  # Gap between fields in panel content
const PANEL_FOOTER_GAP := 8.0  # Gap between status and actions in footer
const PANEL_ACTION_GAP := 8.0  # Gap between action buttons

# Foldable group spacing
const FOLD_GROUP_TITLE_HEIGHT := 32.0
const FOLD_GROUP_TITLE_GAP := 8.0  # Gap between title and fold button

# Tabs spacing
const TAB_HEIGHT := 40.0  # Tab button height

# Typography sizes (re-export from Typography)
const BODY_SIZE = Typography.BODY
const CAPTION_SIZE = Typography.CAPTION
const SECTION_SIZE = Typography.SECTION

const MOBILE_PANEL_WIDTH := 320.0
const COLLAPSED_WIDTH := 48.0

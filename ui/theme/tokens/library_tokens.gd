extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

# Library outer shell layout tokens
# These values provide consistent spacing and sizing for the library interface
# surrounding the verified cards. Card dimensions remain in library_card_spec.json.

const TOOLBAR_GAP := 16      # Spacing between search and create button
const CONTROLS_GAP := 12      # Spacing between toolbar, filters, and clear button
const FILTER_GAP := 8         # Spacing within filter components
const CONTENT_INSET := 8      # Margin around grid to prevent border clipping
const GRID_GAP := 24          # Spacing between cards in grid

# Control heights for consistency
const CONTROL_HEIGHT_DESKTOP := 44
const CONTROL_HEIGHT_MOBILE := 48
const FILTER_HEIGHT_DESKTOP := 34  # Compact filter buttons
const FILTER_HEIGHT_MOBILE := 48

# Search field widths
const SEARCH_MIN_WIDTH_DESKTOP := 400
const SEARCH_MIN_WIDTH_MOBILE := 280

# Create button width
const CREATE_BUTTON_WIDTH := 148

# Navigation bar height
const NAVIGATION_HEIGHT := 56
const NAVIGATION_BACK_WIDTH := 104
const NAVIGATION_TAB_WIDTH := 64
const NAVIGATION_TAB_GAP := 8
const SHELL_GAP := 16
const TITLE_SIZE_DESKTOP := Typography.LIBRARY_TITLE
const TITLE_SIZE_MOBILE := Typography.COMPACT_PAGE_TITLE

# Colors (reference Fluent tokens)
const SECONDARY_TEXT := Color("616161")
const ERROR_TEXT := Color("b33c3c")
const CAPTION_SIZE := Typography.STATUS

# Status messages
const STATUS_GAP := 12

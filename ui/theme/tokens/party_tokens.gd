extends RefCounted

# 团员名单尺寸集中在party_tokens；卡片与名单外框均按内容收高，不拉满页面。
const WIDTH := 232.0
const COMPACT_WIDTH := 208.0
const WORKSPACE_WIDTH := 1600.0
const CARD_HEIGHT := 64.0
const MOBILE_CARD_HEIGHT := 80.0
const CARD_PADDING_H := 14
const CARD_PADDING_V := 6
const FRAME_PADDING := 12
const ROW_GAP := 2
const ROLE_GAP := 8
const NAME_SUFFIX_GAP := 4
const LIST_GAP := 8
const MORE_BUTTON_SIZE := 32.0
const MOBILE_MORE_BUTTON_SIZE := 48.0
const MORE_ICON_SIZE := 18
# 状态行右侧为更多图标预留的宽度（图标18+与状态文字间隔8）；按钮触摸区居中于此，不占整高列。
const MORE_SLOT_WIDTH := 26.0
# 手机专用：48触摸区放在首行下方并与状态行纵向居中，不压到昵称／角色；桌面不读取以下值。
const MOBILE_ROW_GAP := 6
const MOBILE_STATUS_ROW_HEIGHT := 38.0
# 状态文字在48触摸区左缘前保留的间隔。
const MOBILE_MORE_TEXT_GAP := 8.0
const MORE_BUTTON_RADIUS := 6
const MORE_BUTTON_BORDER := 1
const CONTENT_INSET := 2
# 标题与外框之间的间隔；标题位于外框上方，不计入外框高度。
const TITLE_GAP := 6

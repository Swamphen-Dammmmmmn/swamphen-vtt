extends RefCounted

# Project font and size authority. Keep original font files unmodified.
const REGULAR: Font = preload("res://ui/theme/fonts/HarmonyOS_Sans_SC_Regular.ttf")
const MEDIUM: Font = preload("res://ui/theme/fonts/HarmonyOS_Sans_SC_Medium.ttf")
const BOLD: Font = preload("res://ui/theme/fonts/HarmonyOS_Sans_SC_Bold.ttf")
static var WORLD_REGULAR: Font = _world_font()

static func _world_font() -> FontFile:
	# Share the original TTF data; keep the mutable rendering cache independent.
	var font := REGULAR.duplicate() as FontFile
	font.multichannel_signed_distance_field = true
	font.msdf_size = 64
	font.msdf_pixel_range = 16
	font.generate_mipmaps = true
	return font

const TAG := 12
const STATUS := 13
const CAPTION := 14
const LEGACY_BODY := 15
const BODY := 16
const SUBTITLE := 18
const SECTION := 20
const EMPHASIS := 22
const DIALOG_TITLE := 24
const COMPACT_PAGE_TITLE := 26
const LIBRARY_TITLE := 28
const COMPACT_HERO := 30
const PAGE_TITLE := 32
const PREVIEW_MEASURE := 40
const HERO := 42
const PREVIEW_DIRECTION := 64

# Scene text roles retain existing visual variants and sizes without local numbers.
static func apply_theme(target: Theme) -> void:
	target.default_font = REGULAR
	for type_name in target.get_type_list():
		for key in target.get_font_list(type_name):
			target.set_font(key, type_name, BOLD if "bold" in key else REGULAR)
		# Adapt third-party theme sizes here; do not fork the addon theme.
		for key in target.get_font_size_list(type_name):
			var text_size := BODY
			if type_name in ["GoCaptionLabel", "GoCompactButton", "TooltipLabel"]: text_size = STATUS
			elif type_name in ["GoCompactLabel", "GoMicroLabel", "ProgressBar"]: text_size = TAG
			elif type_name == "GoSubtitleLabel": text_size = EMPHASIS
			elif type_name == "GoTitleLabel": text_size = LIBRARY_TITLE
			target.set_font_size(key, type_name, text_size)
	for pair in [["normal_font", REGULAR], ["bold_font", BOLD], ["italics_font", REGULAR], ["bold_italics_font", BOLD], ["mono_font", REGULAR]]:
		target.set_font(pair[0], "RichTextLabel", pair[1])
	for entry in [["TypographyBody", "Label", BODY], ["TypographyStatus", "Label", STATUS], ["TypographyTag", "Label", TAG], ["TypographySection", "Label", SECTION], ["TypographySubtitle", "Label", SUBTITLE], ["TypographyTokenName", "Label", LIBRARY_TITLE], ["TypographyMutedStatus", "MutedLabel", STATUS], ["TypographyOnDarkStatus", "OnDarkLabel", STATUS], ["TypographyOnDarkEmphasis", "OnDarkLabel", EMPHASIS]]:
		target.set_type_variation(entry[0], entry[1])
		target.set_font_size("font_size", entry[0], entry[2])
	target.set_font("font", "TypographyTokenName", BOLD)
	target.set_type_variation("TypographyMedium", "Label")
	target.set_font("font", "TypographyMedium", MEDIUM)
	target.set_type_variation("TypographyStrong", "Label")
	target.set_font("font", "TypographyStrong", BOLD)
	target.set_font("font", "GoTitleLabel", BOLD)
	target.set_font("font", "GoSubtitleLabel", MEDIUM)

extends RefCounted

# Stay just short of the poles to keep look_at's world-up orientation stable.
const PITCH_LIMIT := PI * 89.0 / 180.0

static func clamp_pitch(value: float) -> float:
	return clampf(value, -PITCH_LIMIT, PITCH_LIMIT)

extends RefCounted
class_name MatchLayout

const HEIGHT_MIN := 720.0
const HEIGHT_MAX := 1080.0
const SCALE_MIN := 0.62
const SCALE_MAX := 1.0

const BASE_LINE_W := 80.0
const BASE_LINE_H := 126.0
const BASE_HAND_W := 132.0
const BASE_HAND_H := 206.0
const BASE_PORTRAIT_W := 72.0
const BASE_PORTRAIT_H := 118.0
const BASE_PICK_W := 132.0
const BASE_PICK_H := 218.0


static func scale_factor(viewport: Vector2) -> float:
	var h := viewport.y
	if h <= HEIGHT_MIN:
		return SCALE_MIN
	if h >= HEIGHT_MAX:
		return SCALE_MAX
	var t := (h - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN)
	return lerpf(SCALE_MIN, SCALE_MAX, t)


static func _scaled_pair(base_w: float, base_h: float, viewport: Vector2) -> Dictionary:
	var s := scale_factor(viewport)
	return {"display_w": base_w * s, "display_h": base_h * s}


static func line_card_opts(viewport: Vector2) -> Dictionary:
	return _scaled_pair(BASE_LINE_W, BASE_LINE_H, viewport)


static func hand_card_opts(viewport: Vector2) -> Dictionary:
	return _scaled_pair(BASE_HAND_W, BASE_HAND_H, viewport)


static func mulligan_card_opts(viewport: Vector2) -> Dictionary:
	return hand_card_opts(viewport)


static func portrait_opts(viewport: Vector2) -> Dictionary:
	return _scaled_pair(BASE_PORTRAIT_W, BASE_PORTRAIT_H, viewport)


static func pick_card_opts(viewport: Vector2) -> Dictionary:
	return _scaled_pair(BASE_PICK_W, BASE_PICK_H, viewport)


static func step_title_font_size(viewport: Vector2) -> int:
	var s := scale_factor(viewport)
	return int(round(lerpf(14.0, 20.0, (s - SCALE_MIN) / maxf(0.001, SCALE_MAX - SCALE_MIN))))


static func hand_fan_host_min_height(viewport: Vector2) -> int:
	var s := scale_factor(viewport)
	return int(round(lerpf(130.0, 200.0, (s - SCALE_MIN) / maxf(0.001, SCALE_MAX - SCALE_MIN))))


## Fraction of each hand card visible above the screen bottom (LoR-style peek).
static func hand_card_peek_ratio() -> float:
	return 0.17


static func hand_bell_peak_height(viewport: Vector2) -> float:
	var s := scale_factor(viewport)
	return lerpf(14.0, 22.0, (s - SCALE_MIN) / maxf(0.001, SCALE_MAX - SCALE_MIN))


static func hand_peek_strip_height(viewport: Vector2) -> int:
	var card_h: float = hand_card_opts(viewport)["display_h"]
	var peek := hand_card_peek_ratio()
	var bell := hand_bell_peak_height(viewport)
	return int(round(card_h * peek + bell + 16.0))

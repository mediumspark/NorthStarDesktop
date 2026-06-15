extends RefCounted
class_name MatchHud

## Shared HUD helpers for CPU matches (star tracks, phase labels).


static func rebuild_star_track(row: HBoxContainer, caption: String, stars: int, max_stars: int, filled: Color, empty: Color) -> void:
	for c in row.get_children():
		c.queue_free()
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	row.add_child(cap)
	for i in range(maxi(1, max_stars)):
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 20)
		star.add_theme_color_override("font_color", filled if i < stars else empty)
		row.add_child(star)


static func phase_label(phase: int, setup_round: int, faceoff_pending: bool) -> String:
	if faceoff_pending and phase == MatchState.Phase.SETUP:
		return "Review lines"
	match phase:
		MatchState.Phase.PICK_RESTAURANT:
			return "Restaurant pick"
		MatchState.Phase.MULLIGAN:
			return "Mulligan"
		MatchState.Phase.SETUP:
			if setup_round > 0:
				return "Setup R%d" % setup_round
			return "Setup"
		MatchState.Phase.FACEOFF:
			return "Faceoff"
		MatchState.Phase.SCORE:
			return "Scoring"
		MatchState.Phase.ENDED:
			return "Match over"
		_:
			return "…"


static func should_banner_message(text: String) -> bool:
	var lower := text.to_lower()
	if "star" in lower:
		return true
	if "scores —" in lower or "scores -" in lower:
		return true
	if "win" in lower or "lose" in lower or "draw" in lower:
		return true
	if "deck" in lower and ("empty" in lower or "cannot draw" in lower):
		return true
	if "mulligan" in lower:
		return true
	if "faceoff" in lower and "reveal" in lower:
		return true
	if "cpu has set" in lower:
		return true
	if "setup:" in lower:
		return true
	return false

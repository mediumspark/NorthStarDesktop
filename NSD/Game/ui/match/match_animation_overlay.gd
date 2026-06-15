extends CanvasLayer
class_name MatchAnimationOverlay

## Full-screen faceoff and game-end animations for CPU matches.

const SCENE_PATH := "res://ui/match/match_animation_overlay.tscn"

@onready var _backdrop: ColorRect = %Backdrop
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %TitleLabel
@onready var _subtitle: Label = %SubtitleLabel
@onready var _you_score: Label = %YouScoreLabel
@onready var _cpu_score: Label = %CpuScoreLabel
@onready var _vs_label: Label = %VsLabel
@onready var _result_banner: Label = %ResultBanner


func _ready() -> void:
	layer = 90
	visible = false
	_reset_visuals()
	get_viewport().size_changed.connect(_apply_viewport_layout)
	call_deferred("_apply_viewport_layout")


func _apply_viewport_layout() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0:
		return
	var w := minf(520.0, vp.x * 0.88)
	var h := minf(340.0, vp.y * 0.45)
	_panel.offset_left = -w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_bottom = h * 0.5


static func attach(host: Node) -> MatchAnimationOverlay:
	var existing: Node = host.get_node_or_null("MatchAnimationOverlay")
	if existing is MatchAnimationOverlay:
		return existing as MatchAnimationOverlay
	var overlay := load(SCENE_PATH).instantiate() as MatchAnimationOverlay
	overlay.name = "MatchAnimationOverlay"
	host.add_child(overlay)
	return overlay


func play_faceoff_intro() -> void:
	_reset_visuals()
	visible = true
	_backdrop.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_title.text = "FACE OFF"
	_subtitle.text = "Revealing cards left to right…"
	_title.scale = Vector2(0.6, 0.6)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.25)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.3)
	var tween2 := create_tween()
	tween2.tween_property(_title, "scale", Vector2(1.08, 1.08), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween2.tween_property(_title, "scale", Vector2.ONE, 0.15).set_delay(0.35)
	await tween2.finished


func play_slot_reveal(slot_index: int, slot_count: int, human_name: String = "", cpu_name: String = "") -> void:
	if human_name.is_empty() and cpu_name.is_empty():
		_subtitle.text = "Slot %d of %d" % [slot_index + 1, slot_count]
	else:
		_subtitle.text = "Slot %d — You: %s · CPU: %s" % [
			slot_index + 1,
			human_name,
			cpu_name,
		]
	_panel.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(_panel, "scale", Vector2(1.04, 1.04), 0.12)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.12)
	await tween.finished
	await get_tree().create_timer(0.18).timeout


func play_faceoff_result(summary: Dictionary) -> void:
	var score_h: int = int(summary.get("score_h", 0))
	var score_c: int = int(summary.get("score_c", 0))
	var dh: int = int(summary.get("star_h_delta", 0))
	var dc: int = int(summary.get("star_c_delta", 0))
	_title.text = "SCORES"
	_subtitle.text = "Round total"
	_you_score.text = "You: 0"
	_cpu_score.text = "CPU: 0"
	_you_score.modulate = Color.WHITE
	_cpu_score.modulate = Color.WHITE
	_result_banner.visible = true
	_result_banner.modulate.a = 0.0
	_result_banner.scale = Vector2(0.85, 0.85)
	var outcome := _faceoff_outcome_text(score_h, score_c, dh, dc)
	_result_banner.text = outcome
	var count_tween := create_tween()
	count_tween.tween_method(func(v: float) -> void:
		_you_score.text = "You: %d" % int(round(v))
	, 0.0, float(score_h), 0.45)
	count_tween.parallel().tween_method(func(v: float) -> void:
		_cpu_score.text = "CPU: %d" % int(round(v))
	, 0.0, float(score_c), 0.45)
	await count_tween.finished
	_you_score.text = "You: %d  %s" % [score_h, _star_delta_chip(dh)]
	_cpu_score.text = "CPU: %d  %s" % [score_c, _star_delta_chip(dc)]
	if score_h > score_c:
		_you_score.modulate = Color(0.45, 1.0, 0.55)
	elif score_c > score_h:
		_cpu_score.modulate = Color(1.0, 0.55, 0.45)
	else:
		_you_score.modulate = Color(0.85, 0.88, 1.0)
		_cpu_score.modulate = Color(0.85, 0.88, 1.0)
	var banner_tween := create_tween().set_parallel(true)
	banner_tween.tween_property(_result_banner, "modulate:a", 1.0, 0.25)
	banner_tween.tween_property(_result_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await banner_tween.finished
	await get_tree().create_timer(0.85).timeout


func play_game_over(result: String) -> void:
	_reset_visuals()
	visible = true
	_backdrop.modulate.a = 1.0
	_panel.modulate.a = 1.0
	_you_score.visible = false
	_cpu_score.visible = false
	_vs_label.visible = false
	_subtitle.visible = false
	_result_banner.visible = true
	_result_banner.modulate.a = 0.0
	_result_banner.scale = Vector2(0.7, 0.7)
	var kind := _game_over_kind(result)
	match kind:
		"win":
			_title.text = "VICTORY!"
			_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.25))
			_result_banner.text = result
			_result_banner.add_theme_color_override("font_color", Color(0.55, 0.95, 0.62))
			_backdrop.color = Color(0.05, 0.12, 0.08, 0.88)
		"loss":
			_title.text = "DEFEAT"
			_title.add_theme_color_override("font_color", Color(0.95, 0.45, 0.42))
			_result_banner.text = result
			_result_banner.add_theme_color_override("font_color", Color(0.92, 0.55, 0.5))
			_backdrop.color = Color(0.14, 0.05, 0.06, 0.88)
		_:
			_title.text = "MATCH OVER"
			_title.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
			_result_banner.text = result
			_result_banner.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
			_backdrop.color = Color(0.06, 0.07, 0.1, 0.88)
	_title.scale = Vector2(0.5, 0.5)
	var intro := create_tween().set_parallel(true)
	intro.tween_property(_title, "scale", Vector2(1.12, 1.12), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(_result_banner, "modulate:a", 1.0, 0.35)
	intro.tween_property(_result_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await intro.finished
	var pulse := create_tween()
	pulse.tween_property(_title, "scale", Vector2(1.05, 1.05), 0.35)
	pulse.tween_property(_title, "scale", Vector2.ONE, 0.35)
	await pulse.finished
	await get_tree().create_timer(1.4).timeout
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_panel, "modulate:a", 0.0, 0.35)
	fade.tween_property(_backdrop, "modulate:a", 0.0, 0.35)
	await fade.finished
	visible = false
	_reset_visuals()


func dismiss() -> void:
	visible = false
	_reset_visuals()


func _reset_visuals() -> void:
	_backdrop.modulate = Color(1, 1, 1, 1)
	_backdrop.color = Color(0.02, 0.025, 0.04, 0.78)
	_panel.modulate = Color(1, 1, 1, 1)
	_panel.scale = Vector2.ONE
	_title.scale = Vector2.ONE
	_title.text = ""
	_title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.28))
	_subtitle.text = ""
	_subtitle.visible = true
	_you_score.visible = true
	_cpu_score.visible = true
	_vs_label.visible = true
	_you_score.text = "You: —"
	_cpu_score.text = "CPU: —"
	_you_score.modulate = Color.WHITE
	_cpu_score.modulate = Color.WHITE
	_result_banner.visible = false
	_result_banner.text = ""
	_result_banner.modulate = Color(1, 1, 1, 1)
	_result_banner.scale = Vector2.ONE
	_result_banner.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))


static func _star_delta_chip(delta: int) -> String:
	if delta > 0:
		return "(+%d ★)" % delta
	return "(+0 ★)"


static func _faceoff_outcome_text(score_h: int, score_c: int, dh: int, dc: int) -> String:
	if dh > 0 and dc > 0:
		return "Tie — both earn a star!"
	if dh > 0:
		return "You win the Faceoff — +1 star!"
	if dc > 0:
		return "CPU wins the Faceoff — +1 star."
	if score_h == score_c:
		return "Tie round — no star awarded."
	if score_h > score_c:
		return "You scored higher this round."
	return "CPU scored higher this round."


static func _game_over_kind(result: String) -> String:
	var lower := result.to_lower()
	if "you win" in lower or "you won" in lower:
		return "win"
	if "cpu win" in lower or "you lose" in lower or "defeat" in lower:
		return "loss"
	return "draw"

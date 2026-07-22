extends RefCounted
class_name TutorialVisuals

const _CARD_W := 76.0
const _CARD_H := 100.0


static func clear_band(band: Control) -> void:
	if band == null:
		return
	for c in band.get_children():
		c.queue_free()


static func _flat_panel(bg: Color, border: Color, width_px: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width_px)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	return sb


static func _chip(title: String, subtitle: String = "", accent: Color = Color(0.32, 0.55, 0.82)) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(_CARD_W, _CARD_H)
	p.add_theme_stylebox_override("panel", _flat_panel(Color(0.11, 0.12, 0.15), accent, 2))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 13)
	var s := Label.new()
	s.text = subtitle
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.add_theme_font_size_override("font_size", 11)
	s.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	v.add_child(t)
	if not subtitle.is_empty():
		v.add_child(s)
	p.add_child(v)
	return p


static func add_goal_zones(band: Control, highlight_chef: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var chef_accent := Color(0.95, 0.75, 0.35) if highlight_chef else Color(0.32, 0.55, 0.82)
	row.add_child(_chip("Chef", "Baseline influence", chef_accent))
	row.add_child(_chip("Restaurant\ndeck", "Pick one to run", Color(0.42, 0.72, 0.55)))
	row.add_child(_chip("Main deck", "Staff / meals /\nevents / support", Color(0.62, 0.45, 0.82)))
	band.add_child(row)


static func add_star_track(band: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.text = "Stars to win — "
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)
	for i in range(MatchConfig.STARS_TO_WIN):
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 22)
		star.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35) if i < 2 else Color(0.35, 0.36, 0.4))
		row.add_child(star)
	band.add_child(row)


static func add_restaurant_top_bottom(band: Control) -> void:
	var tables := TutorialCatalog.load_tables()
	var top := TutorialCatalog.row_by_code(tables, DeckRules.RESTAURANT_TABLE, "TUT_REST_TOP")
	var bot := TutorialCatalog.row_by_code(tables, DeckRules.RESTAURANT_TABLE, "TUT_REST_BOT")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var top_name := DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, top) if not top.is_empty() else "Top"
	var bot_name := DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, bot) if not bot.is_empty() else "Bottom"
	row.add_child(_chip("TOP of deck", top_name, Color(0.38, 0.62, 0.9)))
	var stack := VBoxContainer.new()
	var deck_lbl := Label.new()
	deck_lbl.text = "Restaurant\ndeck"
	deck_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deck_lbl.add_theme_font_size_override("font_size", 12)
	deck_lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	stack.add_child(deck_lbl)
	var mini := HBoxContainer.new()
	mini.add_theme_constant_override("separation", -18)
	for i in range(3):
		var back := ColorRect.new()
		back.custom_minimum_size = Vector2(44, 58)
		back.color = Color(0.18, 0.22, 0.3).lerp(Color(0.12, 0.14, 0.18), float(i) / 3.0)
		back.rotation = deg_to_rad(-5.0 + float(i) * 5.0)
		mini.add_child(back)
	stack.add_child(mini)
	row.add_child(stack)
	row.add_child(_chip("BOTTOM of deck", bot_name, Color(0.42, 0.72, 0.55)))
	band.add_child(row)


static func add_restaurant_deck_stack(band: Control) -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", -14)
	for i in range(4):
		var back := ColorRect.new()
		back.custom_minimum_size = Vector2(48, 64)
		back.color = Color(0.22, 0.38, 0.52).lerp(Color(0.11, 0.13, 0.17), float(i) / 4.0)
		back.rotation = deg_to_rad(-4.0 + float(i) * 2.5)
		row.add_child(back)
	var cap := Label.new()
	cap.text = "Shuffled restaurant deck — you peek top & bottom, then pick one."
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.custom_minimum_size = Vector2(380, 0)
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
	col.add_child(row)
	col.add_child(cap)
	band.add_child(col)


static func add_mulligan_intro(band: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var deck := PanelContainer.new()
	deck.custom_minimum_size = Vector2(56, 72)
	deck.add_theme_stylebox_override("panel", _flat_panel(Color(0.14, 0.16, 0.2), Color(0.35, 0.38, 0.45), 1))
	var dl := Label.new()
	dl.text = "Deck"
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deck.add_child(dl)
	row.add_child(deck)
	var ar := Label.new()
	ar.text = "⇒"
	ar.add_theme_font_size_override("font_size", 28)
	ar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ar)
	var hand := HBoxContainer.new()
	hand.add_theme_constant_override("separation", 4)
	for _i in range(MatchConfig.OPENING_HAND_SIZE):
		hand.add_child(_mini_back(Color(0.28, 0.52, 0.78)))
	row.add_child(hand)
	col.add_child(row)
	var cap := Label.new()
	cap.text = "Opening hand — up to one full mulligan before round 1"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.7, 0.73, 0.78))
	col.add_child(cap)
	band.add_child(col)


static func _mini_back(accent: Color) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(34, 46)
	p.add_theme_stylebox_override("panel", _flat_panel(accent.darkened(0.35), accent, 1))
	return p


static func add_staff_hand_backs(band: Control, count: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := clampi(count, 0, MatchConfig.OPENING_HAND_SIZE)
	for _i in range(n):
		row.add_child(_mini_back(Color(0.32, 0.55, 0.82)))
	var cap := Label.new()
	cap.text = "  %d cards" % n
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	band.add_child(row)


static func add_setup_lane_hint(band: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var inf := PanelContainer.new()
	inf.custom_minimum_size = Vector2(120, 44)
	inf.add_theme_stylebox_override("panel", _flat_panel(Color(0.12, 0.14, 0.18), Color(0.45, 0.75, 0.55), 2))
	var il := Label.new()
	il.text = "Influence\n(spend to set)"
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	il.add_theme_font_size_override("font_size", 11)
	inf.add_child(il)
	row.add_child(inf)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	for i in range(4):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(52, 64)
		var slot_style := _flat_panel(Color(0.08, 0.09, 0.11), Color(0.28, 0.3, 0.34), 1)
		slot.add_theme_stylebox_override("panel", slot_style)
		var sl := Label.new()
		sl.text = str(i + 1)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.add_theme_font_size_override("font_size", 12)
		sl.add_theme_color_override("font_color", Color(0.4, 0.42, 0.48))
		slot.add_child(sl)
		row.add_child(slot)
	col.add_child(row)
	var hint := Label.new()
	hint.text = "Face-down line (Staff / Meal / Event in this lesson)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.68, 0.7, 0.75))
	col.add_child(hint)
	band.add_child(col)


static func add_faceoff_boards(band: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var order := Label.new()
	order.text = "Reveal order in a real Faceoff: left → right along your line"
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.add_theme_font_size_override("font_size", 12)
	order.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	col.add_child(order)
	var boards := HBoxContainer.new()
	boards.add_theme_constant_override("separation", 20)
	boards.alignment = BoxContainer.ALIGNMENT_CENTER
	boards.add_child(_faceoff_column("You", Color(0.32, 0.55, 0.82)))
	var vs := Label.new()
	vs.text = "vs"
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.add_theme_font_size_override("font_size", 18)
	boards.add_child(vs)
	boards.add_child(_faceoff_column("Opponent", Color(0.82, 0.45, 0.38)))
	col.add_child(boards)
	band.add_child(col)


static func _faceoff_column(title: String, accent: Color) -> PanelContainer:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", _flat_panel(Color(0.1, 0.11, 0.14), accent, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 13)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	for i in range(3):
		var c := _mini_back(accent.darkened(0.15 + float(i) * 0.08))
		c.custom_minimum_size = Vector2(30, 42)
		line.add_child(c)
	var meal := Label.new()
	meal.text = "+ meals → total"
	meal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meal.add_theme_font_size_override("font_size", 10)
	meal.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	v.add_child(t)
	v.add_child(line)
	v.add_child(meal)
	outer.add_child(v)
	return outer


static func add_deck_counts(band: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_count_chip("Main", "%d cards" % DeckRules.MAIN_DECK_SIZE, Color(0.32, 0.55, 0.82)))
	row.add_child(_count_chip("Restaurants", "%d–%d unique" % [DeckRules.RESTAURANT_MIN, DeckRules.RESTAURANT_MAX], Color(0.42, 0.72, 0.55)))
	row.add_child(_count_chip("Chef", "×1", Color(0.95, 0.75, 0.35)))
	band.add_child(row)


static func _count_chip(title: String, detail: String, accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(108, 72)
	p.add_theme_stylebox_override("panel", _flat_panel(Color(0.11, 0.12, 0.15), accent, 2))
	var v := VBoxContainer.new()
	var a := Label.new()
	a.text = title
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_size_override("font_size", 14)
	var b := Label.new()
	b.text = detail
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	v.add_child(a)
	v.add_child(b)
	p.add_child(v)
	return p


static func fill_default_band(lesson_id: String, step_idx: int, band: Control) -> void:
	clear_band(band)
	if band == null:
		return
	match lesson_id:
		"goal_zones":
			add_star_track(band)
			add_goal_zones(band, step_idx >= 2)
		"restaurant_pick":
			if step_idx == 0:
				add_restaurant_deck_stack(band)
			elif step_idx == 1:
				add_restaurant_top_bottom(band)
		"mulligan":
			if step_idx == 0:
				add_mulligan_intro(band)
			elif step_idx == 1:
				add_staff_hand_backs(band, MatchConfig.OPENING_HAND_SIZE)
		"setup":
			if step_idx == 2:
				add_setup_lane_hint(band)
			elif step_idx <= 1:
				var row := HBoxContainer.new()
				row.alignment = BoxContainer.ALIGNMENT_CENTER
				var l := Label.new()
				l.text = "Draw to at least %d in hand, then set Staff, Meals, and Events face-down up to influence." % MatchConfig.SETUP_MIN_HAND
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(420, 0)
				row.add_child(l)
				band.add_child(row)
		"faceoff":
			if step_idx <= 2:
				add_faceoff_boards(band)
		"deck_teaser":
			add_deck_counts(band)
		_:
			pass

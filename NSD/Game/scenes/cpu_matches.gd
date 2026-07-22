extends Control

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const OVERLAY_PATH := "res://data/cpu_dev_catalog_overlay.json"
const BUNDLED_SAMPLE_LOADOUT := "res://data/bundled_sample_loadout.json"
const _CARD_EFFECT_REGISTRY := preload("res://scripts/card_effects/card_effect_registry.gd")
const _MatchAnimationOverlay := preload("res://ui/match/match_animation_overlay.gd")
const _MatchHud := preload("res://ui/match/match_hud.gd")
const _MatchLayout := preload("res://ui/match/match_layout.gd")
const _MatchHandFan := preload("res://ui/match/match_hand_fan.gd")
const _MatchTargetPicker := preload("res://ui/match/match_target_picker.gd")
const CPU_SETUP_CARD_DELAY := 0.35

signal _target_pick_completed(index: int)

var _tables_data: Dictionary = {}
var _catalog_ready: bool = false
var _catalog_warnings: PackedStringArray = PackedStringArray()
var _loadout: Dictionary = {}
var _loadout_note: String = ""
var _match: MatchState
var _preview: CardPreviewSidebar
var _match_overlay
var _faceoff_animating: bool = false
var _cpu_setup_animating: bool = false
var _cpu_anim_visible_count: int = 0
var _pending_game_over: String = ""
var _log_expanded: bool = false
var _banner_tween: Tween
var _target_picker: MatchTargetPicker


func _game_menu() -> Node:
	return get_node("/root/GameMenu")


func _ready() -> void:
	var menu := _game_menu()
	menu.register_context(menu.Context.IN_MATCH, _back_to_menu_task, _can_surrender)
	%BackButton.pressed.connect(_on_back_pressed)
	%LogToggleButton.pressed.connect(_on_log_toggle_pressed)
	%MulliganYesButton.pressed.connect(_on_mulligan_yes)
	%MulliganNoButton.pressed.connect(_on_mulligan_no)
	%RemoveLastButton.pressed.connect(_on_remove_last_setup)
	%LockSetupButton.pressed.connect(_on_lock_setup)
	%RevealFaceoffButton.pressed.connect(_on_reveal_faceoff)
	%BattleRoot.resized.connect(_on_battle_root_resized)
	%BattleRootInner.resized.connect(_on_hand_fan_host_resized)
	%HandFanHost.resized.connect(_on_hand_fan_host_resized)
	_set_log_expanded(false)
	call_deferred("_ensure_preview")
	SupabaseClient.batch_progress.connect(_on_batch_progress)
	SupabaseClient.batch_finished.connect(_on_catalog_batch_finished)
	_load_loadout_from_disk()
	_set_status("Loading catalog…")
	if SupabaseClient.load_catalog_from_cache():
		return
	if not SupabaseClient.load_config():
		_set_error(
			"Missing cache and config: run launcher Sync or add res://secrets/supabase.local.json."
		)
		return
	SupabaseClient.fetch_all_tables()


func _exit_tree() -> void:
	_game_menu().clear_context()


func _can_surrender() -> bool:
	return not _cpu_setup_animating and not _faceoff_animating


func _viewport_size() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	if vp.x > 1.0 and vp.y > 1.0:
		return vp
	return Vector2(1280.0, 720.0)


func _line_opts() -> Dictionary:
	return _MatchLayout.line_card_opts(_viewport_size())


func _hand_opts() -> Dictionary:
	return _MatchLayout.hand_card_opts(_viewport_size())


func _mulligan_opts() -> Dictionary:
	return _MatchLayout.mulligan_card_opts(_viewport_size())


func _portrait_opts() -> Dictionary:
	return _MatchLayout.portrait_opts(_viewport_size())


func _pick_opts() -> Dictionary:
	return _MatchLayout.pick_card_opts(_viewport_size())


func _on_battle_root_resized() -> void:
	if _match != null:
		_refresh_all_ui()


func _on_hand_fan_host_resized() -> void:
	if _match == null:
		return
	if _match.phase != MatchState.Phase.SETUP:
		return
	if _match.is_faceoff_pending() or _cpu_setup_animating:
		return
	if not %HandRow.visible:
		return
	_layout_hand_fan()


func _ensure_preview() -> void:
	if _preview != null:
		return
	_preview = CardPreviewSidebar.attach_to_host(self, $Margin)


func _ensure_match_overlay() -> void:
	if _match_overlay != null:
		return
	_match_overlay = _MatchAnimationOverlay.attach(self)


func _load_loadout_from_disk() -> void:
	var path := DeckRules.LOADOUT_PATH
	if not FileAccess.file_exists(path):
		_loadout = {}
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_loadout = {}
		return
	var parsed: Variant = DeckRules.parse_stored_json(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_loadout = parsed
	else:
		_loadout = {}


func _on_batch_progress(table_name: String, ok: bool, rows: Array, err_msg: String) -> void:
	if ok:
		_tables_data[table_name] = rows
	else:
		_tables_data[table_name] = []
		push_warning("CPU matches: table %s failed: %s" % [table_name, err_msg])


func _on_catalog_batch_finished() -> void:
	_catalog_ready = true
	_merge_catalog_overlay_if_present()
	_ensure_playable_loadout()
	var leg := DeckLegality.validate_for_match(_tables_data, _loadout)
	var errs: PackedStringArray = leg.get("errors", PackedStringArray()) as PackedStringArray
	var warns: PackedStringArray = leg.get("warnings", PackedStringArray()) as PackedStringArray
	if not errs.is_empty():
		_set_error("; ".join(errs))
		return
	_catalog_warnings = warns
	if warns.size() > 0:
		push_warning("CPU matches catalog warnings: %s" % "; ".join(warns))
	_begin_match()


func _merge_catalog_overlay_if_present() -> void:
	if not FileAccess.file_exists(OVERLAY_PATH):
		return
	var f := FileAccess.open(OVERLAY_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	for table_name in root.keys():
		var rows: Variant = root[table_name]
		if typeof(rows) != TYPE_ARRAY:
			continue
		var existing: Array = []
		if _tables_data.has(table_name) and typeof(_tables_data[table_name]) == TYPE_ARRAY:
			existing = (_tables_data[table_name] as Array).duplicate()
		for new_row in rows:
			if typeof(new_row) != TYPE_DICTIONARY:
				continue
			var nr: Dictionary = new_row
			var nid := DeckRules.row_id(nr)
			if nid.is_empty():
				continue
			var replaced := false
			for i in range(existing.size()):
				var er: Variant = existing[i]
				if typeof(er) != TYPE_DICTIONARY:
					continue
				if DeckRules.row_id(er) == nid:
					var merged: Dictionary = (er as Dictionary).duplicate()
					for k in nr.keys():
						merged[k] = nr[k]
					existing[i] = merged
					replaced = true
					break
			if not replaced:
				existing.append(nr.duplicate())
		_tables_data[table_name] = existing


func _read_loadout_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = DeckRules.parse_stored_json(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _loadout_passes_legality(lo: Dictionary) -> bool:
	if lo.is_empty():
		return false
	var errs: PackedStringArray = DeckLegality.validate_for_match(_tables_data, lo).get(
		"errors", PackedStringArray()
	) as PackedStringArray
	return errs.is_empty()


func _ensure_playable_loadout() -> void:
	_loadout_note = ""
	if _loadout_passes_legality(_loadout):
		return
	var had_disk_save := not _loadout.is_empty()
	var bundled := _read_loadout_json(BUNDLED_SAMPLE_LOADOUT)
	if _loadout_passes_legality(bundled):
		_loadout = bundled
		if had_disk_save:
			_loadout_note = (
				"Your save at %s is not legal with this catalog. Using the bundled sample deck (file not changed)."
				% DeckRules.LOADOUT_PATH
			)
		else:
			_loadout_note = "No saved deck — using the bundled sample deck from res://data/bundled_sample_loadout.json."
		return
	var gen := SampleDeckBuilder.try_build_loadout(_tables_data)
	if bool(gen.get("ok", false)):
		_loadout = gen["loadout"] as Dictionary
		if had_disk_save:
			_loadout_note = (
				"Your save and the bundled sample do not work with this catalog. Using an auto-built starter deck (save file not changed)."
			)
		else:
			_loadout_note = "Using an auto-built starter deck from the synced catalog."
		return


func _begin_match() -> void:
	_ensure_preview()
	if _loadout.is_empty():
		_set_error(
			"No legal deck: sync catalog data, or save a deck in Deck building. "
			+ "Tried your save, bundled sample, and catalog auto-build."
		)
		return
	_match = MatchState.new()
	_match.message.connect(_on_match_message)
	_match.phase_changed.connect(_on_phase_changed)
	_match.stars_changed.connect(_on_stars_changed)
	_match.game_over.connect(_on_game_over)
	_faceoff_animating = false
	_cpu_setup_animating = false
	_cpu_anim_visible_count = 0
	_pending_game_over = ""
	%EndedLabel.visible = false
	%EndedLabel.text = ""
	_match.start_match(_tables_data, _loadout)
	_start_battle_music()
	if not _loadout_note.is_empty():
		_append_log(_loadout_note)
	_refresh_all_ui()


func _start_battle_music() -> void:
	var player := %BattleMusic as AudioStreamPlayer
	if player.playing:
		return
	player.volume_db = -8.0
	player.play()


func _on_match_message(text: String) -> void:
	_append_log(text)
	if _MatchHud.should_banner_message(text):
		_show_status_banner(text, 3.0)


func _on_phase_changed(_p: int) -> void:
	_refresh_all_ui()


func _on_stars_changed(h: int, c: int) -> void:
	_MatchHud.rebuild_star_track(
		%YouStarsTrack,
		"",
		h,
		MatchConfig.STARS_TO_WIN,
		Color(0.45, 0.78, 1.0),
		Color(0.28, 0.3, 0.36),
		true
	)
	_MatchHud.rebuild_star_track(
		%CpuStarsTrack,
		"",
		c,
		MatchConfig.STARS_TO_WIN,
		Color(1.0, 0.55, 0.45),
		Color(0.28, 0.3, 0.36),
		true
	)


func _refresh_match_hud() -> void:
	if _match == null:
		return
	%PhaseBadge.text = _MatchHud.phase_label(
		_match.phase,
		_match.get_setup_round(),
		_match.is_faceoff_pending()
	)
	var rnd := _match.get_setup_round()
	%RoundLabel.text = "R%d" % rnd if rnd > 0 else ""
	%RoundLabel.visible = rnd > 0
	%StepTitle.add_theme_font_size_override(
		"font_size",
		_MatchLayout.step_title_font_size(_viewport_size())
	)


func _on_game_over(result: String) -> void:
	_append_log(result)
	_show_status_banner(result, 4.0)
	%EndedLabel.text = result
	if _faceoff_animating:
		_pending_game_over = result
		return
	_play_game_over_anim(result)


func _play_game_over_anim(result: String) -> void:
	_game_over_anim_task(result)


func _game_over_anim_task(result: String) -> void:
	_ensure_match_overlay()
	await _match_overlay.play_game_over(result)
	%EndedLabel.visible = true


func _set_status(s: String) -> void:
	%StatusLabel.text = s
	%ErrorLabel.visible = false


func _set_error(s: String) -> void:
	%ErrorLabel.text = s
	%ErrorLabel.visible = true
	%StatusLabel.text = ""
	_hide_gameplay()


func _hide_gameplay() -> void:
	%BattleRoot.visible = false


func _set_board_chrome_visible(show_board: bool) -> void:
	%BoardChrome.visible = show_board


func _set_modal_open(open: bool) -> void:
	%ModalDim.visible = open


func _set_log_expanded(expanded: bool) -> void:
	_log_expanded = expanded
	%LogScroll.visible = expanded
	%LogToggleButton.text = "▼ Log" if expanded else "▶ Log"


func _on_log_toggle_pressed() -> void:
	_set_log_expanded(not _log_expanded)


func _append_log(s: String) -> void:
	var cur := str(%LogLabel.text)
	if cur.length() > 8000:
		cur = cur.substr(maxi(0, cur.length() - 4000), 4000)
	%LogLabel.text = cur + s + "\n"
	if _log_expanded:
		call_deferred("_scroll_log_to_bottom")


func _scroll_log_to_bottom() -> void:
	var scroll := %LogScroll as ScrollContainer
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _show_status_banner(text: String, duration: float = 3.0) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	%StatusBanner.text = text
	%StatusBanner.visible = true
	%StatusBanner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(%StatusBanner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(duration)
	_banner_tween.tween_property(%StatusBanner, "modulate:a", 0.0, 0.35)
	_banner_tween.tween_callback(func() -> void:
		%StatusBanner.visible = false
	)


func _refresh_all_ui() -> void:
	if _match == null:
		return
	%BattleRoot.visible = true
	_refresh_match_hud()
	_on_stars_changed(int(_match.stars[MatchState.P_HUMAN]), int(_match.stars[MatchState.P_CPU]))
	_refresh_active_restaurants_ui()
	match _match.phase:
		MatchState.Phase.PICK_RESTAURANT:
			_refresh_pick_restaurant_ui()
		MatchState.Phase.MULLIGAN:
			_refresh_mulligan_ui()
		MatchState.Phase.SETUP:
			_refresh_setup_ui()
		MatchState.Phase.FACEOFF, MatchState.Phase.SCORE:
			%StepTitle.text = "Faceoff / Score"
			_hide_phase_panels()
		MatchState.Phase.ENDED:
			%StepTitle.text = "Match over"
			_hide_phase_panels()
	if not _cpu_setup_animating:
		_refresh_hand_buttons()


func _hide_phase_panels() -> void:
	_set_modal_open(false)
	%PickPanel.visible = false
	%MulliganPanel.visible = false
	%SetupPanel.visible = false
	_set_board_chrome_visible(true)
	%HandRow.visible = false
	%HandDock.visible = false
	%ActionRail.visible = false


func _refresh_active_restaurants_ui() -> void:
	if _match == null:
		return
	var human_rest := _match.get_active_restaurant(MatchState.P_HUMAN)
	var cpu_rest := _match.get_active_restaurant(MatchState.P_CPU)
	_ensure_preview()
	if cpu_rest.is_empty():
		for c in %CpuRestaurantRow.get_children():
			c.queue_free()
	else:
		_rebuild_restaurant_slot(%CpuRestaurantRow, cpu_rest)
	if human_rest.is_empty():
		for c in %HumanRestaurantRow.get_children():
			c.queue_free()
	else:
		_rebuild_restaurant_slot(%HumanRestaurantRow, human_rest)


func _rebuild_restaurant_slot(row: HBoxContainer, rest_row: Dictionary) -> void:
	for c in row.get_children():
		c.queue_free()
	var tile := CardTileButton.new()
	tile.setup_card(DeckRules.RESTAURANT_TABLE, rest_row, _portrait_opts())
	CardPreviewSidebar.wire_tile(tile, _preview)
	row.add_child(tile)


func _refresh_pick_restaurant_ui() -> void:
	_ensure_preview()
	_set_modal_open(true)
	_set_board_chrome_visible(false)
	%PickPanel.visible = true
	%MulliganPanel.visible = false
	%SetupPanel.visible = false
	%HandDock.visible = false
	%ActionRail.visible = false
	%StepTitle.text = "Choose starting restaurant"
	for c in %PickRestaurantRow.get_children():
		c.queue_free()
	var pv := _match.restaurant_top_bottom_preview(MatchState.P_HUMAN)
	var pick_opts := _pick_opts()
	if bool(pv.get("ok", false)):
		var top: Dictionary = pv.get("top", {}) as Dictionary
		var bot: Dictionary = pv.get("bottom", {}) as Dictionary
		var id_t := str(top.get("id", ""))
		var id_b := str(bot.get("id", ""))
		var row_t := _resolve_row(DeckRules.RESTAURANT_TABLE, id_t)
		var row_b := _resolve_row(DeckRules.RESTAURANT_TABLE, id_b)
		var single := _match.get_restaurant_deck_size(MatchState.P_HUMAN) == 1
		if single:
			var card := RestaurantPickCard.new()
			card.setup_pick(top, row_t, "YOUR RESTAURANT", Callable(self, "_on_pick_top_pressed"), pick_opts)
			CardPreviewSidebar.wire_tile(card, _preview)
			%PickRestaurantRow.add_child(card)
		else:
			var c_top := RestaurantPickCard.new()
			c_top.setup_pick(top, row_t, "TOP OF DECK", Callable(self, "_on_pick_top_pressed"), pick_opts)
			CardPreviewSidebar.wire_tile(c_top, _preview)
			%PickRestaurantRow.add_child(c_top)
			var c_bot := RestaurantPickCard.new()
			c_bot.setup_pick(bot, row_b, "BOTTOM OF DECK", Callable(self, "_on_pick_bottom_pressed"), pick_opts)
			CardPreviewSidebar.wire_tile(c_bot, _preview)
			%PickRestaurantRow.add_child(c_bot)
	else:
		var err := Label.new()
		err.text = "No restaurant cards in deck."
		%PickRestaurantRow.add_child(err)


func _resolve_row(table: String, id_str: String) -> Dictionary:
	var rows: Variant = _tables_data.get(table, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		if DeckRules.row_id(r) == id_str:
			return r
	return {}


func _card_display_name(table: String, card: Dictionary) -> String:
	var row := _resolve_row(table, str(card.get("id", "")))
	if row.is_empty():
		return str(card.get("id", "Card"))
	return DeckRules.display_name_for_row(table, row)


func _refresh_mulligan_ui() -> void:
	_set_modal_open(true)
	_set_board_chrome_visible(false)
	%StepTitle.text = "Mulligan (once, all-or-nothing)"
	%MulliganPanel.visible = true
	%PickPanel.visible = false
	%SetupPanel.visible = false
	%HandDock.visible = false
	%ActionRail.visible = false
	_ensure_preview()
	for c in %MulliganHandRow.get_children():
		c.queue_free()
	var hand: Array = _match.get_hand(MatchState.P_HUMAN)
	for card_v in hand:
		if typeof(card_v) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = card_v
		var t := str(card.get("table", ""))
		var row := _resolve_row(t, str(card.get("id", "")))
		var tile := CardTileButton.new()
		tile.setup_card(t, row, _mulligan_opts())
		CardPreviewSidebar.wire_tile(tile, _preview)
		%MulliganHandRow.add_child(tile)
	var card_h: float = _mulligan_opts().get("display_h", 158.0)
	%MulliganHandRow.custom_minimum_size.y = int(card_h) + 8


func _set_cpu_influence_label(remaining: int, base: int) -> void:
	%CpuInfluenceLabel.text = "Inf %d/%d" % [remaining, base]


func _refresh_setup_ui() -> void:
	_set_modal_open(false)
	_set_board_chrome_visible(true)
	%PickPanel.visible = false
	%MulliganPanel.visible = false
	%SetupPanel.visible = true
	%HandDock.visible = true
	%ActionRail.visible = true
	%OpponentZone.visible = true
	%PlayerBenchZone.visible = true
	if _match.is_faceoff_pending() and not _cpu_setup_animating:
		%StepTitle.text = "Review — reveal Faceoff when ready"
	elif _cpu_setup_animating:
		%StepTitle.text = "CPU is setting its line…"
	else:
		%StepTitle.text = "Setup — place cards on your line"
	var pending := _match.is_faceoff_pending() and not _cpu_setup_animating
	%HandRow.visible = not pending and not _cpu_setup_animating
	%HandHint.visible = not pending and not _cpu_setup_animating
	if pending:
		%HandHint.text = "Line locked — tap Reveal when ready."
	else:
		%HandHint.text = "Tap a hand card to add it to your line."
	var base_inf := _match.get_base_influence_value()
	%InfluenceLabel.text = "Inf %d/%d" % [
		_match.get_influence(MatchState.P_HUMAN),
		base_inf,
	]
	%CenterInfluenceLabel.text = "CPU %s   |   You %s" % [
		%CpuInfluenceLabel.text,
		%InfluenceLabel.text,
	]
	if _cpu_setup_animating:
		pass
	elif pending:
		_set_cpu_influence_label(_match.get_influence(MatchState.P_CPU), base_inf)
	else:
		_set_cpu_influence_label(base_inf, base_inf)
	_rebuild_line_row(%HumanLineRow, _match.get_setup_line(MatchState.P_HUMAN), false)
	_refresh_cpu_line_display(pending)
	var buttons_locked := pending or _cpu_setup_animating
	%LockSetupButton.visible = not pending and not _cpu_setup_animating
	%RevealFaceoffButton.visible = pending
	%RemoveLastButton.disabled = buttons_locked
	%LockSetupButton.disabled = _cpu_setup_animating


func _refresh_cpu_line_display(pending: bool) -> void:
	if _cpu_setup_animating:
		var placements: Array = _match.get_cpu_setup_placements()
		var partial: Array = []
		for i in range(mini(_cpu_anim_visible_count, placements.size())):
			partial.append(placements[i])
		_rebuild_line_row_from_placements(%CpuLineRow, partial, true)
	elif pending:
		_rebuild_line_row(%CpuLineRow, _match.get_setup_line(MatchState.P_CPU), true)
	else:
		_rebuild_line_row(%CpuLineRow, [], true)


func _rebuild_line_row_from_placements(row: HBoxContainer, placements: Array, conceal: bool) -> void:
	var cards: Array = []
	for entry in placements:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		cards.append({"table": str(d.get("table", "")), "id": str(d.get("id", ""))})
	_rebuild_line_row(row, cards, conceal)


func _refresh_hand_buttons() -> void:
	_ensure_preview()
	for c in %HandRow.get_children():
		c.queue_free()
	if _match == null:
		return
	if _match.phase != MatchState.Phase.SETUP:
		return
	if _match.is_faceoff_pending() or _cpu_setup_animating:
		return
	var hand: Array = _match.get_hand(MatchState.P_HUMAN)
	for i in range(hand.size()):
		var card: Dictionary = hand[i] as Dictionary
		var t := str(card.get("table", ""))
		var id_str := str(card.get("id", ""))
		var row := _resolve_row(t, id_str)
		var fx = _CARD_EFFECT_REGISTRY.make(t, id_str, row)
		var hc := CpuHandCard.new()
		hc.setup_from(i, fx, _hand_opts())
		hc.card_chosen.connect(_on_add_hand_card)
		CardPreviewSidebar.wire_tile(hc, _preview)
		%HandRow.add_child(hc)
	call_deferred("_layout_hand_fan")


func _layout_hand_fan(retry: bool = false) -> void:
	var vp := _viewport_size()
	var peek_h := _MatchLayout.hand_peek_strip_height(vp)
	%HandFanHost.custom_minimum_size.y = peek_h
	var dock: Control = %HandDock
	var dock_h := float(peek_h + 22)
	dock.anchor_left = 0.0
	dock.anchor_right = 1.0
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = 0.0
	dock.offset_top = -dock_h
	dock.offset_right = 0.0
	dock.offset_bottom = 0.0
	var spread: float = %HandRow.size.x
	if spread < 8.0:
		spread = %HandFanHost.size.x
	if spread < 8.0:
		spread = dock.size.x
	var inner: Control = %BattleRootInner
	var apex_local_x: float = (
		inner.global_position.x + inner.size.x * 0.5 - %HandRow.global_position.x
	)
	if not _MatchHandFan.apply_to(
		%HandRow,
		spread,
		_MatchLayout.hand_card_peek_ratio(),
		_MatchHandFan.FanShape.BELL_CURVE,
		_MatchLayout.hand_bell_peak_height(vp),
		apex_local_x
	):
		if not retry:
			call_deferred("_layout_hand_fan_retry")


func _layout_hand_fan_retry() -> void:
	_layout_hand_fan(true)


func _rebuild_line_row(row: HBoxContainer, cards: Array, conceal: bool) -> void:
	var face_up_through := 999 if not conceal else -1
	_rebuild_line_row_reveal(row, cards, face_up_through)


func _rebuild_line_row_reveal(row: HBoxContainer, cards: Array, face_up_through: int) -> void:
	_ensure_preview()
	for c in row.get_children():
		c.queue_free()
	var opts_base := _line_opts()
	for i in range(cards.size()):
		var card: Variant = cards[i]
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		var t := str(d.get("table", ""))
		var id_str := str(d.get("id", ""))
		var card_row := _resolve_row(t, id_str)
		var opts: Dictionary = opts_base.duplicate()
		opts["face_down"] = i > face_up_through
		var tile := CardTileButton.new()
		tile.setup_card(t, card_row, opts)
		CardPreviewSidebar.wire_tile(tile, _preview)
		row.add_child(tile)


func _rebuild_both_lines_revealed(reveal_through: int) -> void:
	if _match == null:
		return
	_rebuild_line_row_reveal(
		%HumanLineRow,
		_match.get_setup_line(MatchState.P_HUMAN),
		reveal_through
	)
	_rebuild_line_row_reveal(
		%CpuLineRow,
		_match.get_setup_line(MatchState.P_CPU),
		reveal_through
	)


func _slot_card_names(slot: int) -> Dictionary:
	var human_line: Array = _match.get_setup_line(MatchState.P_HUMAN)
	var cpu_line: Array = _match.get_setup_line(MatchState.P_CPU)
	var human_name := "—"
	var cpu_name := "—"
	if slot < human_line.size() and typeof(human_line[slot]) == TYPE_DICTIONARY:
		var hc: Dictionary = human_line[slot]
		human_name = _card_display_name(str(hc.get("table", "")), hc)
	if slot < cpu_line.size() and typeof(cpu_line[slot]) == TYPE_DICTIONARY:
		var cc: Dictionary = cpu_line[slot]
		cpu_name = _card_display_name(str(cc.get("table", "")), cc)
	return {"human": human_name, "cpu": cpu_name}


func _on_add_hand_card(hand_index: int) -> void:
	if _match == null:
		return
	var r := _match.setup_add_card(MatchState.P_HUMAN, hand_index)
	if not bool(r.get("ok", false)):
		_append_log(str(r.get("error", "Could not add card.")))
	_refresh_all_ui()


func _on_pick_top_pressed() -> void:
	_commit_pick(true)


func _on_pick_bottom_pressed() -> void:
	_commit_pick(false)


func _commit_pick(take_top: bool) -> void:
	if _match == null:
		return
	var pv := _match.restaurant_top_bottom_preview(MatchState.P_HUMAN)
	if not bool(pv.get("ok", false)) and _match.get_restaurant_deck_size(MatchState.P_HUMAN) == 1:
		take_top = true
	var res := _match.commit_restaurant_pick(MatchState.P_HUMAN, take_top)
	if not bool(res.get("ok", false)):
		_set_error(str(res.get("error", "Pick failed.")))
		return
	_match.cpu_auto_pick_restaurant()
	_match.begin_opening_hands_after_restaurant_pick()
	if _match.phase == MatchState.Phase.ENDED:
		_refresh_all_ui()
		return
	_refresh_all_ui()


func _on_mulligan_yes() -> void:
	if _match == null:
		return
	var r := _match.mulligan_all_or_nothing(MatchState.P_HUMAN, true)
	if not bool(r.get("ok", false)):
		_append_log(str(r.get("error", "Mulligan failed.")))
	_match.mulligan_all_or_nothing(MatchState.P_CPU, false)
	_after_mulligan_done()


func _on_mulligan_no() -> void:
	if _match == null:
		return
	_match.mulligan_all_or_nothing(MatchState.P_HUMAN, false)
	_match.mulligan_all_or_nothing(MatchState.P_CPU, false)
	_after_mulligan_done()


func _after_mulligan_done() -> void:
	if _match == null:
		return
	if _match.phase == MatchState.Phase.ENDED:
		_refresh_all_ui()
		return
	if not _match.start_setup_round():
		return
	_refresh_all_ui()


func _on_remove_last_setup() -> void:
	if _match == null or _cpu_setup_animating:
		return
	var r := _match.setup_remove_last(MatchState.P_HUMAN)
	if not bool(r.get("ok", false)):
		_append_log(str(r.get("error", "Nothing to remove.")))
	_refresh_all_ui()


func _on_lock_setup() -> void:
	if _match == null or _cpu_setup_animating:
		return
	var r := _match.submit_human_setup()
	if not bool(r.get("ok", false)):
		_append_log(str(r.get("error", "Lock failed.")))
		return
	_run_cpu_setup_anim()


func _run_cpu_setup_anim() -> void:
	_cpu_setup_anim_task()


func _cpu_setup_anim_task() -> void:
	_cpu_setup_animating = true
	_cpu_anim_visible_count = 0
	_show_status_banner("CPU is setting its line…", 2.5)
	_refresh_setup_ui()
	var placements: Array = _match.get_cpu_setup_placements()
	var base_inf := _match.get_base_influence_value()
	var display_inf := base_inf
	_set_cpu_influence_label(display_inf, base_inf)
	_rebuild_line_row_from_placements(%CpuLineRow, [], true)
	for i in range(placements.size()):
		_cpu_anim_visible_count = i + 1
		if typeof(placements[i]) == TYPE_DICTIONARY:
			var entry: Dictionary = placements[i]
			display_inf -= int(entry.get("cost", 0))
		_set_cpu_influence_label(maxi(0, display_inf), base_inf)
		_refresh_cpu_line_display(false)
		await get_tree().create_timer(CPU_SETUP_CARD_DELAY).timeout
	await get_tree().create_timer(0.2).timeout
	_cpu_setup_animating = false
	_cpu_anim_visible_count = 0
	_show_status_banner("Review both lines — reveal Faceoff when ready.", 3.0)
	_refresh_all_ui()


func _on_reveal_faceoff() -> void:
	_run_faceoff_anim()


func _ensure_target_picker() -> MatchTargetPicker:
	if _target_picker != null:
		return _target_picker
	_target_picker = _MatchTargetPicker.attach(self)
	if not _target_picker.candidate_chosen.is_connected(_on_target_candidate_chosen):
		_target_picker.candidate_chosen.connect(_on_target_candidate_chosen)
	return _target_picker


func _pick_faceoff_target(request: Dictionary) -> int:
	_ensure_preview()
	_ensure_match_overlay()
	var prompt := str(request.get("prompt", "Choose a target."))
	var candidates: Array = request.get("candidates", []) as Array
	_match_overlay.enter_target_mode(prompt)
	_show_status_banner(prompt, 0.0)
	var picker := _ensure_target_picker()
	picker.show_candidates(prompt, candidates, _resolve_row, _hand_opts(), _preview)
	var chosen: int = await _target_pick_completed
	picker.hide_picker()
	_match_overlay.exit_target_mode()
	return chosen


func _on_target_candidate_chosen(index: int) -> void:
	_target_pick_completed.emit(index)


func _drain_pending_targets(slot: int = -1) -> void:
	while _match.has_pending_target():
		var pick: int = await _pick_faceoff_target(_match.get_pending_target())
		var sub: Dictionary = _match.submit_target(pick)
		if not bool(sub.get("ok", false)):
			_append_log(str(sub.get("error", "Target failed.")))
			break
	if slot >= 0:
		return
	while true:
		var cont: Dictionary = _match.continue_faceoff_after_target()
		if bool(cont.get("waiting_target", false)) or _match.has_pending_target():
			await _drain_pending_targets()
			continue
		break


func _run_faceoff_anim() -> void:
	if _match == null or _faceoff_animating or _cpu_setup_animating:
		return
	if not _match.is_faceoff_pending():
		return
	_faceoff_animating = true
	_pending_game_over = ""
	%RevealFaceoffButton.disabled = true
	_ensure_match_overlay()
	_match.set_auto_resolve_targets(false)
	var begin_r: Dictionary = _match.begin_faceoff_resolution()
	var slot_count := int(begin_r.get("slots", 0))
	await _match_overlay.play_faceoff_intro()
	_rebuild_both_lines_revealed(-1)
	for slot in range(slot_count):
		_rebuild_both_lines_revealed(slot)
		var names := _slot_card_names(slot)
		await _match_overlay.play_slot_reveal(
			slot,
			slot_count,
			str(names.get("human", "—")),
			str(names.get("cpu", "—"))
		)
		while true:
			var r: Dictionary = _match.resolve_faceoff_slot(slot)
			if bool(r.get("waiting_target", false)) or _match.has_pending_target():
				await _drain_pending_targets(slot)
				if _match.has_pending_target():
					continue
				r = _match.resolve_faceoff_slot(slot)
			if not bool(r.get("waiting_target", false)):
				break
	while true:
		var fin: Dictionary = _match.finalize_faceoff_resolution()
		if bool(fin.get("waiting_target", false)) or _match.has_pending_target():
			await _drain_pending_targets()
			if _match.has_pending_target():
				continue
			fin = _match.finalize_faceoff_resolution()
		if not bool(fin.get("ok", false)):
			_append_log(str(fin.get("error", "Reveal failed.")))
			_match.set_auto_resolve_targets(true)
			_match_overlay.dismiss()
			_faceoff_animating = false
			%RevealFaceoffButton.disabled = false
			_refresh_all_ui()
			return
		if not bool(fin.get("waiting_target", false)):
			break
	_match.set_auto_resolve_targets(true)
	await _match_overlay.play_faceoff_result(_match.get_last_faceoff_summary())
	_match_overlay.dismiss()
	_faceoff_animating = false
	_refresh_all_ui()
	if not _pending_game_over.is_empty():
		var result := _pending_game_over
		_pending_game_over = ""
		await _match_overlay.play_game_over(result)
		%EndedLabel.visible = true
	%RevealFaceoffButton.disabled = false


func _on_back_pressed() -> void:
	if _cpu_setup_animating or _faceoff_animating:
		return
	_back_to_menu_task()


func _back_to_menu_task() -> void:
	var player := %BattleMusic as AudioStreamPlayer
	if player.playing:
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -40.0, 0.4)
		await tween.finished
		player.stop()
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)

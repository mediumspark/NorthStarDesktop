extends Node

## Sequential PostgREST fetches for catalog tables. Expects [member CONFIG_PATH].
## Session is read from [member SESSION_PATH_USER] then [member SESSION_PATH_RES]; writes try res first, then user://.

const CONFIG_PATH := "res://secrets/supabase.local.json"
const CACHE_PATH := "res://data/catalog_cache.json"
## Packaged / editor session next to project (launcher writes here in dev).
const SESSION_PATH_RES := "res://data/session.json"
## Writable copy for exported builds (and fallback when res:// is read-only).
const SESSION_PATH_USER := "user://session.json"

## Set true when [method load_catalog_from_cache] supplied data for the current session.
var used_cache_for_last_load: bool = false

var _session_loaded: bool = false
var _session_access_token: String = ""
var _session_expires_at: int = 0
var _session_user_id: String = ""
var _session_user_email: String = ""

const TABLE_ORDER: Array[String] = [
	"cards",
	"chef_cards",
	"event_cards",
	"meal_cards",
	"restaurant_cards",
	"staff_cards",
	"support_cards",
]

const TABLE_LABELS := {
	"cards": "Cards",
	"chef_cards": "Chef",
	"event_cards": "Event",
	"meal_cards": "Meal",
	"restaurant_cards": "Restaurant",
	"staff_cards": "Staff",
	"support_cards": "Support",
}

signal batch_progress(table_name: String, ok: bool, rows: Array, err_msg: String)
signal batch_finished

var _http: HTTPRequest
var _base_url: String = ""
var _anon_key: String = ""
var _queue: Array[String] = []
var _current_table: String = ""


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func get_base_url() -> String:
	return _base_url


func get_anon_key() -> String:
	return _anon_key


## Prefer user:// (export-safe), then packaged res:// (launcher / editor).
func load_session_file() -> bool:
	if _session_loaded:
		return not _session_access_token.is_empty()
	var paths := [SESSION_PATH_USER, SESSION_PATH_RES]
	var data: Variant = null
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			break
		data = null
	_session_loaded = true
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	var at: String = str(d.get("access_token", ""))
	if at.is_empty():
		return false
	var exp_raw: Variant = d.get("expires_at", 0)
	var exp: int = 0
	match typeof(exp_raw):
		TYPE_INT:
			exp = exp_raw
		TYPE_FLOAT:
			exp = int(exp_raw)
		_:
			exp = 0
	var now: int = int(Time.get_unix_time_from_system())
	if exp > 0 and now >= exp - 120:
		_session_access_token = ""
		return false
	_session_access_token = at
	_session_expires_at = exp
	var u: Variant = d.get("user", {})
	if typeof(u) == TYPE_DICTIONARY:
		var ud: Dictionary = u
		_session_user_id = str(ud.get("id", ""))
		_session_user_email = str(ud.get("email", ""))
	return true


func invalidate_session_cache() -> void:
	_session_loaded = false
	_session_access_token = ""
	_session_expires_at = 0
	_session_user_id = ""
	_session_user_email = ""


## Launcher-compatible JSON: access_token, refresh_token, expires_at, user { id, email }.
func save_session_dict(session: Dictionary) -> bool:
	var text := JSON.stringify(session)
	if text.is_empty():
		return false
	var f_res := FileAccess.open(SESSION_PATH_RES, FileAccess.WRITE)
	if f_res:
		f_res.store_string(text)
		f_res.close()
		invalidate_session_cache()
		load_session_file()
		return true
	var f_user := FileAccess.open(SESSION_PATH_USER, FileAccess.WRITE)
	if f_user:
		f_user.store_string(text)
		f_user.close()
		invalidate_session_cache()
		load_session_file()
		return true
	push_warning("Could not write session to res:// or user://")
	return false


## From Supabase password grant or refresh body: access_token, refresh_token, expires_in, user.
func save_session_from_auth_token_response(body: Dictionary) -> bool:
	var at := str(body.get("access_token", ""))
	var rt := str(body.get("refresh_token", ""))
	var ei_raw: Variant = body.get("expires_in", 3600)
	var ei := 3600
	match typeof(ei_raw):
		TYPE_INT:
			ei = ei_raw
		TYPE_FLOAT:
			ei = int(ei_raw)
		TYPE_STRING:
			var s := str(ei_raw)
			if s.is_valid_int():
				ei = int(s)
	var exp_at := int(Time.get_unix_time_from_system()) + ei
	var u: Variant = body.get("user", {})
	var uid := ""
	var em := ""
	if typeof(u) == TYPE_DICTIONARY:
		var ud: Dictionary = u
		uid = str(ud.get("id", ""))
		em = str(ud.get("email", ""))
	var sess := {
		"access_token": at,
		"refresh_token": rt,
		"expires_at": exp_at,
		"user": {"id": uid, "email": em},
	}
	return save_session_dict(sess)


func get_user_access_token() -> String:
	load_session_file()
	return _session_access_token


func get_session_user_id() -> String:
	load_session_file()
	return _session_user_id


func get_session_user_email() -> String:
	load_session_file()
	return _session_user_email


func is_session_valid() -> bool:
	return not get_user_access_token().is_empty()


func load_config() -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("Missing config: %s (copy secrets/supabase.local.example.json)" % CONFIG_PATH)
		return false
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	_base_url = str(d.get("supabase_url", "")).strip_edges().trim_suffix("/")
	_anon_key = str(d.get("supabase_anon_key", "")).strip_edges()
	return not _base_url.is_empty() and not _anon_key.is_empty()


func load_catalog_from_cache() -> bool:
	used_cache_for_last_load = false
	for path in _catalog_cache_path_candidates():
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var root = JSON.parse_string(text)
		if typeof(root) != TYPE_DICTIONARY:
			continue
		if not _emit_catalog_from_cache_dict(root):
			continue
		used_cache_for_last_load = true
		batch_finished.emit()
		return true
	return false


## Tries several paths so the cache works from the Godot editor (F5/F6), exported builds, and the launcher.
func _catalog_cache_path_candidates() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var add := func(p: String) -> void:
		if p.is_empty():
			return
		p = p.replace("\\", "/")
		if seen.has(p):
			return
		seen[p] = true
		out.append(p)
	# Absolute path — most reliable for loose files under res:// when running in the editor.
	var abs_primary := ProjectSettings.globalize_path(CACHE_PATH)
	if not abs_primary.is_empty():
		add.call(abs_primary)
	add.call(CACHE_PATH)
	var alt := _alternate_catalog_cache_path()
	if not alt.is_empty():
		add.call(alt)
	# Writable copy (e.g. after a future save, or manual copy) — works in editor and export.
	add.call("user://data/catalog_cache.json")
	add.call("user://catalog_cache.json")
	return out


## When the Love launcher synced to repo_root/data/ but the Godot project lives in repo_root/NorthStarDesktop/.
func _alternate_catalog_cache_path() -> String:
	var gp := ProjectSettings.globalize_path("res://")
	if gp.is_empty():
		return ""
	gp = gp.replace("\\", "/").trim_suffix("/")
	var last_slash := gp.rfind("/")
	if last_slash <= 0:
		return ""
	return gp.substr(0, last_slash) + "/data/catalog_cache.json"


func _emit_catalog_from_cache_dict(root: Dictionary) -> bool:
	var tables: Variant = root.get("tables", null)
	if typeof(tables) != TYPE_DICTIONARY:
		return false
	var td: Dictionary = tables
	for table_name in TABLE_ORDER:
		var rows: Variant = td.get(table_name, null)
		if typeof(rows) != TYPE_ARRAY:
			return false
		batch_progress.emit(table_name, true, rows, "")
	return true


func fetch_all_tables() -> void:
	used_cache_for_last_load = false
	_queue.clear()
	for t in TABLE_ORDER:
		_queue.append(t)
	_fetch_next()


func _fetch_next() -> void:
	if _queue.is_empty():
		batch_finished.emit()
		return
	_current_table = _queue.pop_front()
	var url := "%s/rest/v1/%s" % [_base_url, _current_table]
	var headers := PackedStringArray([
		"apikey: %s" % _anon_key,
		"Authorization: Bearer %s" % _anon_key,
		"Accept: application/json",
	])
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		batch_progress.emit(_current_table, false, [], "HTTPRequest.request failed: %s" % err)
		_fetch_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_str := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		batch_progress.emit(_current_table, false, [], "Transport error: result=%s body=%s" % [result, body_str.left(400)])
		_fetch_next()
		return
	if response_code != 200:
		batch_progress.emit(_current_table, false, [], "HTTP %s: %s" % [response_code, body_str.left(500)])
		_fetch_next()
		return
	var parsed = JSON.parse_string(body_str)
	if typeof(parsed) != TYPE_ARRAY:
		batch_progress.emit(_current_table, false, [], "Expected JSON array, got: %s" % body_str.left(200))
		_fetch_next()
		return
	batch_progress.emit(_current_table, true, parsed, "")
	_fetch_next()

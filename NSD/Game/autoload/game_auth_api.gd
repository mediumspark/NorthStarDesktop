extends Node

## Supabase Auth + profiles REST for in-game account UI. Uses a dedicated HTTPRequest (not [member SupabaseClient._http]).

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


func _headers_anon() -> PackedStringArray:
	return PackedStringArray([
		"apikey: %s" % SupabaseClient.get_anon_key(),
		"Content-Type: application/json",
		"Accept: application/json",
	])


func _headers_bearer(token: String) -> PackedStringArray:
	return PackedStringArray([
		"apikey: %s" % SupabaseClient.get_anon_key(),
		"Authorization: Bearer %s" % token,
		"Content-Type: application/json",
		"Accept: application/json",
	])


func _await_completed() -> Array:
	var out = await _http.request_completed
	if out is Array:
		return out
	return [out]


func recover_password(email: String) -> Dictionary:
	if not SupabaseClient.load_config():
		return {"ok": false, "error": "Missing Supabase config (secrets/supabase.local.json).", "code": 0}
	var url := "%s/auth/v1/recover" % SupabaseClient.get_base_url()
	var em := email.strip_edges()
	if em.is_empty():
		return {"ok": false, "error": "Enter an email address.", "code": 0}
	var body := JSON.stringify({"email": em})
	var err := _http.request(url, _headers_anon(), HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % err, "code": 0}
	var res := await _await_completed()
	return _parse_simple(res, [200, 204])


func fetch_profile() -> Dictionary:
	if not SupabaseClient.load_config():
		return {"ok": false, "error": "Missing Supabase config.", "code": 0}
	var token := SupabaseClient.get_user_access_token()
	var uid := SupabaseClient.get_session_user_id()
	if token.is_empty() or uid.is_empty():
		return {"ok": false, "error": "Not signed in.", "code": 0}
	var url := "%s/rest/v1/profiles?select=*&id=eq.%s" % [SupabaseClient.get_base_url(), uid]
	var err := _http.request(url, _headers_bearer(token), HTTPClient.METHOD_GET)
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % err, "code": 0}
	var res := await _await_completed()
	var parsed := _parse_simple(res, [200])
	if not parsed.ok:
		return parsed
	var rows = JSON.parse_string(str(parsed.get("body_str", "")))
	if typeof(rows) != TYPE_ARRAY:
		return {"ok": false, "error": "Bad profiles response.", "code": parsed.code}
	if rows.is_empty():
		return {"ok": true, "row": {}, "code": 200}
	return {"ok": true, "row": rows[0], "code": 200}


func patch_display_name(display_name: String) -> Dictionary:
	if not SupabaseClient.load_config():
		return {"ok": false, "error": "Missing Supabase config.", "code": 0}
	var token := SupabaseClient.get_user_access_token()
	var uid := SupabaseClient.get_session_user_id()
	if token.is_empty() or uid.is_empty():
		return {"ok": false, "error": "Not signed in.", "code": 0}
	var dn := display_name.strip_edges()
	if dn.is_empty():
		return {"ok": false, "error": "Display name cannot be empty.", "code": 0}
	var url := "%s/rest/v1/profiles?id=eq.%s" % [SupabaseClient.get_base_url(), uid]
	var body := JSON.stringify({"display_name": dn})
	var headers := _headers_bearer(token)
	headers.append("Prefer: return=minimal")
	var err := _http.request(url, headers, HTTPClient.METHOD_PATCH, body)
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % err, "code": 0}
	var res := await _await_completed()
	var parsed := _parse_simple(res, [200, 204])
	return parsed


## Re-authenticates with current password, updates password via Auth API, then persists session from password-grant tokens.
func change_password(email: String, current_password: String, new_password: String) -> Dictionary:
	if not SupabaseClient.load_config():
		return {"ok": false, "error": "Missing Supabase config.", "code": 0}
	var em := email.strip_edges()
	if em.is_empty() or current_password.is_empty() or new_password.is_empty():
		return {"ok": false, "error": "Fill in all password fields.", "code": 0}
	if new_password.length() < 8:
		return {"ok": false, "error": "New password must be at least 8 characters.", "code": 0}
	# 1) Password grant
	var token_url := "%s/auth/v1/token?grant_type=password" % SupabaseClient.get_base_url()
	var grant_body := JSON.stringify({"email": em, "password": current_password})
	var err := _http.request(token_url, _headers_anon(), HTTPClient.METHOD_POST, grant_body)
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % err, "code": 0}
	var res1 := await _await_completed()
	var p1 := _parse_simple(res1, [200])
	if not p1.ok:
		return {"ok": false, "error": _auth_error_message(p1.body_str, "Current password incorrect or email not confirmed."), "code": p1.code}
	var grant = JSON.parse_string(str(p1.body_str))
	if typeof(grant) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid auth response.", "code": 0}
	var access: String = str(grant.get("access_token", ""))
	if access.is_empty():
		return {"ok": false, "error": "No access token from sign-in.", "code": 0}
	# 2) Update password
	var user_url := "%s/auth/v1/user" % SupabaseClient.get_base_url()
	var patch_body := JSON.stringify({"password": new_password})
	err = _http.request(user_url, _headers_bearer(access), HTTPClient.METHOD_PUT, patch_body)
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % err, "code": 0}
	var res2 := await _await_completed()
	var p2 := _parse_simple(res2, [200])
	if not p2.ok:
		return {"ok": false, "error": _auth_error_message(p2.body_str, "Could not update password."), "code": p2.code}
	# Persist session (tokens from re-auth remain valid after password change).
	if not SupabaseClient.save_session_from_auth_token_response(grant):
		return {"ok": false, "error": "Password updated but could not save session file.", "code": 0}
	return {"ok": true, "error": "", "code": 200}


func _parse_simple(res: Array, ok_codes: Array = [200]) -> Dictionary:
	if res.size() < 4:
		return {"ok": false, "error": "Incomplete HTTP response.", "code": 0}
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	var body_str := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Network error (%s): %s" % [result, body_str.left(300)], "code": code, "body_str": body_str}
	if not ok_codes.has(code):
		return {"ok": false, "error": "HTTP %s: %s" % [code, body_str.left(400)], "code": code, "body_str": body_str}
	return {"ok": true, "code": code, "body_str": body_str}


func _auth_error_message(raw: String, fallback: String) -> String:
	var trimmed := str(raw).strip_edges()
	var j = JSON.parse_string(trimmed)
	if typeof(j) == TYPE_DICTIONARY:
		var d: Dictionary = j
		var msg: String = str(d.get("msg", d.get("error_description", d.get("message", d.get("error", "")))))
		if not msg.is_empty():
			return msg
	if not trimmed.is_empty():
		return trimmed.left(400)
	return fallback

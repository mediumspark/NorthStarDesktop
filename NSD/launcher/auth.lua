--[[ Supabase Auth: password + refresh_token via curl. ]]

local json = require("json")
local net = require("net_util")
local session = require("session")

local M = {}

function M.sign_in_with_password(base_url, anon_key, email, password)
	local url = base_url:gsub("/+$", "") .. "/auth/v1/token?grant_type=password"
	local ok_enc, payload = pcall(json.encode, { email = email, password = password })
	if not ok_enc then
		return nil, tostring(payload)
	end
	local raw, code = net.curl_post_json(url, anon_key, "_auth_body.json", payload)
	if not raw then
		return nil, "network error"
	end
	if code ~= 200 then
		local err_t, _, ej = json.decode(raw)
		local msg = raw:sub(1, 300)
		if type(err_t) == "table" then
			msg = tostring(err_t.error_description or err_t.error or msg)
		end
		return nil, "Auth HTTP " .. tostring(code) .. ": " .. msg
	end
	local body, _, jerr = json.decode(raw)
	if jerr or type(body) ~= "table" then
		return nil, "Invalid auth response JSON"
	end
	local sess, serr = session.from_auth_response(body, nil)
	if not sess then
		return nil, serr
	end
	return sess
end

--- Sign up. Returns session table if tokens returned; nil + "EMAIL_CONFIRM" if user must confirm email; nil + err otherwise.
function M.sign_up(base_url, anon_key, email, password, display_name)
	local url = base_url:gsub("/+$", "") .. "/auth/v1/signup"
	local req = { email = email, password = password }
	if type(display_name) == "string" and display_name ~= "" then
		-- Supabase GoTrue supports options.data for user_metadata on signup.
		req.options = { data = { display_name = display_name } }
	end
	local ok_enc, payload = pcall(json.encode, req)
	if not ok_enc then
		return nil, tostring(payload)
	end
	local raw, code = net.curl_post_json(url, anon_key, "_auth_signup.json", payload)
	if not raw then
		return nil, "network error"
	end
	if code ~= 200 then
		local err_t, _, _ = json.decode(raw)
		local msg = raw:sub(1, 300)
		if type(err_t) == "table" then
			msg = tostring(err_t.error_description or err_t.msg or err_t.message or err_t.error or msg)
		end
		return nil, "Sign up HTTP " .. tostring(code) .. ": " .. msg
	end
	local body, _, jerr = json.decode(raw)
	if jerr or type(body) ~= "table" then
		return nil, "Invalid sign-up response JSON"
	end
	-- Nested session (Supabase AuthResponse shape)
	local user_obj = body.user
	if type(body.session) == "table" and type(body.session.access_token) == "string" then
		local s = body.session
		body = {
			access_token = s.access_token,
			refresh_token = s.refresh_token,
			expires_in = s.expires_in,
			user = user_obj,
		}
	end
	if type(body.expires_in) ~= "number" then
		body.expires_in = 3600
	end
	if type(body.access_token) == "string" and body.access_token ~= "" then
		local sess, serr = session.from_auth_response(body, nil)
		if not sess then
			return nil, serr
		end
		return sess
	end
	-- Email confirmation required, or user payload without session
	if type(body.user) == "table" or type(body.id) == "string" then
		return nil, "EMAIL_CONFIRM"
	end
	return nil, "Unexpected sign-up response (no session)"
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- GET /auth/v1/user — returns user table or nil, err
function M.fetch_auth_user(base_url, anon_key, access_token)
	local url = base_url:gsub("/+$", "") .. "/auth/v1/user"
	local raw, rc = net.curl_get_bearer(url, anon_key, access_token)
	if not raw then
		return nil, "curl failed"
	end
	if rc ~= 0 then
		return nil, "curl rc " .. tostring(rc)
	end
	local body, _, jerr = json.decode(raw)
	if jerr or type(body) ~= "table" then
		return nil, "invalid user JSON"
	end
	if type(body.error) == "string" or type(body.msg) == "string" then
		return nil, trim(body.error or body.msg or "auth user error")
	end
	return body, nil
end

function M.user_metadata_display_name(user_tbl)
	if type(user_tbl) ~= "table" then
		return ""
	end
	local m = user_tbl.user_metadata
	if type(m) ~= "table" then
		return ""
	end
	local v = m.display_name or m["display_name"]
	return trim(v)
end

--- Try POST profiles (requires RLS insert for auth.uid()). Optional display_name.
function M.try_insert_profile_row(base_url, anon_key, access_token, user_id, display_name)
	local q_id = user_id:gsub("[^%w%-]", "")
	if q_id == "" then
		return false, "invalid user id"
	end
	local url = base_url:gsub("/+$", "") .. "/rest/v1/profiles"
	local row = { id = q_id }
	if type(display_name) == "string" and trim(display_name) ~= "" then
		row.display_name = trim(display_name)
	end
	local ok_enc, payload = pcall(json.encode, row)
	if not ok_enc then
		return false, tostring(payload)
	end
	local raw, code = net.curl_post_json_user(url, anon_key, access_token, "_profile_insert.json", payload)
	if raw == nil then
		return false, "network error"
	end
	if code and code >= 200 and code < 300 then
		return true
	end
	local msg = raw:sub(1, 400)
	local err_t, _, _ = json.decode(raw)
	if type(err_t) == "table" then
		msg = tostring(err_t.message or err_t.hint or msg)
	end
	return false, "HTTP " .. tostring(code) .. ": " .. msg
end

--- PATCH profiles.display_name for own row (RLS update). Returns true on 2xx.
function M.try_patch_profile_display_name(base_url, anon_key, access_token, user_id, display_name)
	local q_id = user_id:gsub("[^%w%-]", "")
	if q_id == "" then
		return false, "invalid user id"
	end
	local dn = trim(display_name)
	if dn == "" then
		return false, "empty display_name"
	end
	local url = base_url:gsub("/+$", "") .. "/rest/v1/profiles?id=eq." .. q_id
	local ok_enc, payload = pcall(json.encode, { display_name = dn })
	if not ok_enc then
		return false, tostring(payload)
	end
	local raw, code = net.curl_patch_json_user(url, anon_key, access_token, "_profile_patch.json", payload)
	if raw == nil then
		return false, "network error"
	end
	if code and code >= 200 and code < 300 then
		return true
	end
	local msg = raw:sub(1, 400)
	local err_t, _, _ = json.decode(raw)
	if type(err_t) == "table" then
		msg = tostring(err_t.message or err_t.hint or msg)
	end
	return false, "HTTP " .. tostring(code) .. ": " .. msg
end

--- If profiles.display_name is blank but Auth user_metadata has display_name, INSERT or PATCH it.
function M.try_sync_profile_display_name_from_auth(base_url, anon_key, access_token, user_id)
	local user, uerr = M.fetch_auth_user(base_url, anon_key, access_token)
	if not user then
		return false, uerr
	end
	local dn = M.user_metadata_display_name(user)
	if dn == "" then
		return true
	end
	local rows, perr = M.fetch_profile_row(base_url, anon_key, access_token, user_id)
	if perr then
		return false, perr
	end
	if type(rows) ~= "table" then
		return false, "bad profile response"
	end
	if type(rows[1]) ~= "table" then
		local ok_ins, ierr = M.try_insert_profile_row(base_url, anon_key, access_token, user_id, dn)
		if ok_ins then
			return true
		end
		rows, perr = M.fetch_profile_row(base_url, anon_key, access_token, user_id)
		if perr or type(rows) ~= "table" or type(rows[1]) ~= "table" then
			return false, ierr
		end
	end
	local cur = rows[1].display_name
	if type(cur) == "string" and trim(cur) ~= "" then
		return true
	end
	return M.try_patch_profile_display_name(base_url, anon_key, access_token, user_id, dn)
end

function M.refresh_session(base_url, anon_key, refresh_token)
	local url = base_url:gsub("/+$", "") .. "/auth/v1/token?grant_type=refresh_token"
	local ok_enc, payload = pcall(json.encode, { refresh_token = refresh_token })
	if not ok_enc then
		return nil, tostring(payload)
	end
	local raw, code = net.curl_post_json(url, anon_key, "_auth_refresh.json", payload)
	if not raw then
		return nil, "network error"
	end
	if code ~= 200 then
		local err_t, _, _ = json.decode(raw)
		local msg = raw:sub(1, 300)
		if type(err_t) == "table" then
			msg = tostring(err_t.error_description or err_t.error or msg)
		end
		return nil, "Refresh HTTP " .. tostring(code) .. ": " .. msg
	end
	local body, _, jerr = json.decode(raw)
	if jerr or type(body) ~= "table" then
		return nil, "Invalid refresh response JSON"
	end
	local sess, serr = session.from_auth_response(body, refresh_token)
	if not sess then
		return nil, serr
	end
	return sess
end

--- GET profiles for user id; returns rows array or nil, err
function M.fetch_profile_row(base_url, anon_key, access_token, user_id)
	local q_id = user_id:gsub("[^%w%-]", "")
	if q_id == "" then
		return nil, "invalid user id"
	end
	local url = base_url:gsub("/+$", "") .. "/rest/v1/profiles?select=*&id=eq." .. q_id
	local raw, rc = net.curl_get_bearer(url, anon_key, access_token)
	if not raw then
		return nil, "curl failed"
	end
	if rc ~= 0 then
		return nil, "curl rc " .. tostring(rc)
	end
	local arr, _, jerr = json.decode(raw)
	if jerr then
		return nil, tostring(jerr)
	end
	if type(arr) == "table" and arr.code and arr.message then
		return nil, tostring(arr.message or "API error")
	end
	if type(arr) ~= "table" then
		return nil, "expected array"
	end
	return arr
end

return M

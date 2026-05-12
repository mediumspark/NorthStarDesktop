--[[ Session file read/write + expiry (NorthStarDesktop/data/session.json). ]]

local json = require("json")
local net = require("net_util")

local M = {}

local SKEW = 120

function M.path_for_godot_root(godot_root)
	return (godot_root .. "/data/session.json"):gsub("\\", "/")
end

function M.is_expired(sess)
	if type(sess) ~= "table" then
		return true
	end
	local exp = sess.expires_at
	if type(exp) ~= "number" then
		return true
	end
	return os.time() >= (exp - SKEW)
end

function M.load_from_disk(path)
	local raw = net.read_file_bin(path)
	if not raw or raw == "" then
		return nil
	end
	local t, _, err = json.decode(raw)
	if err or type(t) ~= "table" then
		return nil
	end
	return t
end

function M.save_to_disk(path, sess)
	local ok_enc, encoded = pcall(json.encode, sess)
	if not ok_enc then
		return false, tostring(encoded)
	end
	return net.write_file_bin(path, encoded)
end

function M.delete_disk(path)
	net.remove_file(path)
end

--- Build session table from Supabase auth token response.
--- If refresh is omitted in the JSON (some refresh responses), pass previous refresh as [fallback_refresh].
function M.from_auth_response(body_tbl, fallback_refresh)
	local at = body_tbl.access_token
	local rt = body_tbl.refresh_token
	if (type(rt) ~= "string" or rt == "") and type(fallback_refresh) == "string" then
		rt = fallback_refresh
	end
	local ei = body_tbl.expires_in
	if type(at) ~= "string" or type(ei) ~= "number" then
		return nil, "missing token fields"
	end
	if type(rt) ~= "string" then
		rt = ""
	end
	local user = body_tbl.user
	local uid, email = "", ""
	if type(user) == "table" then
		uid = tostring(user.id or "")
		email = tostring(user.email or "")
	end
	return {
		access_token = at,
		refresh_token = rt,
		expires_at = os.time() + math.floor(ei),
		user = { id = uid, email = email },
	}
end

return M

--[[ Shared curl/FFI helpers for the launcher. ]]

local ffi = require("ffi")
ffi.cdef[[
typedef struct FILE FILE;
FILE *popen(const char *command, const char *mode);
int pclose(FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
FILE *fopen(const char *path, const char *mode);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int fclose(FILE *stream);
char *getenv(const char *name);
int system(const char *command);
int remove(const char *path);
]]

local M = {}

function M.is_windows()
	return love.system.getOS() == "Windows"
end

function M.sh_quote(s)
	return "'" .. string.gsub(s, "'", "'\"'\"'") .. "'"
end

function M.win_quote(s)
	return '"' .. string.gsub(s, '"', '\\"') .. '"'
end

function M.getenv_c(name)
	local p = ffi.C.getenv(name)
	if p == nil then
		return nil
	end
	return ffi.string(p)
end

function M.popen_read(cmd)
	local pipe = ffi.C.popen(cmd, "r")
	if pipe == nil then
		return nil, "popen failed"
	end
	local parts = {}
	local buf = ffi.new("char[16384]")
	while true do
		local n = ffi.C.fread(buf, 1, 16384, pipe)
		if n == 0 then
			break
		end
		parts[#parts + 1] = ffi.string(buf, n)
	end
	local rc = ffi.C.pclose(pipe)
	return table.concat(parts), rc
end

function M.write_file_bin(path, content)
	local f = ffi.C.fopen(path, "wb")
	if f == nil then
		return false, "fopen failed for " .. path
	end
	local n = #content
	if n > 0 then
		local buf = ffi.new("char[?]", n)
		ffi.copy(buf, content, n)
		ffi.C.fwrite(buf, 1, n, f)
	end
	ffi.C.fclose(f)
	return true
end

function M.read_file_bin(path)
	local f = ffi.C.fopen(path, "rb")
	if f == nil then
		return nil
	end
	local parts = {}
	local buf = ffi.new("char[8192]")
	while true do
		local n = ffi.C.fread(buf, 1, 8192, f)
		if n == 0 then
			break
		end
		parts[#parts + 1] = ffi.string(buf, n)
	end
	ffi.C.fclose(f)
	return table.concat(parts)
end

function M.remove_file(path)
	ffi.C.remove(path)
end

function M.file_exists(path)
	if path == nil then
		return false
	end
	-- Defensive: avoid LuaJIT FFI crash if callers pass non-strings.
	if type(path) ~= "string" then
		path = tostring(path)
	end
	if path == "" then
		return false
	end
	local f = ffi.C.fopen(path, "rb")
	if f == nil then
		return false
	end
	ffi.C.fclose(f)
	return true
end

--- Write a temp JSON body for curl --data-binary @path (Love save dir).
function M.write_request_body(filename, content)
	love.filesystem.write(filename, content)
	return love.filesystem.getSaveDirectory() .. "/" .. filename
end

--- POST with JSON body file; returns response_body, http_code (number or nil), curl_rc
function M.curl_post_json(url, anon_key, body_relpath_for_write, json_body)
	local abs = M.write_request_body(body_relpath_for_write, json_body)
	local cmd
	if M.is_windows() then
		cmd = string.format(
			"curl.exe -sS -X POST %s %s %s --data-binary @%s %s",
			"-H " .. M.win_quote("apikey: " .. anon_key),
			"-H " .. M.win_quote("Content-Type: application/json"),
			"-H " .. M.win_quote("Accept: application/json"),
			M.win_quote(abs),
			M.win_quote(url)
		)
	else
		cmd = string.format(
			"curl -sS -X POST %s %s %s --data-binary @%s %s",
			"-H " .. M.sh_quote("apikey: " .. anon_key),
			"-H " .. M.sh_quote("Content-Type: application/json"),
			"-H " .. M.sh_quote("Accept: application/json"),
			M.sh_quote(abs),
			M.sh_quote(url)
		)
	end
	cmd = cmd .. " -w " .. (M.is_windows() and M.win_quote("\nHTTPSTATUS:%{http_code}") or M.sh_quote("\nHTTPSTATUS:%{http_code}"))
	local raw, rc = M.popen_read(cmd)
	if not raw then
		return nil, nil, rc
	end
	local code = tonumber(raw:match("HTTPSTATUS:(%d+)%s*$"))
	raw = raw:gsub("\nHTTPSTATUS:%d+%s*$", "")
	return raw, code, rc
end

--- POST JSON as authenticated user (JWT) + anon apikey (PostgREST RLS).
function M.curl_post_json_user(url, anon_key, access_token, body_relpath_for_write, json_body)
	local abs = M.write_request_body(body_relpath_for_write, json_body)
	local cmd
	if M.is_windows() then
		cmd = string.format(
			"curl.exe -sS -X POST %s %s %s %s --data-binary @%s %s",
			"-H " .. M.win_quote("apikey: " .. anon_key),
			"-H " .. M.win_quote("Authorization: Bearer " .. access_token),
			"-H " .. M.win_quote("Content-Type: application/json"),
			"-H " .. M.win_quote("Accept: application/json"),
			"-H " .. M.win_quote("Prefer: return=minimal"),
			M.win_quote(abs),
			M.win_quote(url)
		)
	else
		cmd = string.format(
			"curl -sS -X POST %s %s %s %s --data-binary @%s %s",
			"-H " .. M.sh_quote("apikey: " .. anon_key),
			"-H " .. M.sh_quote("Authorization: Bearer " .. access_token),
			"-H " .. M.sh_quote("Content-Type: application/json"),
			"-H " .. M.sh_quote("Accept: application/json"),
			"-H " .. M.sh_quote("Prefer: return=minimal"),
			M.sh_quote(abs),
			M.sh_quote(url)
		)
	end
	cmd = cmd .. " -w " .. (M.is_windows() and M.win_quote("\nHTTPSTATUS:%{http_code}") or M.sh_quote("\nHTTPSTATUS:%{http_code}"))
	local raw, rc = M.popen_read(cmd)
	if not raw then
		return nil, nil, rc
	end
	local code = tonumber(raw:match("HTTPSTATUS:(%d+)%s*$"))
	raw = raw:gsub("\nHTTPSTATUS:%d+%s*$", "")
	return raw, code, rc
end

--- PATCH JSON as authenticated user (JWT) + anon apikey (PostgREST RLS).
function M.curl_patch_json_user(url, anon_key, access_token, body_relpath_for_write, json_body)
	local abs = M.write_request_body(body_relpath_for_write, json_body)
	local cmd
	if M.is_windows() then
		cmd = string.format(
			"curl.exe -sS -X PATCH %s %s %s %s --data-binary @%s %s",
			"-H " .. M.win_quote("apikey: " .. anon_key),
			"-H " .. M.win_quote("Authorization: Bearer " .. access_token),
			"-H " .. M.win_quote("Content-Type: application/json"),
			"-H " .. M.win_quote("Accept: application/json"),
			"-H " .. M.win_quote("Prefer: return=minimal"),
			M.win_quote(abs),
			M.win_quote(url)
		)
	else
		cmd = string.format(
			"curl -sS -X PATCH %s %s %s %s --data-binary @%s %s",
			"-H " .. M.sh_quote("apikey: " .. anon_key),
			"-H " .. M.sh_quote("Authorization: Bearer " .. access_token),
			"-H " .. M.sh_quote("Content-Type: application/json"),
			"-H " .. M.sh_quote("Accept: application/json"),
			"-H " .. M.sh_quote("Prefer: return=minimal"),
			M.sh_quote(abs),
			M.sh_quote(url)
		)
	end
	cmd = cmd .. " -w " .. (M.is_windows() and M.win_quote("\nHTTPSTATUS:%{http_code}") or M.sh_quote("\nHTTPSTATUS:%{http_code}"))
	local raw, rc = M.popen_read(cmd)
	if not raw then
		return nil, nil, rc
	end
	local code = tonumber(raw:match("HTTPSTATUS:(%d+)%s*$"))
	raw = raw:gsub("\nHTTPSTATUS:%d+%s*$", "")
	return raw, code, rc
end

--- GET with Bearer JWT (and anon apikey).
function M.curl_get_bearer(url, anon_key, access_token)
	local cmd
	if M.is_windows() then
		cmd = string.format(
			"curl.exe -sS %s %s %s %s",
			"-H " .. M.win_quote("apikey: " .. anon_key),
			"-H " .. M.win_quote("Authorization: Bearer " .. access_token),
			"-H " .. M.win_quote("Accept: application/json"),
			M.win_quote(url)
		)
	else
		cmd = string.format(
			"curl -sS %s %s %s %s",
			"-H " .. M.sh_quote("apikey: " .. anon_key),
			"-H " .. M.sh_quote("Authorization: Bearer " .. access_token),
			"-H " .. M.sh_quote("Accept: application/json"),
			M.sh_quote(url)
		)
	end
	local raw, rc = M.popen_read(cmd)
	return raw, rc
end

function M.system(cmd)
	ffi.C.system(cmd)
end

--- Public REST GET with anon key as Bearer (catalog sync). Uses curl -f.
function M.curl_get_rest_anon(url, anon_key)
	local cmd
	if M.is_windows() then
		cmd = string.format(
			"curl.exe -sS -f %s %s %s %s",
			"-H " .. M.win_quote("apikey: " .. anon_key),
			"-H " .. M.win_quote("Authorization: Bearer " .. anon_key),
			"-H " .. M.win_quote("Accept: application/json"),
			M.win_quote(url)
		)
	else
		cmd = string.format(
			"curl -sS -f %s %s %s %s",
			"-H " .. M.sh_quote("apikey: " .. anon_key),
			"-H " .. M.sh_quote("Authorization: Bearer " .. anon_key),
			"-H " .. M.sh_quote("Accept: application/json"),
			M.sh_quote(url)
		)
	end
	return M.popen_read(cmd)
end

return M

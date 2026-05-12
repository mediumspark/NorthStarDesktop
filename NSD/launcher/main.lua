--[[
  Love2D launcher: Supabase login, optional profiles check, catalog sync,
  writes data/catalog_cache.json + data/session.json next to the game build.
  Reads secrets from disk (no Love filesystem mount of the project).
]]

package.path = love.filesystem.getSourceBaseDirectory() .. "/?.lua;" .. package.path
local json = require("json")
local net = require("net_util")
local session = require("session")
local auth = require("auth")

local TABLES = {
	"cards",
	"chef_cards",
	"event_cards",
	"meal_cards",
	"restaurant_cards",
	"staff_cards",
	"support_cards",
}

local screen = "login" -- "login" | "main"
local status_lines = { "" }
local buttons = {}

local godot_root = ""
local cache_path = ""
local session_path = ""
local supabase_url = ""
local supabase_key = ""

local active_session = nil
local login_email = ""
local login_password = ""
local login_confirm = ""
local login_display_name = ""
local auth_mode = "login" -- "login" | "register" (within the login screen)
local login_focus = "email"
local profile_hint = ""

local syncing = false
local auth_busy = false

local UI = {
	name_rect = { x = 100, y = 158, w = 400, h = 26 },
	email_rect = { x = 100, y = 208, w = 400, h = 26 },
	pass_rect = { x = 100, y = 258, w = 400, h = 26 },
	confirm_rect = { x = 100, y = 308, w = 400, h = 26 },
}

local function set_status(lines)
	status_lines = lines
end

local function is_register_mode()
	return auth_mode == "register"
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_display_name(s)
	s = trim(s)
	s = s:gsub("[%c]", "")
	-- collapse repeated whitespace
	s = s:gsub("%s%s+", " ")
	return s
end

local function validate_registration_inputs()
	local dn = normalize_display_name(login_display_name)
	if dn == "" then
		return false, "Enter a display name."
	end
	if #dn < 3 or #dn > 24 then
		return false, "Display name must be 3–24 characters."
	end
	if dn:match("[^%w%_ %-%']") then
		return false, "Display name can use letters, numbers, space, _, -, '."
	end
	if trim(login_email) == "" then
		return false, "Enter email."
	end
	if login_password == "" then
		return false, "Enter password."
	end
	if #login_password < 8 then
		return false, "Password must be at least 8 characters."
	end
	if login_password ~= login_confirm then
		return false, "Passwords do not match."
	end
	return true, dn
end

--- Parent of the folder that contains this Love2D app (e.g. .../NorthStarDesktop/Launcher -> .../NorthStarDesktop).
local function launcher_parent_dir()
	local base = love.filesystem.getSourceBaseDirectory():gsub("\\", "/"):gsub("/$", "")
	local parent = base:match("^(.*)/[^/]+$")
	if parent and parent ~= "" then
		return parent
	end
	return (base .. "/.."):gsub("\\", "/")
end

local function dir_parent(p)
	p = (p or ""):gsub("\\", "/"):gsub("/$", "")
	return p:match("^(.*)/[^/]+$") or ""
end

local function has_game_markers(root)
	if root == "" then
		return false
	end
	root = root:gsub("\\", "/"):gsub("/$", "")
	-- Prefer exported builds if present; else fall back to Godot project markers.
	if net.file_exists(root .. "/build/README.txt") then
		return true
	end
	if net.file_exists(root .. "/project.godot") then
		return true
	end
	if net.file_exists(root .. "/secrets/supabase.local.json") or net.file_exists(root .. "/secrets/supabase.local.example.json") then
		return true
	end
	-- Linux export next to repo root (sibling of nested Godot project folder).
	if net.file_exists(root .. "/Builds/LinuxBuild.x86_64") then
		return true
	end
	-- Same when the marker root is a parent folder (e.g. Desktop) and the game lives under NorthStarDesktop/.
	if net.file_exists(root .. "/NorthStarDesktop/Builds/LinuxBuild.x86_64") then
		return true
	end
	return false
end

--- Resolve the game root on disk even if the launcher is run from Desktop/shortcuts.
--- Prefer a folder that contains project.godot. A parent folder can wrongly match
--- has_game_markers (e.g. via …/NorthStarDesktop/Builds/…) while data/ must live next to the real project.
local function resolve_godot_root()
	local base = love.filesystem.getSourceBaseDirectory():gsub("\\", "/"):gsub("/$", "")
	local parent = dir_parent(base)

	local function norm(p)
		return (p or ""):gsub("\\", "/"):gsub("/$", "")
	end

	-- 1) Direct project.godot paths (most reliable).
	local inner = norm(parent .. "/NorthStarDesktop/project.godot")
	if inner ~= "" and net.file_exists(inner) then
		return norm(parent .. "/NorthStarDesktop")
	end
	local flat = norm(parent .. "/project.godot")
	if flat ~= "" and net.file_exists(flat) then
		return norm(parent)
	end
	local base_flat = norm(base .. "/project.godot")
	if base_flat ~= "" and net.file_exists(base_flat) then
		return norm(base)
	end
	local base_inner = norm(base .. "/NorthStarDesktop/project.godot")
	if base_inner ~= "" and net.file_exists(base_inner) then
		return norm(base .. "/NorthStarDesktop")
	end

	-- 2) Candidate roots — nested Godot project *before* parent-only markers (Builds/ hack).
	local candidates = {
		parent .. "/NorthStarDesktop",
		parent,
		base,
		base .. "/NorthStarDesktop",
	}

	for _, c in ipairs(candidates) do
		c = norm(c)
		if c ~= "" and has_game_markers(c) then
			return c
		end
	end

	-- 3) Walk upward; prefer explicit project.godot, then loose markers.
	local cur = norm(parent)
	for _ = 1, 6 do
		if cur == "" then
			break
		end
		local nested_proj = norm(cur .. "/NorthStarDesktop/project.godot")
		if nested_proj ~= "" and net.file_exists(nested_proj) then
			return norm(cur .. "/NorthStarDesktop")
		end
		if net.file_exists(norm(cur .. "/project.godot")) then
			return cur
		end
		if has_game_markers(cur) then
			return cur
		end
		local nested = norm(cur .. "/NorthStarDesktop")
		if nested ~= "" and has_game_markers(nested) then
			return nested
		end
		cur = norm(dir_parent(cur))
	end

	-- Fallback: keep old behavior (parent of launcher).
	return norm(launcher_parent_dir())
end

local function ensure_data_dir()
	if net.is_windows() then
		local p = net.win_quote(godot_root .. "\\data")
		net.system("if not exist " .. p .. " mkdir " .. p)
	else
		net.system("mkdir -p " .. net.sh_quote(godot_root .. "/data"))
	end
end

--- Game root on disk (secrets, data/, build/) — no Love mount; paths read via net_util.
local function init_launcher_paths()
	godot_root = resolve_godot_root()
	cache_path = (godot_root .. "/data/catalog_cache.json"):gsub("\\", "/")
	session_path = session.path_for_godot_root(godot_root)
	return true
end

local function try_load_secrets()
	local sec_path = (godot_root .. "/secrets/supabase.local.json"):gsub("\\", "/")
	if not net.file_exists(sec_path) then
		set_status({
			"Missing secrets file:",
			"  " .. sec_path,
			"Copy secrets/supabase.local.example.json and add URL + anon key.",
		})
		return false
	end
	local raw = net.read_file_bin(sec_path)
	if not raw then
		set_status({ "Could not read supabase.local.json" })
		return false
	end
	local cfg, _, cerr = json.decode(raw)
	if cerr or type(cfg) ~= "table" then
		set_status({ "Invalid JSON in supabase.local.json", tostring(cerr) })
		return false
	end
	supabase_url = tostring(cfg.supabase_url or ""):gsub("/+$", "")
	supabase_key = tostring(cfg.supabase_anon_key or "")
	if supabase_url == "" or supabase_key == "" then
		set_status({ "supabase_url and supabase_anon_key required in secrets file." })
		return false
	end
	return true
end

local function save_session_disk()
	if not active_session then
		return
	end
	ensure_data_dir()
	local ok, werr = session.save_to_disk(session_path, active_session)
	if not ok then
		set_status({ "Could not save session: " .. tostring(werr) })
	end
end

local function profile_display_name_from_row(row)
	if type(row) ~= "table" then
		return ""
	end
	local v = row.display_name
	if v == nil then
		return ""
	end
	return trim(tostring(v))
end

local function apply_profile_hint(user_id)
	profile_hint = ""
	if not active_session or supabase_url == "" then
		return
	end
	local rows, err = auth.fetch_profile_row(supabase_url, supabase_key, active_session.access_token, user_id)
	if err then
		profile_hint = "profiles check failed: " .. tostring(err)
		return
	end
	if type(rows) ~= "table" then
		return
	end
	if type(rows.message) == "string" and (rows.code or rows.hint) then
		profile_hint = "profiles: " .. rows.message
		return
	end
	if type(rows[1]) == "table" then
		local dn = profile_display_name_from_row(rows[1])
		profile_hint = "profiles: OK"
		if dn == "" then
			local ok_sync, serr = auth.try_sync_profile_display_name_from_auth(supabase_url, supabase_key, active_session.access_token, user_id)
			if ok_sync then
				local rows3, e3 = auth.fetch_profile_row(supabase_url, supabase_key, active_session.access_token, user_id)
				if not e3 and type(rows3) == "table" and type(rows3[1]) == "table" then
					dn = profile_display_name_from_row(rows3[1])
				end
			end
			if dn ~= "" then
				profile_hint = "profiles: OK — display name: " .. dn
			elseif not ok_sync then
				profile_hint = "profiles: OK — display name missing (sync failed: " .. tostring(serr) .. ")"
			end
		end
		return
	end
	if next(rows) == nil then
		local meta_dn = ""
		local au, _ = auth.fetch_auth_user(supabase_url, supabase_key, active_session.access_token)
		if au then
			meta_dn = auth.user_metadata_display_name(au)
		end
		local ok_ins, ierr = auth.try_insert_profile_row(supabase_url, supabase_key, active_session.access_token, user_id, meta_dn)
		if ok_ins then
			local ok_sync, _ = auth.try_sync_profile_display_name_from_auth(supabase_url, supabase_key, active_session.access_token, user_id)
			local rows2, err2 = auth.fetch_profile_row(supabase_url, supabase_key, active_session.access_token, user_id)
			if not err2 and type(rows2) == "table" and type(rows2[1]) == "table" then
				local dn2 = profile_display_name_from_row(rows2[1])
				profile_hint = "profiles: OK (row created via API)"
				if dn2 ~= "" then
					profile_hint = profile_hint .. " — display name: " .. dn2
				elseif not ok_sync and meta_dn ~= "" then
					profile_hint = profile_hint .. " — display name not saved (check RLS / column display_name)"
				end
			else
				profile_hint = "profiles: insert OK; re-check: " .. tostring(err2 or "still empty")
			end
		else
			profile_hint = "No profiles row — " .. tostring(ierr) .. " — add a DB trigger (see supabase/profiles_trigger_example.sql) or RLS insert policy."
		end
	else
		profile_hint = "profiles: OK"
	end
end

local function go_main_after_auth(sess)
	active_session = sess
	save_session_disk()
	local uid = ""
	if type(sess.user) == "table" then
		uid = tostring(sess.user.id or "")
	end
	apply_profile_hint(uid)
	screen = "main"
	local em = ""
	if type(sess.user) == "table" then
		em = tostring(sess.user.email or "")
	end
	set_status({
		"Logged in as " .. (em ~= "" and em or uid),
		profile_hint,
		"Game folder: " .. godot_root,
		"Sync then Start game.",
	})
end

local function try_restore_session()
	local sess = session.load_from_disk(session_path)
	if not sess then
		return false
	end
	if not session.is_expired(sess) then
		go_main_after_auth(sess)
		return true
	end
	local rt = sess.refresh_token
	if type(rt) ~= "string" or rt == "" then
		return false
	end
	local new_sess, err = auth.refresh_session(supabase_url, supabase_key, rt)
	if not new_sess then
		set_status({ "Session expired; refresh failed: " .. tostring(err), "Please sign in again." })
		session.delete_disk(session_path)
		return false
	end
	go_main_after_auth(new_sess)
	return true
end

local function do_login()
	if auth_busy or supabase_url == "" then
		return
	end
	login_email = trim(login_email)
	if login_email == "" or login_password == "" then
		set_status({
			"Login: enter email and password.",
			"Use Register if you need a new account.",
		})
		return
	end
	auth_busy = true
	set_status({ "Signing in…" })
	local em = login_email
	local sess, err = auth.sign_in_with_password(supabase_url, supabase_key, em, login_password)
	auth_busy = false
	if not sess then
		local msg = tostring(err)
		if msg:match("Email not confirmed") or msg:lower():match("confirm") then
			set_status({
				"Login failed: email not confirmed yet.",
				"Open the link in your inbox, then try Login again.",
				"Details: " .. msg,
			})
		else
			set_status({ "Login failed:", msg })
		end
		return
	end
	login_password = ""
	login_confirm = ""
	go_main_after_auth(sess)
end

local function do_register()
	if auth_busy or supabase_url == "" then
		return
	end
	local ok, dn_or_err = validate_registration_inputs()
	if not ok then
		local tip = tostring(dn_or_err)
		set_status({
			"Register: fix the following —",
			tip,
			"Display name: 3–24 chars (letters, numbers, space, _, -, ').",
			"Password: at least 8 characters; must match Confirm.",
		})
		return
	end
	local display_name = dn_or_err
	auth_busy = true
	set_status({ "Creating account…", "Do not close the launcher until this finishes." })
	local sess, err = auth.sign_up(supabase_url, supabase_key, trim(login_email), login_password, display_name)
	auth_busy = false
	if err == "EMAIL_CONFIRM" then
		login_password = ""
		login_confirm = ""
		set_status({
			"Account created for " .. trim(login_email) .. ".",
			"Display name sent with signup: " .. display_name .. " (saved after you confirm).",
			"Next: open the confirmation email and click the link.",
			"Then return here and use Login.",
		})
		return
	end
	if not sess then
		local msg = tostring(err)
		if msg:match("already registered") or msg:lower():match("already") then
			set_status({
				"Sign up failed: that email may already be registered.",
				"Try Login, or use “Forgot password” in Supabase / your provider.",
				"Details: " .. msg,
			})
		else
			set_status({
				"Sign up failed. Check email format, password rules, and network.",
				"Details: " .. msg,
			})
		end
		return
	end
	login_password = ""
	login_confirm = ""
	go_main_after_auth(sess)
end

local function do_logout()
	active_session = nil
	profile_hint = ""
	session.delete_disk(session_path)
	screen = "login"
	set_status({ "Signed out. Enter credentials." })
end

local function curl_fetch_table(table_name)
	local url = supabase_url .. "/rest/v1/" .. table_name
	local body, rc = net.curl_get_rest_anon(url, supabase_key)
	if not body then
		return nil, rc or "curl failed"
	end
	if rc ~= 0 then
		return nil, "curl exit " .. tostring(rc) .. ": " .. body:sub(1, 400)
	end
	local arr, _, jerr = json.decode(body)
	if jerr then
		return nil, "JSON: " .. tostring(jerr)
	end
	if type(arr) ~= "table" then
		return nil, "expected JSON array for " .. table_name
	end
	return arr
end

local function do_sync()
	if not active_session or session.is_expired(active_session) then
		set_status({ "Sign in before syncing." })
		return
	end
	if syncing then
		return
	end
	if supabase_url == "" then
		return
	end
	syncing = true
	love.keyboard.setTextInput(false)
	set_status({ "Syncing…" })

	local out = {
		version = 1,
		fetched_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		tables = {},
	}

	local ok_all = true
	for _, tname in ipairs(TABLES) do
		local rows, err = curl_fetch_table(tname)
		if not rows then
			ok_all = false
			set_status({ "Failed on " .. tname .. ":", tostring(err) })
			break
		end
		out.tables[tname] = rows
	end

	if ok_all then
		ensure_data_dir()
		local ok_enc, encoded = pcall(json.encode, out)
		if not ok_enc then
			set_status({ "encode error", tostring(encoded) })
		else
			local wok, werr = net.write_file_bin(cache_path, encoded)
			if wok then
				local counts = {}
				for _, t in ipairs(TABLES) do
					counts[#counts + 1] = t .. "=" .. tostring(#out.tables[t])
				end
				local lines = {
					"Saved " .. cache_path,
					"Rows: " .. table.concat(counts, " "),
				}
				if profile_hint ~= "" then
					table.insert(lines, 1, profile_hint)
				end
				if active_session and type(active_session.user) == "table" then
					local em = active_session.user.email or ""
					if em ~= "" then
						table.insert(lines, 1, "Logged in as " .. em)
					end
				end
				set_status(lines)
			else
				set_status({ "Write failed:", werr })
			end
		end
	end
	syncing = false
end

--- Exported game paths under [godot_root]/build (see build/README.txt).
local function resolve_build_executable()
	local root = (godot_root .. "/build"):gsub("\\", "/")
	local osys = love.system.getOS()
	if osys == "Windows" then
		local p = (root .. "/windows/NorthStarDesktop.exe"):gsub("/", "\\")
		if net.file_exists(p) then
			return p, "export"
		end
	elseif osys == "OS X" then
		local inner = root .. "/macos/NorthStarDesktop.app/Contents/MacOS/NorthStarDesktop"
		if net.file_exists(inner) then
			return inner, "export"
		end
		local app = root .. "/macos/NorthStarDesktop.app"
		local out, rc = net.popen_read("test -d " .. net.sh_quote(app) .. " && echo OK")
		if rc == 0 and out and out:match("OK") then
			return app, "macapp"
		end
	else
		-- Preferred Linux export: .../NorthStarDesktop/Builds/LinuxBuild.x86_64 (and variants).
		-- Covers: launcher under Desktop, nested godot_root, Builds sibling of inner project, etc.
		local gr = godot_root:gsub("\\", "/")
		local lp = launcher_parent_dir():gsub("\\", "/")
		local parent_of_root = dir_parent(gr)
		local parent_of_launcher = dir_parent(lp)
		for _, p in ipairs({
			lp .. "/Builds/LinuxBuild.x86_64",
			lp .. "/NorthStarDesktop/Builds/LinuxBuild.x86_64",
			gr .. "/Builds/LinuxBuild.x86_64",
			gr .. "/NorthStarDesktop/Builds/LinuxBuild.x86_64",
			(parent_of_root ~= "" and (parent_of_root .. "/Builds/LinuxBuild.x86_64") or ""),
			(parent_of_root ~= "" and (parent_of_root .. "/NorthStarDesktop/Builds/LinuxBuild.x86_64") or ""),
			(parent_of_launcher ~= "" and (parent_of_launcher .. "/NorthStarDesktop/Builds/LinuxBuild.x86_64") or ""),
		}) do
			if p ~= "" and net.file_exists(p) then
				return p, "export"
			end
		end
		for _, rel in ipairs({ "/linux/NorthStarDesktop", "/linux/NorthStarDesktop.x86_64" }) do
			local p = root .. rel
			if net.file_exists(p) then
				return p, "export"
			end
		end
	end
	return nil, nil
end

local function do_start_godot()
	if not active_session or session.is_expired(active_session) then
		set_status({ "Sign in before starting the game." })
		return
	end
	local proj = (godot_root .. "/project.godot"):gsub("\\", "/")
	local build_path, kind = resolve_build_executable()
	if build_path and kind == "export" then
		if net.is_windows() then
			net.system("cmd /c start \"\" " .. net.win_quote(build_path))
		else
			net.system(net.sh_quote(build_path) .. " &")
		end
		set_status({ "Launched build: " .. build_path })
		love.event.quit()
		return
	end
	if build_path and kind == "macapp" then
		net.system("open " .. net.sh_quote(build_path))
		set_status({ "Launched build: " .. build_path })
		love.event.quit()
		return
	end
	local bin = net.getenv_c("GODOT")
	if not bin or bin == "" then
		bin = net.is_windows() and "godot.exe" or "godot"
	end
	if net.is_windows() then
		net.system("cmd /c start \"\" " .. net.win_quote(bin) .. " " .. net.win_quote(proj))
	else
		net.system(net.sh_quote(bin) .. " " .. net.sh_quote(proj) .. " &")
	end
	set_status({
		"No export in build/ — opened editor/project.",
		"Expected Linux export: …/NorthStarDesktop/Builds/LinuxBuild.x86_64",
		"(also tried under game folder: " .. godot_root .. "/Builds/ and build/linux/… — see build/README.txt)",
		bin .. " " .. proj,
		"(set GODOT env if the editor is not on PATH)",
	})
	love.event.quit()
end

local function layout_buttons()
	local w, h = love.graphics.getDimensions()
	if screen == "login" then
		if is_register_mode() then
			buttons = {
				{ x = 100, y = h - 80, w = 140, h = 36, label = "Create account", id = "register_submit" },
				{ x = 260, y = h - 80, w = 180, h = 36, label = "Back to Login", id = "register_back" },
			}
		else
			buttons = {
				{ x = 100, y = h - 80, w = 120, h = 36, label = "Login", id = "login_submit" },
				{ x = 240, y = h - 80, w = 160, h = 36, label = "Register", id = "register_show" },
			}
		end
	else
		buttons = {
			{ x = 20, y = h - 140, w = 100, h = 32, label = "Log out", id = "logout" },
			{ x = 20, y = h - 100, w = 140, h = 36, label = "Sync", id = "sync" },
			{ x = 180, y = h - 100, w = 160, h = 36, label = "Start game", id = "godot" },
		}
	end
end

function love.load()
	love.graphics.setFont(love.graphics.newFont(15))
	love.keyboard.setTextInput(true)
	if init_launcher_paths() and try_load_secrets() then
		if try_restore_session() then
			layout_buttons()
			return
		end
		set_status({
			"Sign in or Register with your Supabase account.",
			"Email provider must be enabled in Supabase Auth.",
		})
	end
	screen = "login"
	layout_buttons()
end

function love.resize()
	layout_buttons()
end

function love.mousepressed(mx, my, btn)
	if btn ~= 1 then
		return
	end
	if screen == "login" then
		if is_register_mode() then
			if mx >= UI.name_rect.x and mx <= UI.name_rect.x + UI.name_rect.w and my >= UI.name_rect.y and my <= UI.name_rect.y + UI.name_rect.h then
				login_focus = "display_name"
				return
			end
			if mx >= UI.email_rect.x and mx <= UI.email_rect.x + UI.email_rect.w and my >= UI.email_rect.y and my <= UI.email_rect.y + UI.email_rect.h then
				login_focus = "email"
				return
			end
			if mx >= UI.pass_rect.x and mx <= UI.pass_rect.x + UI.pass_rect.w and my >= UI.pass_rect.y and my <= UI.pass_rect.y + UI.pass_rect.h then
				login_focus = "password"
				return
			end
			if mx >= UI.confirm_rect.x and mx <= UI.confirm_rect.x + UI.confirm_rect.w and my >= UI.confirm_rect.y and my <= UI.confirm_rect.y + UI.confirm_rect.h then
				login_focus = "confirm"
				return
			end
		else
			if mx >= UI.email_rect.x and mx <= UI.email_rect.x + UI.email_rect.w and my >= UI.email_rect.y and my <= UI.email_rect.y + UI.email_rect.h then
				login_focus = "email"
				return
			end
			if mx >= UI.pass_rect.x and mx <= UI.pass_rect.x + UI.pass_rect.w and my >= UI.pass_rect.y and my <= UI.pass_rect.y + UI.pass_rect.h then
				login_focus = "password"
				return
			end
		end
	end
	for _, b in ipairs(buttons) do
		if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
			if b.id == "login_submit" then
				do_login()
			elseif b.id == "register_show" then
				auth_mode = "register"
				login_focus = "display_name"
				set_status({ "Create an account. Email confirmation is required." })
				layout_buttons()
			elseif b.id == "register_back" then
				auth_mode = "login"
				login_focus = "email"
				login_password = ""
				login_confirm = ""
				set_status({ "Sign in with your Supabase account." })
				layout_buttons()
			elseif b.id == "register_submit" then
				do_register()
			elseif b.id == "logout" then
				do_logout()
			elseif b.id == "sync" then
				do_sync()
			elseif b.id == "godot" then
				do_start_godot()
			end
			return
		end
	end
end

function love.textinput(t)
	if screen ~= "login" then
		return
	end
	if login_focus == "display_name" then
		login_display_name = login_display_name .. t
	elseif login_focus == "email" then
		login_email = login_email .. t
	elseif login_focus == "password" then
		login_password = login_password .. t
	elseif login_focus == "confirm" then
		login_confirm = login_confirm .. t
	end
end

function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
	elseif key == "tab" and screen == "login" then
		if is_register_mode() then
			if login_focus == "display_name" then
				login_focus = "email"
			elseif login_focus == "email" then
				login_focus = "password"
			elseif login_focus == "password" then
				login_focus = "confirm"
			else
				login_focus = "display_name"
			end
		else
			login_focus = (login_focus == "email") and "password" or "email"
		end
	elseif key == "return" or key == "kpenter" then
		if screen == "login" then
			if is_register_mode() then
				do_register()
			else
				do_login()
			end
		else
			do_sync()
		end
	elseif key == "g" and screen == "main" then
		do_start_godot()
	elseif key == "backspace" and screen == "login" then
		if login_focus == "display_name" then
			login_display_name = login_display_name:sub(1, -2)
		elseif login_focus == "email" then
			login_email = login_email:sub(1, -2)
		elseif login_focus == "password" then
			login_password = login_password:sub(1, -2)
		elseif login_focus == "confirm" then
			login_confirm = login_confirm:sub(1, -2)
		end
	end
end

function love.draw()
	love.graphics.clear(0.12, 0.12, 0.14, 1)
	love.graphics.setColor(0.95, 0.95, 0.92, 1)
	love.graphics.print("NorthStar — launcher (Love2D)", 20, 16)
	love.graphics.setColor(0.75, 0.75, 0.72, 1)
	local y = 48
	for _, line in ipairs(status_lines) do
		love.graphics.print(line, 20, y)
		y = y + 22
	end

	if screen == "login" then
		love.graphics.setColor(0.85, 0.85, 0.82, 1)
		if is_register_mode() then
			love.graphics.print("Display name", 20, UI.name_rect.y + 4)
		end
		love.graphics.print("Email", 20, UI.email_rect.y + 4)
		love.graphics.print("Password", 20, UI.pass_rect.y + 4)
		if is_register_mode() then
			love.graphics.print("Confirm", 20, UI.confirm_rect.y + 4)
		end
		love.graphics.setColor(0.35, 0.38, 0.48, 1)
		if is_register_mode() then
			love.graphics.rectangle("line", UI.name_rect.x, UI.name_rect.y, UI.name_rect.w, UI.name_rect.h)
		end
		love.graphics.rectangle("line", UI.email_rect.x, UI.email_rect.y, UI.email_rect.w, UI.email_rect.h)
		love.graphics.rectangle("line", UI.pass_rect.x, UI.pass_rect.y, UI.pass_rect.w, UI.pass_rect.h)
		if is_register_mode() then
			love.graphics.rectangle("line", UI.confirm_rect.x, UI.confirm_rect.y, UI.confirm_rect.w, UI.confirm_rect.h)
		end
		love.graphics.setColor(0.95, 0.95, 0.92, 1)
		if is_register_mode() then
			love.graphics.print(login_display_name, UI.name_rect.x + 6, UI.name_rect.y + 4)
		end
		love.graphics.print(login_email, UI.email_rect.x + 6, UI.email_rect.y + 4)
		local mask_p = string.rep("*", #login_password)
		love.graphics.print(mask_p, UI.pass_rect.x + 6, UI.pass_rect.y + 4)
		local mask_c = string.rep("*", #login_confirm)
		if is_register_mode() then
			love.graphics.print(mask_c, UI.confirm_rect.x + 6, UI.confirm_rect.y + 4)
		end
		if math.floor(love.timer.getTime() * 2) % 2 == 0 then
			local cx, cy
			if login_focus == "display_name" then
				cx = UI.name_rect.x + 6 + love.graphics.getFont():getWidth(login_display_name)
				cy = UI.name_rect.y + 4
			elseif login_focus == "email" then
				cx = UI.email_rect.x + 6 + love.graphics.getFont():getWidth(login_email)
				cy = UI.email_rect.y + 4
			elseif login_focus == "confirm" then
				cx = UI.confirm_rect.x + 6 + love.graphics.getFont():getWidth(mask_c)
				cy = UI.confirm_rect.y + 4
			else
				cx = UI.pass_rect.x + 6 + love.graphics.getFont():getWidth(mask_p)
				cy = UI.pass_rect.y + 4
			end
			love.graphics.line(cx, cy, cx, cy + 16)
		end
		love.graphics.setColor(0.4, 0.45, 0.55, 1)
		if is_register_mode() then
			love.graphics.print("Tab: next field   Enter: Create account   Esc: quit", 20, love.graphics.getHeight() - 28)
		else
			love.graphics.print("Tab: switch field   Enter: Login   Click Register to sign up   Esc: quit", 20, love.graphics.getHeight() - 28)
		end
	else
		love.graphics.setColor(0.4, 0.45, 0.55, 1)
		love.graphics.print("Enter: Sync   G: Start game   Esc: quit", 20, love.graphics.getHeight() - 28)
	end

	for _, b in ipairs(buttons) do
		love.graphics.setColor(0.25, 0.28, 0.35, 1)
		love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 4, 4)
		love.graphics.setColor(0.9, 0.9, 0.88, 1)
		love.graphics.print(b.label, b.x + 12, b.y + 9)
	end
end

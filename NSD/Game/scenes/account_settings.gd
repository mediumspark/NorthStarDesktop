extends Control

const SCENE_MAIN := "res://scenes/main_menu.tscn"


func _ready() -> void:
	SupabaseClient.load_config()
	SupabaseClient.load_session_file()
	%BackButton.pressed.connect(_on_back_pressed)
	%RecoveryButton.pressed.connect(_on_recovery_pressed)
	%SaveProfileButton.pressed.connect(_on_save_profile_pressed)
	%ChangePasswordButton.pressed.connect(_on_change_password_pressed)
	_refresh_session_ui()
	if SupabaseClient.is_session_valid():
		_load_profile_into_form()


func _refresh_session_ui() -> void:
	var signed_in := SupabaseClient.is_session_valid()
	# Includes profile + change-password blocks (PasswordSection is inside ProfileSection).
	%ProfileSection.visible = signed_in
	# Generic message if not signed in (recovery still works).
	if not signed_in:
		%EmailReadout.text = "Not signed in. Use the launcher to log in, or request a password reset below."
		%DisplayNameEdit.text = ""
		%RecoveryEmail.text = ""
	else:
		%EmailReadout.text = "Email: %s" % SupabaseClient.get_session_user_email()
		%RecoveryEmail.text = SupabaseClient.get_session_user_email()


func _load_profile_into_form() -> void:
	%ProfileStatus.text = "Loading profile…"
	var r: Dictionary = await GameAuthApi.fetch_profile()
	if not r.ok:
		%ProfileStatus.text = r.get("error", "Load failed")
		return
	var row: Variant = r.get("row", {})
	if typeof(row) != TYPE_DICTIONARY:
		%ProfileStatus.text = "No profile row yet (save to create)."
		return
	%DisplayNameEdit.text = str(row.get("display_name", ""))
	%ProfileStatus.text = ""


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN)


func _on_recovery_pressed() -> void:
	%RecoveryStatus.text = "Sending…"
	%RecoveryButton.disabled = true
	var r: Dictionary = await GameAuthApi.recover_password(%RecoveryEmail.text)
	%RecoveryButton.disabled = false
	if r.ok:
		%RecoveryStatus.text = "If an account exists for that email, a reset link has been sent. Check your inbox."
	else:
		%RecoveryStatus.text = r.get("error", "Request failed")


func _on_save_profile_pressed() -> void:
	if not SupabaseClient.is_session_valid():
		%ProfileStatus.text = "Sign in required."
		return
	%ProfileStatus.text = "Saving…"
	%SaveProfileButton.disabled = true
	var r: Dictionary = await GameAuthApi.patch_display_name(%DisplayNameEdit.text)
	%SaveProfileButton.disabled = false
	if r.ok:
		%ProfileStatus.text = "Profile saved."
	else:
		%ProfileStatus.text = r.get("error", "Save failed")


func _on_change_password_pressed() -> void:
	if not SupabaseClient.is_session_valid():
		%PasswordStatus.text = "Sign in required."
		return
	var em := SupabaseClient.get_session_user_email()
	if em.is_empty():
		%PasswordStatus.text = "Session has no email; reopen the game from the launcher."
		return
	var new_p: String = %NewPassword.text
	if new_p != %ConfirmPassword.text:
		%PasswordStatus.text = "New password and confirmation do not match."
		return
	%PasswordStatus.text = "Updating password…"
	%ChangePasswordButton.disabled = true
	var r: Dictionary = await GameAuthApi.change_password(em, %CurrentPassword.text, new_p)
	%ChangePasswordButton.disabled = false
	if r.ok:
		%PasswordStatus.text = "Password updated. Session saved."
		%CurrentPassword.text = ""
		%NewPassword.text = ""
		%ConfirmPassword.text = ""
		SupabaseClient.invalidate_session_cache()
		SupabaseClient.load_session_file()
		_refresh_session_ui()
	else:
		%PasswordStatus.text = r.get("error", "Update failed")

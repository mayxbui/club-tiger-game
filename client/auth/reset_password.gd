extends Node2D

# Reset-password screen, one step at a time (BtnSubmit moves the player to the next step):
#   EMAIL    (EmailVBoxContainer) -> server emails a 6-digit code
#   CODE     (CodeHBox)           -> server checks the code and sends back a one-time reset token
#   PASSWORD (PassVBoxContainer)  -> server changes the password using that token
#   DONE     (LabelMsg2)          -> BtnBack returns to sign in
enum Step { EMAIL, CODE, PASSWORD, DONE }

var step := Step.EMAIL
var email := ""
var reset_token := ""
# 6-digit boxes in CodeHBox (Digit1..Digit6)
var digit_boxes: Array[LineEdit] = []
var email_check := RegEx.new()

func show_message(msg: String) -> void:
	$LabelDebug.text = msg
	$TimerDebug.start()

# Hooks up the code boxes and the Enter key, listens for server replies, and starts on the EMAIL step.
func _ready() -> void:
	$TimerDebug.timeout.connect(func(): $LabelDebug.text = "")
	Network.message_received.connect(_on_message_received)
	email_check.compile("^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,4}$")

	for child in $CodeHBox.get_children():
		digit_boxes.append(child as LineEdit)
	for i in digit_boxes.size():
		digit_boxes[i].text_changed.connect(_on_digit_changed.bind(i))
		digit_boxes[i].gui_input.connect(_on_digit_gui_input.bind(i))
		digit_boxes[i].text_submitted.connect(func(_text): _on_btn_submit_pressed())
	# Pressing Enter in any text field works like clicking Submit.
	$EmailVBoxContainer/InputEmail.text_submitted.connect(func(_text): _on_btn_submit_pressed())
	$PassVBoxContainer/InputNewPassword.text_submitted.connect(func(_text): $PassVBoxContainer/InputConfirm.grab_focus())
	$PassVBoxContainer/InputConfirm.text_submitted.connect(func(_text): _on_btn_submit_pressed())

	_show_step(Step.EMAIL)

# Shows only the controls for this step, sets the instructions in LabelMsg, and focuses the first field.
func _show_step(new_step: Step) -> void:
	step = new_step
	$EmailVBoxContainer.visible = step == Step.EMAIL
	$CodeHBox.visible = step == Step.CODE
	$PassVBoxContainer.visible = step == Step.PASSWORD
	$LabelMsg2.visible = step == Step.DONE
	# BtnSubmit and BtnBack sit in the same spot, so only one is shown at a time.
	$BtnSubmit.visible = step != Step.DONE
	$BtnSubmit.disabled = false
	$BtnBack.visible = step == Step.DONE
	$LabelMsg.visible = step == Step.CODE or step == Step.PASSWORD

	match step:
		Step.EMAIL:
			$EmailVBoxContainer/InputEmail.grab_focus()
		Step.CODE:
			$LabelMsg.text = "If this email has an account, we sent it a 6-digit code. It expires in 15 minutes."
			_clear_code()
		Step.PASSWORD:
			$LabelMsg.text = "Choose a new password."
			$PassVBoxContainer/InputNewPassword.clear()
			$PassVBoxContainer/InputConfirm.clear()
			$PassVBoxContainer/InputNewPassword.grab_focus()

# Runs the current step's check and sends it to the server
func _on_btn_submit_pressed() -> void:
	if $BtnSubmit.disabled:
		return  # waiting for the server
	match step:
		Step.EMAIL:
			_submit_email()
		Step.CODE:
			_submit_code()
		Step.PASSWORD:
			_submit_password()

# EMAIL step: asks the server to email a reset code.
func _submit_email() -> void:
	email = $EmailVBoxContainer/InputEmail.text.strip_edges().to_lower()
	if email.is_empty():
		show_message("Please enter your email.\n")
		return
	# Catches typos like "abc" or "me@school" before asking the server (it would silently ignore them).
	if email_check.search(email) == null:
		show_message("Please enter a valid email address.\n")
		return
	_send({"type": "request_password_reset", "email": email})

# CODE: sends the six digits for the server to check
func _submit_code() -> void:
	var code := _get_code()
	if code.length() != 6:
		show_message("Please enter the code.\n")
		return
	_send({"type": "verify_reset_code", "email": email, "code": code})

# PASSWORD: checks the new password on the client first (same rule as create_account.gd), then sends it with the token.
func _submit_password() -> void:
	var password: String = $PassVBoxContainer/InputNewPassword.text
	var confirm: String = $PassVBoxContainer/InputConfirm.text
	if password.length() < 8 or password.length() > 72:
		show_message("Password must be 8 to 72 characters long.\n")
		return
	if password != confirm:
		show_message("Passwords don't match.\n")
		$PassVBoxContainer/InputConfirm.clear()
		$PassVBoxContainer/InputConfirm.grab_focus()
		return
	_send({"type": "reset_password", "reset_token": reset_token, "new_password": password})

func _send(message: Dictionary) -> void:
	if Network.send(message):
		$BtnSubmit.disabled = true
	else:
		show_message("Not connected to server yet.\n")

func _on_message_received(data: Dictionary) -> void:
	match data.get("type"):
		# Server sends type "error" for crashes/malformed messages (e.g. DB failures); let the player try again
		"error":
			show_message("Server error: " + str(data.get("error")) + "\n")
			$BtnSubmit.disabled = false
		# Always success (the server never says whether the email has an account), so go on to the code
		"request_password_reset_result":
			_show_step(Step.CODE)
		"verify_reset_code_result":
			if data.get("success", false):
				reset_token = str(data.get("resetToken", ""))
				_show_step(Step.PASSWORD)
			else:
				show_message(str(data.get("error", "Invalid or expired code.")) + "\n")
				$BtnSubmit.disabled = false
				_clear_code()
		"reset_password_result":
			if data.get("success", false):
				reset_token = ""
				_show_step(Step.DONE)
			else:
				# The password was already checked above, so a failure here means the reset token expired (10 minutes):
				# the player needs a new code
				show_message(str(data.get("error", "Your reset expired. Please request a new code.")) + "\n")
				reset_token = ""
				_show_step(Step.EMAIL)

# Keeps each code box to one digit and moves to the next box after typing one. Pasting the whole code fills
# the boxes from this one onward
func _on_digit_changed(new_text: String, index: int) -> void:
	var digits := ""
	for c in new_text:
		if c >= "0" and c <= "9":
			digits += c

	if digits.length() <= 1:
		_set_digit(index, digits)
		if digits.length() == 1 and index < digit_boxes.size() - 1:
			digit_boxes[index + 1].grab_focus()
		return

	# More than one digit arrived at once (a paste): spread them across this box and the ones after it.
	var last := index
	for i in digits.length():
		if index + i >= digit_boxes.size():
			break
		_set_digit(index + i, digits[i])
		last = index + i
	digit_boxes[mini(last + 1, digit_boxes.size() - 1)].grab_focus()

# Backspace in an empty box clears the previous box and moves back to it; Left/Right arrows move between boxes
func _on_digit_gui_input(event: InputEvent, index: int) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_BACKSPACE:
			if digit_boxes[index].text.is_empty() and index > 0:
				_set_digit(index - 1, "")
				digit_boxes[index - 1].grab_focus()
				get_viewport().set_input_as_handled()
		KEY_LEFT:
			if index > 0:
				digit_boxes[index - 1].grab_focus()
				get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if index < digit_boxes.size() - 1:
				digit_boxes[index + 1].grab_focus()
				get_viewport().set_input_as_handled()

# Sets one code box's text without triggering text_changed again, and keeps the caret after the digit.
func _set_digit(index: int, digit: String) -> void:
	digit_boxes[index].text = digit
	digit_boxes[index].caret_column = digit.length()

# Joins the six boxes into one code string.
func _get_code() -> String:
	var code := ""
	for box in digit_boxes:
		code += box.text
	return code

# Empties all six code boxes and puts the cursor in the first one.
func _clear_code() -> void:
	for i in digit_boxes.size():
		_set_digit(i, "")
	digit_boxes[0].grab_focus()

# Goes back to the sign-in screen.
func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/signin.tscn")

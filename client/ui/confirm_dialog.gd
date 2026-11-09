class_name ConfirmDialog
extends CanvasLayer

# Shared "Are you sure?" pop-up. The player card and the other-player card each have one, and every action that
# changes someone else's relation to you (add, unfriend, block, visit) goes through it first.
# Usage: confirm_dialog.ask("Block sam?", "Block", func(): Network.send(...)). The callable runs only on Yes.
# Cancel and Confirm are connected in confirm_dialog.tscn.

# What to run if the player confirms (empty while the dialog is closed).
var _on_confirm := Callable()

@onready var label_message: RichTextLabel = $Panel/VBox/LabelMessage
@onready var btn_confirm: Button = $Panel/VBox/Buttons/BtnConfirm


# --- Setup ---

# Starts hidden (the scene is saved visible so it can be edited).
func _ready() -> void:
	visible = false


# Escape works like Cancel. This node is a child of its card, so it gets Escape before the card does.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


# --- Called by the cards ---

# Shows the question with confirm_text on the Yes button; on_confirm runs only if the player clicks it.
func ask(message: String, confirm_text: String, on_confirm: Callable) -> void:
	label_message.text = message
	btn_confirm.text = confirm_text
	_on_confirm = on_confirm
	visible = true


# Closes the dialog without running anything (Cancel, Escape, or its card closing).
func cancel() -> void:
	visible = false
	_on_confirm = Callable()


# --- Button handlers (connected in confirm_dialog.tscn) ---

# Cancel closes the dialog and does nothing.
func _on_btn_cancel_pressed() -> void:
	cancel()


# Confirm closes the dialog first (so the action can open another dialog if it needs to), then runs the action.
func _on_btn_confirm_pressed() -> void:
	var action := _on_confirm
	cancel()
	if action.is_valid():
		action.call()

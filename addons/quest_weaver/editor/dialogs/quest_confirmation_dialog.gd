# res://addons/quest_weaver/editor/dialogs/quest_confirmation_dialog.gd
@tool
class_name QuestConfirmationDialog
extends ConfirmationDialog

signal save_requested
signal discard_requested
signal action_cancelled


func _ready() -> void:
	get_ok_button().hide()

	add_button("Save", false, "save")
	add_button("Discard", true, "discard")

	custom_action.connect(_on_custom_action)
	canceled.connect(_on_action_cancelled)


func prompt(p_title: String, p_description: String) -> void:
	title = p_title
	dialog_text = p_description
	popup_centered()


func _on_custom_action(action: StringName) -> void:
	match action:
		"save":
			save_requested.emit()
		"discard":
			discard_requested.emit()

	queue_free()


func _on_action_cancelled() -> void:
	action_cancelled.emit()
	queue_free()

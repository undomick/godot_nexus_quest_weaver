# res://addons/quest_weaver/nodes/flow/jump_node/jump_node_editor.gd
@tool
class_name JumpNodeEditor
extends NodePropertyEditorBase

@onready var target_edit: LineEdit = %TargetNameEdit
@onready var paste_name_button: Button = %PasteNameButton
@onready var copy_name_button: Button = %CopyNameButton


func _ready() -> void:
	target_edit.text_submitted.connect(func(_text): _on_target_confirmed())
	target_edit.focus_exited.connect(_on_target_confirmed)
	paste_name_button.pressed.connect(_on_paste_name_pressed)
	copy_name_button.pressed.connect(_on_copy_name_pressed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is JumpNodeResource:
		return

	target_edit.text = node_data.target_anchor_name

	paste_name_button.icon = get_theme_icon("Bucket", "EditorIcons")
	paste_name_button.tooltip_text = "Paste Name from Clipboard"
	paste_name_button.flat = true
	copy_name_button.icon = get_theme_icon("Duplicate", "EditorIcons")
	copy_name_button.tooltip_text = "Copy Name to Clipboard"
	copy_name_button.flat = true


func _on_target_confirmed() -> void:
	var new_text = target_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.target_anchor_name != new_text:
		property_update_requested.emit(
			edited_node_data.id, "target_anchor_name", StringName(new_text), null, {}
		)


func _on_paste_name_pressed() -> void:
	var text = DisplayServer.clipboard_get()
	if not text.is_empty():
		target_edit.text = text
		_on_target_confirmed()


func _on_copy_name_pressed():
	if is_instance_valid(target_edit):
		DisplayServer.clipboard_set(target_edit.text)

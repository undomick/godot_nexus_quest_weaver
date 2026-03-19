# res://addons/quest_weaver/nodes/flow/anchor_node/anchor_node_editor.gd
@tool
class_name AnchorNodeEditor
extends NodePropertyEditorBase

@onready var name_edit: LineEdit = %AnchorNameEdit
@onready var paste_name_button: Button = %PasteNameButton
@onready var copy_name_button: Button = %CopyNameButton


func _ready() -> void:
	name_edit.text_submitted.connect(func(_text): _on_name_confirmed())
	name_edit.focus_exited.connect(_on_name_confirmed)
	paste_name_button.pressed.connect(_on_paste_name_pressed)
	copy_name_button.pressed.connect(_on_copy_name_pressed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is AnchorNodeResource:
		return

	name_edit.text = node_data.anchor_name

	paste_name_button.icon = get_theme_icon("Bucket", "EditorIcons")
	paste_name_button.tooltip_text = "Paste Name from Clipboard"
	paste_name_button.flat = true
	copy_name_button.icon = get_theme_icon("Duplicate", "EditorIcons")
	copy_name_button.tooltip_text = "Copy Name to Clipboard"
	copy_name_button.flat = true


func _on_name_confirmed() -> void:
	var new_text = name_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.anchor_name != new_text:
		property_update_requested.emit(
			edited_node_data.id, "anchor_name", StringName(new_text), null, {}
		)


func _on_paste_name_pressed() -> void:
	var text = DisplayServer.clipboard_get()
	if not text.is_empty():
		name_edit.text = text
		_on_name_confirmed()


func _on_copy_name_pressed():
	if is_instance_valid(name_edit):
		DisplayServer.clipboard_set(name_edit.text)

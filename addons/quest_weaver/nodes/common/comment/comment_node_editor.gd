# res://addons/quest_weaver/nodes/common/comment/comment_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var text_edit: TabFocusTextEdit = %TextEdit


func _ready() -> void:
	text_edit.focus_exited.connect(_on_text_confirmed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is CommentNodeResource:
		return

	text_edit.text = node_data.text


func _on_text_confirmed() -> void:
	# Check if the text has actually changed before creating a history entry.
	if is_instance_valid(edited_node_data) and edited_node_data.text != text_edit.text:
		property_update_requested.emit(edited_node_data.id, "text", text_edit.text, null, {})

# res://addons/quest_weaver/nodes/logic/cancel_scope_node/cancel_scope_node_editor.gd
@tool
class_name CancelScopeNodeEditor
extends NodePropertyEditorBase

@onready var scope_id_edit: LineEdit = %ScopeIDEdit


func _ready() -> void:
	if is_instance_valid(scope_id_edit):
		scope_id_edit.text_submitted.connect(func(_text): _on_scope_id_confirmed())
		scope_id_edit.focus_exited.connect(_on_scope_id_confirmed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is CancelScopeNodeResource:
		return
	if is_instance_valid(scope_id_edit):
		scope_id_edit.text = node_data.target_scope_id


func _on_scope_id_confirmed() -> void:
	var new_text = scope_id_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data is CancelScopeNodeResource:
		if edited_node_data.target_scope_id != StringName(new_text):
			property_update_requested.emit(
				edited_node_data.id, "target_scope_id", StringName(new_text), null, {}
			)

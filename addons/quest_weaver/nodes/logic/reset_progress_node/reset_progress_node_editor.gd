# res://addons/quest_weaver/nodes/logic/reset_progress_node/reset_progress_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var target_scope_id_edit: LineEdit = %TargetScopeIDEdit
@onready var restart_scope_checkbox: CheckBox = %RestartScopeCheckbox


func _ready() -> void:
	target_scope_id_edit.text_submitted.connect(func(_text): _on_scope_id_confirmed())
	target_scope_id_edit.focus_exited.connect(_on_scope_id_confirmed)

	restart_scope_checkbox.toggled.connect(_on_restart_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is ResetProgressNodeResource:
		return

	target_scope_id_edit.text = node_data.target_scope_id
	restart_scope_checkbox.button_pressed = node_data.restart_scope_on_completion


func _on_scope_id_confirmed() -> void:
	var new_text = target_scope_id_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.target_scope_id != new_text:
		property_update_requested.emit(
			edited_node_data.id, "target_scope_id", StringName(new_text), null, {}
		)


func _on_restart_toggled(is_pressed: bool) -> void:
	if (
		is_instance_valid(edited_node_data)
		and edited_node_data.restart_scope_on_completion != is_pressed
	):
		property_update_requested.emit(
			edited_node_data.id, "restart_scope_on_completion", is_pressed, null, {}
		)

# res://addons/quest_weaver/nodes/logic/start_scope_node/start_scope_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var scope_id_edit: LineEdit = %ScopeIDEdit
@onready var max_executions_spinbox: SpinBox = %MaxExecutionsSpinBox


func _ready() -> void:
	scope_id_edit.text_submitted.connect(func(_text): _on_scope_id_confirmed())
	scope_id_edit.focus_exited.connect(_on_scope_id_confirmed)

	max_executions_spinbox.value_changed.connect(_on_max_executions_changed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is StartScopeNodeResource:
		return

	scope_id_edit.text = node_data.scope_id
	max_executions_spinbox.set_value_no_signal(node_data.max_executions)


func _on_scope_id_confirmed() -> void:
	var new_text = scope_id_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.scope_id != new_text:
		property_update_requested.emit(
			edited_node_data.id, "scope_id", StringName(new_text), null, {}
		)


func _on_max_executions_changed(new_value: float) -> void:
	if not is_instance_valid(edited_node_data):
		return
	if edited_node_data.max_executions != int(new_value):
		property_update_requested.emit(
			edited_node_data.id, "max_executions", int(new_value), null, {}
		)

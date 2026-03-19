# res://addons/quest_weaver/nodes/flow/wait_node/wait_node_editor.gd
@tool

extends NodePropertyEditorBase

var _duration_undo_value: float = 1.0

@onready var wait_duration_edit: LineEdit = %WaitDurationEdit


func _ready() -> void:
	wait_duration_edit.focus_entered.connect(_on_edit_started)
	wait_duration_edit.text_submitted.connect(func(_new_text): _on_value_confirmed())
	wait_duration_edit.focus_exited.connect(_on_value_confirmed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is WaitNodeResource:
		return

	wait_duration_edit.text = str(node_data.wait_duration)


func _on_edit_started() -> void:
	if is_instance_valid(edited_node_data):
		_duration_undo_value = edited_node_data.wait_duration


func _on_value_confirmed():
	var input_text = wait_duration_edit.text
	if not input_text.is_valid_float():
		wait_duration_edit.text = str(_duration_undo_value)
		return

	var new_value = input_text.to_float()
	if new_value <= 0:
		new_value = 0.1
		wait_duration_edit.text = str(new_value)

	if is_instance_valid(edited_node_data) and not is_equal_approx(_duration_undo_value, new_value):
		property_update_requested.emit(edited_node_data.id, "wait_duration", new_value, null, {})

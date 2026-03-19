# res://addons/quest_weaver/nodes/flow/timer_node/timer_node_editor.gd
@tool

extends NodePropertyEditorBase

var _duration_undo_value: int = 0

@onready var duration_edit: LineEdit = %DurationEdit


func _ready() -> void:
	duration_edit.focus_entered.connect(_on_duration_edit_started)
	duration_edit.text_submitted.connect(func(_new_text): _on_value_confirmed())
	duration_edit.focus_exited.connect(_on_value_confirmed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is TimerNodeResource:
		return

	duration_edit.text = str(node_data.duration)


func _on_duration_edit_started() -> void:
	if is_instance_valid(edited_node_data):
		_duration_undo_value = edited_node_data.duration


func _on_value_confirmed():
	var input_text = duration_edit.text
	if not input_text.is_valid_int():
		duration_edit.text = str(_duration_undo_value)
		return

	var new_value = input_text.to_int()
	if new_value < 1:
		new_value = 1
		duration_edit.text = str(new_value)

	# Only create the UndoRedo action if the value has actually changed.
	if is_instance_valid(edited_node_data) and _duration_undo_value != new_value:
		var history_payload := {
			"property_name": "duration", "old_value": _duration_undo_value, "new_value": new_value
		}

		property_update_requested.emit(edited_node_data.id, "duration", new_value, null, {})

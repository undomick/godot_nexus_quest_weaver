# res://addons/quest_weaver/nodes/logic/objective_node/objective_node_editor.gd
@tool
class_name ObjectiveNodeEditor
extends NodePropertyEditorBase

@onready var action_picker: OptionButton = %ActionPicker
@onready var target_id_edit: LineEdit = %TargetIdEdit
@onready var terminal_checkbox: CheckBox = %TerminalCheckBox


func _ready():
	target_id_edit.text_submitted.connect(func(_new_text): _on_id_confirmed())
	target_id_edit.focus_exited.connect(_on_id_confirmed)

	if action_picker:
		action_picker.item_selected.connect(_on_action_changed)

	terminal_checkbox.toggled.connect(_on_terminal_toggled)


func set_node_data(node_data: GraphNodeResource):
	super.set_node_data(node_data)
	if not node_data is ObjectiveNodeResource:
		return

	target_id_edit.text = node_data.target_objective_id

	if action_picker:
		action_picker.clear()
		for action_name in node_data.Action.keys():
			action_picker.add_item(action_name.capitalize())
		action_picker.select(node_data.action)

	terminal_checkbox.button_pressed = node_data.is_terminal


func _on_id_confirmed():
	var new_id = target_id_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.target_objective_id != new_id:
		property_update_requested.emit(
			edited_node_data.id, "target_objective_id", StringName(new_id), null, {}
		)


func _on_action_changed(index: int):
	if is_instance_valid(edited_node_data) and edited_node_data.action != index:
		property_update_requested.emit(edited_node_data.id, "action", index, null, {})


func _on_terminal_toggled(pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.is_terminal != pressed:
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})

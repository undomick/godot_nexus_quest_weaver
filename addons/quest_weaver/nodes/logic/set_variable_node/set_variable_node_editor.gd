# res://addons/quest_weaver/nodes/logic/set_variable_node/set_variable_node_editor.gd
@tool
extends NodePropertyEditorBase

@onready var variable_name_edit: LineEdit = %VariableNameEdit
@onready var value_to_set_edit: LineEdit = %ValueToSetEdit
@onready var operator_picker: OptionButton = %OperatorPicker
@onready var terminal_checkbox: CheckBox = %TerminalCheckBox


func _ready() -> void:
	variable_name_edit.text_submitted.connect(func(_text): _on_variable_name_confirmed())
	variable_name_edit.focus_exited.connect(_on_variable_name_confirmed)

	value_to_set_edit.text_submitted.connect(func(_text): _on_value_to_set_confirmed())
	value_to_set_edit.focus_exited.connect(_on_value_to_set_confirmed)

	operator_picker.item_selected.connect(_on_operator_changed)
	terminal_checkbox.toggled.connect(_on_terminal_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is SetVariableNodeResource:
		return

	variable_name_edit.text = node_data.variable_name
	value_to_set_edit.text = node_data.value_to_set_string
	value_to_set_edit.placeholder_text = "123, true, text, $some_variable"

	operator_picker.clear()
	for op_name in node_data.Operator.keys():
		operator_picker.add_item(op_name)
	operator_picker.select(node_data.operator)

	terminal_checkbox.button_pressed = node_data.is_terminal

	_update_ui_for_operator()


func _on_variable_name_confirmed():
	var new_text = variable_name_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.variable_name != new_text:
		property_update_requested.emit(
			edited_node_data.id, "variable_name", StringName(new_text), null, {}
		)


func _on_value_to_set_confirmed():
	var new_text = value_to_set_edit.text
	if is_instance_valid(edited_node_data) and edited_node_data.value_to_set_string != new_text:
		property_update_requested.emit(
			edited_node_data.id, "value_to_set_string", new_text, null, {}
		)


func _on_operator_changed(index: int):
	if is_instance_valid(edited_node_data) and edited_node_data.operator != index:
		property_update_requested.emit(edited_node_data.id, "operator", index, null, {})

	_update_ui_for_operator()


func _update_ui_for_operator():
	if not is_instance_valid(edited_node_data):
		return

	var is_toggle = edited_node_data.operator == SetVariableNodeResource.Operator.TOGGLE

	value_to_set_edit.editable = not is_toggle
	value_to_set_edit.modulate.a = 0.5 if is_toggle else 1.0


func _on_terminal_toggled(pressed: bool) -> void:
	if is_instance_valid(edited_node_data) and edited_node_data.is_terminal != pressed:
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})

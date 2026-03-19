# res://addons/quest_weaver/nodes/flow/all_complete_node/all_complete_node_editor.gd
@tool

class_name AllCompleteNodeEditor

extends NodePropertyEditorBase

var _is_setting_up := false

@onready var keep_listening_checkbox: CheckBox = %KeepListeningCheckbox

@onready var input_count_spin: SpinBox = %InputCountSpin


func _ready() -> void:
	if is_instance_valid(keep_listening_checkbox):
		keep_listening_checkbox.toggled.connect(_on_keep_listening_toggled)
	if is_instance_valid(input_count_spin):
		input_count_spin.value_changed.connect(_on_input_count_changed)


func set_node_data(node_data: GraphNodeResource) -> void:
	_is_setting_up = true
	super.set_node_data(node_data)
	if not node_data is AllCompleteNodeResource:
		_is_setting_up = false
		return

	if is_instance_valid(keep_listening_checkbox):
		keep_listening_checkbox.button_pressed = node_data.keep_listening
	if is_instance_valid(input_count_spin):
		input_count_spin.min_value = 1
		input_count_spin.max_value = 16
		input_count_spin.value = node_data.input_count
	_is_setting_up = false


func _on_keep_listening_toggled(pressed: bool) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data) and edited_node_data is AllCompleteNodeResource:
		if edited_node_data.keep_listening != pressed:
			property_update_requested.emit(edited_node_data.id, "keep_listening", pressed, null, {})


func _on_input_count_changed(new_value: float) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data) and edited_node_data is AllCompleteNodeResource:
		var int_val := int(new_value)
		if edited_node_data.input_count != int_val:
			property_update_requested.emit(edited_node_data.id, "input_count", int_val, null, {})

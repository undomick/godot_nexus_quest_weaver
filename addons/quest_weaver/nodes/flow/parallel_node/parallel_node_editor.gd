# res://addons/quest_weaver/nodes/flow/parallel_node/parallel_node_editor.gd
@tool

class_name ParallelNodeEditor

extends NodePropertyEditorBase

signal ports_need_refresh

signal connections_from_port_removal_requested(port_index: int)

var _is_setting_up := false

@onready var keep_listening_checkbox: CheckBox = %KeepListeningCheckbox

@onready var outputs_container: VBoxContainer = %OutputsContainer

@onready var add_output_button: Button = %AddOutputButton


func _ready():
	if is_instance_valid(keep_listening_checkbox):
		keep_listening_checkbox.toggled.connect(_on_keep_listening_toggled)
	add_output_button.pressed.connect(_on_add_output_pressed)


func set_node_data(node_data: GraphNodeResource):
	_is_setting_up = true
	super.set_node_data(node_data)
	if not node_data is ParallelNodeResource:
		_is_setting_up = false
		return
	if is_instance_valid(keep_listening_checkbox):
		keep_listening_checkbox.button_pressed = node_data.keep_listening
	_rebuild_outputs_list()
	_is_setting_up = false


func _on_keep_listening_toggled(pressed: bool) -> void:
	if _is_setting_up:
		return
	if is_instance_valid(edited_node_data) and edited_node_data is ParallelNodeResource:
		if edited_node_data.keep_listening != pressed:
			property_update_requested.emit(edited_node_data.id, "keep_listening", pressed, null, {})


func _rebuild_outputs_list():
	for child in outputs_container.get_children():
		child.queue_free()

	var parallel_node: ParallelNodeResource = edited_node_data
	if not is_instance_valid(parallel_node):
		return

	for i in range(parallel_node.outputs.size()):
		var output_info = parallel_node.outputs[i]
		var entry: ParallelOutputEditorEntry = QWConstants.OutputEntryScene.instantiate()

		entry.remove_requested.connect(_on_remove_output_pressed.bind(i))
		entry.name_changed.connect(_on_output_name_changed.bind(i))

		entry.property_changed.connect(_make_parallel_condition_property_handler(i))

		entry.rebuild_requested.connect(_rebuild_outputs_list)

		outputs_container.add_child(entry)
		entry.display_data(output_info)


func _make_parallel_condition_property_handler(output_index: int):
	return func(prop: String, val: Variant, _target: Resource):
		property_update_requested.emit(
			edited_node_data.id, prop, val, null, {"output_index": output_index}
		)


func _on_add_output_pressed() -> void:
	complex_action_requested.emit(edited_node_data.id, "add_parallel_output", {})


func _on_remove_output_pressed(index: int) -> void:
	var payload = {"index": index}
	complex_action_requested.emit(edited_node_data.id, "remove_parallel_output", payload)


func _on_output_name_changed(new_name: String, index: int) -> void:
	var payload = {"index": index, "new_name": new_name}
	complex_action_requested.emit(edited_node_data.id, "update_parallel_port_name", payload)

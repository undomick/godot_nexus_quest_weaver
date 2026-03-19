# res://addons/quest_weaver/nodes/action/task_node/task_node_editor.gd
@tool

extends NodePropertyEditorBase

var _ui_entry_map: Dictionary = {}

var _is_setting_up := false

@onready var objectives_list: VBoxContainer = %ObjectivesList

@onready var add_objective_button: Button = %AddObjectiveButton

@onready var terminal_checkbox: CheckBox = %TerminalCheckBox


func _ready() -> void:
	add_objective_button.pressed.connect(_on_add_objective_pressed)
	terminal_checkbox.toggled.connect(_on_terminal_toggled)


func set_node_data(node_data: GraphNodeResource) -> void:
	_is_setting_up = true
	super.set_node_data(node_data)
	if not node_data is TaskNodeResource:
		for child in objectives_list.get_children():
			child.queue_free()
		_ui_entry_map.clear()
		_is_setting_up = false
		return

	_rebuild_objectives_list()
	terminal_checkbox.button_pressed = node_data.is_terminal
	_is_setting_up = false


func _rebuild_objectives_list() -> void:
	for child in objectives_list.get_children():
		child.queue_free()
	_ui_entry_map.clear()

	var task_node: TaskNodeResource = edited_node_data
	if not is_instance_valid(task_node):
		return

	var total_count = task_node.objectives.size()

	for i in range(total_count):
		var objective = task_node.objectives[i]
		_add_objective_ui(objective, i, total_count)


func _add_objective_ui(objective_resource: ObjectiveResource, index: int, total_count: int):
	var entry_instance: ObjectiveEditorEntry = QWConstants.ObjectiveEditorEntryScene.instantiate()

	entry_instance.move_up_requested.connect(_on_move_objective.bind(objective_resource, index, -1))
	entry_instance.move_down_requested.connect(
		_on_move_objective.bind(objective_resource, index, 1)
	)
	entry_instance.description_changed.connect(
		_on_objective_description_changed.bind(objective_resource, index)
	)
	entry_instance.trigger_type_changed.connect(
		_on_objective_trigger_type_changed.bind(objective_resource, index)
	)
	entry_instance.trigger_param_changed.connect(
		_on_objective_trigger_param_changed.bind(objective_resource, index)
	)
	entry_instance.delete_requested.connect(
		_on_objective_delete_requested.bind(objective_resource, index)
	)

	if entry_instance.has_signal("direct_property_changed"):
		entry_instance.direct_property_changed.connect(
			_on_objective_direct_property_changed.bind(objective_resource, index)
		)

	entry_instance.id_changed.connect(_on_objective_id_changed.bind(objective_resource, index))
	entry_instance.requirements_changed.connect(
		_on_objective_requirements_changed.bind(objective_resource, index)
	)

	objectives_list.add_child(entry_instance)
	entry_instance.set_objective(objective_resource)
	entry_instance.update_sort_index(index, total_count)
	_ui_entry_map[objective_resource] = entry_instance


func _on_move_objective(
	_objective: ObjectiveResource, objective_index: int, direction: int
) -> void:
	var payload = {"objective_index": objective_index, "direction": direction}
	complex_action_requested.emit(edited_node_data.id, "move_objective", payload)


func _remove_objective_ui(objective_resource: ObjectiveResource) -> void:
	if _ui_entry_map.has(objective_resource):
		_ui_entry_map[objective_resource].queue_free()
		_ui_entry_map.erase(objective_resource)


func _on_add_objective_pressed() -> void:
	complex_action_requested.emit(edited_node_data.id, "add_objective", {})


func _on_objective_delete_requested(_objective: ObjectiveResource, objective_index: int) -> void:
	var payload = {"objective_index": objective_index}
	complex_action_requested.emit(edited_node_data.id, "remove_objective", payload)


# --- Signal Handlers for property changes ---


func _on_objective_direct_property_changed(
	property_name: String, new_value: Variant, _objective: ObjectiveResource, objective_index: int
):
	property_update_requested.emit(
		edited_node_data.id, property_name, new_value, null, {"objective_index": objective_index}
	)


func _on_objective_description_changed(
	new_text: String, _objective: ObjectiveResource, objective_index: int
) -> void:
	property_update_requested.emit(
		edited_node_data.id, "description", new_text, null, {"objective_index": objective_index}
	)


func _on_objective_trigger_type_changed(
	new_type_index: int, _objective: ObjectiveResource, objective_index: int
) -> void:
	property_update_requested.emit(
		edited_node_data.id,
		"trigger_type",
		new_type_index,
		null,
		{"objective_index": objective_index}
	)


func _on_objective_trigger_param_changed(
	param_name: String, new_value: Variant, _objective: ObjectiveResource, objective_index: int
) -> void:
	var payload = {
		"objective_index": objective_index, "param_name": param_name, "param_value": new_value
	}
	complex_action_requested.emit(edited_node_data.id, "update_objective_trigger_param", payload)


func _on_objective_id_changed(
	new_id: String, _objective: ObjectiveResource, objective_index: int
) -> void:
	var payload = {"objective_index": objective_index, "new_id": StringName(new_id)}
	complex_action_requested.emit(edited_node_data.id, "update_objective_id", payload)


func _on_objective_requirements_changed(
	new_requirements: Dictionary, _objective: ObjectiveResource, objective_index: int
) -> void:
	var payload = {"objective_index": objective_index, "requirements": new_requirements}
	complex_action_requested.emit(edited_node_data.id, "update_objective_requirements", payload)


func _on_terminal_toggled(pressed: bool) -> void:
	if _is_setting_up:
		return  # GUARD
	if is_instance_valid(edited_node_data) and edited_node_data.is_terminal != pressed:
		property_update_requested.emit(edited_node_data.id, "is_terminal", pressed, null, {})
		edited_node_data.is_terminal = pressed
		edited_node_data._update_ports_from_data()

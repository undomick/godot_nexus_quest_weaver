@tool
class_name SwitchNodeEditor
extends NodePropertyEditorBase

const SwitchCaseEntryScene = preload(
	"res://addons/quest_weaver/editor/components/switch_case_editor_entry.tscn"
)

@onready var variable_name_edit: LineEdit = %VariableNameEdit
@onready var cases_container: VBoxContainer = %CasesContainer
@onready var add_case_button: Button = %AddCaseButton


func _ready() -> void:
	add_case_button.pressed.connect(_on_add_case_pressed)


func set_node_data(node_data: GraphNodeResource) -> void:
	super.set_node_data(node_data)
	if not node_data is SwitchNodeResource:
		return
	call_deferred(&"_rebuild_cases_list")


func _rebuild_cases_list() -> void:
	for child in cases_container.get_children():
		child.queue_free()

	var switch_node: SwitchNodeResource = edited_node_data as SwitchNodeResource
	if not is_instance_valid(switch_node):
		return

	variable_name_edit.text = switch_node.variable_name

	for i in range(switch_node.cases.size()):
		var case_port: SwitchCasePort = switch_node.cases[i]
		var entry: HBoxContainer = SwitchCaseEntryScene.instantiate()
		cases_container.add_child(entry)
		entry.display_data(case_port)
		entry.value_changed.connect(_on_value_changed.bind(i))
		entry.port_name_changed.connect(_on_port_name_changed.bind(i))
		entry.remove_requested.connect(_on_remove_case_pressed.bind(i))


func _on_add_case_pressed() -> void:
	complex_action_requested.emit(edited_node_data.id, "add_switch_case", {})
	call_deferred(&"_rebuild_cases_list")


func _on_remove_case_pressed(index: int) -> void:
	complex_action_requested.emit(edited_node_data.id, "remove_switch_case", {"index": index})
	call_deferred(&"_rebuild_cases_list")


func _on_value_changed(new_value: String, index: int) -> void:
	var switch_node: SwitchNodeResource = edited_node_data as SwitchNodeResource
	if is_instance_valid(switch_node) and index < switch_node.cases.size():
		if switch_node.cases[index].value_string != new_value:
			property_update_requested.emit(
				edited_node_data.id, "value_string", new_value, null, {"case_index": index}
			)


func _on_port_name_changed(new_name: String, index: int) -> void:
	var switch_node: SwitchNodeResource = edited_node_data as SwitchNodeResource
	if is_instance_valid(switch_node) and index < switch_node.cases.size():
		if switch_node.cases[index].port_name != new_name:
			complex_action_requested.emit(
				edited_node_data.id,
				"update_switch_case_name",
				{"index": index, "new_name": new_name}
			)
